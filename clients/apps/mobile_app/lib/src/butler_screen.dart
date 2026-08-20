import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'address_sheet.dart';
import 'butler_requests_list.dart';
import 'cart.dart';
import 'delivery_address.dart';

/// Butler — the vertical with no catalog behind it.
///
/// Two jobs share this screen because they share a shape: a free-text description, two places, and
/// a price nobody can quote from a product table. They are kept as one form with a mode rather
/// than two screens, because the difference between them is three fields, not a different task.
///
/// The two differ in one way that matters: **buy** has a goods price discovered after purchase,
/// **send** has no goods price at all. That is why the budget field belongs to one and not the
/// other, and why they could not simply be merged.
///
/// The requests this creates are real. A shopper claims one, buys the goods, and reports what they
/// cost; the customer approves that price and only then does an order — and a charge — exist. The
/// list beside this form is where that answer is given.
class ButlerScreen extends StatefulWidget {
  const ButlerScreen({
    super.key,
    required this.addresses,
    required this.zoneApi,
    required this.api,
    required this.orderApi,
    required this.storeApi,
    required this.cart,
  });

  final DeliveryAddressStore addresses;

  /// Offered to the address sheet so a customer can say which area they are in.
  final DeliveryZoneApi zoneApi;
  final ButlerApi api;

  /// Threaded through so an approved errand can open as an ordinary order — which is exactly what
  /// it becomes the moment its price is agreed.
  final OrderApi orderApi;
  final StoreApi storeApi;
  final Cart cart;

  @override
  State<ButlerScreen> createState() => _ButlerScreenState();
}

