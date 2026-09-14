import 'dart:async';
import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'address_sheet.dart';
import 'delivery_address.dart';
import 'order_placement.dart';
import 'service_order_files.dart';
import 'service_order_words.dart';
import 'services_kit.dart';
import 'utf16_length_limit.dart';

/// Configuring and placing one service order (Figma 126:437), pushed from a provider's Order button.
///
/// A one-line checkout of its own rather than the basket: a service is ordered one at a time, is
/// never queued offline, and carries what no basket does — the files, the instructions and how the
/// customer gets the work.
///
/// What the frame draws, and what it could not:
///
/// * **Packs, shown as units.** The stepper counts packs of the offer's unit (1–99, the server's own
///   bounds) and shows what they come to — "1,000 cards · 2 packs" — while the line sends the packs.
/// * **Options** from the offer's own groups; a required one blocks the price until it is chosen.
/// * **Files per the offer's policy.** A picked file is checked at once (PDF, JPEG or PNG, 10 MB) and
///   refused in words before any byte moves; a REQUIRED policy keeps Place disabled until an upload
///   has confirmed.
/// * **How the customer gets it**, limited to what the offer is sold with: pickup at the shop, free;
///   or YouDrop delivery, with the address row the frame forgot and the fee the server quotes for it.
/// * **The server's total, before the tap.** Every figure is `OrderApi.quoteService`'s answer for the
///   order exactly as configured; while it is being asked, or if it could not be, the total is a dash
///   and Place cannot be tapped. Placement asserts that total, so a price that moved in between is
///   shown and asked about again rather than charged.
/// * **Cash**, the only payment a service order takes, said as when it is paid.
/// * **Refusals in words** — a closed category, a file the provider needs, an address the shop does
///   not deliver to, a body the server will not read.
/// * **The order that was sent, and only it.** Every input is held while a send is out, so a total
///   that moved is placed only for the order the customer sees; anything changed meanwhile is priced
///   again instead. A send whose answer never came — or came unreadable — is never called a failure:
///   trying again sends the same attempt, which cannot place a second order, and leaving the screen
///   after one warns first, because another visit starts an attempt of its own.
class ServiceOrderScreen extends StatefulWidget {
  const ServiceOrderScreen({
    super.key,
    required this.kit,
    required this.store,
    required this.offer,
  });

  final ServicesKit kit;
  final Store store;

  /// The offer being ordered, with its service terms.
  final Product offer;

  @override
  State<ServiceOrderScreen> createState() => _ServiceOrderScreenState();
}

enum _Upload { sending, sent, failed }

/// What the customer chose when asked on the way out after an unanswered send.
enum _Leave { stay, leave, orders }

/// One file row: its name, where its upload stands, and the id its confirmation gave it.
class _FileSlot {
  _FileSlot(this.name);

  final String name;
  _Upload state = _Upload.sending;
  double progress = 0;
  String? fileId;

  /// Why it was refused; null for a failure that was not a refusal (the connection).
  AttachmentRefusal? refusal;
}

class _ServiceOrderScreenState extends State<ServiceOrderScreen> {
  /// Order Manager's bounds on a line's quantity, which for a service counts packs.
  static const int _maxPacks = 99;
  static const int _maxInstructions = 1000;

  ServicesKit get _kit => widget.kit;
  ServiceTerms? get _terms => widget.offer.service;

  /// Whether every term of the offer is one this build knows. An offer with an unknown term — a
  /// fulfilment or file policy a newer server added — cannot be configured honestly here.
  bool get _termsKnown => _terms?.isEditable ?? false;

  int _packs = 1;

  List<OptionGroup>? _groups;
  bool _optionsFailed = false;

  /// The options chosen, per group id, in the order they were chosen.
  final Map<String, List<String>> _chosen = <String, List<String>>{};

  final List<_FileSlot> _files = <_FileSlot>[];

  /// Why the last picked file was refused before it was sent; null once another is picked.
  String? _fileNotice;

  final TextEditingController _instructions = TextEditingController();

  late Fulfilment _fulfilment = _initialFulfilment();

  ServiceQuoteResult? _quote;
  bool _quoting = false;
  bool _quoteFailed = false;
  String? _quotedFor;

  /// Bumped for every question asked, so an answer to a question nobody is asking any more — the
  /// stepper moved on while it was in flight — is dropped instead of drawn.
  int _quoteSeq = 0;

  /// One attempt per visit to this screen, sent with every try of it — see [OrderSubmission]. A send
  /// whose answer was lost and a later one with changed packs share it, and the server answers the
  /// second with the order the first placed rather than placing another.
  late final String _attemptKey = newIdempotencyKey();

  /// Whether an order is out. While it is, every input — packs, options, files, instructions, how the
  /// customer gets it, the address — is held, so the order on screen stays the order being sent, and a
  /// "place it at the new total?" can only ever be about that order.
  bool _placing = false;

  /// Whether a send of this attempt went without an answer this build could read — so it may have
  /// placed the order — and nothing the server said since has shown that it did not. Leaving then
  /// warns first ([_confirmLeave]): another visit orders with a fresh attempt the server cannot match.
  bool _unconfirmed = false;

