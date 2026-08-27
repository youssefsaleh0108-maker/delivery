import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'address_sheet.dart';
import 'cart.dart';
import 'delivery_address.dart';

/// Review the basket and place the order.
///
/// Laid out as the 2026-08 Figma redesign draws it (`customer-checkout`, node 3:471): a 56px white
/// header, a 24px body of three stacked sections — saved addresses as radio cards, the payment
/// strip, the order note — and a sticky white summary bar carrying the total on the start side and
/// the pill CTA on the end.
///
/// The total shown here is computed from cached catalog prices, and the server recomputes it from
/// the live catalog when the order is placed. They can legitimately differ if a merchant re-priced
/// mid-session, so the confirmation shows the SERVER's total rather than the one on this screen.
///
/// The basket recap the previous layout carried is gone, as in the design: the Basket screen this
/// is pushed from lists every line immediately before, and the money — the part that must not be a
/// surprise — is in the sticky bar the whole time.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.api,
    required this.cart,
    required this.addresses,
    this.zoneApi,
    this.geocodingApi,
    this.promo,
  });

  final OrderApi api;
  final Cart cart;
  final DeliveryAddressStore addresses;

  /// Passed straight through to the address sheet so the area picker appears when a new address is
  /// added from here. Optional so a test can pump this screen without a server.
  final DeliveryZoneApi? zoneApi;

  /// Passed straight through to the address sheet for the place search. Optional for the same
  /// reason as [zoneApi].
  final GeocodingApi? geocodingApi;

  /// The promo quote the basket validated, carried here so the code travels with the order and
  /// the sticky bar can show the same advisory total the basket showed. Only ever a VALID quote —
  /// the basket does not hand over a refused one. The discount that is billed is recomputed by
  /// the server at placement.
  final PromoQuote? promo;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  /// The address line the customer is delivering to, identifying one of the saved addresses.
  ///
  /// The line rather than an index: the recents list reorders itself whenever an address is picked,
  /// so an index would quietly come to mean a different address.
  String? _addressLine;

  /// Cash by default — the one method that moves real money. Card and wallet are selectable too,
  /// authorising against the DEV payment provider, and the strip labels them as test payments so
  /// nobody mistakes a dev authorisation for a charge.
  PaymentMethod _payment = PaymentMethod.cash;

  /// What the checkout strip offers, in the design's order: cash first, then the two dev-provider
  /// test methods.
  static const List<PaymentMethod> _methods = <PaymentMethod>[
    PaymentMethod.cash,
    PaymentMethod.card,
    PaymentMethod.wallet,
  ];

  /// The opaque instrument handle a real processor's SDK would mint on the device. The DEV
  /// provider deliberately never reads it, so a fixed marker is the honest value — there is no
  /// card to tokenise.
  static const String _devInstrumentToken = 'dev-test-instrument';

  bool _placing = false;

  @override
  void initState() {
    super.initState();
    // Pre-selects the address chosen on the home screen. Retyping it here was the whole reason that
    // header existed, and re-asking would invite the two answers to differ.
    final DeliveryAddress? chosen = widget.addresses.selected;
    _addressLine = chosen?.line;
    // The door instructions saved with the address, seeded into the note that travels with the
    // order — the order is the only thing the rider ever sees, so anything left only on the address
    // never reaches the door it describes.
    if (chosen?.notes != null && chosen!.notes!.isNotEmpty) {
      _notes.text = chosen.notes!;
    }
    widget.addresses.addListener(_onAddressesChanged);
  }

  @override
  void dispose() {
    widget.addresses.removeListener(_onAddressesChanged);
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Follows the store when the address sheet saves a new address.
  ///
  /// The sheet selects what it saved, so the newly added address is the one this screen should now
  /// be delivering to — the customer opened it in order to use it.
  void _onAddressesChanged() {
    if (!mounted) return;
    _choose(widget.addresses.selected?.line);
  }

  /// Points the screen at an address, and re-seeds the note that goes with it.
  ///
  /// The note follows the address rather than the session: "second buzzer, blue door" describes one
  /// door, and carrying it across to a different one is worse than losing it.
  void _choose(String? line) {
    setState(() {
      _addressLine = line;
      final DeliveryAddress? address = _address;
      _notes.text = address?.notes ?? '';
    });
  }

  /// The address the radio list currently names, or null when nothing is chosen yet.
  DeliveryAddress? get _address {
    final String? line = _addressLine;
    if (line == null) return null;
    for (final DeliveryAddress a in widget.addresses.recents) {
      if (a.line == line) return a;
    }
    // Selected but absent from recents cannot normally happen — selecting promotes into recents —
    // but a stale line must not silently resolve to somebody else's address.
    final DeliveryAddress? selected = widget.addresses.selected;
    return selected?.line == line ? selected : null;
  }

  Future<void> _addAddress() async {
    await showAddressSheet(context, widget.addresses,
        zoneApi: widget.zoneApi, geocodingApi: widget.geocodingApi);
    // The listener has already taken the sheet's answer; this only repaints if it saved nothing.
    if (mounted) setState(() {});
  }

  Future<void> _place() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final DeliveryAddress? address = _address;
    if (address == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.addressRequired)));
      return;
    }
    if (!_form.currentState!.validate()) return;

    // Read before the await below: re-selecting the address notifies the store, which re-seeds this
    // field, and reading it afterwards would send the address's saved note instead of what the
    // customer actually typed.
    final String notes = _notes.text.trim();

    setState(() => _placing = true);
    try {
      // Re-selects it unchanged, which promotes it to the top of the recents for next time.
      //
      // Unchanged is the point. Checkout used to write this screen's notes field back onto the
      // saved address, so an order-specific "ring twice, they are expecting me" quietly replaced
      // the door instructions the address had been carrying.
      await widget.addresses.select(address);

      final DeliveryOrder order = await widget.api.place(
        items: widget.cart.toOrderLines(),
        deliveryAddress: address.line,
        // The area comes from the address that was picked, so the two can no longer disagree the
        // way they could when the line was a free-text box sitting over a remembered zone id.
        deliveryZoneId: address.zoneId,
        contactPhone: _phone.text.trim(),
        notes: notes,
        paymentMethod: _payment,
        // The canonical code the server quoted, never raw field text. The discount is recomputed
        // at placement against the basket the server priced itself.
        promoCode: widget.promo?.code,
        // Non-cash goes to the DEV provider, which ignores the token by design — there is no
        // card SDK to mint a real one. A decline comes back as a 402 and the order is not placed.
        paymentInstrumentToken:
            _payment.needsProvider ? _devInstrumentToken : null,
        // The pin from the place picker, when the address has one. This is what gives the
        // tracking service a real point to measure the rider's ETA against.
        deliveryLatitude: address.latitude,
        deliveryLongitude: address.longitude,
      );
      widget.cart.clear();
      if (!mounted) return;
      Navigator.of(context).pop(order);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _placing = false);

      // 422 is the interesting case: an item went out of stock, was archived, or the basket somehow
      // spans two merchants. The server's message is specific, so show it rather than a generic one.
      final String message = switch (e.response?.statusCode) {
        // The server's own detail wins where it has one — it names the actual item — and only the
        // fallback is translated. A specific English sentence beats a vague Arabic one here.
        422 => (e.response?.data is Map<String, dynamic>
                ? (e.response!.data as Map<String, dynamic>)['detail'] as String?
                : null) ??
            t.itemNoLongerAvailable,
        // 402: the payment provider said no and the placement rolled back — there is no order.
        // The provider's own sentence names the reason when it sent one.
        402 => (e.response?.data is Map<String, dynamic>
                ? (e.response!.data as Map<String, dynamic>)['detail'] as String?
                : null) ??
            t.custPaymentDeclined,
        400 => t.checkDeliveryDetails,
        _ => t.couldNotPlaceOrder,
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<CartLine> lines = widget.cart.lines;

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(
        title: t.checkout,
        onBack: () => Navigator.of(context).maybePop(),
        backSemanticLabel: t.back,
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(DeliverySpacing.lg),
              children: <Widget>[
                _addressSection(t),
                const SizedBox(height: _sectionGap),
                _paymentSection(t),
                const SizedBox(height: _sectionGap),
                Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _notesSection(t),
                      const SizedBox(height: _sectionGap),
                      // Not drawn in the redesign, kept because the order carries it: a rider with
                      // no number to ring has to guess at a closed door. Written in the design's
                      // own section language rather than as a leftover Material field.
                      _fieldSection(
                        title: t.contactPhoneOptional,
                        child: TextFormField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          style: _fieldTextStyle,
                          decoration: _boxDecoration(t.contactPhoneOptional),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: DeliverySpacing.sm),
              ],
            ),
          ),
          _summaryBar(t, lines),
        ],
      ),
    );
  }

  /// 20px between top-level body sections, per the frame.
  static const double _sectionGap = 20;

  static const TextStyle _fieldTextStyle =
      TextStyle(fontSize: 13, color: DeliveryColors.ink, height: 1.4);

  /// The design's plain input box: white, 1px [DeliveryColors.border], radius 12, 12px padding,
  /// 13px placeholder in [DeliveryColors.faint].
  InputDecoration _boxDecoration(String hint) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: DeliveryColors.white,
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: DeliveryColors.faint, height: 1.4),
      contentPadding: const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
      border: border(DeliveryColors.border, 1),
      enabledBorder: border(DeliveryColors.border, 1),
      focusedBorder: border(DeliveryColors.brand, 1.5),
      errorBorder: border(DeliveryAccent.critical.color, 1),
      focusedErrorBorder: border(DeliveryAccent.critical.color, 1.5),
    );
  }

  // ------------------------------------------------------------------ section 1: where it goes

  Widget _addressSection(DeliveryStrings t) {
    final List<DeliveryAddress> saved = widget.addresses.recents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Title row: heading on the start side, the add action on the end — the design's inline
        // brand text link rather than a button, at SemiBold 13.
        YdSectionHeader(
          title: t.deliveryAddress,
          fontSize: 15,
          trailing: Semantics(
            button: true,
            child: InkWell(
              onTap: _addAddress,
              borderRadius: BorderRadius.circular(DeliveryRadius.sm),
              child: Padding(
                padding: const EdgeInsetsDirectional.all(DeliverySpacing.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.add_rounded, size: 14, color: DeliveryColors.brand),
                    const SizedBox(width: 2),
                    Text(
                      t.addANewAddress,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: DeliveryColors.brand,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        if (saved.isEmpty)
          // Nothing saved yet: the one card is the way to make one, so it says so rather than
          // showing an empty section with an action hidden in the title row.
          YdCard(
            onTap: _addAddress,
            child: Row(
              children: <Widget>[
                const Icon(Icons.add_location_alt_outlined,
                    size: 20, color: DeliveryColors.brand),
                const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
                Expanded(
                  child: Text(
                    t.chooseAnAddress,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: DeliveryColors.ink,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          for (int i = 0; i < saved.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            _addressCard(saved[i]),
          ],
      ],
    );
  }

  /// One saved address as the design's radio card: 16px padding, radius 16, a 20px radio with a
  /// 2px ring and a 10px dot when chosen, then a bold label over a 12px detail line.
  Widget _addressCard(DeliveryAddress address) {
    final bool selected = address.line == _addressLine;
    final String detail = _detail(address);

    return Semantics(
      selected: selected,
      button: true,
      child: YdCard(
        onTap: () => _choose(address.line),
        child: Row(
          children: <Widget>[
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? DeliveryColors.brand : DeliveryColors.border,
                  width: 2,
                ),
              ),
              child: selected
                  ? Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: DeliveryColors.brand,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    address.label == null || address.label!.isEmpty
                        ? address.line
                        : address.label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: DeliveryColors.ink,
                      height: 1.25,
                    ),
                  ),
                  if (detail.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: DeliveryColors.muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The street, area and door notes behind an address — everything the bold label does not carry.
  String _detail(DeliveryAddress address) => <String>[
        if (address.label != null && address.label!.isNotEmpty) address.line,
        if (address.zoneName != null && address.zoneName!.isNotEmpty) address.zoneName!,
        if (address.notes != null && address.notes!.isNotEmpty) address.notes!,
      ].join(' · ');

  // ------------------------------------------------------------------ section 2: how it is paid

  /// The payment strip: equal cards in the design's geometry, cash first.
  ///
  /// Card and wallet are selectable and authorise against the DEV payment provider — no real
  /// money moves — so each carries a "Test payment" caption, and choosing one puts the fuller
  /// sentence under the strip. Presenting a dev authorisation as a live charge would be a lie
  /// told in the shape of a feature; presenting it as a test payment is exactly what a tester
  /// needs.
  Widget _paymentSection(DeliveryStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          t.paymentMethod,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
            height: 1.25,
          ),
        ),
        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (int i = 0; i < _methods.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: _payCard(
                  icon: switch (_methods[i]) {
                    PaymentMethod.cash => Icons.attach_money_rounded,
                    PaymentMethod.card => Icons.credit_card,
                    PaymentMethod.wallet => Icons.account_balance_wallet_outlined,
                  },
                  label: _methods[i] == PaymentMethod.wallet
                      ? t.paymentWallet
                      : _methods[i].labelIn(t),
                  // The honesty caption: the dev provider moves no money, and the card says so.
                  caption: _methods[i].needsProvider ? t.custTestPayment : null,
                  selected: _payment == _methods[i],
                  onTap: () => setState(() => _payment = _methods[i]),
                ),
              ),
            ],
          ],
        ),
        if (_payment.needsProvider) ...<Widget>[
          const SizedBox(height: DeliverySpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.science_outlined, size: 14, color: DeliveryColors.muted),
              const SizedBox(width: DeliverySpacing.xs + 2),
              Expanded(
                child: Text(
                  t.paymentTestModeNote,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DeliveryColors.muted,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _payCard({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback? onTap,
    String? caption,
  }) {
    final Color foreground = selected ? DeliveryColors.ink : DeliveryColors.muted;

    return Semantics(
      button: onTap != null,
      selected: selected,
      child: Material(
        color: DeliveryColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          side: BorderSide(
            color: selected ? DeliveryColors.brand : DeliveryColors.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: DeliverySpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: foreground,
                          height: 1.2,
                        ),
                      ),
                      if (caption != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: DeliveryColors.faint,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ section 3: the note

  Widget _notesSection(DeliveryStrings t) {
    return _fieldSection(
      title: t.custOrderNotes,
      child: TextFormField(
        controller: _notes,
        maxLines: 3,
        minLines: 2,
        style: _fieldTextStyle,
        decoration: _boxDecoration(t.custOrderNotesHint),
      ),
    );
  }

  Widget _fieldSection({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
            height: 1.25,
          ),
        ),
        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        child,
      ],
    );
  }

  // ------------------------------------------------------------------ the sticky summary

  Widget _summaryBar(DeliveryStrings t, List<CartLine> lines) {
    // The same advisory number the basket showed: the validated code's quote off the cached
    // total. The server recomputes at placement and the confirmation shows ITS total.
    final double promoDiscount = widget.promo?.valid == true ? widget.promo!.discount : 0;
    final double payable = (widget.cart.total - promoDiscount)
        .clamp(0, double.infinity)
        .toDouble();

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(top: BorderSide(color: DeliveryColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(DeliverySpacing.lg),
          child: Row(
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    t.custTotalPrice,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DeliveryColors.faint,
                      height: 1.3,
                    ),
                  ),
                  Text(
                    payable.toStringAsFixed(2),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: DeliveryColors.brand,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              YdPillButton(
                label: t.custPlaceOrder,
                expand: false,
                busy: _placing,
                onPressed: _placing || lines.isEmpty ? null : _place,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
