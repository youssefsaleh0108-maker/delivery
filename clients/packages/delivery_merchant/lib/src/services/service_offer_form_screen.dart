import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../order_detail_screen.dart';
import '../product_form_screen.dart';
import '../product_options_editor.dart';
import 'service_choice.dart';
import 'service_offers_screen.dart';
import 'service_shop.dart';
import 'service_words.dart';

/// A service offer, created or edited — Figma `service-add-offer` (126:133), "New service offer".
///
/// Built on the product form's plumbing rather than a copy of it: the same photo picker and
/// three-step upload (held until the first save gives the offer an id), the same option-group editor,
/// and the same catalogue calls, with the service terms that make it an offer.
///
/// Where it departs from the frame, and why:
/// - The price is typed in dollars only, with the LBP beside it as a read-only conversion at the
///   platform's rate. The frame's USD/LBP toggle is gone: a price typed in pounds would be stored as an
///   odd dollar amount at a rate that moves, and the platform keeps no second price.
/// - Category is the shop's, shown rather than chosen: a shop has one category.
/// - "Estimated delivery time" is Turnaround, in presets: delivery comes on top of it, and the order's
///   promise is acceptance plus the longest of it.
/// - What the other frames depend on is added: the pack a customer orders in ("500 cards"), whether
///   the customer sends a file, the question put to them, and option groups.
/// - YouDrop delivery is offered only by a shop that reaches somebody — delivery areas or a pin — as
///   the server requires at publishing.
/// - Validation says, in the provider's language, what Product Service would refuse.
class ServiceOfferFormScreen extends StatefulWidget {
  const ServiceOfferFormScreen({
    super.key,
    required this.api,
    required this.shop,
    this.storeApi,
    this.deliveryReach,
    this.existing,
    this.pendingApproval = false,
  });

  final CatalogApi api;

  /// The services shop the offer is sold in: its id, and its category.
  final Store shop;

  /// Reads the offer's option groups. Null draws no options card rather than claiming there are none.
  final StoreApi? storeApi;

  /// Whether the shop reaches anybody for delivery (see [svcDeliveryReach]); null when unknown.
  final bool? deliveryReach;

  /// The offer to edit; null creates one.
  final Product? existing;

  final bool pendingApproval;

  @override
  State<ServiceOfferFormScreen> createState() => _ServiceOfferFormScreenState();
}

enum _OfferAction { pause, resume, archive }

class _ServiceOfferFormScreenState extends State<ServiceOfferFormScreen> {
  // Product Service's own limits (ProductRequest, ServiceTermsRequest, ServiceTerms).
  static const int _maxTitle = 200;
  static const int _maxDescription = 4000;
  static const int _maxUnitLabel = 40;
  static const int _maxUnitSize = 100000;
  static const int _maxPrompt = 160;

  static final RegExp _money = RegExp(r'^\d{1,10}(\.\d{1,2})?$');

  final GlobalKey<FormState> _form = GlobalKey<FormState>();