class _ButlerScreenState extends State<ButlerScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Shared by both modes: what it is.
  final TextEditingController _what = TextEditingController();

  // Buy only.
  final TextEditingController _from = TextEditingController();
  final TextEditingController _budget = TextEditingController();

  // Send only.
  final TextEditingController _pickup = TextEditingController();
  final TextEditingController _recipient = TextEditingController();

  ButlerMode _mode = ButlerMode.buy;

  /// The fee, fetched rather than assumed. The server sets it and the customer sees it before
  /// committing to anything.
  late final Future<ButlerTerms> _terms = widget.api.terms();
  bool _submitting = false;

  /// Bumped after a successful submit so the list beside the form reloads and the new request is
  /// visible where its answer will eventually be needed.
  int _listVersion = 0;

  @override
  void dispose() {
    _what.dispose();
    _from.dispose();
    _budget.dispose();
    _pickup.dispose();
    _recipient.dispose();
    super.dispose();
  }

  /// Switching modes resets the form's validation state.
  ///
  /// Without this, errors raised against the fields of the mode you just left stay on screen
  /// against fields that are no longer there.
  void _setMode(ButlerMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _formKey.currentState?.reset();
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // The drop-off is the delivery address for both modes, so neither can be submitted without it.
    if (!widget.addresses.isSet) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DeliveryStrings.of(context).setAddressFirst)),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final String dropoff = widget.addresses.selected!.display;
      final ButlerRequest created = _mode == ButlerMode.buy
          ? await widget.api.requestPurchase(
              what: _what.text.trim(),
              dropoffAddress: dropoff,
              sourceHint: _blankToNull(_from.text),
              budgetCap: double.tryParse(_budget.text.trim()),
              contactPhone: _blankToNull(widget.addresses.selected!.notes),
            )
          : await widget.api.requestPickup(
              what: _what.text.trim(),
              pickupAddress: _pickup.text.trim(),
              dropoffAddress: dropoff,
              recipient: _blankToNull(_recipient.text),
            );

      if (!mounted) return;
      // Cleared rather than kept: the request now lives in the list below, and leaving the text in
      // place invites a second identical errand.
      _what.clear();
      _from.clear();
      _budget.clear();
      _pickup.clear();
      _recipient.clear();
      _formKey.currentState?.reset();
      setState(() => _listVersion++);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(created.mode == ButlerMode.buy
            ? DeliveryStrings.of(context).sentBuyConfirmation
            : DeliveryStrings.of(context).sentMoveConfirmation),
      ));
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_messageFor(e, DeliveryStrings.of(context)))));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// The service's own sentence where it has one — it knows things the client does not, like which
  /// field the two modes each require.
  static String _messageFor(DioException e, DeliveryStrings t) {
    final dynamic body = e.response?.data;
    if (body is Map && body['detail'] is String) return body['detail'] as String;
    if (e.response?.statusCode == 403) return t.cannotRequestErrands;
    return t.couldNotSendRequest;
  }

  static String? _blankToNull(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: AppBar(
        backgroundColor: DeliveryColors.brand,
        foregroundColor: DeliveryColors.white,
        elevation: 0,
        title: Text(DeliveryStrings.of(context).butler, style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(DeliverySpacing.md),
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(DeliverySpacing.md),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[DeliveryColors.brand, DeliveryColors.brandDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(DeliveryRadius.lg),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                      _mode == ButlerMode.buy
                          ? Icons.pedal_bike_rounded
                          : Icons.local_shipping_rounded,
                      color: Colors.white,
                      size: 34),
                  const SizedBox(width: DeliverySpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                            _mode == ButlerMode.buy
                                ? DeliveryStrings.of(context).butlerTagline
                                : DeliveryStrings.of(context).butlerMoveTagline,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16)),
                        const SizedBox(height: 3),
                        Text(
                          _mode == ButlerMode.buy
                              ? DeliveryStrings.of(context).butlerBlurb
                              : DeliveryStrings.of(context).butlerMoveBlurb,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12.5, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: DeliverySpacing.md),
            _modeSelector(),
            const SizedBox(height: DeliverySpacing.md),
            if (_mode == ButlerMode.buy) ...<Widget>[
              _field(
                controller: _what,
                label: DeliveryStrings.of(context).whatDoYouNeed,
                hint: DeliveryStrings.of(context).buyHint,
                icon: Icons.edit_note_rounded,
                maxLines: 3,
                validator: (String? v) => (v == null || v.trim().length < 8)
                    ? DeliveryStrings.of(context).buyValidator
                    : null,
              ),
              _field(
                controller: _from,
                label: DeliveryStrings.of(context).whereFromOptional,
                hint: DeliveryStrings.of(context).whereFromHint,
                icon: Icons.storefront_outlined,
              ),
              _field(
                controller: _budget,
                label: DeliveryStrings.of(context).budgetCapOptional,
                hint: '30.00',
                icon: Icons.payments_outlined,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (String? v) => (v == null || v.trim().isEmpty)
                    ? null
                    : (double.tryParse(v.trim()) == null ? DeliveryStrings.of(context).budgetValidator : null),
              ),
            ] else ...<Widget>[
              _field(
                controller: _what,
                label: DeliveryStrings.of(context).whatAreWeMoving,
                hint: DeliveryStrings.of(context).moveHint,
                icon: Icons.inventory_2_outlined,
                maxLines: 3,
                validator: (String? v) => (v == null || v.trim().length < 8)
                    ? DeliveryStrings.of(context).moveValidator
                    : null,
              ),
              // Required, unlike the buy flow's optional "where from": a rider cannot collect
              // something without being told where it is.
              _field(
                controller: _pickup,
                label: DeliveryStrings.of(context).pickUpFrom,
                hint: DeliveryStrings.of(context).pickUpHint,
                icon: Icons.my_location_rounded,
                maxLines: 2,
                validator: (String? v) => (v == null || v.trim().length < 6)
                    ? DeliveryStrings.of(context).pickUpValidator
                    : null,
              ),
              _field(
                controller: _recipient,
                label: DeliveryStrings.of(context).whoReceivesItOptional,
                hint: DeliveryStrings.of(context).receiverHint,
                icon: Icons.person_outline_rounded,
              ),
            ],
            const SizedBox(height: DeliverySpacing.sm),
            _addressRow(),
            const SizedBox(height: DeliverySpacing.lg),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: DeliveryColors.brand,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(DeliveryRadius.md)),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: DeliveryColors.white),
                      )
                    : Text(
                        _mode == ButlerMode.buy ? DeliveryStrings.of(context).requestAButler : DeliveryStrings.of(context).requestAPickup,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
            const SizedBox(height: DeliverySpacing.sm),
            // The fee, and — for a purchase — the plain fact that the goods price comes later. Said
            // before submitting rather than discovered at approval time.
            FutureBuilder<ButlerTerms>(
              future: _terms,
              builder: (BuildContext context, AsyncSnapshot<ButlerTerms> snapshot) {
                final String fee = snapshot.hasData
                    ? snapshot.data!.errandFee.toStringAsFixed(2)
                    : '—';
                return Text(
                  _mode == ButlerMode.buy
                      ? DeliveryStrings.of(context).errandFeeBuy(fee)
                      : DeliveryStrings.of(context).errandFeeMove(fee),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12, color: DeliveryColors.muted, height: 1.35),
                );
              },
            ),
            ButlerRequestsList(
              api: widget.api,
              orderApi: widget.orderApi,
              storeApi: widget.storeApi,
              cart: widget.cart,
              version: _listVersion,
            ),
            const SizedBox(height: DeliverySpacing.xl),
          ],
        ),
      ),
    );
  }

  /// The two jobs, side by side and equally weighted.
  ///
  /// Not a dropdown: there are exactly two, and which one you are in changes the whole form — that
  /// should be visible without opening anything.
  Widget _modeSelector() {
    return Row(
      children: <Widget>[
        Expanded(
          child: _modeCard(
            mode: ButlerMode.buy,
            icon: Icons.shopping_basket_outlined,
            title: DeliveryStrings.of(context).buyMeSomething,
            subtitle: DeliveryStrings.of(context).aShopperBuysIt,
          ),
        ),
        const SizedBox(width: DeliverySpacing.sm),
        Expanded(
          child: _modeCard(
            mode: ButlerMode.send,
            icon: Icons.local_shipping_outlined,
            title: DeliveryStrings.of(context).deliverYourStuff,
            subtitle: DeliveryStrings.of(context).youAlreadyHaveIt,
          ),
        ),
      ],
    );
  }

  Widget _modeCard({
    required ButlerMode mode,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final bool selected = _mode == mode;
    return Material(
      color: selected ? DeliveryColors.brandSoft : DeliveryColors.white,
      borderRadius: BorderRadius.circular(DeliveryRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        onTap: () => _setMode(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: DeliverySpacing.sm + 2, vertical: DeliverySpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
            border: Border.all(
              color: selected ? DeliveryColors.brand : DeliveryColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon,
                  size: 26,
                  color: selected ? DeliveryColors.brand : DeliveryColors.muted),
              const SizedBox(height: DeliverySpacing.xs + 2),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: selected ? DeliveryColors.brand : DeliveryColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 11.5, color: DeliveryColors.muted, height: 1.25),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addressRow() {
    return Material(
      color: DeliveryColors.white,
      borderRadius: BorderRadius.circular(DeliveryRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        onTap: () async {
          await showAddressSheet(context, widget.addresses, zoneApi: widget.zoneApi);
          if (mounted) setState(() {});
        },
        child: Container(
          padding: const EdgeInsets.all(DeliverySpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
            border: Border.all(color: DeliveryColors.border),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.place_outlined, color: DeliveryColors.muted),
              const SizedBox(width: DeliverySpacing.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(_mode == ButlerMode.buy ? DeliveryStrings.of(context).deliverTo : DeliveryStrings.of(context).dropOffAt,
                        style: const TextStyle(
                            fontSize: 11.5, color: DeliveryColors.muted)),
                    Text(widget.addresses.headerLabelOr(DeliveryStrings.of(context).setDeliveryAddress),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: DeliveryColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.md),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon),
          filled: true,
          fillColor: DeliveryColors.white,
        ),
        validator: validator,
      ),
    );
  }
}
