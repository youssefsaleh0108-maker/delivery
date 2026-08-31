import 'dart:math' as math;

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'address_sheet.dart';
import 'split_complete_screen.dart';
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
    this.transferApi,
    this.splitApi,
  });

  final OrderApi api;
  final Cart cart;
  final DeliveryAddressStore addresses;

  /// The money surface: the locked rate, the wallet methods, and where the approved payment
  /// intent is recorded after placement. Optional so a test can pump this screen without a
  /// server; the screen then falls back to the display rate and cash-only.
  final TransferApi? transferApi;

  /// Closes the group split plan over the placed order and shows the All-Shares-Paid screen.
  /// Optional like [transferApi]; without it a split basket still checks out, just without the
  /// ceremony.
  final SplitApi? splitApi;

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

  // The old cash/card/wallet strip left with the Lebanese redesign: the method rows below offer
  // cash and whichever wallet transfers a connector will actually carry.

  // ------------------------------------------------------------- the Lebanese money surface

  /// The transfer service's LOCKED rate and rider-change promise. Null until fetched; the
  /// screen then leans on the display rate and draws no lock it cannot promise.
  TransferRate? _rate;

  /// Wallet methods some connector will actually carry (WHISH/OMT wire names). Empty until
  /// fetched, and empty keeps those rows undrawn — a method that shows and then fails is worse
  /// than one that never showed.
  List<String> _walletMethods = const <String>[];

  /// The wallet method chosen INSTEAD of a card/wallet row, or null when paying cash. Rides on
  /// top of [_payment]: the order itself is placed as the dev-provider wallet payment, and the
  /// transfer ledger records which instrument actually carried it.
  String? _walletChoice;

  /// The USD half of the cash split. Text so the field can be blank (= all USD).
  final TextEditingController _splitUsd = TextEditingController();

  Future<void> _loadMoney() async {
    final TransferApi? api = widget.transferApi;
    if (api == null) return;
    try {
      final TransferRate rate = await api.rate();
      final List<String> methods = await api.methods();
      if (!mounted) return;
      setState(() {
        _rate = rate;
        _walletMethods = methods.where((String m) => m != 'CASH_ON_DELIVERY').toList();
      });
    } catch (_) {
      // Cash-only, display rate. The screen stays usable.
    }
  }

  /// The opaque instrument handle a real processor's SDK would mint on the device. The DEV
  /// provider deliberately never reads it, so a fixed marker is the honest value — there is no
  /// card to tokenise.
  static const String _devInstrumentToken = 'dev-test-instrument';

  /// How fast the customer asked for it. Standard by default, and sent explicitly either way —
  /// an absent tier means STANDARD on the server, but saying so is what keeps this screen and the
  /// order agreeing when that default ever changes.
  ///
  /// The premium is priced entirely server-side from `delivery.orders.express-surcharge` and
  /// snapshotted onto the order at placement. **Nothing publishes that figure before an order
  /// exists** — there is no quote endpoint and, by the contract, never a surcharge field on the
  /// request — so this screen offers the choice and says a surcharge applies, and the amount is
  /// itemised on the receipt from the order's own `expressSurcharge`. A number guessed here would
  /// be a price the server never quoted.
  DeliveryTier _tier = DeliveryTier.standard;

  /// The two tiers, in the order the server declares them.
  static const List<DeliveryTier> _tiers = <DeliveryTier>[
    DeliveryTier.standard,
    DeliveryTier.express,
  ];

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
    _loadMoney();
  }

  @override
  void dispose() {
    widget.addresses.removeListener(_onAddressesChanged);
    _phone.dispose();
    _notes.dispose();
    _splitUsd.dispose();
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

    // The merchant's delivery circle, honoured before promising: when the shop declared a radius
    // and both pins exist, the spheroid decides. An address with no pin passes — the zones still
    // gate it, and refusing over information nobody has would block real orders.
    final StoreCard? shop = widget.cart.store;
    if (shop != null &&
        shop.deliveryRadiusMetres != null &&
        shop.latitude != null &&
        shop.longitude != null &&
        address.latitude != null &&
        address.longitude != null) {
      final double metres = _distanceMetres(shop.latitude!, shop.longitude!,
          address.latitude!, address.longitude!);
      if (metres > shop.deliveryRadiusMetres!) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t.custOutsideDeliveryArea(shop.name,
                (shop.deliveryRadiusMetres! / 1000).toStringAsFixed(1)))));
        return;
      }
    }

    // Read before the await below: re-selecting the address notifies the store, which re-seeds this
    // field, and reading it afterwards would send the address's saved note instead of what the
    // customer actually typed. The diaspora gift note, when one was written, rides in front — the
    // order's notes are the only thing that reaches the door.
    final String typed = _notes.text.trim();
    final String? gift = widget.cart.giftNote?.trim();
    final String notes = <String>[
      if (gift != null && gift.isNotEmpty) '🎁 $gift',
      if (typed.isNotEmpty) typed,
    ].join('\n');

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
        // Always sent, never inferred. The surcharge that follows from it is the server's to
        // price and the receipt's to itemise.
        deliveryTier: _tier,
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
      // The approved payment intent, into the transfer ledger with the locked rate — which
      // instrument actually carries the money (cash split, Whish, OMT), a fact the order's own
      // cash/wallet field is too coarse to hold. Best-effort by design: the order exists either
      // way, and cash collection reads the ledger only when a row is there to read.
      final TransferApi? transfers = widget.transferApi;
      if (transfers != null) {
        try {
          await transfers.initiate(
            orderId: order.id,
            method: _walletChoice ?? 'CASH_ON_DELIVERY',
            amountUsd: order.totalAmount,
            splitUsd:
                _payment == PaymentMethod.cash ? _splitUsdValue : null,
          );
        } catch (_) {
          // The ledger missed one intent; the order and its payment method stand.
        }
      }
      // A group split closes over its order and gets its All-Shares-Paid moment. Read before
      // clear() wipes it with the rest of the basket's order-scoped state.
      final String? planId = widget.cart.splitPlanId;
      if (planId != null && widget.splitApi != null) {
        try {
          final SplitPlan plan =
              await widget.splitApi!.attachOrder(planId, order.id);
          if (mounted) {
            await Navigator.of(context).push<void>(MaterialPageRoute<void>(
              builder: (BuildContext ctx) => SplitCompleteScreen(
                plan: plan,
                onTrack: () => Navigator.of(ctx).pop(),
              ),
            ));
          }
        } catch (_) {
          // The order stands; the ceremony can be skipped, the ledger cannot.
        }
      }
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
                _rateBanner(t),
                const SizedBox(height: _sectionGap),
                _addressSection(t),
                const SizedBox(height: _sectionGap),
                _tierSection(t),
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

  // ------------------------------------------------------------------ section 2: how fast

  /// The delivery tier: the same two-up card strip the payment section uses, because it is the
  /// same kind of decision — one of a short list, made once, in the same geometry.
  ///
  /// Express carries a caption saying a surcharge applies rather than a figure. The premium is a
  /// server config value snapshotted at placement and no endpoint publishes it beforehand, so the
  /// amount appears where the server first states it: on the receipt, itemised as its own line.
  Widget _tierSection(DeliveryStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          t.custDeliverySpeed,
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
            for (int i = 0; i < _tiers.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: _payCard(
                  icon: _tiers[i] == DeliveryTier.express
                      ? Icons.bolt_rounded
                      : Icons.schedule_rounded,
                  label: _tiers[i] == DeliveryTier.express
                      ? t.deliveryTierExpress
                      : t.deliveryTierStandard,
                  caption: _tiers[i] == DeliveryTier.express
                      ? t.custExpressSurchargeApplies
                      : null,
                  selected: _tier == _tiers[i],
                  onTap: () => setState(() => _tier = _tiers[i]),
                ),
              ),
            ],
          ],
        ),
        if (_tier == DeliveryTier.express) ...<Widget>[
          const SizedBox(height: DeliverySpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.info_outline, size: 14, color: DeliveryColors.muted),
              const SizedBox(width: DeliverySpacing.xs + 2),
              Expanded(
                child: Text(
                  t.custExpressNote,
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

  // ------------------------------------------------------------------ section 3: how it is paid

  /// The payment strip: equal cards in the design's geometry, cash first.
  ///
  /// Card and wallet are selectable and authorise against the DEV payment provider — no real
  /// money moves — so each carries a "Test payment" caption, and choosing one puts the fuller
  /// sentence under the strip. Presenting a dev authorisation as a live charge would be a lie
  /// told in the shape of a feature; presenting it as a test payment is exactly what a tester
  /// needs.
  /// The current LBP-per-USD figure the screen renders with: the transfer service's LOCKED rate
  /// when it answered, the display rate until then.
  double get _lbpRate => _rate?.lbpPerUsd ?? MarketRates.instance.lbpPerUsd;

  /// The frame's amber lock banner: the platform rate, promised.
  Widget _rateBanner(DeliveryStrings t) {
    final double rate = _lbpRate;
    if (rate <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF3D7),
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        border: Border.all(color: const Color(0xFFF2DFA4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.lock_rounded, size: 18, color: Color(0xFFB8860B)),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  t.custPlatformRate(_groupLbp(rate)),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t.custRateLocked,
                  style: const TextStyle(
                      fontSize: 11.5, color: DeliveryColors.muted, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _groupLbp(double amount) {
    final String digits = amount.round().toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  double get _orderTotal {
    final double promoDiscount = widget.promo?.discount ?? 0;
    return (widget.cart.total - promoDiscount).clamp(0, double.infinity).toDouble();
  }

  /// The USD half of the cash split: what was typed, clamped into [0, total]. Blank = all USD.
  double get _splitUsdValue {
    final double total = _orderTotal;
    final double typed = double.tryParse(_splitUsd.text.trim()) ?? total;
    return typed.clamp(0, total).toDouble();
  }

  /// The frame's Lebanese Split Payment card, drawn for cash only — a wallet transfer has no
  /// notes to mix. USD side is typed; the lira side is COMPUTED at the locked rate, because two
  /// editable halves that must sum is an argument waiting to happen.
  Widget _splitCard(DeliveryStrings t) {
    final double total = _orderTotal;
    final double rate = _lbpRate;
    if (total <= 0 || rate <= 0) return const SizedBox.shrink();
    final double usdPart = _splitUsdValue;
    final double lbpInUsd = total - usdPart;
    final double lbpFace = (lbpInUsd * rate / 1000).round() * 1000;
    final int pctUsd = total == 0 ? 100 : ((usdPart / total) * 100).round();

    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            t.custSplitPayment,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            t.custSplitBlurb,
            style: const TextStyle(
                fontSize: 12.5, color: DeliveryColors.muted, height: 1.4),
          ),
          const SizedBox(height: DeliverySpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      t.custPayInUsd,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DeliveryColors.muted,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _splitUsd,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixText: '\$ ',
                        hintText: total.toStringAsFixed(2),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DeliverySpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      t.custPayInLbp,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DeliveryColors.muted,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: lbpInUsd > 0
                                ? DeliveryColors.brand
                                : DeliveryColors.border),
                        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                      ),
                      child: Text(
                        'LBP ${_groupLbp(lbpFace)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: lbpInUsd > 0
                              ? DeliveryColors.brand
                              : DeliveryColors.faint,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md),
          Row(
            children: <Widget>[
              Text(
                t.custPctUsd(pctUsd),
                style: const TextStyle(
                    fontSize: 11, color: DeliveryColors.faint, height: 1.2),
              ),
              const Spacer(),
              Text(
                t.custPctLbp(100 - pctUsd),
                style: const TextStyle(
                    fontSize: 11, color: DeliveryColors.faint, height: 1.2),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 1 : usdPart / total,
              minHeight: 6,
              backgroundColor: DeliveryColors.brandSoft,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(DeliveryColors.brand),
            ),
          ),
          if ((_rate?.riderChangeLimitLbp ?? 0) > 0) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsetsDirectional.all(DeliverySpacing.sm + 2),
              decoration: BoxDecoration(
                color: DeliveryColors.brandSoft,
                borderRadius: BorderRadius.circular(DeliveryRadius.sm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.payments_outlined,
                      size: 15, color: DeliveryColors.brand),
                  const SizedBox(width: DeliverySpacing.sm),
                  Expanded(
                    child: Text(
                      t.custRiderChange(
                          _groupLbp(_rate!.riderChangeLimitLbp)),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: DeliveryColors.brand,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _paymentSection(DeliveryStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          t.custLocalPaymentMethods,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
            height: 1.25,
          ),
        ),
        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        // The frame's rows with radio circles: cash first, then whichever wallet transfers a
        // connector will actually carry. Whish/OMT ride the dev provider's order rail while the
        // transfer ledger records the real instrument — the test note below says so.
        _methodRow(
          t,
          icon: Icons.payments_outlined,
          label: t.custCashUsdLbp,
          selected: _payment == PaymentMethod.cash,
          onTap: () => setState(() {
            _payment = PaymentMethod.cash;
            _walletChoice = null;
          }),
        ),
        if (_walletMethods.contains('WHISH')) ...<Widget>[
          const SizedBox(height: DeliverySpacing.sm),
          _methodRow(
            t,
            icon: Icons.account_balance_wallet_outlined,
            label: t.custWhishTransfer,
            selected: _walletChoice == 'WHISH',
            onTap: () => setState(() {
              _payment = PaymentMethod.wallet;
              _walletChoice = 'WHISH';
            }),
          ),
        ],
        if (_walletMethods.contains('OMT')) ...<Widget>[
          const SizedBox(height: DeliverySpacing.sm),
          _methodRow(
            t,
            icon: Icons.currency_exchange,
            label: t.custOmtTransfer,
            selected: _walletChoice == 'OMT',
            onTap: () => setState(() {
              _payment = PaymentMethod.wallet;
              _walletChoice = 'OMT';
            }),
          ),
        ],
        if (_payment == PaymentMethod.cash) ...<Widget>[
          const SizedBox(height: DeliverySpacing.md),
          _splitCard(t),
        ],
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

  Widget _methodRow(DeliveryStrings t,
      {required IconData icon,
      required String label,
      required bool selected,
      required VoidCallback onTap}) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? DeliveryColors.brand : DeliveryColors.border,
                width: selected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
            ),
            child: Row(
              children: <Widget>[
                Icon(icon,
                    size: 20,
                    color:
                        selected ? DeliveryColors.brand : DeliveryColors.muted),
                const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected ? DeliveryColors.ink : DeliveryColors.muted,
                      height: 1.25,
                    ),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected ? DeliveryColors.brand : DeliveryColors.faint,
                ),
              ],
            ),
          ),
        ),
      ),
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

  // ------------------------------------------------------------------ section 4: the note

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
                // The frame prints the total on the button.
                label: t.custPlaceOrderAmount(
                    '\$${_orderTotal.toStringAsFixed(2)}'),
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

/// Great-circle distance in metres — the haversine, enough precision for a delivery circle.
double _distanceMetres(double lat1, double lng1, double lat2, double lng2) {
  const double earthRadius = 6371000;
  final double dLat = _rad(lat2 - lat1);
  final double dLng = _rad(lng2 - lng1);
  final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) * math.cos(_rad(lat2)) *
          math.sin(dLng / 2) * math.sin(dLng / 2);
  return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _rad(double deg) => deg * math.pi / 180;