  late final ServiceTerms? _terms = widget.existing?.service;

  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.existing?.description ?? '');
  late final TextEditingController _price =
      TextEditingController(text: widget.existing?.price.toStringAsFixed(2) ?? '');
  late final TextEditingController _unitLabel =
      TextEditingController(text: _terms?.unitLabel ?? '');
  late final TextEditingController _packSize =
      TextEditingController(text: '${_terms?.unitSize ?? 1}');
  late final TextEditingController _prompt =
      TextEditingController(text: _terms?.instructionsPrompt ?? '');

  late ServicePricingType? _pricing = widget.existing == null
      ? ServicePricingType.fixed
      : (_terms?.pricingType == ServicePricingType.unknown ? null : _terms?.pricingType);

  late (int, int)? _turnaround = switch (_terms) {
    ServiceTerms(turnaroundMinHours: final int min, turnaroundMaxHours: final int max) =>
      (min, max),
    _ => null,
  };

  late ServiceFulfilment? _fulfilment =
      _terms?.fulfilmentModes == ServiceFulfilment.unknown ? null : _terms?.fulfilmentModes;

  late ServiceAttachmentPolicy _filePolicy =
      _terms == null || _terms.attachmentPolicy == ServiceAttachmentPolicy.unknown
          ? ServiceAttachmentPolicy.none
          : _terms.attachmentPolicy;

  late Product? _product = widget.existing;

  /// Photos picked before the offer exists, uploaded by the first save — as the product form does.
  final List<PickedImageBytes> _pendingImages = <PickedImageBytes>[];

  late Future<List<OptionGroup>>? _options = _loadOptions();

  bool _saving = false;
  bool _uploading = false;
  bool _savingOptions = false;

  /// Whether every term the offer holds is one this build can save back. A new offer's always are.
  bool get _editable => _terms?.isEditable ?? true;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    _unitLabel.dispose();
    _packSize.dispose();
    _prompt.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ reading the form

  /// Arabic-Indic digits and the Arabic decimal mark as the ASCII the server reads: a keyboard in
  /// Arabic types "٢٠٫٥٠" for 20.50.
  static String _ascii(String text) {
    final StringBuffer out = StringBuffer();
    for (final int rune in text.trim().runes) {
      if (rune >= 0x0660 && rune <= 0x0669) {
        out.writeCharCode(0x30 + rune - 0x0660);
      } else if (rune >= 0x06F0 && rune <= 0x06F9) {
        out.writeCharCode(0x30 + rune - 0x06F0);
      } else if (rune == 0x066B) {
        out.write('.');
      } else {
        out.writeCharCode(rune);
      }
    }
    return out.toString();
  }

  /// A price Product Service takes — above zero, at most ten whole digits and two decimals — or null.
  static double? _priceOf(String text) {
    final String value = _ascii(text);
    if (!_money.hasMatch(value)) return null;
    final double? price = double.tryParse(value);
    return price == null || price < 0.01 ? null : price;
  }

  int? get _packSizeValue => int.tryParse(_ascii(_packSize.text));

  ServiceTerms _termsFromForm() => ServiceTerms(
        pricingType: _pricing!,
        fulfilmentModes: _fulfilment!,
        unitLabel: _unitLabel.text.trim().isEmpty ? null : _unitLabel.text.trim(),
        unitSize: _pricing == ServicePricingType.perUnit ? 1 : _packSizeValue!,
        turnaroundMinHours: _turnaround!.$1,
        turnaroundMaxHours: _turnaround!.$2,
        attachmentPolicy: _filePolicy,
        instructionsPrompt: _prompt.text.trim().isEmpty ? null : _prompt.text.trim(),
      );

  // ------------------------------------------------------------------ saving

  Future<void> _save({required bool publish}) async {
    if (!_editable || _saving) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    final DeliveryStrings t = DeliveryStrings.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);

    setState(() => _saving = true);
    final Product draft = Product(
      id: _product?.id ?? '',
      merchantId: '',
      storeId: widget.shop.id,
      name: _title.text.trim(),
      description: _description.text.trim().isEmpty ? null : _description.text.trim(),
      price: _priceOf(_price.text)!,
      status: ProductStatus.draft,
      service: _termsFromForm(),
    );

    Product saved;
    try {
      saved = _product == null
          ? await widget.api.create(draft)
          : await widget.api.update(_product!.id, draft);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(
          content: Text(e.response?.statusCode == 422 ? t.svcOfferRefused : t.svcOfferSaveFailed)));
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(t.svcOfferSaveFailed)));
      return;
    }
    if (!mounted) return;
    setState(() {
      _product = saved;
      _options ??= _loadOptions();
    });

    final String? photoProblem = await _uploadPending(saved.id);
    if (_pendingImages.isEmpty) {
      try {
        // The server's copy, so the photo tiles show hosted images and the status is its own.
        saved = await widget.api.read(saved.id);
      } catch (_) {
        // The offer and its photos are saved; only the re-read failed.
      }
    }
    if (!mounted) return;
    setState(() => _product = saved);

    if (!publish) {
      setState(() => _saving = false);
      final bool live =
          saved.status == ProductStatus.active || saved.status == ProductStatus.paused;
      messenger.showSnackBar(
          SnackBar(content: Text(photoProblem ?? (live ? t.saved : t.svcDraftSaved))));
      return;
    }

    if (!svcHasPhoto(saved)) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(photoProblem ?? t.svcPhotoRequired)));
      return;
    }
    try {
      final Product live = saved.status == ProductStatus.paused
          ? await widget.api.resume(saved.id)
          : await widget.api.publish(saved.id);
      messenger.showSnackBar(SnackBar(content: Text(t.svcOfferPublished)));
      navigator.pop(live);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final bool delivers = _fulfilment?.includesDelivery ?? false;
      messenger.showSnackBar(SnackBar(
        content: Text(switch (e.response?.statusCode) {
          403 => t.svcPublishAfterApproval,
          422 => delivers && widget.deliveryReach != true
              ? t.svcDeliveryNeedsAreas
              : t.svcOfferRefused,
          _ => t.svcOfferSaveFailed,
        }),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(t.svcOfferSaveFailed)));
    }
  }

  /// Uploads the photos picked before the offer existed. Each that lands leaves the queue, so a retry
  /// repeats only what did not; answers a sentence when one failed.
  Future<String?> _uploadPending(String productId) async {
    for (final PickedImageBytes image in List<PickedImageBytes>.of(_pendingImages)) {
      try {
        await widget.api.uploadImage(
          productId: productId,
          bytes: image.bytes,
          contentType: image.contentType,
        );
        _pendingImages.remove(image);
      } catch (e) {
        if (!mounted) return null;
        return DeliveryStrings.of(context).uploadFailedBecause(productImageFailureReason(e));
      }
    }
    return null;
  }

  Future<void> _addImage() async {
    final PickedImageBytes? picked = await pickProductImage(context);
    if (picked == null || !mounted) return;
    final Product? product = _product;
    if (product == null) {
      setState(() => _pendingImages.add(picked));
      return;
    }
    final DeliveryStrings t = DeliveryStrings.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _uploading = true);
    try {
      await widget.api.uploadImage(
        productId: product.id,
        bytes: picked.bytes,
        contentType: picked.contentType,
      );
      final Product refreshed = await widget.api.read(product.id);
      if (!mounted) return;
      setState(() {
        _product = refreshed;
        _uploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      messenger.showSnackBar(
          SnackBar(content: Text(t.uploadFailedBecause(productImageFailureReason(e)))));
    }
  }

  Future<void> _removeImage(String objectKey) async {
    final Product product = _product!;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final DeliveryStrings t = DeliveryStrings.of(context);
    try {
      await widget.api.removeImage(productId: product.id, objectKey: objectKey);
      final Product refreshed = await widget.api.read(product.id);
      if (!mounted) return;
      setState(() => _product = refreshed);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(t.thatDidNotGoThrough)));
    }
  }

  Future<List<OptionGroup>>? _loadOptions() {
    final Product? product = _product;
    final StoreApi? store = widget.storeApi;
    if (product == null || store == null) return null;
    return store.productOptions(product.id);
  }

  /// The option editor, writing the whole structure back — the endpoint replaces, so the existing
  /// groups are read first and travel into the sheet, exactly as the product form does it.
  Future<void> _editOptions(DeliveryStrings t) async {
    final Product? product = _product;
    final StoreApi? store = widget.storeApi;
    if (product == null || store == null) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    List<OptionGroup> existing;
    try {
      existing = await store.productOptions(product.id);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(t.merchbOptionsLoadFailed)));
      return;
    }
    if (!mounted) return;
    final List<OptionGroupDraft>? edited = await showModalBottomSheet<List<OptionGroupDraft>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProductOptionsEditor(groups: existing.map(OptionGroupDraft.from).toList()),
    );
    if (edited == null || !mounted) return;

    setState(() => _savingOptions = true);
    try {
      await widget.api.setProductOptions(product.id, edited);
      if (!mounted) return;
      setState(() {
        _savingOptions = false;
        _options = _loadOptions();
      });
      messenger.showSnackBar(SnackBar(content: Text(t.saved)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingOptions = false);
      messenger.showSnackBar(SnackBar(content: Text(t.merchbOptionsSaveFailed)));
    }
  }

  Future<void> _onAction(_OfferAction action, DeliveryStrings t) async {
    final Product? product = _product;
    if (product == null) return;
    switch (action) {
      case _OfferAction.pause || _OfferAction.resume:
        final Product? moved = await svcToggleOffer(context, widget.api, product,
            deliveryReach: widget.deliveryReach);
        if (moved != null && mounted) setState(() => _product = moved);
      case _OfferAction.archive:
        final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
        final NavigatorState navigator = Navigator.of(context);
        final bool? sure = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            content: Text(t.svcArchiveConfirm),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(t.cancel)),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(t.svcArchiveOffer),
              ),
            ],
          ),
        );
        if (sure != true) return;
        try {
          await widget.api.archive(product.id);
          messenger.showSnackBar(SnackBar(content: Text(t.svcOfferArchived)));
          navigator.pop(true);
        } catch (_) {
          messenger.showSnackBar(SnackBar(content: Text(t.thatDidNotGoThrough)));
        }
    }
  }

  // ------------------------------------------------------------------ layout

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            MerchantScreenHeader(
              title: widget.existing == null ? t.svcNewOffer : t.svcEditOffer,
              onBack: () => Navigator.of(context).maybePop(),
              backSemanticLabel: t.back,
              trailing: _overflow(t),
            ),
            Expanded(
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.all(DeliverySpacing.md),
                  children: <Widget>[
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: merchantMaxContentWidth),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _fields(t),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _actions(t),
          ],
        ),
      ),
    );
  }

  Widget? _overflow(DeliveryStrings t) {
    final Product? product = _product;
    if (product == null) return null;
    return PopupMenuButton<_OfferAction>(
      tooltip: t.svcMoreActions,
      icon: const Icon(Icons.more_horiz_rounded, color: DeliveryColors.ink),
      onSelected: (_OfferAction action) => _onAction(action, t),
      itemBuilder: (_) => <PopupMenuEntry<_OfferAction>>[
        if (product.status == ProductStatus.active)
          PopupMenuItem<_OfferAction>(value: _OfferAction.pause, child: Text(t.svcPauseOffer)),
        if (product.status == ProductStatus.paused)
          PopupMenuItem<_OfferAction>(value: _OfferAction.resume, child: Text(t.svcResumeOffer)),
        PopupMenuItem<_OfferAction>(value: _OfferAction.archive, child: Text(t.svcArchiveOffer)),
      ],
    );
  }

  List<Widget> _fields(DeliveryStrings t) {
    const SizedBox gap = SizedBox(height: DeliverySpacing.md + DeliverySpacing.xs);
    final bool perUnit = _pricing == ServicePricingType.perUnit;
    final ServiceFulfilment? initialFulfilment =
        _terms?.fulfilmentModes == ServiceFulfilment.unknown ? null : _terms?.fulfilmentModes;
    final List<(int, int)> turnarounds = <(int, int)>[
      for (final SvcTurnaround preset in SvcTurnaround.values) (preset.minHours, preset.maxHours),
      // Hours no preset names, set some other way, stay a choice rather than being rewritten.
      if (_terms case ServiceTerms(
            turnaroundMinHours: final int min,
            turnaroundMaxHours: final int max,
          ) when SvcTurnaround.matching(min, max) == null)
        (min, max),
    ];

    return <Widget>[
      if (!_editable) ...<Widget>[SvcNotice(text: t.svcOfferNotEditable), gap],
      if (widget.pendingApproval) ...<Widget>[SvcNotice(text: t.svcPublishAfterApproval), gap],
      _Label(t.svcOfferTitle),
      TextFormField(
        controller: _title,
        textInputAction: TextInputAction.next,
        validator: (String? value) {
          final String text = (value ?? '').trim();
          if (text.isEmpty) return t.svcOfferTitleRequired;
          if (text.length > _maxTitle) return t.svcTooLong('$_maxTitle');
          return null;
        },
      ),
      gap,
      _Label(t.svcDescription),
      TextFormField(
        controller: _description,
        minLines: 3,
        maxLines: 6,
        validator: (String? value) => (value ?? '').trim().length > _maxDescription
            ? t.svcTooLong(svcThousands(_maxDescription))
            : null,
      ),
      gap,
      _Label(t.svcCategory),
      _category(t),
      gap,
      _Label(t.svcPriceLabel),
      TextFormField(
        controller: _price,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (String? value) => _priceOf(value ?? '') == null ? t.svcPriceInvalid : null,
      ),
      _lbpPreview(t),
      gap,
      _Label(t.svcPricingType),
      SvcChoiceField<ServicePricingType>(
        values: const <ServicePricingType>[
          ServicePricingType.fixed,
          ServicePricingType.perUnit,
          ServicePricingType.from,
        ],
        initialValue: _pricing,
        labelOf: (ServicePricingType type) => switch (type) {
          ServicePricingType.fixed => t.svcPricingFixed,
          ServicePricingType.perUnit => t.svcPricingPerUnit,
          ServicePricingType.from || ServicePricingType.unknown => t.svcPricingFrom,
        },
        requiredMessage: t.svcPricingType,
        onChanged: (ServicePricingType type) => setState(() {
          _pricing = type;
          // A price per unit is the price of one unit; the server refuses it in steps.
          if (type == ServicePricingType.perUnit) _packSize.text = '1';
        }),
      ),
      gap,
      _Label(t.svcUnitLabel),
      TextFormField(
        controller: _unitLabel,
        onChanged: (_) => setState(() {}),
        validator: (String? value) {
          final String text = (value ?? '').trim();
          final int? size = _packSizeValue;
          final bool needsUnit = perUnit || (size != null && size > 1);
          if (needsUnit && text.isEmpty) return t.svcUnitRequired;
          if (text.length > _maxUnitLabel) return t.svcTooLong('$_maxUnitLabel');
          return null;
        },
      ),
      const SizedBox(height: DeliverySpacing.sm),
      _Label(t.svcPackSize),
      TextFormField(
        controller: _packSize,
        enabled: !perUnit,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(helperText: perUnit ? t.svcPerUnitIsOne : null),
        validator: (String? value) {
          if (perUnit) return null;
          final int? size = int.tryParse(_ascii(value ?? ''));
          return size == null || size < 1 || size > _maxUnitSize
              ? t.svcPackSizeRange('1', svcThousands(_maxUnitSize))
              : null;
        },
      ),
      _packPreview(t),
      gap,
      _Label(t.svcPhotos),
      _photos(t),
      const SizedBox(height: DeliverySpacing.xs),
      Text(t.svcPhotoRequired, style: const TextStyle(fontSize: 12, color: DeliveryColors.faint)),
      gap,
      _Label(t.svcTurnaround),
      SvcChoiceField<(int, int)>(
        values: turnarounds,
        initialValue: _turnaround,
        chips: true,
        labelOf: ((int, int) hours) => svcTurnaroundWords(hours.$1, hours.$2, t)!,
        requiredMessage: t.svcTurnaroundRequired,
        onChanged: ((int, int) hours) => setState(() => _turnaround = hours),
      ),
      gap,
      _Label(t.svcFulfilment),
      SvcChoiceField<ServiceFulfilment>(
        values: const <ServiceFulfilment>[
          ServiceFulfilment.pickup,
          ServiceFulfilment.delivery,
          ServiceFulfilment.both,
        ],
        initialValue: _fulfilment,
        labelOf: (ServiceFulfilment mode) => switch (mode) {
          ServiceFulfilment.pickup => t.svcFulfilmentPickup,
          ServiceFulfilment.delivery => t.svcFulfilmentDelivery,
          ServiceFulfilment.both || ServiceFulfilment.unknown => t.svcFulfilmentBoth,
        },
        // Delivery only from a shop that reaches somebody. What the offer already has stays
        // selectable, so opening it cannot quietly change it.
        isEnabled: (ServiceFulfilment mode) =>
            !mode.includesDelivery || widget.deliveryReach != false || mode == initialFulfilment,
        requiredMessage: t.svcFulfilmentRequired,
        onChanged: (ServiceFulfilment mode) => setState(() => _fulfilment = mode),
      ),
      if (widget.deliveryReach == false) ...<Widget>[
        const SizedBox(height: DeliverySpacing.xs),
        Text(
          t.svcDeliveryNeedsAreas,
          style: TextStyle(fontSize: 12, color: DeliveryAccent.caution.onTint, height: 1.35),
        ),
      ],
      gap,
      _Label(t.svcCustomerFile),
      SvcChoiceField<ServiceAttachmentPolicy>(
        values: const <ServiceAttachmentPolicy>[
          ServiceAttachmentPolicy.none,
          ServiceAttachmentPolicy.optional,
          ServiceAttachmentPolicy.required,
        ],
        initialValue: _filePolicy,
        chips: true,
        labelOf: (ServiceAttachmentPolicy policy) => switch (policy) {
          ServiceAttachmentPolicy.none ||
          ServiceAttachmentPolicy.unknown =>
            t.svcCustomerFileNone,
          ServiceAttachmentPolicy.optional => t.svcCustomerFileOptional,
          ServiceAttachmentPolicy.required => t.svcCustomerFileRequired,
        },
        onChanged: (ServiceAttachmentPolicy policy) => setState(() => _filePolicy = policy),
      ),
      gap,
      _Label(t.svcInstructionsPrompt),
      TextFormField(
        controller: _prompt,
        decoration: InputDecoration(hintText: t.svcInstructionsPromptHint),
        validator: (String? value) =>
            (value ?? '').trim().length > _maxPrompt ? t.svcTooLong('$_maxPrompt') : null,
      ),
      if (widget.storeApi != null) ...<Widget>[gap, _optionsCard(t)],
      const SizedBox(height: DeliverySpacing.lg),
    ];
  }

  Widget _category(DeliveryStrings t) {
    final ServiceCategory? category = widget.shop.serviceCategory;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DeliverySpacing.md,
            vertical: DeliverySpacing.md - DeliverySpacing.xs,
          ),
          decoration: BoxDecoration(
            color: DeliveryColors.white,
            border: Border.all(color: DeliveryColors.border),
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
          ),
          child: Row(
            children: <Widget>[
              Icon(category?.icon ?? Icons.design_services_outlined,
                  size: 18, color: DeliveryColors.muted),
              const SizedBox(width: DeliverySpacing.sm),
              Expanded(
                child: Text(
                  category?.labelIn(t) ?? '—',
                  style: const TextStyle(fontSize: 14, color: DeliveryColors.ink),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: DeliverySpacing.xs),
        Text(
          t.svcCategoryOfShop,
          style: const TextStyle(fontSize: 12, color: DeliveryColors.faint),
        ),
      ],
    );
  }

  /// The dollar price in pounds, at the platform's rate, rounded to the thousand: shown, never
  /// typed, and gone when there is no rate or no valid price to convert.
  Widget _lbpPreview(DeliveryStrings t) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_price, MarketRates.instance]),
      builder: (BuildContext context, _) {
        final double? usd = _priceOf(_price.text);
        final String? lbp = usd == null ? null : svcLbp(usd, t);
        if (lbp == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: DeliverySpacing.sm),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DeliverySpacing.md,
              vertical: DeliverySpacing.sm,
            ),
            decoration: BoxDecoration(
              color: DeliveryColors.brandSoft,
              border: Border.all(color: DeliveryColors.brandLine),
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
            ),
            child: Text(
              t.svcLbpPreview(lbp),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: DeliveryColors.brand,
              ),
            ),
          ),
        );
      },
    );
  }

  /// "Customers order in steps of 500 cards", or "Per sqm" — what the customer's stepper will read.
  Widget _packPreview(DeliveryStrings t) {
    final String unit = _unitLabel.text.trim();
    if (unit.isEmpty) return const SizedBox.shrink();
    final String? words;
    if (_pricing == ServicePricingType.perUnit) {
      words = t.svcUnitPer(unit);
    } else {
      final int? size = _packSizeValue;
      words = size == null || size < 1
          ? null
          : t.svcPackPreview(t.svcUnitPack(svcThousands(size), unit));
    }
    if (words == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: DeliverySpacing.xs),
      child: Text(words, style: const TextStyle(fontSize: 12, color: DeliveryColors.muted)),
    );
  }

  Widget _photos(DeliveryStrings t) {
    final Product? product = _product;
    final List<String> urls = product?.imageUrls ?? const <String>[];
    return Wrap(
      spacing: DeliverySpacing.sm,
      runSpacing: DeliverySpacing.sm,
      children: <Widget>[
        for (int i = 0; i < urls.length; i++)
          ProductImageTile(
            url: urls[i],
            onRemove: !_saving && i < product!.imageRefs.length
                ? () => _removeImage(product.imageRefs[i])
                : null,
          ),
        for (int i = 0; i < _pendingImages.length; i++)
          PendingProductImageTile(
            bytes: _pendingImages[i].bytes,
            onRemove: _saving ? null : () => setState(() => _pendingImages.removeAt(i)),
          ),
        _AddPhotoTile(
          label: t.svcAddPhoto,
          busy: _uploading,
          onTap: _saving || _uploading ? null : _addImage,
        ),
      ],
    );
  }

  Widget _optionsCard(DeliveryStrings t) {
    final Product? product = _product;
    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  t.svcOptions,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                  ),
                ),
              ),
              TextButton(
                onPressed: product == null || _savingOptions ? null : () => _editOptions(t),
                child: Text(t.svcEditOptions),
              ),
            ],
          ),
          if (product == null)
            Text(
              t.svcOptionsAfterSave,
              style: const TextStyle(fontSize: 12, color: DeliveryColors.faint, height: 1.35),
            )
          else
            FutureBuilder<List<OptionGroup>>(
              future: _options,
              builder: (BuildContext context, AsyncSnapshot<List<OptionGroup>> snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 20,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: DeliveryColors.brand),
                      ),
                    ),
                  );
                }
                if (snap.hasError) {
                  return Text(
                    t.merchbOptionsLoadFailed,
                    style: const TextStyle(fontSize: 13, color: DeliveryColors.muted),
                  );
                }
                final List<OptionGroup> groups = snap.data ?? const <OptionGroup>[];
                return Text(
                  groups.isEmpty
                      ? t.svcNoOptions
                      : groups.map((OptionGroup g) => g.name).join(' · '),
                  style: const TextStyle(fontSize: 13, color: DeliveryColors.muted),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _actions(DeliveryStrings t) {
    final ProductStatus status = _product?.status ?? ProductStatus.draft;
    final bool live = status == ProductStatus.active || status == ProductStatus.paused;
    final bool enabled = _editable && !_saving;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(top: BorderSide(color: DeliveryColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(DeliverySpacing.md),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: merchantMaxContentWidth),
              child: live
                  ? YdPillButton(
                      label: t.svcSaveChanges,
                      busy: _saving,
                      onPressed: enabled ? () => _save(publish: false) : null,
                    )
                  : Row(
                      children: <Widget>[
                        Expanded(
                          child: YdPillButton.secondary(
                            label: t.svcSaveDraft,
                            onPressed: enabled ? () => _save(publish: false) : null,
                          ),
                        ),
                        const SizedBox(width: DeliverySpacing.sm),
                        Expanded(
                          child: YdPillButton(
                            label: t.svcPublishOffer,
                            busy: _saving,
                            // Publishing waits for approval; the notice at the top says so.
                            onPressed: enabled && !widget.pendingApproval
                                ? () => _save(publish: true)
                                : null,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The frame's field label: small, SemiBold, muted, above its field.
class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: DeliverySpacing.xs + 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: DeliveryColors.muted,
        ),
      ),
    );
  }
}

/// The frame's camera tile: add a photo.
class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.label, required this.busy, this.onTap});

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      enabled: onTap != null,
      excludeSemantics: true,
      child: Material(
        color: DeliveryColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          side: const BorderSide(color: DeliveryColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 104,
            height: 104,
            child: Center(
              child: busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.brand),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.photo_camera_outlined, color: DeliveryColors.muted),
                        const SizedBox(height: DeliverySpacing.xs),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: DeliveryColors.muted),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
