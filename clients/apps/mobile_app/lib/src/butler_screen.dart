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
///
/// Drawn to `butler-page` (Figma 20:4): the white header with its search box, the prompt, the two
/// task cards, and the recent-tasks card. The frame draws no form — a task has to be described
/// before anybody can be sent to do it — so the fields sit between the cards and the history, in
/// the same bordered-card language as everything else on the page.
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

  /// The header's search box. There is no task-search endpoint; it filters the history below.
  final TextEditingController _search = TextEditingController();
  String _query = '';

  ButlerMode _mode = ButlerMode.buy;

  /// The fee, fetched rather than assumed. The server sets it and the customer sees it before
  /// committing to anything.
  late final Future<ButlerTerms> _terms = widget.api.terms();
  bool _submitting = false;

  /// Bumped after a successful submit so the list beside the form reloads and the new request is
  /// visible where its answer will eventually be needed.
  int _listVersion = 0;

  static const double _gutter = DeliverySpacing.lg;

  @override
  void dispose() {
    _what.dispose();
    _from.dispose();
    _budget.dispose();
    _pickup.dispose();
    _recipient.dispose();
    _search.dispose();
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
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _header(),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                      _gutter, DeliverySpacing.md, _gutter, DeliverySpacing.lg),
                  children: <Widget>[
                    Text(
                      t.custChooseWhatYouNeed,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: DeliveryColors.muted,
                      ),
                    ),
                    const SizedBox(height: DeliverySpacing.md),
                    _modeRow(),
                    const SizedBox(height: DeliverySpacing.md),
                    _formCard(),
                    const SizedBox(height: DeliverySpacing.md),
                    ButlerRequestsList(
                      api: widget.api,
                      orderApi: widget.orderApi,
                      storeApi: widget.storeApi,
                      cart: widget.cart,
                      version: _listVersion,
                      query: _query,
                    ),
                    const SizedBox(height: DeliverySpacing.lg),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The white `butler-header`: the centred title and, under it, the search box.
  ///
  /// The frame draws a back chip on the start side. Butler is a root tab in this app — there is
  /// nothing behind it to go back to — so the slot is left empty and the title keeps its place.
  Widget _header() {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Container(
      width: double.infinity,
      color: DeliveryColors.white,
      padding: const EdgeInsetsDirectional.fromSTEB(
          _gutter, DeliverySpacing.md - 4, _gutter, DeliverySpacing.md),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 32,
            child: Center(
              child: Text(
                t.custButlerTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.ink,
                ),
              ),
            ),
          ),
          const SizedBox(height: DeliverySpacing.md - 4),
          YdSearchField(
            controller: _search,
            hintText: t.custSearchTasksHint,
            onChanged: (String value) => setState(() => _query = value),
            searchSemanticLabel: t.custSearchTasksHint,
          ),
        ],
      ),
    );
  }

  /// The two jobs, side by side and equally weighted.
  ///
  /// Not a dropdown: there are exactly two, and which one you are in changes the whole form — that
  /// should be visible without opening anything.
  Widget _modeRow() {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: _modeCard(
              mode: ButlerMode.buy,
              icon: Icons.shopping_cart_outlined,
              title: t.custBuyAnything,
              subtitle: t.custBuyAnythingBlurb,
            ),
          ),
          const SizedBox(width: DeliverySpacing.md - 4),
          Expanded(
            child: _modeCard(
              mode: ButlerMode.send,
              icon: Icons.inventory_2_outlined,
              title: t.custSendAnything,
              subtitle: t.custSendAnythingBlurb,
            ),
          ),
        ],
      ),
    );
  }

  /// `butler-card`: a 28px glyph over a Bold 15 title and an 11px caption. Selected takes the
  /// brand tint and a brand hairline; the other stays white on the ordinary border.
  Widget _modeCard({
    required ButlerMode mode,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final bool selected = _mode == mode;
    final BorderRadius corners = BorderRadius.circular(DeliveryRadius.lg);

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? DeliveryColors.brandSoft : DeliveryColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: corners,
          side: BorderSide(
              color: selected ? DeliveryColors.brand : DeliveryColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _setMode(mode),
          child: Padding(
            padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 28, color: DeliveryColors.brand),
                const SizedBox(height: DeliverySpacing.sm),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                      fontSize: 11, color: DeliveryColors.muted, height: 1.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// What the errand is, where it comes from, and where it goes.
  Widget _formCard() {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (_mode == ButlerMode.buy) ...<Widget>[
            _field(
              controller: _what,
              label: t.whatDoYouNeed,
              hint: t.buyHint,
              icon: Icons.edit_note_outlined,
              maxLines: 3,
              validator: (String? v) =>
                  (v == null || v.trim().length < 8) ? t.buyValidator : null,
            ),
            _field(
              controller: _from,
              label: t.whereFromOptional,
              hint: t.whereFromHint,
              icon: Icons.storefront_outlined,
            ),
            _field(
              controller: _budget,
              label: t.budgetCapOptional,
              hint: '30.00',
              icon: Icons.payments_outlined,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (String? v) => (v == null || v.trim().isEmpty)
                  ? null
                  : (double.tryParse(v.trim()) == null ? t.budgetValidator : null),
            ),
          ] else ...<Widget>[
            _field(
              controller: _what,
              label: t.whatAreWeMoving,
              hint: t.moveHint,
              icon: Icons.inventory_2_outlined,
              maxLines: 3,
              validator: (String? v) =>
                  (v == null || v.trim().length < 8) ? t.moveValidator : null,
            ),
            // Required, unlike the buy flow's optional "where from": a rider cannot collect
            // something without being told where it is.
            _field(
              controller: _pickup,
              label: t.pickUpFrom,
              hint: t.pickUpHint,
              icon: Icons.my_location_outlined,
              maxLines: 2,
              validator: (String? v) =>
                  (v == null || v.trim().length < 6) ? t.pickUpValidator : null,
            ),
            _field(
              controller: _recipient,
              label: t.whoReceivesItOptional,
              hint: t.receiverHint,
              icon: Icons.person_outline,
            ),
          ],
          _addressRow(),
          const SizedBox(height: DeliverySpacing.md),
          YdPillButton(
            label: _mode == ButlerMode.buy ? t.requestAButler : t.requestAPickup,
            busy: _submitting,
            onPressed: _submitting ? null : _submit,
          ),
          const SizedBox(height: DeliverySpacing.sm),
          // The fee, and — for a purchase — the plain fact that the goods price comes later. Said
          // before submitting rather than discovered at approval time.
          FutureBuilder<ButlerTerms>(
            future: _terms,
            builder: (BuildContext context, AsyncSnapshot<ButlerTerms> snapshot) {
              final String fee =
                  snapshot.hasData ? snapshot.data!.errandFee.toStringAsFixed(2) : '—';
              return Text(
                _mode == ButlerMode.buy ? t.errandFeeBuy(fee) : t.errandFeeMove(fee),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 11, color: DeliveryColors.faint, height: 1.35),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _addressRow() {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Material(
      color: DeliveryColors.background,
      borderRadius: BorderRadius.circular(DeliveryRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await showAddressSheet(context, widget.addresses, zoneApi: widget.zoneApi);
          if (mounted) setState(() {});
        },
        child: Padding(
          padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
          child: Row(
            children: <Widget>[
              const Icon(Icons.location_on_outlined, size: 20, color: DeliveryColors.brand),
              const SizedBox(width: DeliverySpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(_mode == ButlerMode.buy ? t.deliverTo : t.dropOffAt,
                        style: const TextStyle(
                            fontSize: 12, color: DeliveryColors.faint, height: 1.25)),
                    Text(
                      widget.addresses.headerLabelOr(t.setDeliveryAddress),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: DeliveryColors.ink,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.chevron_left
                    : Icons.chevron_right,
                size: 18,
                color: DeliveryColors.faint,
              ),
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
      padding: const EdgeInsetsDirectional.only(bottom: DeliverySpacing.md),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 14, color: DeliveryColors.ink),
        cursorColor: DeliveryColors.brand,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 14, color: DeliveryColors.faint),
          labelStyle: const TextStyle(fontSize: 14, color: DeliveryColors.muted),
          floatingLabelStyle: const TextStyle(color: DeliveryColors.brand),
          prefixIcon: Icon(icon, size: 18, color: DeliveryColors.faint),
          filled: true,
          fillColor: DeliveryColors.background,
          contentPadding: const EdgeInsetsDirectional.symmetric(
              horizontal: DeliverySpacing.md - DeliverySpacing.xs,
              vertical: DeliverySpacing.md - DeliverySpacing.xs),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
            borderSide: const BorderSide(color: DeliveryColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
            borderSide: const BorderSide(color: DeliveryColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
            borderSide: const BorderSide(color: DeliveryColors.brand),
          ),
        ),
        validator: validator,
      ),
    );
  }
}