  /// Pickup when the offer allows it — it needs no address and costs nothing — otherwise delivery.
  Fulfilment _initialFulfilment() {
    final ServiceFulfilment modes = _terms?.fulfilmentModes ?? ServiceFulfilment.unknown;
    if (modes.includesPickup) return Fulfilment.pickup;
    if (modes.includesDelivery) return Fulfilment.delivery;
    return Fulfilment.unknown;
  }

  @override
  void initState() {
    super.initState();
    _kit.addresses.addListener(_onAddress);
    _kit.connectivity.addListener(_onConnectivity);
    if (_termsKnown) unawaited(_loadOptions());
  }

  @override
  void dispose() {
    _kit.addresses.removeListener(_onAddress);
    _kit.connectivity.removeListener(_onConnectivity);
    _instructions.dispose();
    super.dispose();
  }

  void _onAddress() {
    if (!mounted) return;
    setState(() {});
    if (_fulfilment == Fulfilment.delivery) unawaited(_requote());
  }

  void _onConnectivity() {
    if (mounted) setState(() {});
  }

  Future<void> _loadOptions() async {
    try {
      final List<OptionGroup> groups = await _kit.storeApi.productOptions(widget.offer.id);
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _chosen.clear();
        for (final OptionGroup group in groups) {
          final List<String> defaults = group.options
              .where((ProductOptionChoice o) => o.isDefault && o.available)
              .map((ProductOptionChoice o) => o.id)
              .take(group.maxSelect)
              .toList();
          if (defaults.isNotEmpty) _chosen[group.id] = defaults;
        }
      });
      unawaited(_requote());
    } catch (_) {
      if (mounted) setState(() => _optionsFailed = true);
    }
  }

  void _retryOptions() {
    setState(() => _optionsFailed = false);
    unawaited(_loadOptions());
  }

  // ------------------------------------------------------------------ the question and its price

  bool _satisfied(OptionGroup group) {
    final int count = _chosen[group.id]?.length ?? 0;
    final int least = group.required && group.minSelect < 1 ? 1 : group.minSelect;
    return count >= least && count <= group.maxSelect;
  }

  OptionGroup? get _unmetGroup {
    for (final OptionGroup group in _groups ?? const <OptionGroup>[]) {
      if (!_satisfied(group)) return group;
    }
    return null;
  }

  List<String> get _optionIds => <String>[
        for (final OptionGroup group in _groups ?? const <OptionGroup>[]) ...?_chosen[group.id],
      ];

  DeliveryAddress? get _address =>
      _fulfilment == Fulfilment.delivery ? _kit.addresses.selected : null;

  /// The order as configured, as a question for the quote; null while it cannot be priced — options
  /// still loading or unchosen, or a delivery with nowhere to go.
  BasketQuestion? get _question {
    if (!_termsKnown || _groups == null || _unmetGroup != null) return null;
    if (_fulfilment == Fulfilment.unknown) return null;
    if (_fulfilment == Fulfilment.delivery && _kit.addresses.selected == null) return null;
    return BasketQuestion.service(
      productId: widget.offer.id,
      packs: _packs,
      optionIds: _optionIds,
      fulfilment: _fulfilment,
      deliveryZoneId: _address?.zoneId,
    );
  }

  /// Asks the server what the order costs as it now stands. [again] asks even when the question has
  /// not changed — the customer's Try again, or a total that moved at placement.
  Future<void> _requote({bool again = false}) async {
    final BasketQuestion? question = _question;
    if (question == null) {
      _quoteSeq++;
      if (_quote != null || _quoting || _quoteFailed || _quotedFor != null) {
        setState(() {
          _quote = null;
          _quoting = false;
          _quoteFailed = false;
          _quotedFor = null;
        });
      }
      return;
    }
    final String signature = question.signature;
    if (!again && signature == _quotedFor && !_quoteFailed) return;
    final int seq = ++_quoteSeq;
    setState(() {
      _quotedFor = signature;
      // Cleared rather than kept: a total for two packs under a stepper that says three is a
      // number the order does not have.
      _quote = null;
      _quoting = true;
      _quoteFailed = false;
    });
    try {
      final ServiceQuoteResult result = await _kit.orderApi.quoteService(question);
      if (!mounted || seq != _quoteSeq) return;
      setState(() {
        _quote = result;
        _quoting = false;
      });
    } catch (_) {
      if (!mounted || seq != _quoteSeq) return;
      setState(() {
        _quoting = false;
        _quoteFailed = true;
      });
    }
  }

  ShopQuote? get _shopQuote => switch (_quote) {
        ServiceQuoted(:final ShopQuote? shop) => shop,
        _ => null,
      };

  /// The total the server quoted for the order as configured; null while there is none to place at.
  double? get _total {
    final ServiceQuoteResult? quote = _quote;
    if (quote is! ServiceQuoted || !quote.quote.placeable) return null;
    return quote.quote.totalAmount ?? quote.shop?.totalAmount;
  }

  /// Why Place cannot be tapped, in words; null when it can — or when all that is missing is a price
  /// still being asked, which the dash already says.
  String? _blocker(DeliveryStrings t) {
    // A service order is never queued offline: it needs its files, and a provider's acceptance.
    if (!_kit.connectivity.value) return t.svcOfflineNoQueue;
    final OptionGroup? unmet = _unmetGroup;
    if (unmet != null) return '${unmet.name}: ${t.svcChooseOption}';
    if (_fulfilment == Fulfilment.delivery) {
      final DeliveryAddress? address = _kit.addresses.selected;
      if (address == null) return t.svcChooseDeliveryAddress;
      // The shop's own circle, as every checkout honours it (isOutsideDeliveryRadius).
      if (isOutsideDeliveryRadius(widget.store.toCard(), address)) {
        return t.custOutsideDeliveryArea(
            widget.store.name, (widget.store.deliveryRadiusMetres! / 1000).toStringAsFixed(1));
      }
    }
    final ServiceAttachmentPolicy policy =
        _terms?.attachmentPolicy ?? ServiceAttachmentPolicy.unknown;
    if (policy == ServiceAttachmentPolicy.required && _kit.files == null) {
      return t.svcRefusedAttachmentsUnavailable;
    }
    if (_files.any((_FileSlot f) => f.state == _Upload.sending)) return t.svcUploading;
    if (policy == ServiceAttachmentPolicy.required &&
        !_files.any((_FileSlot f) => f.state == _Upload.sent)) {
      return t.svcFileRequired;
    }
    final ServiceQuoteResult? quote = _quote;
    switch (quote) {
      case ServiceQuoteRefused(:final ServiceOrderRefusal refusal):
        return serviceRefusalMessage(refusal, t);
      case ServiceQuoteUnavailable():
        return t.svcDirectoryUnavailable;
      case ServiceQuoted():
        if (!quote.quote.placeable) return _shopRefusal(quote.shop, t);
      case null:
        if (_quoteFailed) return t.svcQuoteFailed;
    }
    return null;
  }

  String _shopRefusal(ShopQuote? shop, DeliveryStrings t) {
    final String name = widget.store.name;
    final double? minimum = shop?.minimumOrder;
    return switch (shop?.refusal) {
      ShopRefusal.closed => t.svcShopClosed(name),
      ShopRefusal.notServed => t.svcNotServed(name),
      ShopRefusal.belowMinimum when minimum != null => t.svcBelowMinimum(name, svcUsd(minimum)),
      _ => shop?.refusalMessage ?? t.svcRefusedGeneric,
    };
  }

  // ------------------------------------------------------------------ placing

  /// The order exactly as the screen now shows it, as a submission of this visit's attempt.
  OrderSubmission _submission() {
    final DeliveryAddress? address = _address;
    return OrderSubmission(
      idempotencyKey: _attemptKey,
      items: <OrderLineSubmission>[
        (productId: widget.offer.id, qty: _packs, optionIds: _optionIds),
      ],
      // Not sent for a pickup, which goes nowhere (OrderSubmission.toBody).
      deliveryAddress: address?.line ?? '',
      deliveryZoneId: address?.zoneId,
      deliveryLatitude: address?.latitude,
      deliveryLongitude: address?.longitude,
      // The door note a rider reads; the provider's instructions travel separately.
      notes: address?.notes,
      paymentMethod: PaymentMethod.cash,
      fulfilment: _fulfilment,
      attachmentFileIds: <String>[
        for (final _FileSlot slot in _files)
          if (slot.state == _Upload.sent && slot.fileId != null) slot.fileId!,
      ],
      serviceInstructions: _instructions.text.trim().isEmpty ? null : _instructions.text.trim(),
    );
  }

  /// Whether two submissions ask for the same order: the same body as the server reads it — packs,
  /// options, files, instructions, fulfilment and address alike. Both carry this visit's key.
  static bool _sameOrder(OrderSubmission a, OrderSubmission b) =>
      jsonEncode(a.toBody()) == jsonEncode(b.toBody());

  Future<void> _place() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final double? agreed = _total;
    if (agreed == null || _placing || _blocker(t) != null) return;

    // Built once and sent unchanged on every try below, key and all.
    final OrderSubmission submission = _submission();

    setState(() => _placing = true);
    double expected = agreed;
    try {
      while (true) {
        final PlaceOrderResult result =
            await _kit.orderApi.place(submission, expectedTotal: expected);
        if (!mounted) return;
        switch (result) {
          case OrderPlaced(:final DeliveryOrder order):
            _openTracking(order.id, preview: order);
            return;
          case OrderAlreadyPlaced(:final String orderId):
            // An earlier try of this visit went through: that order is the truth, and it is shown.
            _say(t.offlineAlreadyPlaced);
            _openTracking(orderId);
            return;
          case OrderPriceChanged(:final double total):
            // Nothing is stored under the key for a total that moved, so no earlier try of this
            // visit placed an order either.
            _settled();
            unawaited(_requote(again: true));
            if (!await _confirmNewTotal(total, expected, t) || !mounted) return;
            // The yes was to the order as it was sent. If what the screen shows has changed since —
            // an address chosen elsewhere meanwhile — the yes is not about it: its price is asked
            // again, and nothing is placed until the customer taps Place at that price.
            if (!_sameOrder(_submission(), submission)) {
              _say(t.svcOrderChangedRequote);
              unawaited(_requote());
              return;
            }
            setState(() => _placing = true);
            expected = total;
          case ServiceOrderRefused(:final ServiceOrderRefusal refusal):
            _settled();
            _say(serviceRefusalMessage(refusal, t));
            return;
          case ServicesDirectoryUnavailable():
            _settled();
            _say(t.svcDirectoryUnavailable);
            return;
        }
      }
    } on DioException catch (e) {
      if (!mounted) return;
      // No answer, or a server error after the request arrived: the order may exist. Never "it did
      // not go through" — and trying again is safe, because it sends this same attempt.
      if (OrderApi.mayHavePlaced(e)) {
        _unanswered(t);
        return;
      }
      final int? status = e.response?.statusCode;
      // A rule's refusal (422) comes after the server looked this attempt's key up and found no order,
      // so it settles an earlier unanswered try; a 400 is refused before that lookup and settles
      // nothing.
      if (status == 422) {
        _settled();
      } else {
        setState(() => _placing = false);
      }
      // A 400 is a body the server would not read. placementRefusalMessage calls that "check the
      // delivery details", which a pickup does not even have: a service order says what it is.
      _say(status == 400 ? t.svcOrderNotAccepted : placementRefusalMessage(e, t));
    } catch (_) {
      // An answer this build could not read — a 201 whose order did not parse, say — still answers a
      // send that may have placed the order: said as a lost answer is, with Place given back.
      if (!mounted) return;
      _unanswered(t);
    }
  }

  /// The server answered in a way that shows this attempt placed nothing: Place is back, and leaving
  /// needs no warning.
  void _settled() => setState(() {
        _placing = false;
        _unconfirmed = false;
      });

  /// A send with no answer this build could read: the order may exist.
  void _unanswered(DeliveryStrings t) {
    setState(() {
      _placing = false;
      _unconfirmed = true;
    });
    _say(t.offlineUnconfirmedRetry);
  }

  /// Asked on the way out after a send whose answer never came. Another visit orders with a fresh
  /// attempt the server cannot match to this one, so ordering again without looking could place the
  /// same work twice: the customer is told so, and offered the Orders tab to look first.
  Future<void> _confirmLeave() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final VoidCallback? openOrders = _kit.openOrders;
    final _Leave? choice = await showDialog<_Leave>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: DeliveryColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
        title: Text(t.svcUnconfirmedLeaveTitle,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: DeliveryColors.ink)),
        content: Text(t.svcUnconfirmedLeaveBody,
            style: const TextStyle(fontSize: 14, color: DeliveryColors.muted, height: 1.4)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_Leave.stay),
            style: TextButton.styleFrom(foregroundColor: DeliveryColors.muted),
            child: Text(t.svcStayHere),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_Leave.leave),
            style: TextButton.styleFrom(foregroundColor: DeliveryColors.muted),
            child: Text(t.svcLeaveAnyway),
          ),
          if (openOrders != null)
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(_Leave.orders),
              style: FilledButton.styleFrom(
                backgroundColor: DeliveryColors.brand,
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.md)),
              ),
              child: Text(t.svcCheckOrders),
            ),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case _Leave.orders:
        openOrders?.call();
      case _Leave.leave:
        // pop, not maybePop: the question on the way out has been answered.
        Navigator.of(context).pop();
      case _Leave.stay || null:
        break;
    }
  }

  void _openTracking(String orderId, {DeliveryOrder? preview}) {
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => _kit.trackingScreen(orderId, preview: preview),
    ));
  }

  /// A newer answer replaces the one on screen rather than queueing behind it: "the category is
  /// closed" must not still be showing when the next try says something else.
  void _say(String message) => ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  /// Shows the server's new [total] beside the [agreed] one and asks whether to place at it. True only
  /// for an explicit yes: dismissing the question places nothing.
  Future<bool> _confirmNewTotal(double total, double agreed, DeliveryStrings t) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: DeliveryColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
        title: Text(t.multiCartPriceChangedTitle,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: DeliveryColors.ink)),
        content: Text(t.svcPriceChangedBody(svcUsd(total), svcUsd(agreed)),
            style: const TextStyle(fontSize: 14, color: DeliveryColors.muted, height: 1.4)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(foregroundColor: DeliveryColors.muted),
            child: Text(t.notNow),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: DeliveryColors.brand,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.md)),
            ),
            child: Text(t.svcPlaceOrderTotal(svcUsd(total))),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  // ------------------------------------------------------------------ files

  Future<void> _pickFile() async {
    final ServiceOrderFiles? files = _kit.files;
    if (files == null || _placing) return;
    final DeliveryStrings t = DeliveryStrings.of(context);
    final PickedServiceFile? picked;
    try {
      picked = await _kit.pickFile();
    } catch (_) {
      return;
    }
    if (picked == null || !mounted) return;

    final String? contentType = serviceFileContentType(picked.name, reported: picked.mimeType);
    final AttachmentRefusal? refused =
        precheckServiceFile(contentType: contentType, sizeBytes: picked.sizeBytes);
    if (refused != null || contentType == null) {
      setState(() =>
          _fileNotice = attachmentRefusalMessage(refused ?? AttachmentRefusal.wrongType, t));
      return;
    }

    final _FileSlot slot = _FileSlot(picked.name);
    setState(() {
      _fileNotice = null;
      _files.add(slot);
    });
    try {
      final Uint8List bytes = await picked.readBytes();
      final String fileId = await files.upload(
        bytes: bytes,
        contentType: contentType,
        onProgress: (int sent, int total) {
          if (mounted && total > 0) setState(() => slot.progress = (sent / total).clamp(0, 1));
        },
      );
      if (!_files.contains(slot)) {
        // Removed while it was on its way: take it back rather than leave it waiting.
        unawaited(_forget(files, fileId));
        return;
      }
      if (!mounted) return;
      setState(() {
        slot.fileId = fileId;
        slot.state = _Upload.sent;
      });
    } on ServiceFileRefused catch (e) {
      if (!mounted) return;
      setState(() {
        slot.state = _Upload.failed;
        slot.refusal = e.refusal;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => slot.state = _Upload.failed);
    }
  }

  void _removeFile(_FileSlot slot) {
    // Never while the order is out: the file may already be on it, and its row must not vanish.
    if (_placing) return;
    final String? fileId = slot.fileId;
    setState(() => _files.remove(slot));
    final ServiceOrderFiles? files = _kit.files;
    if (fileId != null && files != null) unawaited(_forget(files, fileId));
  }

  static Future<void> _forget(ServiceOrderFiles files, String fileId) async {
    try {
      await files.remove(fileId);
    } catch (_) {
      // The server sweeps an upload no order took within a day either way.
    }
  }

  // ------------------------------------------------------------------ the screen

  // Each of these is also held by its control while an order is out ([_placing]); the checks here
  // catch a tap already on its way when the send began.

  Future<void> _chooseAddress() async {
    if (_placing) return;
    await showAddressSheet(context, _kit.addresses,
        zoneApi: _kit.zoneApi, geocodingApi: _kit.geocodingApi);
    if (!mounted) return;
    setState(() {});
    unawaited(_requote());
  }

  void _setPacks(int packs) {
    if (_placing) return;
    setState(() => _packs = packs.clamp(1, _maxPacks));
    unawaited(_requote());
  }

  void _chooseFulfilment(Fulfilment fulfilment) {
    if (_placing) return;
    setState(() => _fulfilment = fulfilment);
    unawaited(_requote());
  }

  void _choose(OptionGroup group, ProductOptionChoice option) {
    if (_placing) return;
    final List<String> chosen = <String>[...?_chosen[group.id]];
    if (group.singleChoice) {
      chosen
        ..clear()
        ..add(option.id);
    } else if (chosen.contains(option.id)) {
      chosen.remove(option.id);
    } else if (chosen.length < group.maxSelect) {
      chosen.add(option.id);
    } else {
      return;
    }
    setState(() => _chosen[group.id] = chosen);
    unawaited(_requote());
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool configurable = _termsKnown && _groups != null;
    // After a send whose answer never came, the way out — the header's back or the phone's — asks
    // first ([_confirmLeave]).
    return PopScope<Object?>(
      canPop: !_unconfirmed,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) unawaited(_confirmLeave());
      },
      child: Scaffold(
        backgroundColor: DeliveryColors.background,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SafeArea(
              bottom: false,
              child: YdScreenHeader(
                title: t.svcOrderServiceTitle,
                onBack: () => Navigator.of(context).maybePop(),
                backSemanticLabel: t.back,
              ),
            ),
            Expanded(child: _body(t)),
          ],
        ),
        bottomNavigationBar: configurable ? _placeBar(t) : null,
      ),
    );
  }

  Widget _body(DeliveryStrings t) {
    if (!_termsKnown) {
      return YdEmptyState(
          icon: Icons.design_services_outlined, title: t.svcRefusedOfferNotOrderable);
    }
    if (_optionsFailed) {
      return YdEmptyState(
        icon: Icons.cloud_off_rounded,
        title: t.svcCouldNotLoadOffer,
        action: YdPillButton(
          label: t.tryAgain,
          expand: false,
          size: YdPillButtonSize.compact,
          onPressed: _retryOptions,
        ),
      );
    }
    final List<OptionGroup>? groups = _groups;
    if (groups == null) {
      return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
    }
    final ServiceTerms terms = _terms!;
    final ServiceFulfilment modes = terms.fulfilmentModes;
    final bool takesFiles = terms.attachmentPolicy == ServiceAttachmentPolicy.optional ||
        terms.attachmentPolicy == ServiceAttachmentPolicy.required;
    const SizedBox gap = SizedBox(height: DeliverySpacing.md);

    return ListView(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
      children: <Widget>[
        Text(widget.offer.name,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: DeliveryColors.ink, height: 1.25)),
        const SizedBox(height: 2),
        Text(t.svcProviderLine(widget.store.name),
            style: const TextStyle(fontSize: 14, color: DeliveryColors.muted)),
        gap,
        _quantityCard(terms, t),
        for (final OptionGroup group in groups) ...<Widget>[gap, _optionGroup(group, t)],
        if (takesFiles && _kit.files != null) ...<Widget>[gap, _filesSection(terms, t)],
        gap,
        _instructionsField(terms, t),
        gap,
        _caption(t.svcHowYouGetIt),
        const SizedBox(height: DeliverySpacing.sm),
        if (modes.includesPickup) _fulfilmentRow(Fulfilment.pickup, t),
        if (modes.includesPickup && modes.includesDelivery)
          const SizedBox(height: DeliverySpacing.sm),
        if (modes.includesDelivery) _fulfilmentRow(Fulfilment.delivery, t),
        if (_fulfilment == Fulfilment.delivery) ...<Widget>[
          const SizedBox(height: DeliverySpacing.sm),
          _addressRow(t),
        ],
        gap,
        _summary(t),
      ],
    );
  }

  Widget _quantityCard(ServiceTerms terms, DeliveryStrings t) {
    final int units = _packs * terms.unitSize;
    final String? unit = terms.unitLabel;
    final String detail = <String>[
      if (unit != null) t.svcUnitsLine(svcCount(units), unit),
      if (terms.unitSize > 1) t.svcPacksCount(_packs),
    ].join(' · ');
    return YdCard.bordered(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(t.svcQuantity,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: DeliveryColors.ink)),
                if (detail.isNotEmpty)
                  Text(detail, style: const TextStyle(fontSize: 12, color: DeliveryColors.muted)),
              ],
            ),
          ),
          _StepButton(
            icon: Icons.remove_rounded,
            semanticLabel: t.custDecreaseQuantity,
            background: DeliveryColors.border,
            foreground: DeliveryColors.ink,
            onTap: _packs > 1 && !_placing ? () => _setPacks(_packs - 1) : null,
          ),
          Padding(
            // The frame's 12px between tile and figure, 8 of which each tile's 48dp square now holds.
            padding: const EdgeInsetsDirectional.symmetric(horizontal: DeliverySpacing.xs),
            child: Text(svcCount(units),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: DeliveryColors.ink)),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            semanticLabel: t.custIncreaseQuantity,
            background: DeliveryColors.brandSoft,
            foreground: DeliveryColors.brand,
            onTap: _packs < _maxPacks && !_placing ? () => _setPacks(_packs + 1) : null,
          ),
        ],
      ),
    );
  }

  Widget _optionGroup(OptionGroup group, DeliveryStrings t) {
    final List<String> chosen = _chosen[group.id] ?? const <String>[];
    final Widget control;
    if (group.singleChoice) {
      control = Container(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: DeliverySpacing.md - 4),
        decoration: BoxDecoration(
          color: DeliveryColors.white,
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          border: Border.all(color: DeliveryColors.border),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: chosen.isEmpty ? null : chosen.first,
            hint: Text(t.svcChooseOption,
                style: const TextStyle(fontSize: 14, color: DeliveryColors.muted)),
            items: <DropdownMenuItem<String>>[
              for (final ProductOptionChoice option in group.options)
                DropdownMenuItem<String>(
                  value: option.id,
                  enabled: option.available,
                  child: Text(_optionLabel(option),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, color: DeliveryColors.ink)),
                ),
            ],
            onChanged: _placing
                ? null
                : (String? id) {
                    final ProductOptionChoice? option =
                        group.options.where((ProductOptionChoice o) => o.id == id).firstOrNull;
                    if (option != null) _choose(group, option);
                  },
          ),
        ),
      );
    } else {
      control = Wrap(
        spacing: DeliverySpacing.sm,
        runSpacing: DeliverySpacing.sm,
        children: <Widget>[
          for (final ProductOptionChoice option in group.options)
            YdChip(
              label: _optionLabel(option),
              selected: chosen.contains(option.id),
              onTap: option.available && !_placing ? () => _choose(group, option) : null,
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _captionRow(group.name, group.required ? t.svcOptionRequired : t.svcOptionOptional),
        const SizedBox(height: DeliverySpacing.sm),
        control,
      ],
    );
  }

  /// A choice with what it adds, as the catalogue prices it: "Matte (+$1.00)".
  static String _optionLabel(ProductOptionChoice option) => option.priceDelta == 0
      ? option.name
      : '${option.name} (${option.priceDelta > 0 ? '+' : '-'}${svcUsd(option.priceDelta.abs())})';

  Widget _filesSection(ServiceTerms terms, DeliveryStrings t) {
    final bool required = terms.attachmentPolicy == ServiceAttachmentPolicy.required;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _captionRow(t.svcUploadDesign, required ? t.svcOptionRequired : t.svcOptionOptional),
        const SizedBox(height: DeliverySpacing.sm),
        for (final _FileSlot slot in _files) ...<Widget>[
          _fileRow(slot, t),
          const SizedBox(height: DeliverySpacing.sm),
        ],
        if (_files.length < serviceFilesPerOrder)
          Semantics(
            button: true,
            child: Material(
              color: DeliveryColors.white,
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
              child: InkWell(
                onTap: _placing ? null : _pickFile,
                borderRadius: BorderRadius.circular(DeliveryRadius.md),
                child: Container(
                  padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: DeliverySpacing.md - 4, vertical: DeliverySpacing.md + 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(DeliveryRadius.md),
                    border: Border.all(color: DeliveryColors.border),
                  ),
                  child: Column(
                    children: <Widget>[
                      const Icon(Icons.file_upload_outlined, size: 24, color: DeliveryColors.brand),
                      const SizedBox(height: 6),
                      Text(
                        _files.isEmpty ? t.svcUploadHint : t.svcAddAnotherFile,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600, color: DeliveryColors.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (_fileNotice != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 6),
            child: Text(_fileNotice!,
                style: TextStyle(fontSize: 12.5, color: DeliveryAccent.critical.onTint)),
          ),
      ],
    );
  }

  Widget _fileRow(_FileSlot slot, DeliveryStrings t) {
    final bool failed = slot.state == _Upload.failed;
    final String status = switch (slot.state) {
      _Upload.sending => t.svcUploading,
      _Upload.sent => t.svcUploaded,
      _Upload.failed =>
        slot.refusal == null ? t.svcUploadFailed : attachmentRefusalMessage(slot.refusal!, t),
    };
    return YdCard.bordered(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                slot.name.toLowerCase().endsWith('.pdf')
                    ? Icons.picture_as_pdf_outlined
                    : Icons.image_outlined,
                size: 20,
                color: DeliveryColors.brand,
              ),
              const SizedBox(width: DeliverySpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(slot.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600, color: DeliveryColors.ink)),
                    Text(status,
                        style: TextStyle(
                            fontSize: 11.5,
                            color: failed ? DeliveryAccent.critical.onTint : DeliveryColors.muted)),
                  ],
                ),
              ),
              TextButton(
                onPressed: _placing ? null : () => _removeFile(slot),
                style: TextButton.styleFrom(foregroundColor: DeliveryColors.brand),
                child: Text(t.svcRemoveFile),
              ),
            ],
          ),
          if (slot.state == _Upload.sending)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 6),
              child: LinearProgressIndicator(
                // Always determinate: the bar says how much has gone, never spins for nothing.
                value: slot.progress,
                color: DeliveryColors.brand,
                backgroundColor: DeliveryColors.brandSoft,
              ),
            ),
        ],
      ),
    );
  }

  Widget _instructionsField(ServiceTerms terms, DeliveryStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _caption(t.svcSpecialInstructions),
        // The provider's own question, when they asked one.
        if (terms.instructionsPrompt != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 4),
            child: Text(terms.instructionsPrompt!,
                style: const TextStyle(fontSize: 12.5, color: DeliveryColors.muted)),
          ),
        const SizedBox(height: DeliverySpacing.sm),
        TextField(
          controller: _instructions,
          // Held as Order Manager counts, in UTF-16 units (`@Size(max = 1000)`): Flutter's maxLength
          // counts an emoji as one, and would let through instructions the server refuses.
          inputFormatters: const <TextInputFormatter>[Utf16LengthLimit(_maxInstructions)],
          buildCounter: (BuildContext context,
                  {required int currentLength, required bool isFocused, required int? maxLength}) =>
              Text(t.svcInstructionsLength(_instructions.text.length, _maxInstructions),
                  style: const TextStyle(fontSize: 11.5, color: DeliveryColors.muted)),
          // Read-only rather than disabled while the order is out: the words stay as sent, and look it.
          readOnly: _placing,
          minLines: 2,
          maxLines: 5,
          style: const TextStyle(fontSize: 14, color: DeliveryColors.ink),
          decoration: InputDecoration(
            hintText: t.svcInstructionsHint,
            hintStyle: const TextStyle(fontSize: 14, color: DeliveryColors.faint),
            filled: true,
            fillColor: DeliveryColors.white,
            contentPadding: const EdgeInsetsDirectional.all(DeliverySpacing.md - 4),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
              borderSide: const BorderSide(color: DeliveryColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
              borderSide: const BorderSide(color: DeliveryColors.brand),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fulfilmentRow(Fulfilment option, DeliveryStrings t) {
    final bool selected = _fulfilment == option;
    final bool pickup = option == Fulfilment.pickup;
    String? price;
    Color priceColor = DeliveryColors.brand;
    if (pickup) {
      price = t.free.toUpperCase();
      priceColor = DeliveryAccent.positive.onTint;
    } else if (selected) {
      // The area's fee as the server quoted it for this address — never a figure of the frame's.
      final double? fee = _shopQuote?.deliveryFeeCharged;
      if (fee != null) price = fee == 0 ? t.free.toUpperCase() : t.svcDeliveryFeePlus(svcUsd(fee));
    }
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? DeliveryColors.brandSoft : DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          onTap: selected || _placing ? null : () => _chooseFulfilment(option),
          child: Container(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: DeliverySpacing.md, vertical: DeliverySpacing.md - 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
              border: Border.all(color: selected ? DeliveryColors.brand : DeliveryColors.border),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: selected ? DeliveryColors.brand : DeliveryColors.border, width: 2),
                  ),
                  child: selected
                      ? Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                              color: DeliveryColors.brand, shape: BoxShape.circle),
                        )
                      : null,
                ),
                const SizedBox(width: DeliverySpacing.md - 4),
                Expanded(
                  child: Text(
                    pickup ? t.svcPickupAtShop : t.svcYouDropDelivery,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                        color: DeliveryColors.ink),
                  ),
                ),
                if (price != null)
                  Text(price,
                      style: TextStyle(
                          fontSize: pickup ? 11.5 : 14, fontWeight: FontWeight.w700, color: priceColor)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _addressRow(DeliveryStrings t) {
    final DeliveryAddress? address = _kit.addresses.selected;
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    return YdCard.bordered(
      onTap: _placing ? null : _chooseAddress,
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - 4),
      child: Row(
        children: <Widget>[
          const Icon(Icons.location_on_outlined, size: 20, color: DeliveryColors.brand),
          const SizedBox(width: DeliverySpacing.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(t.deliveryAddress,
                    style: const TextStyle(fontSize: 11.5, color: DeliveryColors.muted)),
                Text(
                  address?.display ?? t.chooseAnAddress,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: DeliveryColors.ink),
                ),
              ],
            ),
          ),
          Icon(rtl ? Icons.chevron_left : Icons.chevron_right, size: 20, color: DeliveryColors.muted),
        ],
      ),
    );
  }

  Widget _summary(DeliveryStrings t) {
    final ShopQuote? shop = _shopQuote;
    final double? total = _total;
    final bool pickup = _fulfilment == Fulfilment.pickup;
    final double discount = shop?.discountAmount ?? 0;
    final String? lbp = total == null ? null : MarketRates.instance.lbp(total);
    String money(double? value) => value == null ? '—' : svcUsd(value);

    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _row(t.subtotal, money(shop?.subtotal)),
          // A pickup has no fee by rule; a delivery's is the server's, or a dash.
          _row(t.svcDeliveryFee, pickup ? t.free : money(shop?.deliveryFeeCharged)),
          if (discount > 0) _row(t.svcDiscount, '-${svcUsd(discount)}'),
          const Divider(height: DeliverySpacing.md, color: DeliveryColors.borderFaint),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(t.total,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: DeliveryColors.ink)),
              ),
              Text(money(total),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800, color: DeliveryColors.brand)),
            ],
          ),
          if (lbp != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(lbp, style: const TextStyle(fontSize: 11, color: DeliveryColors.muted)),
            ),
          const SizedBox(height: DeliverySpacing.sm),
          Row(
            children: <Widget>[
              const Icon(Icons.payments_outlined, size: 18, color: DeliveryColors.brand),
              const SizedBox(width: DeliverySpacing.sm),
              Expanded(
                child: Text(pickup ? t.svcPayCashPickup : t.svcPayCashDelivery,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: DeliveryColors.ink)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _placeBar(DeliveryStrings t) {
    final String? blocker = _blocker(t);
    final double? total = _total;
    final bool askAgain = _quoteFailed || _quote is ServiceQuoteUnavailable;
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: DeliveryColors.white,
          border: Border(top: BorderSide(color: DeliveryColors.border)),
        ),
        padding: const EdgeInsetsDirectional.fromSTEB(
            DeliverySpacing.md, DeliverySpacing.sm + 4, DeliverySpacing.md, DeliverySpacing.sm + 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (blocker != null) ...<Widget>[
              Text(blocker,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: DeliveryColors.muted, height: 1.35)),
              if (askAgain && _kit.connectivity.value)
                TextButton(
                  onPressed: () => _requote(again: true),
                  style: TextButton.styleFrom(foregroundColor: DeliveryColors.brand),
                  child: Text(t.tryAgain),
                ),
              const SizedBox(height: DeliverySpacing.sm),
            ],
            YdPillButton(
              label: t.svcPlaceOrderTotal(total == null ? '—' : svcUsd(total)),
              busy: _placing,
              onPressed: blocker == null && total != null && !_placing ? _place : null,
            ),
          ],
        ),
      ),
    );
  }

  static Widget _caption(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: DeliveryColors.muted, letterSpacing: 0.3),
      );

  static Widget _captionRow(String title, String rule) => Row(
        children: <Widget>[
          Expanded(child: _caption(title)),
          Text(rule, style: const TextStyle(fontSize: 11, color: DeliveryColors.faint)),
        ],
      );

  static Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: <Widget>[
            Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 12.5, color: DeliveryColors.muted))),
            Text(value,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: DeliveryColors.ink)),
          ],
        ),
      );
}

/// One side of the pack stepper: the frame's tile, grey for fewer and brand-tinted for more. A null
/// [onTap] dims it — at one pack, at the ninety-ninth, or while the order is out.
///
/// The tile is drawn at 32dp, but a tap anywhere in the 48dp square around it counts: a thumb aimed
/// at a small tile beside a number misses it easily, and a miss here is a price that did not change.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.semanticLabel,
    required this.background,
    required this.foreground,
    this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      // The square around the tile: a tap on the tile is the InkWell's, with its ripple; a tap beside
      // it lands here and does the same.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onTap,
        child: SizedBox.square(
          dimension: kMinInteractiveDimension,
          child: Center(
            child: Opacity(
              opacity: onTap == null ? 0.4 : 1,
              child: Material(
                color: background,
                borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: SizedBox.square(
                    dimension: 32,
                    child: Icon(icon, size: 18, color: foreground),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
