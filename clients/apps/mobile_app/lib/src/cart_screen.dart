import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'basket_quote.dart';
import 'cart.dart';
import 'checkout_screen.dart';
import 'delivery_terms_book.dart';
import 'gift_checkout_screen.dart';
import 'order_outbox.dart';
import 'split_add_friend_sheet.dart';
import 'split_status_screen.dart';
import 'delivery_address.dart';
import 'product_detail_screen.dart' show CustomerPhoto, QuantityStepper;
import 'product_options_sheet.dart';

/// The basket (Figma `customer-basket`, node 3:389), and the Smart Basket it becomes when it holds
/// several shops (Figma `multi-merchant-cart`, node 121:358).
///
/// One shop: a white header, the lines as cards with a stepper each, the promo row, and then the
/// money — itemised on a white plinth with the checkout button under it.
///
/// Several shops: the header names the basket and counts its shops, and each shop's lines sit in a
/// bordered card of their own under "FROM {SHOP} (n ITEMS)", with that shop's delivery fee and —
/// when the server says so — why its part cannot be checked out yet (under its minimum, closed, not
/// delivering to the address), beside a way to take that shop out. The frame draws the lines
/// read-only; the steppers stay, because this is where quantities are changed.
///
/// **Every figure is the server's** (`POST /api/orders/quote`, kept current by a [BasketQuoter]):
/// the fee for the selected address's area, each shop's minimum for it, any waiver, and what the
/// promo code is worth on this basket — so the total here is the total checkout charges. Before the
/// server has answered, or when it cannot, a one-shop basket shows its card's figures where those
/// are the platform's own (an address with no area) and a dash where they are not; a basket from
/// several shops shows dashes, and is not checked out until the server has priced it.
///
/// **What the frame draws and this does not:** a "Unified Delivery Fee" and a "You save" badge
/// beside the struck-through sum of every shop's fee. The platform has no bundle price — each
/// shop's order is priced, dispatched and settled on its own, so the customer pays each shop's own
/// fee — and a saving the server does not give is not shown. The checkout button carries the full
/// total, delivery included, which the frame's "$34.50" (the goods alone) did not.
///
/// The promo code the customer types is judged by that same quote as they type (debounced), and
/// travels with the order at placement, where the discount is decided again. Nothing here trusts a
/// figure for money; it only decides what the summary shows.
class CartScreen extends StatefulWidget {
  const CartScreen({
    super.key,
    required this.cart,
    required this.addresses,
    required this.orderApi,
    required this.offerApi,
    required this.onOrderPlaced,
    this.zoneApi,
    this.transferApi,
    this.splitApi,
    this.profileApi,
    this.session,
    this.geocodingApi,
    this.outbox,
    this.connectivity,
    this.deliveryTerms,
    this.showing = true,
  });

  final Cart cart;
  final DeliveryAddressStore addresses;
  final OrderApi orderApi;

  /// Handed to checkout so a new address added there can still pick its area.
  final DeliveryZoneApi? zoneApi;

  /// Used to re-ask what the basket qualifies for when its contents change on this screen.
  final OfferApi offerApi;

  /// Checkout's money surface (rate lock, split, wallet methods). Optional so the screen still
  /// builds without a server behind it, as a test pumps it.
  final TransferApi? transferApi;

  /// The group split flow (Figma 83:*). All three arrive together or the Split tab stays
  /// undrawn: the toggle without the APIs behind it would be a promise with nothing under it.
  final SplitApi? splitApi;
  final ProfileApi? profileApi;
  final AuthSession? session;

  /// Handed through to checkout's address sheet for the place search. Optional for the same
  /// reason as [transferApi].
  final GeocodingApi? geocodingApi;

  /// Handed to checkout, which queues a checkout here when the platform cannot be reached.
  /// Optional for the same reason as [transferApi]; without it checkout offers no queue.
  final OrderOutbox? outbox;

  /// Handed to checkout, so it knows the platform is unreachable before it tries.
  final ValueListenable<bool>? connectivity;

  /// Handed to checkout, which prices delivery to an address's area from it when the platform
  /// cannot quote. Optional for the same reason as [transferApi].
  final DeliveryTermsBook? deliveryTerms;

  /// After a placement AND after a checkout is queued: either way the customer's next question is
  /// "where is it?", and the Orders tab is where both answers live.
  final VoidCallback onOrderPlaced;

  /// Whether the Basket tab is the one on screen.
  ///
  /// The shell builds every tab at once and keeps them alive (an IndexedStack), so this screen is in
  /// the tree while the customer shops on another tab. Its price follows the basket and the address,
  /// and without this every add on a shop page and every change of address asked Order Manager for a
  /// whole quote nobody was looking at. A hidden basket asks nothing: it asks once as it comes on
  /// screen, and follows every change from then on — including under a checkout pushed from it,
  /// which is where the customer comes back to. True by default, for a basket shown on its own.
  final bool showing;

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  static const double _gutter = DeliverySpacing.lg;

  /// What a figure the platform has not given reads as: a dash, never a zero or a guess.
  static const String _dash = '—';

  final TextEditingController _promo = TextEditingController();

  /// The server's price for this basket, delivered to the selected address, with the code in the
  /// promo field — kept current as any of the three changes.
  late final BasketQuoter _quoter = BasketQuoter(widget.orderApi);

  @override
  void initState() {
    super.initState();
    // Asked first and listened to after, so the first ask's own notification does not rebuild a
    // screen that has not been built yet.
    _askForQuote();
    _quoter.addListener(_onQuote);
    // A basket edit changes every figure — crossing a shop's minimum or an offer's is exactly the
    // moment the summary must change — and so does another delivery address, priced by its area.
    widget.cart.addListener(_askForQuote);
    widget.addresses.addListener(_askForQuote);
  }

