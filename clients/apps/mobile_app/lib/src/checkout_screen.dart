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
/// The total shown here is computed from cached catalog prices, and the server recomputes it from
/// the live catalog when the order is placed. They can legitimately differ if a merchant re-priced
/// mid-session, so the confirmation shows the SERVER's total rather than the one on this screen.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.api,
    required this.cart,
    required this.addresses,
    this.zoneApi,
  });

  final OrderApi api;
  final Cart cart;
  final DeliveryAddressStore addresses;

  /// Passed straight through to the address sheet so the area picker appears when a new address is
  /// added from here. Optional so a test can pump this screen without a server.
  final DeliveryZoneApi? zoneApi;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  /// The sentinel the "add a new address" row carries.
  ///
  /// A dropdown value rather than a button beside the dropdown: adding an address is one of the
  /// choices of where to deliver, and splitting it out makes a customer with no saved address hunt
  /// for the control that does the only thing they can do.
  static const String _addNew = '__add_new__';

  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  /// The address line the customer is delivering to, identifying one of the saved addresses.
  ///
  /// The line rather than an index: the recents list reorders itself whenever an address is picked,
  /// so an index would quietly come to mean a different address.
  String? _addressLine;

  /// Cash, and only cash — see [PaymentMethod.offered]. Held in state rather than assumed so that
  /// adding a second method is a change to that list and not to this screen.
  PaymentMethod _payment = PaymentMethod.cash;

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

  /// The address the dropdown currently names, or null when nothing is chosen yet.
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
    await showAddressSheet(context, widget.addresses, zoneApi: widget.zoneApi);
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
      // the door instructions the address had been carrying — and now that the dropdown shows those
      // notes, it would replace them visibly.
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
        400 => t.checkDeliveryDetails,
        _ => t.couldNotPlaceOrder,
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<CartLine> lines = widget.cart.lines;
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(t.checkout)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(DeliverySpacing.md),
          children: <Widget>[
            _orderCard(context, t, lines),
            const SizedBox(height: DeliverySpacing.md),
            _addressCard(context, t),
            const SizedBox(height: DeliverySpacing.md),
            _paymentCard(context, t),
            const SizedBox(height: DeliverySpacing.md),
            Form(
              key: _form,
              child: Column(
                children: <Widget>[
                  TextFormField(
                    controller: _phone,
                    decoration: InputDecoration(
                      labelText: t.contactPhoneOptional,
                      prefixIcon: const Icon(Icons.phone_outlined),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: DeliverySpacing.md),
                  TextFormField(
                    controller: _notes,
                    decoration: InputDecoration(
                      labelText: t.merchantNotesOptional,
                      prefixIcon: const Icon(Icons.sticky_note_2_outlined),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(height: DeliverySpacing.xl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _placing || lines.isEmpty ? null : _place,
                child: Text(_placing
                    ? t.placing
                    : t.placeOrderWithTotal(widget.cart.total.toStringAsFixed(2))),
              ),
            ),
            const SizedBox(height: DeliverySpacing.sm),
          ],
        ),
      ),
    );
  }

  Widget _orderCard(BuildContext context, DeliveryStrings t, List<CartLine> lines) {
    return SoftCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(DeliverySpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(t.yourOrder, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: DeliverySpacing.sm),
            for (final CartLine line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: DeliverySpacing.xs),
                child: Row(
                  children: <Widget>[
                    // A multiplication sign, not the letter x: it needs no translating and reads
                    // the same in both scripts.
                    Text('${line.qty} × '),
                    Expanded(
                      child: Text(line.product.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Text((line.product.price * line.qty).toStringAsFixed(2)),
                  ],
                ),
              ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(t.total, style: Theme.of(context).textTheme.titleMedium),
                Text(widget.cart.total.toStringAsFixed(2),
                    style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Where it goes: picked from the addresses the customer has already saved.
  ///
  /// A dropdown rather than a text box. The address was already entered, with its area, in a sheet
  /// that validates both — retyping it here produced a second, unvalidated copy that could name a
  /// street in one area while carrying the zone id of another.
  Widget _addressCard(BuildContext context, DeliveryStrings t) {
    final List<DeliveryAddress> saved = widget.addresses.recents;
    final DeliveryAddress? address = _address;

    return SoftCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(DeliverySpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(t.deliverTo, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: DeliverySpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _addressLine,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: t.deliveryAddress,
                hintText: t.chooseAnAddress,
                prefixIcon: const Icon(Icons.place_outlined),
              ),
              items: <DropdownMenuItem<String>>[
                for (final DeliveryAddress a in saved)
                  DropdownMenuItem<String>(
                    value: a.line,
                    child: Text(a.display, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                DropdownMenuItem<String>(
                  value: _addNew,
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.add_location_alt_outlined,
                          size: 18, color: DeliveryColors.brand),
                      const SizedBox(width: DeliverySpacing.sm),
                      Flexible(
                        child: Text(t.addANewAddress,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: DeliveryColors.brand, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ],
              onChanged: (String? value) {
                if (value == _addNew) {
                  // Leaves the previous choice in place while the sheet is open, so cancelling out
                  // of it does not clear an address the customer had already picked.
                  _addAddress();
                  return;
                }
                _choose(value);
              },
            ),
            if (address != null && _detail(address).isNotEmpty) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.map_outlined, size: 15, color: DeliveryColors.muted),
                  const SizedBox(width: DeliverySpacing.xs + 2),
                  Expanded(
                    child: Text(_detail(address),
                        style: const TextStyle(fontSize: 12.5, color: DeliveryColors.muted)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The area and door notes behind the chosen address, so what the dropdown row could not fit is
  /// still visible before the order is placed.
  String _detail(DeliveryAddress address) => <String>[
        if (address.zoneName != null && address.zoneName!.isNotEmpty) address.zoneName!,
        if (address.notes != null && address.notes!.isNotEmpty) address.notes!,
      ].join(' · ');

  /// How it gets paid for.
  ///
  /// One method today, and shown as a chosen option rather than as a note at the bottom of the
  /// screen: "cash on delivery" is something the customer needs before they commit, not a footnote
  /// after they have.
  Widget _paymentCard(BuildContext context, DeliveryStrings t) {
    return SoftCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(DeliverySpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(t.paymentMethod, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: DeliverySpacing.sm),
            for (final PaymentMethod method in PaymentMethod.offered)
              _paymentTile(context, t, method),
          ],
        ),
      ),
    );
  }

  Widget _paymentTile(BuildContext context, DeliveryStrings t, PaymentMethod method) {
    final bool selected = _payment == method;
    return InkWell(
      borderRadius: BorderRadius.circular(DeliveryRadius.md),
      onTap: () => setState(() => _payment = method),
      child: Container(
        padding: const EdgeInsets.all(DeliverySpacing.sm + 2),
        decoration: BoxDecoration(
          color: selected ? DeliveryColors.brandSoft : DeliveryColors.white,
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          border: Border.all(color: selected ? DeliveryColors.brand : DeliveryColors.border),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              method == PaymentMethod.cash
                  ? Icons.payments_outlined
                  : Icons.credit_card_outlined,
              color: selected ? DeliveryColors.brand : DeliveryColors.muted,
            ),
            const SizedBox(width: DeliverySpacing.sm + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(method.labelIn(t),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                  const SizedBox(height: 1),
                  Text(method.descriptionIn(t),
                      style: const TextStyle(fontSize: 12, color: DeliveryColors.muted)),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 20,
              color: selected ? DeliveryColors.brand : DeliveryColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}
