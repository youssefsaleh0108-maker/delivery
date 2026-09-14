import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'address_sheet.dart';
import 'cart.dart';
import 'delivery_address.dart';
import 'delivery_terms_book.dart';
import 'gift_hub_screen.dart';
import 'lebanese_phone.dart';
import 'order_placement.dart';

/// Gift Details (Figma 112:1830): the checkout for a basket somebody else receives.
///
/// It places through the same machinery as the regular checkout — one [OrderSubmission] under the
/// basket's own key ([Cart.checkoutKey]), sent by [OrderApi.place], with [OrderApi.mayHavePlaced]
/// deciding whether an unanswered send may have landed — and differs exactly where a gift differs:
///
/// * **Who receives it** is its own part of the order ([GiftDetails]): their name, a Lebanese
///   phone, the card, the wrap. The server shows that phone to the rider carrying the order and to
///   nobody else who does not need it; this phone remembers it with the recipient for next time.
/// * **Never cash.** Cash is collected at the door, from the person receiving it, and the server
///   refuses a cash gift — so no cash row is drawn. The methods offered are the server's own list
///   ([GiftTerms.paymentMethods]), labelled as test payments while the provider is the development
///   one, as the regular checkout labels them. Where that list is empty the screen says a gift
///   cannot be sent yet rather than drawing a button placement would only refuse.
/// * **Never queued for later.** The offline outbox takes cash orders only — a card or wallet hold
///   needs the provider while the customer waits — so a gift that cannot reach the platform is not
///   sent and not queued, and the screen says why ([DeliveryStrings.giftOfflineCannotWait]).
/// * **Today only.** Order Manager has no scheduling, so the screen says in one plain line that the
///   gift goes today while the shop is open — offering no day it cannot keep — and the order goes
///   STANDARD.
/// * **The card and the name are held to the server's own limits**, counted in UTF-16 units as Java
///   counts them, so a card full of emoji is stopped in the field rather than refused at placement.
///
/// **The total is honest or absent.** Goods; the delivery fee Order Manager will charge to the
/// chosen address when this phone knows it ([DeliveryTermsBook]) and a dash when it does not; the
/// wrap at the server's configured price; less a promo quote. With a promo the shop's flat fee stays
/// beside it, the regular checkout's rule, because that is the fee the code was quoted at — and when
/// the address is charged another, the screen says the total is confirmed at placement rather than
/// presenting a mixed figure as final. No express premium can appear: a gift is sent STANDARD. The
/// confirmation shows the server's own total either way.
class GiftCheckoutScreen extends StatefulWidget {
  const GiftCheckoutScreen({
    super.key,
    required this.api,
    required this.cart,
    required this.addresses,
    this.zoneApi,
    this.geocodingApi,
    this.promo,
    this.connectivity,
    this.deliveryTerms,
  });

  final OrderApi api;
  final Cart cart;

  /// The recipient is the selected address: chosen on the gift hub, or changed here.
  final DeliveryAddressStore addresses;
  final DeliveryZoneApi? zoneApi;
  final GeocodingApi? geocodingApi;

  /// The valid promo quote the basket carried, as the regular checkout takes it.
  final PromoQuote? promo;

  /// Whether the platform is reachable. Known unreachable, the screen says a gift cannot wait and
  /// sends nothing.
  final ValueListenable<bool>? connectivity;

  /// Where the delivery fee for the address's area comes from. Null shows a dash for any address
  /// with an area.
  final DeliveryTermsBook? deliveryTerms;

  @override
  State<GiftCheckoutScreen> createState() => _GiftCheckoutScreenState();
}