  @override
  void didUpdateWidget(CartScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // On screen again: the basket and the address may both have changed while it was hidden, and
    // nothing asked about them then.
    if (widget.showing && !oldWidget.showing) _askForQuote();
  }

  @override
  void dispose() {
    widget.cart.removeListener(_askForQuote);
    widget.addresses.removeListener(_askForQuote);
    _quoter.removeListener(_onQuote);
    _quoter.dispose();
    _promo.dispose();
    super.dispose();
  }

  void _onQuote() {
    if (mounted) setState(() {});
  }

  /// The area of the selected address. Null prices every shop at its flat fee, which is what Order
  /// Manager charges an address with no area — and so the one case in which a shop card's fee is
  /// the platform's own figure.
  String? get _zoneId => widget.addresses.selected?.zoneId;

  void _askForQuote() {
    // Behind another tab nothing is on screen, so nothing is asked ([CartScreen.showing]).
    if (!mounted || !widget.showing) return;
    _quoter.ask(questionFor(widget.cart, zoneId: _zoneId, promoCode: _promo.text));
  }

  void _onPromoTyped(String _) {
    // The quoter waits for the typing to pause, and only the answer about the code still in the
    // field is ever shown.
    _askForQuote();
    setState(() {});
  }

  void _removePromo() {
    _promo.clear();
    _askForQuote();
    if (mounted) setState(() {});
  }

  /// What the server said the code in the field is worth on this basket — the answer on screen,
  /// kept while a newer one is on its way. Null while the field is empty, or when the basket could
  /// not be priced and so the code was not judged. Never trusted for money.
  PromoQuote? get _shownPromo => _promo.text.trim().isEmpty ? null : _quoter.shown?.promo;

  /// A code checkout may send: one the server judged valid for this very basket, as it stands now.
  /// Placing with a refused code fails the whole order, so a refused one is never handed on.
  PromoQuote? get _validPromo {
    final PromoQuote? outcome = _quoter.quote?.promo;
    return _promo.text.trim().isNotEmpty && outcome != null && outcome.valid ? outcome : null;
  }

  /// The discount the summary shows: every shop's share of the code, as the server shared it out.
  /// Zero unless the server said the code applies.
  double get _promoDiscount {
    final PromoQuote? outcome = _shownPromo;
    return outcome != null && outcome.valid ? (_quoter.shown?.discountAmount ?? 0) : 0;
  }