class _GiftCheckoutScreenState extends State<GiftCheckoutScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _note = TextEditingController();

  /// The server's gift terms. Null while loading or after a failure ([_termsFailed]); nothing that
  /// depends on them — the wrap price, the payment rows, the button — is drawn without them.
  GiftTerms? _terms;
  bool _termsFailed = false;
  PaymentMethod? _method;
  bool _placing = false;

  /// The address line the recipient fields were last filled from.
  String? _filledFrom;

  /// The development provider never reads the instrument token; a fixed marker is the honest value,
  /// exactly as the regular checkout sends.
  static const String _devInstrumentToken = 'dev-test-instrument';

  /// Order Manager's `@Size` limits on the recipient's name and on the card, in UTF-16 code units.
  static const int _nameLimit = 80;
  static const int _cardLimit = 240;

  @override
  void initState() {
    super.initState();
    _note.text = widget.cart.giftNote ?? '';
    _followAreaTerms();
    widget.addresses.addListener(_onAddressesChanged);
    _loadTerms();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filledFrom == null) _fillRecipientFrom(widget.addresses.selected);
  }

  @override
  void dispose() {
    widget.addresses.removeListener(_onAddressesChanged);
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Prefills who receives it from the address, where the address knows: the recipient a previous
  /// gift saved, or a label that names a person. Fields the address knows nothing about keep what
  /// was typed.
  void _fillRecipientFrom(DeliveryAddress? address) {
    if (address == null) return;
    _filledFrom = address.line;
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String? name = address.personName(t);
    if (name != null) _name.text = name;
    final String? phone = LebanesePhone.prefill(address.recipientPhone);
    if (phone != null) _phone.text = phone;
  }

  void _onAddressesChanged() {
    if (!mounted) return;
    final DeliveryAddress? selected = widget.addresses.selected;
    if (selected != null && selected.line != _filledFrom) _fillRecipientFrom(selected);
    setState(_followAreaTerms);
  }

  Future<void> _loadTerms() async {
    setState(() => _termsFailed = false);
    try {
      final GiftTerms terms = await widget.api.giftTerms();
      if (!mounted) return;
      setState(() {
        _terms = terms;
        _method = terms.paymentMethods.isEmpty ? null : terms.paymentMethods.first;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _termsFailed = true);
    }
  }

  // ------------------------------------------------------------------------------- the money

  /// The shop's terms for the chosen address's area, and the `storeId|zoneId` they answer for —
  /// the regular checkout's bookkeeping, for the one address this screen delivers to.
  ZoneTerms? _areaTerms;
  String? _areaTermsFor;

  void _followAreaTerms() {
    final DeliveryTermsBook? book = widget.deliveryTerms;
    final String? storeId = widget.cart.storeId;
    final String? zoneId = widget.addresses.selected?.zoneId;
    if (book == null || storeId == null || zoneId == null) {
      _areaTerms = null;
      _areaTermsFor = null;
      return;
    }
    final String pair = '$storeId|$zoneId';
    if (_areaTermsFor == pair) return;
    _areaTerms = book.known(storeId, zoneId);
    _areaTermsFor = pair;
    book.learn(storeId, zoneId).then((ZoneTerms? learned) {
      if (!mounted || _areaTermsFor != pair) return;
      setState(() => _areaTerms = learned);
    });
  }

  /// What Order Manager will charge to deliver to the chosen address before any waiver, or null when
  /// this phone cannot know it: the shop's flat fee for an address with no area, the area's fee
  /// from the shop's terms otherwise.
  double? get _serverDeliveryFee {
    final DeliveryAddress? address = widget.addresses.selected;
    final String? storeId = widget.cart.storeId;
    final StoreCard? shop = widget.cart.store;
    if (address == null || storeId == null || shop == null) return null;
    final String? zoneId = address.zoneId;
    if (zoneId == null) return shop.deliveryFee;
    final ZoneTerms? terms = _areaTerms;
    if (terms == null || !terms.served || _areaTermsFor != '$storeId|$zoneId') return null;
    return terms.deliveryFee;
  }

  /// What delivery adds on this screen: nothing when an offer waives it; with a promo, the flat fee
  /// the promo was quoted at; otherwise the address's fee, or null when unknown.
  double? get _deliveryFeeCharged {
    if (widget.cart.deliveryIsFree) return 0;
    if (widget.promo != null) return widget.cart.deliveryFee;
    return _serverDeliveryFee;
  }

  /// A promo quoted at a fee other than the one the address will be charged — the one case where
  /// the figure on screen is known not to be exactly the server's.
  bool get _promoAtAnotherFee {
    if (widget.promo == null || widget.cart.deliveryIsFree) return false;
    final double? fee = _serverDeliveryFee;
    return fee == null || (fee * 100).round() != (widget.cart.deliveryFee * 100).round();
  }

  double get _wrapFee => widget.cart.giftWrap ? (_terms?.wrapFee ?? 0) : 0;

  /// Goods and delivery less the discount, then the wrap — a promo code is never sized against the
  /// wrap. Null when the delivery fee is not known.
  double? get _total {
    final double? fee = _deliveryFeeCharged;
    if (fee == null) return null;
    final double discount = widget.promo?.discount ?? 0;
    final double goodsAndDelivery =
        (widget.cart.subtotal + fee - discount).clamp(0, double.infinity).toDouble();
    return goodsAndDelivery + _wrapFee;
  }

  static String _usd(double amount) => '\$${amount.toStringAsFixed(2)}';

  // ------------------------------------------------------------------------------- placing

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickAddress() async {
    await showAddressSheet(context, widget.addresses,
        zoneApi: widget.zoneApi, geocodingApi: widget.geocodingApi);
    if (mounted) setState(() {});
  }

  Future<void> _place() async {
    if (_placing) return;
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool fieldsValid = _form.currentState!.validate();
    final DeliveryAddress? address = widget.addresses.selected;
    if (address == null) {
      _say(t.addressRequired);
      return;
    }
    if (!fieldsValid) return;
    final PaymentMethod? method = _method;
    if (method == null) return;

    final StoreCard? shop = widget.cart.store;
    if (isOutsideDeliveryRadius(shop, address)) {
      _say(t.custOutsideDeliveryArea(
          shop!.name, (shop.deliveryRadiusMetres! / 1000).toStringAsFixed(1)));
      return;
    }
    // Known to be unreachable: a gift cannot wait for the connection, so nothing is sent and
    // nothing is queued — the customer is told why instead of spending a timeout finding out.
    if (widget.connectivity?.value == false) {
      _say(t.giftOfflineCannotWait);
      return;
    }

    final String name = _name.text.trim();
    final String phone = LebanesePhone.international(_phone.text)!;
    final String note = _note.text.trim();
    widget.cart.giftNote = note.isEmpty ? null : note;

    // One attempt per basket, under the basket's key, exactly as the regular checkout: backing out
    // after an unanswered try and sending again is recognised as the same attempt.
    final OrderSubmission submission = OrderSubmission(
      idempotencyKey: widget.cart.checkoutKey,
      items: widget.cart.toOrderLines(),
      deliveryAddress: address.line,
      deliveryZoneId: address.zoneId,
      // The recipient's door instructions saved with their address: the order is all the rider
      // sees. The card travels separately, in the gift.
      notes: address.notes,
      paymentMethod: method,
      deliveryTier: DeliveryTier.standard,
      promoCode: widget.promo?.code,
      paymentInstrumentToken: _devInstrumentToken,
      deliveryLatitude: address.latitude,
      deliveryLongitude: address.longitude,
      gift: GiftDetails(
        recipientName: name,
        recipientPhone: phone,
        message: note.isEmpty ? null : note,
        wrap: widget.cart.giftWrap,
      ),
    );

    setState(() => _placing = true);
    try {
      // Remembered with the recipient before the send, so the next gift to them is prefilled
      // whatever becomes of this one. Selecting also promotes them to the top of the recipients.
      await widget.addresses.select(address.withRecipient(name, phone));

      final PlaceOrderResult result = await widget.api.place(submission);
      final DeliveryOrder order;
      switch (result) {
        case OrderPlaced(order: final DeliveryOrder placed):
          order = placed;
        case OrderAlreadyPlaced(orderId: final String orderId):
          // An earlier try of this basket went through before it changed. That order is the truth.
          _say(t.offlineAlreadyPlaced);
          DeliveryOrder? existing;
          try {
            existing = await widget.api.read(orderId);
          } catch (_) {
            existing = null;
          }
          if (existing == null) {
            widget.cart.settleCheckout();
            if (mounted) Navigator.of(context).pop();
            return;
          }
          order = existing;
        case OrderPriceChanged() || ServiceOrderRefused() || ServicesDirectoryUnavailable():
          // Only ever the answer to a request that asserts a total, which this screen never sends —
          // or to a service order, which a gift never is.
          if (!mounted) return;
          setState(() => _placing = false);
          _say(t.couldNotPlaceOrder);
          return;
      }
      widget.cart.settleCheckout();
      if (!mounted) return;
      Navigator.of(context).pop(order);
    } on DioException catch (e) {
      // First, whether or not this screen is still up: a send that may have placed the gift pins
      // the basket's key, so whatever the customer does next cannot place a second one.
      final bool mayHavePlaced = OrderApi.mayHavePlaced(e);
      if (mayHavePlaced) widget.cart.markCheckoutUnconfirmed(submission.idempotencyKey);
      if (!mounted) return;
      setState(() => _placing = false);
      if (mayHavePlaced) {
        // Never "it didn't go through", and never an offer to send it later: trying again is safe,
        // because it sends this same attempt.
        _say(ConnectivityService.outcomeUnknown(e)
            ? '${t.offlineUnconfirmedRetry} ${t.giftOfflineCannotWait}'
            : t.offlineUnconfirmedRetry);
        return;
      }
      _say(placementRefusalMessage(e, t));
    }
  }

  // ------------------------------------------------------------------------------- layout

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<CartLine> lines = widget.cart.lines;
    const SizedBox gap = SizedBox(height: DeliverySpacing.md);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(
        title: t.giftDetailsTitle,
        subtitle: t.giftCheckoutSub,
        onBack: () => Navigator.of(context).maybePop(),
        backSemanticLabel: t.back,
        trailing: const GiftBrandChip(),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(DeliverySpacing.md),
          children: <Widget>[
            if (widget.connectivity != null)
              ValueListenableBuilder<bool>(
                valueListenable: widget.connectivity!,
                builder: (BuildContext context, bool online, Widget? _) => online
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(bottom: DeliverySpacing.md),
                        child: _notice(t.giftOfflineCannotWait),
                      ),
              ),
            _recipientCard(t),
            gap,
            _noteCard(t),
            if (_terms != null) ...<Widget>[gap, _wrapCard(t, _terms!)],
            gap,
            _paymentCard(t),
            gap,
            _summaryCard(t, lines),
            gap,
            YdPillButton(
              label: t.giftSendAndPay,
              busy: _placing,
              onPressed: _placing || lines.isEmpty || _method == null ? null : _place,
            ),
            const SizedBox(height: DeliverySpacing.lg),
          ],
        ),
      ),
    );
  }

  static Widget _notice(String text) {
    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
      decoration: BoxDecoration(
        color: DeliveryColors.brandSoft,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.wifi_off_rounded, size: 16, color: DeliveryColors.brand),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12, color: DeliveryColors.ink, height: 1.35)),
          ),
        ],
      ),
    );
  }

  static Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: DeliveryColors.muted,
            height: 1.25,
          ),
        ),
      );

  static InputDecoration _filled({String? hint}) {
    final OutlineInputBorder none = OutlineInputBorder(
      borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: DeliveryColors.background,
      counterText: '',
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: none,
      enabledBorder: none,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        borderSide: const BorderSide(color: DeliveryColors.brand),
      ),
    );
  }

  static const BoxDecoration _filledBox = BoxDecoration(
    color: DeliveryColors.background,
    borderRadius: BorderRadius.all(Radius.circular(DeliveryRadius.sm)),
  );

  Widget _recipientCard(DeliveryStrings t) {
    final DeliveryAddress? address = widget.addresses.selected;
    const SizedBox gap = SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs);
    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            t.giftRecipientInfo.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.faint,
              letterSpacing: 0.4,
              height: 1.2,
            ),
          ),
          gap,
          _fieldLabel(t.giftRecipientName),
          TextFormField(
            controller: _name,
            inputFormatters: const <TextInputFormatter>[_Utf16LengthLimit(_nameLimit)],
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 14, color: DeliveryColors.ink),
            decoration: _filled(),
            validator: (String? value) =>
                value == null || value.trim().isEmpty ? t.giftRecipientNameRequired : null,
          ),
          gap,
          _fieldLabel(t.giftRecipientPhone),
          // A phone number reads left to right in Arabic too, prefix first: the row is laid out left
          // to right, and the prefix and the number are written left to right. Only those — the
          // field's error is a sentence in the customer's language and keeps the ambient direction.
          Row(
            textDirection: TextDirection.ltr,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: _filledBox,
                child: const Text(LebanesePhone.countryCode,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: 14, color: DeliveryColors.ink)),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              Expanded(
                child: TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9 +\-]')),
                    LengthLimitingTextInputFormatter(20),
                  ],
                  style: const TextStyle(fontSize: 14, color: DeliveryColors.ink),
                  decoration: _filled(hint: '71 234 567')
                      .copyWith(hintTextDirection: TextDirection.ltr),
                  validator: (String? value) =>
                      LebanesePhone.nationalNumber(value ?? '') == null ? t.giftPhoneInvalid : null,
                ),
              ),
            ],
          ),
          gap,
          _fieldLabel(t.deliveryAddress),
          Material(
            color: DeliveryColors.background,
            borderRadius: BorderRadius.circular(DeliveryRadius.sm),
            child: InkWell(
              onTap: _pickAddress,
              borderRadius: BorderRadius.circular(DeliveryRadius.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.location_on_outlined, size: 16, color: DeliveryColors.brand),
                    const SizedBox(width: DeliverySpacing.sm),
                    Expanded(
                      child: Text(
                        address?.line ?? t.addressRequired,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: address == null ? DeliveryColors.muted : DeliveryColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          gap,
          _fieldLabel(t.giftDeliveryDate),
          // A line, not a choice. Order Manager has no scheduling and a closed shop refuses the
          // order, so a placed gift goes today while the shop is open — and no control offers a day
          // it cannot keep.
          Text(
            t.giftDeliveredToday,
            style: const TextStyle(fontSize: 13, color: DeliveryColors.ink, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _noteCard(DeliveryStrings t) {
    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            t.giftNoteTitle,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
              height: 1.3,
            ),
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          TextField(
            controller: _note,
            minLines: 3,
            maxLines: 5,
            // The server's limit for the card, counted as the server counts it: the field stops at
            // the limit rather than letting a placement fail on it.
            inputFormatters: const <TextInputFormatter>[_Utf16LengthLimit(_cardLimit)],
            style: const TextStyle(fontSize: 13, color: DeliveryColors.ink, height: 18 / 13),
            decoration: _filled(hint: t.custPersonalNoteHint),
            onChanged: (String value) =>
                widget.cart.giftNote = value.trim().isEmpty ? null : value.trim(),
          ),
          const SizedBox(height: DeliverySpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  t.giftNoteHelper,
                  style: const TextStyle(fontSize: 11, color: DeliveryColors.faint, height: 1.3),
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              // The count the limit uses, so the figure reaches its end exactly when the card does.
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _note,
                builder: (BuildContext context, TextEditingValue value, Widget? _) => Text(
                  t.giftNoteLength(value.text.length, _cardLimit),
                  style: const TextStyle(fontSize: 11, color: DeliveryColors.faint, height: 1.3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _wrapCard(DeliveryStrings t, GiftTerms terms) {
    return YdCard.bordered(
      child: Row(
        children: <Widget>[
          const Icon(Icons.redeem_outlined, size: 20, color: DeliveryColors.brand),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  t.giftWrapTitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t.giftWrapSubtitle(_usd(terms.wrapFee)),
                  style: const TextStyle(fontSize: 11, color: DeliveryColors.muted, height: 1.3),
                ),
              ],
            ),
          ),
          Switch(
            value: widget.cart.giftWrap,
            activeTrackColor: DeliveryColors.brand,
            activeThumbColor: DeliveryColors.white,
            onChanged: (bool value) => setState(() => widget.cart.giftWrap = value),
          ),
        ],
      ),
    );
  }

  Widget _paymentCard(DeliveryStrings t) {
    final GiftTerms? terms = _terms;
    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            t.giftPaymentTitle,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
              height: 1.3,
            ),
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          if (terms == null && !_termsFailed)
            const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.brand),
              ),
            )
          else if (terms == null)
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(t.giftTermsFailed,
                      style: const TextStyle(fontSize: 12, color: DeliveryColors.muted)),
                ),
                TextButton(onPressed: _loadTerms, child: Text(t.tryAgain)),
              ],
            )
          else if (!terms.canPay)
            Text(t.giftNoPaymentMethods,
                style: const TextStyle(fontSize: 12, color: DeliveryColors.ink, height: 1.4))
          else ...<Widget>[
            for (final PaymentMethod method in terms.paymentMethods) ...<Widget>[
              _methodRow(t, method),
              const SizedBox(height: DeliverySpacing.sm),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.science_outlined, size: 14, color: DeliveryColors.muted),
                const SizedBox(width: DeliverySpacing.xs + 2),
                Expanded(
                  child: Text(t.paymentTestModeNote,
                      style: const TextStyle(
                          fontSize: 12, color: DeliveryColors.muted, height: 1.35)),
                ),
              ],
            ),
          ],
          const SizedBox(height: DeliverySpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.volunteer_activism_outlined, size: 14, color: DeliveryColors.muted),
              const SizedBox(width: DeliverySpacing.xs + 2),
              Expanded(
                child: Text(t.giftCashNotAllowed,
                    style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.35)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _methodRow(DeliveryStrings t, PaymentMethod method) {
    final bool selected = _method == method;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? DeliveryColors.brandSoft : DeliveryColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          side: BorderSide(color: selected ? DeliveryColors.brand : DeliveryColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          onTap: () => setState(() => _method = method),
          child: Padding(
            padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
            child: Row(
              children: <Widget>[
                Icon(
                  method == PaymentMethod.wallet
                      ? Icons.account_balance_wallet_outlined
                      : Icons.credit_card,
                  size: 18,
                  color: selected ? DeliveryColors.brand : DeliveryColors.muted,
                ),
                const SizedBox(width: DeliverySpacing.sm + 2),
                Expanded(
                  child: Text(
                    method == PaymentMethod.wallet ? t.paymentWallet : method.labelIn(t),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: DeliveryColors.ink,
                    ),
                  ),
                ),
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 18,
                  color: selected ? DeliveryColors.brand : DeliveryColors.faint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryCard(DeliveryStrings t, List<CartLine> lines) {
    final double? fee = _deliveryFeeCharged;
    final double? total = _total;
    final String? lbp = total == null ? null : MarketRates.instance.lbp(total);
    final PromoQuote? promo = widget.promo;
    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            t.giftOrderSummary,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
              height: 1.3,
            ),
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          for (final CartLine line in lines)
            _summaryRow(t.giftLineQty(line.qty, line.product.name), _usd(line.lineTotal)),
          if (widget.cart.giftWrap && _terms != null)
            _summaryRow(t.giftWrapLine, _usd(_terms!.wrapFee)),
          _summaryRow(
            t.giftDeliveryFee,
            // A dash, never a guess, while the address's fee is not known.
            fee == null ? '—' : (fee == 0 ? t.free : _usd(fee)),
            valueColor: fee == 0 ? DeliveryAccent.positive.color : null,
          ),
          if (promo != null)
            _summaryRow(promo.code ?? t.custDiscounts, '-${_usd(promo.discount)}',
                valueColor: DeliveryAccent.positive.color),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: DeliverySpacing.sm),
            child: Divider(height: 1, color: DeliveryColors.border),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  t.giftTotalUsd,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    total == null ? '—' : _usd(total),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: DeliveryColors.brand,
                    ),
                  ),
                  if (lbp != null)
                    Text(t.giftApproxLbp(lbp),
                        style: const TextStyle(fontSize: 11, color: DeliveryColors.faint)),
                ],
              ),
            ],
          ),
          if (_promoAtAnotherFee) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Text(t.giftTotalConfirmed,
                style: const TextStyle(fontSize: 11, color: DeliveryColors.muted, height: 1.35)),
          ],
        ],
      ),
    );
  }

  static Widget _summaryRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.35)),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ?? DeliveryColors.ink,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// Holds a field to [max] UTF-16 code units — what Java's `String.length()`, and so Order Manager's
/// `@Size`, counts — and cuts only between whole characters.
///
/// Not Flutter's `maxLength`, which counts characters as a person sees them: an emoji is one there
/// and two here, so a card that field accepted could come back from placement as a 400 the customer
/// would read as "check delivery details".
class _Utf16LengthLimit extends TextInputFormatter {
  const _Utf16LengthLimit(this.max);

  final int max;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length <= max) return newValue;
    // Already full and typed at a caret: the keystroke is refused, not the end of the card trimmed.
    if (oldValue.text.length == max && oldValue.selection.isCollapsed) return oldValue;
    final StringBuffer kept = StringBuffer();
    for (final String character in newValue.text.characters) {
      if (kept.length + character.length > max) break;
      kept.write(character);
    }
    final String text = kept.toString();
    int within(int offset) => offset > text.length ? text.length : offset;
    return TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: within(newValue.selection.baseOffset),
        extentOffset: within(newValue.selection.extentOffset),
      ),
    );
  }
}