  Future<void> _checkout(BuildContext context) async {
    // A gift is sent from one shop at a time: its checkout waits until only one shop is left.
    if (widget.cart.isGift && widget.cart.isMultiShop) return;
    final PromoQuote? quote = _validPromo;
    // A placed order, a checkout queued for when the connection returns, or nothing (backed out).
    final Object? outcome = await Navigator.of(context).push<Object>(
      MaterialPageRoute<Object>(
        // A gift has its own checkout: who receives it, never cash, never queued for later.
        builder: (_) => widget.cart.isGift
            ? GiftCheckoutScreen(
                api: widget.orderApi,
                cart: widget.cart,
                addresses: widget.addresses,
                zoneApi: widget.zoneApi,
                geocodingApi: widget.geocodingApi,
                promo: quote != null && quote.valid ? quote : null,
                connectivity: widget.connectivity,
                deliveryTerms: widget.deliveryTerms,
              )
            : CheckoutScreen(
          api: widget.orderApi,
          cart: widget.cart,
          addresses: widget.addresses,
          zoneApi: widget.zoneApi,
          geocodingApi: widget.geocodingApi,
          transferApi: widget.transferApi,
          splitApi: widget.splitApi,
          // The canonical stored code, never the raw field text — and only when the server said
          // it applies, because placing with a refused code fails the whole order.
          promo: quote != null && quote.valid ? quote : null,
          outbox: widget.outbox,
          connectivity: widget.connectivity,
          deliveryTerms: widget.deliveryTerms,
        ),
      ),
    );
    if (!context.mounted) return;
    if (outcome is PendingOrder) {
      // Queued, not placed: no order and no server total exist yet, so there is no receipt to
      // toast. The queued card on the Orders tab says what happens next.
      _removePromo();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DeliveryStrings.of(context).offlineQueued)));
      widget.onOrderPlaced();
      return;
    }
    if (outcome is CheckoutPlaced) {
      // Every shop's order at once; the code, if there was one, went with them.
      _removePromo();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(DeliveryStrings.of(context).multiCartPlaced(
              outcome.orders.length, '\$${outcome.totalAmount.toStringAsFixed(2)}'))));
      widget.onOrderPlaced();
      return;
    }
    if (outcome is EarlierCheckoutPlaced) {
      // An earlier try went through as one order per shop. Not one order's receipt, which would read
      // them as a single order: the customer is sent to Orders, where each carries its badge.
      _removePromo();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(DeliveryStrings.of(context)
              .multiCartEarlierCheckoutPlaced(outcome.order.checkoutSize ?? 2))));
      widget.onOrderPlaced();
      return;
    }
    final DeliveryOrder? order = outcome is DeliveryOrder ? outcome : null;
    if (order == null) return;

    // The code was consumed by the order; a stale "applied" chip over an empty basket would
    // claim a discount on nothing.
    _removePromo();

    final DeliveryStrings t = DeliveryStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(<String>[
          t.orderPlacedToastShort(
              order.shortId, order.totalAmount.toStringAsFixed(2)),
          // The express premium, itemised as its own figure the moment the server first states
          // one. It sits INSIDE that total and outside the delivery fee, so the total alone never
          // says what the hurry cost — and this is the first screen that can say it, because the
          // amount does not exist until the order does.
          if (order.expressSurcharge > 0)
            t.deliveryTierExpressSurcharge(
                order.expressSurcharge.toStringAsFixed(2)),
        ].join(' · ')),
      ),
    );
    // Jump to Orders so the customer immediately sees the thing they just created.
    widget.onOrderPlaced();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<CartLine> lines = widget.cart.lines;
    final bool severalShops = widget.cart.isMultiShop;

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      // A tab, so no back chevron whatever the frame draws: there is nothing behind a tab to go
      // back to.
      appBar: severalShops
          ? YdScreenHeader(
              title: t.multiCartTitle,
              subtitle: t.multiCartSubtitle,
              // Shops, not merchants: the basket and the server both count shops, and one merchant
              // may run several.
              trailing: YdBadge(
                label: t.multiCartShopCount(widget.cart.storeCount),
                color: DeliveryColors.brand,
                background: DeliveryColors.brandSoft,
                uppercase: false,
              ),
            )
          : YdScreenHeader(title: t.custMyBasket),
      body: lines.isEmpty
          ? YdEmptyState(
              icon: Icons.shopping_bag_outlined,
              title: t.basketEmpty,
              padding: const EdgeInsets.all(DeliverySpacing.xl),
            )
          : ListView(
              padding: EdgeInsets.zero,
              children: <Widget>[
                if (severalShops)
                  for (final String storeId in widget.cart.storeIds) _shopGroup(context, storeId)
                else ...<Widget>[
                  _storeStrip(context),
                  if (_splitAvailable) _modeToggle(context),
                  if (_splitting) _participantsRow(context),
                  Padding(
                    padding: const EdgeInsetsDirectional.all(_gutter),
                    child: Column(
                      children: <Widget>[
                        for (int i = 0; i < lines.length; i++) ...<Widget>[
                          if (i > 0) const SizedBox(height: DeliverySpacing.md - 4),
                          _basketRow(context, lines[i]),
                          if (_splitting) _assignChip(context, lines[i]),
                        ],
                      ],
                    ),
                  ),
                  if (_splitting) _splitSummary(context),
                ],
                if (severalShops) const SizedBox(height: _gutter),
                _promoSection(context),
                const SizedBox(height: DeliverySpacing.lg),
                if (severalShops) _severalShopsSummary(context) else _summary(context),
              ],
            ),
    );
  }

  // ---------------------------------------------------------- group split (Figma 83:7)

  /// Whether this basket may be split with friends. Never a gift: the gift checkout attaches no
  /// split plan, and placing the gift settles the basket — which clears the plan and would orphan
  /// the payment requests the friends were sent. Never a basket from several shops either: a plan
  /// closes over exactly one order, and that basket becomes several.
  bool get _splitAvailable =>
      widget.splitApi != null &&
      widget.profileApi != null &&
      widget.session != null &&
      !widget.cart.isGift &&
      !widget.cart.isMultiShop;

  /// Split mode as drawn: chosen, and still available — a basket made a gift after Split was chosen
  /// shows none of it.
  bool get _splitting => _splitMode && _splitAvailable;

  /// Split mode on this basket. Participants[0] is always the host.
  bool _splitMode = false;
  final List<SplitParticipant> _friends = <SplitParticipant>[];

  /// Basket line key → participant index (0 = host, i>0 = _friends[i-1]).
  final Map<String, int> _assign = <String, int>{};

  int _assignmentOf(CartLine line) {
    final int index = _assign[line.key] ?? 0;
    return index > _friends.length ? 0 : index;
  }

  String _participantName(BuildContext context, int index) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    if (index == 0) return t.you;
    return _friends[index - 1].name;
  }

  /// The frame's Solo Order / Split Order pill toggle.
  Widget _modeToggle(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
          _gutter, DeliverySpacing.md, _gutter, 0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: DeliveryColors.border,
          borderRadius: BorderRadius.circular(DeliveryRadius.pill),
        ),
        child: Row(
          children: <Widget>[
            _modeHalf(t.custSoloOrder, !_splitMode,
                () => setState(() => _splitMode = false)),
            _modeHalf(t.custSplitOrder, _splitMode,
                () => setState(() => _splitMode = true)),
          ],
        ),
      ),
    );
  }

  Widget _modeHalf(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected ? DeliveryColors.brand : Colors.transparent,
              borderRadius: BorderRadius.circular(DeliveryRadius.pill),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? DeliveryColors.white : DeliveryColors.muted,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The participants strip: the host, every added friend, and the dashed Add Friend circle.
  Widget _participantsRow(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
          _gutter, DeliverySpacing.md, _gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            t.custOrderParticipants,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
              height: 1.25,
            ),
          ),
          const SizedBox(height: DeliverySpacing.sm),
          SizedBox(
            height: 74,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                _participantAvatar(t.you, host: true),
                for (final SplitParticipant friend in _friends)
                  _participantAvatar(friend.name),
                _addFriendCircle(t),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _participantAvatar(String name, {bool host = false}) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: DeliverySpacing.md),
      child: Column(
        children: <Widget>[
          Stack(
            children: <Widget>[
              StoreMonogram(name: name, size: 46, radius: 23),
              if (host)
                PositionedDirectional(
                  bottom: 0,
                  end: 0,
                  child: Icon(Icons.check_circle,
                      size: 15, color: DeliveryAccent.positive.color),
                ),
            ],
          ),
          const SizedBox(height: 3),
          SizedBox(
            width: 52,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: DeliveryColors.ink,
                  height: 1.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addFriendCircle(DeliveryStrings t) {
    return Semantics(
      button: true,
      label: t.custAddFriend,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _addFriend,
        child: Column(
          children: <Widget>[
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DeliveryColors.brandSoft,
                border: Border.all(color: DeliveryColors.brand, width: 1),
              ),
              child: const Icon(Icons.add, size: 20, color: DeliveryColors.brand),
            ),
            const SizedBox(height: 3),
            Text(
              t.custAddFriend,
              style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: DeliveryColors.brand,
                  height: 1.2),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addFriend() async {
    // Recent co-splitters, mined from past plans — the sheet's Quick Add list.
    List<String> recent = <String>[];
    final Map<String, String> recentNames = <String, String>{};
    try {
      final List<SplitPlan> mine = await widget.splitApi!.mine();
      for (final SplitPlan plan in mine) {
        for (final SplitShare share in plan.shares) {
          final String? username = share.username;
          if (username != null &&
              username != widget.session!.username &&
              !recent.contains(username)) {
            recent.add(username);
            recentNames[username] = share.name;
          }
        }
      }
    } catch (_) {
      // The sheet still searches.
    }
    if (!mounted) return;
    final SplitParticipant? added = await showAddFriendSheet(
      context,
      profileApi: widget.profileApi!,
      recentUsernames: recent,
      recentNames: recentNames,
    );
    if (added == null || !mounted) return;
    final bool duplicate = _friends.any((SplitParticipant f) =>
        f.username != null && f.username == added.username);
    if (!duplicate) setState(() => _friends.add(added));
  }

  /// The "Assigned: X" chip under each line — taps through the participants in turn.
  Widget _assignChip(BuildContext context, CartLine line) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final int current = _assignmentOf(line);
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 4, bottom: 2),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Semantics(
          button: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(DeliveryRadius.pill),
            onTap: () => setState(() =>
                _assign[line.key] = (current + 1) % (_friends.length + 1)),
            child: Container(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: DeliveryColors.background,
                borderRadius: BorderRadius.circular(DeliveryRadius.pill),
                border: Border.all(color: DeliveryColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    t.custAssignedTo(_participantName(context, current)),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: DeliveryColors.ink,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.keyboard_arrow_down,
                      size: 14, color: DeliveryColors.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Even mode (Figma `split-setup`): everyone owes total/N and the host absorbs the remainder
  /// cents. Itemized mode (Figma `split-basket`): each pays for the lines assigned to them.
  bool _evenSplit = false;

  /// Per-participant (host first) amounts and item counts under the current split mode.
  (List<double>, List<int>) _shareMath() {
    final List<CartLine> lines = widget.cart.lines;
    final int people = _friends.length + 1;
    final List<double> sums = List<double>.filled(people, 0);
    final List<int> counts = List<int>.filled(people, 0);
    if (_evenSplit) {
      // Cents-exact: each pays floor(total/N) to the cent, the host takes the leftover.
      final double total = widget.cart.total;
      final double each = (total / people * 100).floorToDouble() / 100;
      for (int i = 1; i < people; i++) {
        sums[i] = each;
      }
      sums[0] = total - each * (people - 1);
      return (sums, counts);
    }
    for (final CartLine line in lines) {
      final int index = _assignmentOf(line);
      sums[index] += line.lineTotal;
      counts[index] += 1;
    }
    return (sums, counts);
  }

  /// The frame's per-person summary, and the button that sends the requests.
  Widget _splitSummary(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final (List<double> sums, List<int> counts) = _shareMath();

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(_gutter, 0, _gutter, 0),
      child: YdCard.bordered(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    t.custPaymentSplitSummary,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: DeliveryColors.ink,
                      height: 1.25,
                    ),
                  ),
                ),
                // The frame's other mode: everyone the same, host takes the cents.
                YdChip(
                  label: t.custEvenBreakdown,
                  selected: _evenSplit,
                  onTap: () => setState(() => _evenSplit = !_evenSplit),
                ),
              ],
            ),
            if (_evenSplit) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                t.custHostAbsorbs(
                    '\$${(_shareMath().$1[0] - (widget.cart.total / (_friends.length + 1))).abs().toStringAsFixed(2)}'),
                style: const TextStyle(
                    fontSize: 11, color: DeliveryColors.faint, height: 1.3),
              ),
            ],
            const SizedBox(height: DeliverySpacing.sm),
            for (int i = 0; i <= _friends.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '${_participantName(context, i)} (${t.custItemsCountLine(counts[i])})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5,
                            color: DeliveryColors.muted,
                            height: 1.3),
                      ),
                    ),
                    Text(
                      '\$${sums[i].toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.ink,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: DeliverySpacing.md * 1.5,
                color: DeliveryColors.borderFaint),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    t.custTotalOrderAmount,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: DeliveryColors.ink,
                      height: 1.25,
                    ),
                  ),
                ),
                Text(
                  '\$${widget.cart.total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: DeliveryColors.brand,
                    height: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: DeliverySpacing.md),
            YdPillButton(
              label: t.custSendPaymentRequests,
              onPressed: _friends.isEmpty ? null : () => _sendRequests(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendRequests(BuildContext context) async {
    final (List<double> sums, List<int> counts) = _shareMath();
    final NavigatorState nav = Navigator.of(context);
    try {
      final SplitPlan plan = await widget.splitApi!.create(
        mode: _evenSplit ? 'EVEN' : 'ITEMIZED',
        // The whole obligation, fee included: the friends' shares are their items, and whatever
        // remains — the fee among it — lands on the host's own share server-side.
        totalUsd: widget.cart.total,
        storeName: widget.cart.store?.name,
        shares: <SplitShareDraft>[
          for (int i = 0; i < _friends.length; i++)
            SplitShareDraft(
              username: _friends[i].username,
              name: _friends[i].name,
              amountUsd: sums[i + 1],
              itemsCount: counts[i + 1],
            ),
        ],
      );
      if (!mounted) return;
      widget.cart.splitPlanId = plan.id;
      nav.push(MaterialPageRoute<void>(
        builder: (_) => SplitStatusScreen(
          splitApi: widget.splitApi!,
          plan: plan,
          onReady: () => _checkout(this.context),
        ),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(
          content: Text(DeliveryStrings.of(this.context).somethingWentWrong)));
    }
  }

  /// Names the one shop a basket holds, with its delivery estimate. The frame has no such row; it is
  /// kept because it is the one place a one-shop basket says where it is ordering from. A basket
  /// from several shops names each shop over its own group instead.
  Widget _storeStrip(BuildContext context) {
    final StoreCard? store = widget.cart.store;
    if (store == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: DeliveryColors.brandSoft,
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: _gutter, vertical: DeliverySpacing.md - 4),
      child: Row(
        children: <Widget>[
          const Icon(Icons.storefront, size: 16, color: DeliveryColors.brand),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              store.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: DeliveryColors.ink,
              ),
            ),
          ),
          Text(store.etaLabel,
              style: const TextStyle(fontSize: 12, color: DeliveryColors.muted)),
        ],
      ),
    );
  }

  static const double _thumb = 64;

  /// `basket-row`: a 64px thumbnail, the name over the line price, and the stepper.
  Widget _basketRow(BuildContext context, CartLine line) {
    return Container(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
      decoration: BoxDecoration(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
      ),
      child: Row(
        children: <Widget>[
          CustomerPhoto(
            // A 64px basket thumbnail — a list surface, so the derivative.
            url: line.product.listImageUrl,
            width: _thumb,
            height: _thumb,
            radius: 10,
            icon: Icons.fastfood_outlined,
          ),
          const SizedBox(width: DeliverySpacing.md - 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  line.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
                // The configuration, so two lines of the same product are tellable apart at a
                // glance. Not on the frame, which draws only products without options.
                if (line.optionsSummary.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    line.optionsSummary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: DeliveryColors.faint, height: 1.3),
                  ),
                ],
                const SizedBox(height: DeliverySpacing.xs),
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: '\$${line.unitPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: DeliveryColors.brand,
                        ),
                      ),
                      if (MarketRates.instance.lbpParen(line.unitPrice)
                          case final String lbp)
                        TextSpan(
                          text: ' $lbp',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: DeliveryColors.faint,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          QuantityStepper(
            quantity: line.qty,
            // At one, decrementing removes the line — so the glyph says so. The frame draws no
            // delete affordance at all and a basket you cannot empty is not shippable.
            decreaseIcon: line.qty > 1 ? Icons.remove : Icons.delete_outline,
            onDecrease: () => widget.cart.remove(line.key),
            onIncrease: () => widget.cart.addConfigured(ConfiguredProduct(
              product: line.product,
              optionIds: line.optionIds,
              unitPrice: line.unitPrice,
              summary: line.optionsSummary,
            )),
          ),
        ],
      ),
    );
  }

  /// The promo row, judged by the basket's quote.
  ///
  /// The code in the field rides on the question the basket already asks Order Manager, so what the
  /// row says a code is worth is what it is worth on THIS basket at THIS address. The promotions
  /// endpoint it used to ask could only be told a shop card's flat fee, and a free-delivery code
  /// quoted against that was not what an address priced by its area would be charged. Drawn
  /// whenever the basket is, because the quote that judges the code always is.
  Widget _promoSection(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final PromoQuote? quote = _shownPromo;
    final bool checking = _promo.text.trim().isNotEmpty && _quoter.asking;
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: _gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _promoRowShell(
            t,
            field: TextField(
              controller: _promo,
              onChanged: _onPromoTyped,
              onSubmitted: (_) => _quoter.retry(),
              // A code is at most 32 characters. Anything longer is not one, and would only make the
              // basket's quote refuse the whole question.
              inputFormatters: <TextInputFormatter>[LengthLimitingTextInputFormatter(32)],
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                  fontSize: 14, color: DeliveryColors.ink, height: 1.2),
              decoration: InputDecoration(
                isDense: true,
                isCollapsed: true,
                border: InputBorder.none,
                hintText: t.custPromoCode,
                hintStyle:
                    const TextStyle(fontSize: 14, color: DeliveryColors.faint),
              ),
            ),
            onApply: _quoter.retry,
          ),
          if (checking) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Row(
              children: <Widget>[
                const SizedBox.square(
                  dimension: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: DeliveryColors.brand),
                ),
                const SizedBox(width: DeliverySpacing.sm),
                Text(
                  t.custPromoChecking,
                  style: const TextStyle(
                      fontSize: 12, color: DeliveryColors.muted, height: 1.3),
                ),
              ],
            ),
          ] else if (quote != null && quote.valid) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Row(
              children: <Widget>[
                Icon(Icons.check_circle_rounded,
                    size: 14, color: DeliveryAccent.positive.color),
                const SizedBox(width: DeliverySpacing.xs),
                Expanded(
                  child: Text(
                    '${quote.code ?? _promo.text.trim()} · -${_promoDiscount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DeliveryAccent.positive.color,
                      height: 1.3,
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: t.custPromoRemove,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                    onTap: _removePromo,
                    child: const Padding(
                      padding: EdgeInsetsDirectional.all(DeliverySpacing.xs),
                      child: Icon(Icons.close_rounded,
                          size: 14, color: DeliveryColors.faint),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (quote != null && !quote.valid) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Text(
              custPromoReasonLabel(t, quote.reason),
              style: TextStyle(
                fontSize: 12,
                color: DeliveryAccent.critical.color,
                height: 1.35,
              ),
            ),
          ] else if (_quoter.failed && _promo.text.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Text(
              // The server was not reached — a different fact from a refused code, and the Apply
              // button is the retry.
              t.promoCouldNotCheck,
              style: TextStyle(
                fontSize: 12,
                color: DeliveryAccent.critical.color,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The geometry the frame draws for the promo row: the bordered white field with the tag glyph,
  /// then the tinted Apply button.
  Widget _promoRowShell(DeliveryStrings t,
      {required Widget field, required VoidCallback? onApply}) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Container(
            padding:
                const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
            decoration: BoxDecoration(
              color: DeliveryColors.white,
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
              border: Border.all(color: DeliveryColors.border),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.sell_outlined, size: 18, color: DeliveryColors.faint),
                const SizedBox(width: DeliverySpacing.sm),
                Expanded(child: field),
              ],
            ),
          ),
        ),
        const SizedBox(width: DeliverySpacing.md - 4),
        Semantics(
          button: onApply != null,
          child: InkWell(
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
            onTap: onApply,
            child: Container(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: DeliverySpacing.lg - DeliverySpacing.xs,
                  vertical: DeliverySpacing.md - DeliverySpacing.xs),
              decoration: BoxDecoration(
                color: DeliveryColors.brandSoft,
                borderRadius: BorderRadius.circular(DeliveryRadius.md),
                border: Border.all(color: DeliveryColors.brand),
              ),
              child: Text(
                t.custApply,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: DeliveryColors.brand,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The money, itemised, for a basket from one shop.
  ///
  /// The delivery fee is shown as its own line rather than folded into one number, because a
  /// customer comparing shops is comparing exactly that split — and because a total that silently
  /// grew between the shelf and the basket is the classic reason a basket gets abandoned.
  ///
  /// The server's figures once it has priced the basket; until then, or when it cannot, the shop
  /// card's — but only for an address with no area, where the card's fee IS what Order Manager
  /// charges. At an address priced by its area the fee and the total are a dash until the server
  /// says: the card's flat fee there was the Basket tab quoting a fee nobody would be charged.
  Widget _summary(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final StoreCard? store = widget.cart.store;
    final BasketQuote? quote = _quoter.shown;
    final ShopQuote? shop = quote?.shops.firstOrNull;
    final bool priced = quote != null && shop != null && shop.priced;
    final bool fromCard = !priced && _zoneId == null;

    final double subtotal = priced ? (quote.subtotal ?? widget.cart.subtotal) : widget.cart.subtotal;
    final double? deliveryCharged =
        priced ? shop.deliveryFeeCharged : (fromCard ? widget.cart.deliveryFeeCharged : null);
    final bool waived = priced ? shop.deliveryFeeWaived : fromCard && widget.cart.deliveryIsFree;
    final double waivedFee = priced ? (shop.deliveryFee ?? 0) : widget.cart.deliveryFee;
    final String offerTitle =
        (priced ? shop.offerTitle : widget.cart.waiver?.offerTitle) ?? t.freeDelivery;
    final double promoDiscount = priced ? _promoDiscount : 0;
    final double? payable = priced ? quote.totalAmount : (fromCard ? widget.cart.total : null);

    final String? refusal = _oneShopRefusal(t, shop, store);
    final bool underMinimum = shop?.refusal == ShopRefusal.belowMinimum ||
        (shop == null && !widget.cart.meetsMinimum);
    final bool blocked = refusal != null;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(top: BorderSide(color: DeliveryColors.border)),
      ),
      padding: const EdgeInsetsDirectional.all(_gutter),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              t.custOrderSummary,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: DeliveryColors.ink,
              ),
            ),
            const SizedBox(height: DeliverySpacing.md),
            _summaryRow(t.subtotal, '\$${subtotal.toStringAsFixed(2)}', lbpOf: subtotal),
            if (store != null) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              _summaryRow(
                t.delivery,
                // What will be CHARGED. Adding the shop's fee to the subtotal here, when the
                // platform is absorbing it, quoted the customer a total the server would not bill.
                // "Free" is the thing worth reading; 0.00 makes the eye do arithmetic.
                deliveryCharged == null
                    ? _dash
                    : deliveryCharged == 0
                        ? t.free
                        : '\$${deliveryCharged.toStringAsFixed(2)}',
                lbpOf: deliveryCharged == null || deliveryCharged == 0 ? null : deliveryCharged,
              ),
              // The discounts line, and only when there is a real discount to put on it. Names the
              // promotion underneath: a customer who is not told why their delivery was free has
              // been given something that changes nothing about what they do next.
              if (waived) ...<Widget>[
                const SizedBox(height: DeliverySpacing.sm),
                _summaryRow(
                  t.custDiscounts,
                  '-${waivedFee.toStringAsFixed(2)}',
                  valueColor: DeliveryAccent.positive.color,
                ),
                const SizedBox(height: DeliverySpacing.xs),
                Row(
                  children: <Widget>[
                    const Icon(Icons.redeem_outlined, size: 14, color: DeliveryColors.brand),
                    const SizedBox(width: DeliverySpacing.xs),
                    Expanded(
                      child: Text(
                        offerTitle,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: DeliveryColors.brand,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
            // The promo code's own line, under the code the server recognised. Advisory: what is
            // billed is recomputed at placement, and the confirmation shows the server's total.
            if (promoDiscount > 0) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              _summaryRow(
                _shownPromo?.code ?? t.custPromoCode,
                '-${promoDiscount.toStringAsFixed(2)}',
                valueColor: DeliveryAccent.positive.color,
              ),
            ],
            const Padding(
              padding: EdgeInsetsDirectional.symmetric(vertical: DeliverySpacing.sm),
              child: Divider(height: 1, thickness: 1, color: DeliveryColors.border),
            ),
            _totalRow(t, payable),
            if (payable == null) _quoteNote(t),
            if (blocked) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              _explanation(refusal),
            ],
            if (widget.cart.isGift) ...<Widget>[
              const SizedBox(height: DeliverySpacing.md),
              _giftBanner(t),
            ],
            const SizedBox(height: DeliverySpacing.md),
            YdPillButton(
              // Disabled rather than hidden: a customer needs to see that checkout exists and why
              // it is not available yet.
              label: underMinimum ? t.minimumNotReached : t.custProceedToCheckout,
              onPressed: blocked ? null : () => _checkout(context),
            ),
          ],
        ),
      ),
    );
  }

  /// Why a one-shop basket cannot be checked out as it stands, in the customer's words — or null.
  /// The server's reason once it has priced the basket; the shop card's minimum until then.
  String? _oneShopRefusal(DeliveryStrings t, ShopQuote? shop, StoreCard? store) {
    final ShopRefusal? refusal = shop?.refusal;
    if (shop != null && refusal != null) {
      final String name = shop.storeName ?? store?.name ?? t.tabShop;
      return switch (refusal) {
        ShopRefusal.belowMinimum => t.minimumExplanationFull(
            (shop.minimumOrder ?? 0).toStringAsFixed(2), (shop.shortfall ?? 0).toStringAsFixed(2)),
        ShopRefusal.closed => t.multiCartShopClosed(name),
        ShopRefusal.notServed => t.multiCartShopNotServing(name),
        ShopRefusal.unknown => shop.refusalMessage ?? t.multiCartShopUnavailable(name),
      };
    }
    if (shop == null && !widget.cart.meetsMinimum) {
      return t.minimumExplanationFull((store?.minOrder ?? 0).toStringAsFixed(2),
          widget.cart.amountBelowMinimum.toStringAsFixed(2));
    }
    return null;
  }

  /// The money for a basket from several shops: the goods, every shop's delivery — each shop's own
  /// fee, added up (see the class comment for the unified fee this deliberately does not show) — the
  /// code's discount, and the total the button carries.
  ///
  /// The server's figures only. A sum of shop cards' fees is not what such a basket is charged —
  /// areas, waivers and minimums differ shop by shop — so the figures are a dash until the server has
  /// priced every shop, and the basket is not checked out before it has.
  Widget _severalShopsSummary(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final BasketQuote? quote = _quoter.shown;
    final double subtotal = quote?.subtotal ?? widget.cart.subtotal;
    final double? delivery = quote?.deliveryFeeCharged;
    final double promoDiscount = _promoDiscount;
    final double? payable = quote?.totalAmount;
    final BasketQuote? current = _quoter.quote;
    final bool canCheckOut = current != null &&
        current.placeable &&
        current.totalAmount != null &&
        !widget.cart.isGift;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(top: BorderSide(color: DeliveryColors.border)),
      ),
      padding: const EdgeInsetsDirectional.all(_gutter),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _summaryRow(t.subtotal, '\$${subtotal.toStringAsFixed(2)}', lbpOf: subtotal),
            const SizedBox(height: DeliverySpacing.sm),
            _summaryRow(
              t.multiCartDeliveryFromShops(widget.cart.storeCount),
              delivery == null
                  ? _dash
                  : delivery == 0
                      ? t.free
                      : '\$${delivery.toStringAsFixed(2)}',
              lbpOf: delivery == null || delivery == 0 ? null : delivery,
            ),
            if (promoDiscount > 0) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              _summaryRow(
                _shownPromo?.code ?? t.custPromoCode,
                '-${promoDiscount.toStringAsFixed(2)}',
                valueColor: DeliveryAccent.positive.color,
              ),
            ],
            const Padding(
              padding: EdgeInsetsDirectional.symmetric(vertical: DeliverySpacing.sm),
              child: Divider(height: 1, thickness: 1, color: DeliveryColors.border),
            ),
            _totalRow(t, payable),
            _quoteNote(t),
            if (widget.cart.isGift) ...<Widget>[
              const SizedBox(height: DeliverySpacing.md),
              _giftBanner(t),
              const SizedBox(height: DeliverySpacing.sm),
              _explanation(t.multiCartGiftOneShop),
            ],
            const SizedBox(height: DeliverySpacing.md),
            YdPillButton(
              // The frame's "Checkout — $34.50" was the goods alone. The button carries what the
              // customer will be charged: the goods and every shop's delivery, less any code.
              label: payable == null
                  ? t.checkout
                  : t.multiCartCheckoutAmount('\$${payable.toStringAsFixed(2)}'),
              busy: _quoter.asking,
              onPressed: canCheckOut ? () => _checkout(context) : null,
            ),
          ],
        ),
      ),
    );
  }

  /// One shop's part of a basket from several shops (Figma 121:358): the uppercase "FROM {SHOP}
  /// (n ITEMS)" label, then a bordered card holding that shop's lines, the shop's own delivery fee,
  /// and — when the shop's part cannot be checked out yet — why, with a way to take the shop out.
  Widget _shopGroup(BuildContext context, String storeId) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<CartLine> lines = widget.cart.linesFor(storeId);
    final ShopQuote? priced = _quoter.shown?.shop(storeId);
    final String name = widget.cart.storeFor(storeId)?.name ?? priced?.storeName ?? t.tabShop;
    final int items = lines.fold(0, (int count, CartLine line) => count + line.qty);
    final double? delivery = priced?.deliveryFeeCharged;
    final String? warning = _shopWarning(t, storeId, priced, name);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(_gutter, _gutter, _gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            t.multiCartFromShop(items, name).toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.muted,
              height: 1.3,
            ),
          ),
          const SizedBox(height: DeliverySpacing.sm),
          YdCard.bordered(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < lines.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                  _groupRow(context, lines[i]),
                ],
                const Padding(
                  padding: EdgeInsetsDirectional.symmetric(
                      vertical: DeliverySpacing.md - DeliverySpacing.xs),
                  child: Divider(height: 1, thickness: 1, color: DeliveryColors.borderFaint),
                ),
                // Each shop's own fee: every order is its own delivery, from its own counter.
                _summaryRow(
                  t.multiCartShopDelivery,
                  delivery == null
                      ? _dash
                      : delivery == 0
                          ? t.free
                          : '\$${delivery.toStringAsFixed(2)}',
                ),
                if (warning != null) ...<Widget>[
                  const SizedBox(height: DeliverySpacing.sm),
                  _explanation(warning),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      onPressed: () => widget.cart.removeStore(storeId),
                      style: TextButton.styleFrom(foregroundColor: DeliveryColors.brand),
                      child: Text(t.multiCartRemoveShop(name)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A line inside a shop's group: "2× Beef Shawarma Sandwich", its options, its total, and the
  /// stepper. The frame draws the line read-only; the stepper stays, because the basket is where
  /// quantities are changed and a basket that cannot be edited is not shippable.
  Widget _groupRow(BuildContext context, CartLine line) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                t.giftLineQty(line.qty, line.product.name),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: DeliveryColors.ink, height: 1.3),
              ),
              if (line.optionsSummary.isNotEmpty)
                Text(
                  line.optionsSummary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: DeliveryColors.faint, height: 1.3),
                ),
            ],
          ),
        ),
        const SizedBox(width: DeliverySpacing.sm),
        Text(
          '\$${line.lineTotal.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
          ),
        ),
        const SizedBox(width: DeliverySpacing.sm),
        QuantityStepper(
          quantity: line.qty,
          decreaseIcon: line.qty > 1 ? Icons.remove : Icons.delete_outline,
          onDecrease: () => widget.cart.remove(line.key),
          onIncrease: () => widget.cart.addConfigured(ConfiguredProduct(
            product: line.product,
            optionIds: line.optionIds,
            unitPrice: line.unitPrice,
            summary: line.optionsSummary,
          )),
        ),
      ],
    );
  }

  /// Why one shop's part cannot be checked out yet, naming the shop — or null when it can.
  ///
  /// The server's reason once it has priced the shop. Until then, the shop card's minimum, which is
  /// the platform's own for an address with no area; the server's minimum for an area may differ,
  /// and replaces it as soon as it answers.
  String? _shopWarning(DeliveryStrings t, String storeId, ShopQuote? priced, String name) {
    if (priced != null && priced.refusal != null) return shopRefusalSentence(t, priced, name);
    if (priced == null) {
      final double shortfall = widget.cart.shortfallAt(storeId);
      if (shortfall > 0) return t.multiCartBelowMinimum('\$${shortfall.toStringAsFixed(2)}', name);
    }
    return null;
  }

  /// The summary's total line: the amount with its LBP conversion, or a dash while the platform has
  /// not given one.
  Widget _totalRow(DeliveryStrings t, double? payable) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          t.custTotalAmount,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
          ),
        ),
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: payable == null ? _dash : '\$${payable.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.brand,
                ),
              ),
              if (payable == null ? null : MarketRates.instance.lbpParen(payable)
                  case final String lbp)
                TextSpan(
                  text: ' $lbp',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.muted,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Why the figures are what they are: the server's price on its way, or not to be had just now —
  /// with a way to ask again. Nothing while the figures are the server's own.
  Widget _quoteNote(DeliveryStrings t) {
    if (_quoter.asking) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(top: DeliverySpacing.sm),
        child: Row(
          children: <Widget>[
            const SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.brand),
            ),
            const SizedBox(width: DeliverySpacing.sm),
            Text(
              t.multiCartPricesUpdating,
              style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.3),
            ),
          ],
        ),
      );
    }
    if (_quoter.failed) {
      return Row(
        children: <Widget>[
          Expanded(
            child: Text(
              t.multiCartPricesFailed,
              style: TextStyle(fontSize: 12, color: DeliveryAccent.critical.color, height: 1.35),
            ),
          ),
          TextButton(
            onPressed: _quoter.retry,
            style: TextButton.styleFrom(foregroundColor: DeliveryColors.brand),
            child: Text(t.tryAgain),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  /// A sentence about why checkout is held back, in the brand's warning voice.
  Widget _explanation(String message) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(Icons.info_outline, size: 16, color: DeliveryColors.brand),
        const SizedBox(width: DeliverySpacing.sm),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontSize: 12, color: DeliveryColors.brand, height: 1.35),
          ),
        ),
      ],
    );
  }

  /// Says this basket is going to somebody else, and lets the customer say it is not — which is
  /// what decides the checkout Proceed opens.
  Widget _giftBanner(DeliveryStrings t) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(DeliverySpacing.md - DeliverySpacing.xs,
          DeliverySpacing.xs, DeliverySpacing.xs, DeliverySpacing.xs),
      decoration: BoxDecoration(
        color: DeliveryColors.brandSoft,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.card_giftcard_rounded, size: 18, color: DeliveryColors.brand),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              t.giftBasketBanner,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: DeliveryColors.ink),
            ),
          ),
          TextButton(
            onPressed: () => setState(widget.cart.stopGift),
            style: TextButton.styleFrom(foregroundColor: DeliveryColors.brand),
            child: Text(t.giftBasketNotGift),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value,
      {Color? valueColor, double? lbpOf}) {
    // The frame prices the money rows twice — the dollar figure, then the LBP conversion in
    // faint. `lbpOf` is the dollar amount to convert; rows whose value is a word ("Free") or a
    // discount pass nothing and stay single.
    final String? lbp =
        lbpOf == null ? null : MarketRates.instance.lbpParen(lbpOf);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(label,
            style: const TextStyle(fontSize: 13, color: DeliveryColors.muted)),
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? DeliveryColors.ink,
                ),
              ),
              if (lbp != null)
                TextSpan(
                  text: ' $lbp',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: DeliveryColors.faint,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
