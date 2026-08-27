import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import 'cart.dart';
import 'order_tracking_panel.dart';
import 'rate_rider_sheet.dart';
import 'store_page_screen.dart';

/// One order, in full — the 2026-08 Figma redesign's `customer-order-details` (node 3:542).
///
/// Top to bottom as drawn: a white status block carrying the order reference, the shop it came
/// from, the status pill and the five-step progress row; the live tracking panel while the order is
/// still moving; the ordered items; and the shop card.
///
/// Two blocks below those are not in the frame and are kept anyway, because the data behind them is
/// real and nothing else in the app shows it: the money breakdown (what was charged for delivery,
/// what was waived, how it is being paid) and the Reorder action. Both are written in the design's
/// own card language rather than left as they were.
///
/// Product thumbnails are resolved by re-reading the ordered products from the live catalog — the
/// order lines snapshot name and price at purchase time (correctly, those must not drift) but carry
/// no image reference. Anything since delisted simply renders without a picture.
class OrderDetailsScreen extends StatefulWidget {
  const OrderDetailsScreen({
    super.key,
    required this.orderApi,
    required this.storeApi,
    required this.cart,
    required this.orderId,
    this.trackingApi,
    this.chatApi,
    this.preview,
  });

  final OrderApi orderApi;
  final StoreApi storeApi;
  final Cart cart;
  final String orderId;

  /// The ETA endpoint, handed through to the tracking panel. Optional so call sites that have
  /// not been wired yet keep compiling; the panel then shows what it always showed.
  final TrackingApi? trackingApi;

  /// The order conversation, handed through to the tracking panel's message entry. Optional for
  /// the same reason.
  final ChatApi? chatApi;

  /// The row that was tapped, so the page renders immediately instead of flashing a spinner over
  /// information the list already had.
  final DeliveryOrder? preview;

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  DeliveryOrder? _order;
  Store? _store;

  /// productId -> first image URL, for the line thumbnails.
  Map<String, String> _thumbnails = <String, String>{};

  bool _loading = true;
  bool _reordering = false;

  /// The stars this customer already left, when they have. Null with [_ratingKnown] false means
  /// the question has not been answered yet, and nothing about rating is drawn — a "rate" button
  /// that flashes and turns into "already rated" is the screen guessing out loud.
  RiderRatingEntry? _rating;
  bool _ratingKnown = false;

  @override
  void initState() {
    super.initState();
    _order = widget.preview;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final DeliveryOrder order = await widget.orderApi.read(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order;
        _loading = false;
      });
      // Both are decoration on top of an already-rendered page, so they load after rather than
      // holding it up, and a failure in either leaves the order itself perfectly readable.
      _loadStore(order);
      _loadThumbnails(order);
      _loadRating(order);
    } catch (_) {
      // The error state is the absence of an order, not a stored exception — nothing on this
      // screen distinguishes one failure from another, so keeping the object would be pretence.
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadStore(DeliveryOrder order) async {
    final String? storeId = order.storeId;
    if (storeId == null) return;
    try {
      final Store store = await widget.storeApi.read(storeId);
      if (mounted) setState(() => _store = store);
    } catch (_) {
      // The order carries storeName already; the logo is a nicety.
    }
  }

  Future<void> _loadThumbnails(DeliveryOrder order) async {
    final String? storeId = order.storeId;
    if (storeId == null || order.items.isEmpty) return;
    try {
      final Paged<Product> products = await widget.storeApi.products(
        storeId,
        ids: order.items.map((OrderLine l) => l.productId).toList(),
        size: order.items.length,
      );
      if (!mounted) return;
      setState(() {
        _thumbnails = <String, String>{
          for (final Product p in products.content)
            if (p.imageUrls.isNotEmpty) p.id: p.imageUrls.first,
        };
      });
    } catch (_) {
      // No thumbnails; the lines still render.
    }
  }

  /// Asks whether this delivery was already rated — only for a delivered order with a rider,
  /// because those are the only ones the server accepts a rating on.
  Future<void> _loadRating(DeliveryOrder order) async {
    if (order.status.wire != 'DELIVERED' || order.riderId == null) return;
    try {
      final RiderRatingEntry? rating = await widget.orderApi.orderRating(order.id);
      if (!mounted) return;
      setState(() {
        _rating = rating;
        _ratingKnown = true;
      });
    } catch (_) {
      // Unanswered stays unanswered: no rating affordance is drawn rather than one that may
      // contradict the server.
    }
  }

  Future<void> _rate() async {
    final RiderRatingEntry? entry = await showRateRiderSheet(
      context,
      api: widget.orderApi,
      orderId: widget.orderId,
    );
    if (entry == null || !mounted) return;
    setState(() {
      _rating = entry;
      _ratingKnown = true;
    });
    _say(DeliveryStrings.of(context).custThanksForRating);
  }

  /// Puts the whole order back in the basket.
  ///
  /// Re-read from the live catalog rather than reconstructed from the order lines: prices move, and
  /// a basket built from a months-old snapshot would show a total the server then refuses to match.
  /// Items no longer sold are reported rather than silently dropped.
  Future<void> _reorder() async {
    final DeliveryOrder order = _order!;
    final String? storeId = order.storeId;
    if (storeId == null) return;

    setState(() => _reordering = true);
    try {
      final Paged<Product> live = await widget.storeApi.products(
        storeId,
        ids: order.items.map((OrderLine l) => l.productId).toList(),
        size: order.items.length,
      );
      final Map<String, Product> byId = <String, Product>{
        for (final Product p in live.content) p.id: p,
      };

      // The catalog read is an async gap; everything below reads strings off this context.
      if (!mounted) return;
      if (byId.isEmpty) {
        _say(DeliveryStrings.of(context).nothingStillAvailable);
        return;
      }

      // Starting a fresh basket is the honest behaviour: the one-store rule means we would
      // otherwise have to silently discard whatever was already in it.
      if (widget.cart.isNotEmpty && widget.cart.storeId != storeId) {
        final bool? replace = await _confirmReplaceBasket();
        if (replace != true || !mounted) return;
      }
      widget.cart.switchTo(_store?.toCard() ??
          StoreCard(
            id: storeId,
            slug: '',
            name: order.storeName ?? DeliveryStrings.of(context).tabShop,
            vertical: StoreVertical.restaurant,
            availability: StoreAvailability.open,
          ));

      int added = 0;
      int missing = 0;
      for (final OrderLine line in order.items) {
        final Product? product = byId[line.productId];
        if (product == null) {
          missing++;
          continue;
        }
        for (int i = 0; i < line.qty; i++) {
          widget.cart.add(product);
        }
        added++;
      }

      if (!mounted) return;
      final DeliveryStrings t = DeliveryStrings.of(context);
      // The plural is the string table's job, not an inline ternary: Arabic has six forms and
      // "1 item / n items" cannot express them.
      _say(missing == 0 ? t.addedToBasket(added) : t.addedSomeMissing(added, missing));
    } catch (_) {
      _say(DeliveryStrings.of(context).couldNotReorder);
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  Future<bool?> _confirmReplaceBasket() {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(DeliveryStrings.of(context).replaceYourBasket),
        content: Text(
            '${DeliveryStrings.of(context).basketFromShopReplace(widget.cart.store?.name ?? '')} '
            '${DeliveryStrings.of(context).reorderWillReplace}'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(DeliveryStrings.of(context).keepIt)),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: DeliveryColors.brand),
            child: Text(DeliveryStrings.of(context).replace),
          ),
        ],
      ),
    );
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final DeliveryOrder? order = _order;

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(
        title: t.custOrderStatus,
        onBack: () => Navigator.of(context).maybePop(),
        backSemanticLabel: t.back,
      ),
      body: order == null
          ? Center(
              child: _loading
                  ? const CircularProgressIndicator(color: DeliveryColors.brand)
                  : _errorState(t))
          : RefreshIndicator(
              color: DeliveryColors.brand,
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  _statusCard(t, order),
                  // Live tracking, which draws nothing once the order is finished.
                  OrderTrackingPanel(
                    api: widget.orderApi,
                    order: order,
                    trackingApi: widget.trackingApi,
                    chatApi: widget.chatApi,
                  ),
                  // After delivery, the rating takes the tracking panel's slot: the sheet once,
                  // the stars already given after that.
                  if (_ratingKnown)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                          start: DeliverySpacing.lg,
                          end: DeliverySpacing.lg,
                          top: DeliverySpacing.lg),
                      child: _ratingCard(t),
                    ),
                  _itemsBox(t, order),
                  Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: DeliverySpacing.lg),
                    child: _shopCard(t, order),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(DeliverySpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _receiptCard(t, order),
                        const SizedBox(height: DeliverySpacing.md),
                        YdPillButton(
                          label: t.reorder,
                          icon: Icons.refresh_rounded,
                          busy: _reordering,
                          onPressed:
                              _reordering || order.storeId == null ? null : _reorder,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // ------------------------------------------------------- the white status block, with stepper

  /// The five steps the design draws, in order.
  ///
  /// The wire has six — `READY` sits between PREPARING and PICKED_UP — and the design has no node
  /// for it. It is folded into "Preparing", which is then shown as *done*: the food is made and the
  /// order is waiting for a rider, which is exactly what a completed Preparing node with nothing
  /// lit after it says.
  static const List<String> _steps = <String>[
    'PLACED',
    'ACCEPTED',
    'PREPARING',
    'PICKED_UP',
    'DELIVERED',
  ];

  static int _stepIndex(String wire) => switch (wire) {
        'PLACED' => 0,
        'ACCEPTED' => 1,
        'PREPARING' => 2,
        'READY' => 2,
        'PICKED_UP' => 3,
        'DELIVERED' => 4,
        // Cancelled never reaches the stepper — it is not drawn for a stopped order.
        _ => 0,
      };

  /// Whether the node at [_stepIndex] is finished rather than in progress.
  static bool _stepSettled(String wire) => wire == 'READY' || wire == 'DELIVERED';

  String _stepLabel(DeliveryStrings t, String wire) => switch (wire) {
        'PLACED' => t.stepPlaced,
        'ACCEPTED' => t.stepAccepted,
        'PREPARING' => t.stepPreparing,
        'PICKED_UP' => t.stepOnTheWay,
        _ => t.stepDelivered,
      };

  Widget _statusCard(DeliveryStrings t, DeliveryOrder order) {
    final bool cancelled = order.status.wire == 'CANCELLED';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DeliverySpacing.lg),
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '${t.custOrderRef} #${order.shortId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.ink,
                        height: 1.3,
                      ),
                    ),
                    Text(
                      order.storeName ?? t.tabShop,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: DeliveryColors.muted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              CustomerStatusPill(
                statusWire: order.status.wire,
                label: order.status.labelIn(t),
              ),
            ],
          ),
          if (!cancelled) ...<Widget>[
            const SizedBox(height: 20),
            const Divider(height: 1, thickness: 1, color: DeliveryColors.border),
            const SizedBox(height: 20),
            _stepperRow(t, order),
          ],
        ],
      ),
    );
  }

  Widget _stepperRow(DeliveryStrings t, DeliveryOrder order) {
    final int current = _stepIndex(order.status.wire);
    final bool settled = _stepSettled(order.status.wire);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < _steps.length; i++)
          _stepNode(
            label: _stepLabel(t, _steps[i]),
            done: i < current || (i == current && settled),
            current: i == current && !settled,
          ),
      ],
    );
  }

  Widget _stepNode({required String label, required bool done, required bool current}) {
    late final Widget circle;
    if (done) {
      circle = Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: DeliveryAccent.positive.color,
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
        ),
        child: const Icon(Icons.check_rounded, size: 12, color: DeliveryColors.white),
      );
    } else if (current) {
      circle = Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: DeliveryColors.brand,
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          border: Border.all(color: DeliveryColors.brandSoft, width: 4),
        ),
      );
    } else {
      circle = Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: DeliveryColors.background,
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        circle,
        const SizedBox(height: DeliverySpacing.sm),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: current ? FontWeight.w700 : FontWeight.w500,
            color: current ? DeliveryColors.brand : DeliveryColors.muted,
            height: 1.2,
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ the rating

  /// One card, two states: the invitation to rate, or the stars already given. Drawn only once
  /// the server has answered whether a rating exists.
  Widget _ratingCard(DeliveryStrings t) {
    final RiderRatingEntry? rating = _rating;

    if (rating == null) {
      return YdCard(
        onTap: _rate,
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: DeliveryColors.brandSoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.star_outline_rounded,
                  size: 20, color: DeliveryColors.brand),
            ),
            const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    t.custRateYourRider,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: DeliveryColors.ink,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t.custHowWasDelivery,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DeliveryColors.muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Directionality.of(context) == TextDirection.rtl
                  ? Icons.chevron_left_rounded
                  : Icons.chevron_right_rounded,
              size: 18,
              color: DeliveryColors.muted,
            ),
          ],
        ),
      );
    }

    return YdCard(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              t.custAlreadyRatedDelivery,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.ink,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Semantics(
            label: t.ratingStars(rating.score),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int star = 1; star <= 5; star++)
                  Icon(
                    star <= rating.score
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 18,
                    color: star <= rating.score
                        ? DeliveryAccent.caution.color
                        : DeliveryColors.border,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ what was in it

  Widget _itemsBox(DeliveryStrings t, DeliveryOrder order) {
    return Padding(
      padding: const EdgeInsets.all(DeliverySpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            t.custItemsOrdered,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
              height: 1.25,
            ),
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          for (int i = 0; i < order.items.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: DeliverySpacing.sm),
            _itemRow(t, order.items[i]),
          ],
        ],
      ),
    );
  }

  /// One ordered line: a white radius-12 row, 12px padding, "2x Name" on the start side and the
  /// line total in bold on the end.
  ///
  /// The catalog thumbnail is kept where the design has only text — it is already fetched, and a
  /// picture is how somebody recognises what they ordered a week later. It sits inside the row's
  /// 12px padding at the same 12 radius, so the row's geometry is unchanged.
  Widget _itemRow(DeliveryStrings t, OrderLine line) {
    final String? thumbnail = _thumbnails[line.productId];

    return Container(
      decoration: BoxDecoration(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(DeliveryRadius.sm),
            child: SizedBox(
              width: 32,
              height: 32,
              child: thumbnail == null
                  ? StoreMonogram(name: line.productName, radius: 0)
                  : Image.network(
                      thumbnail,
                      fit: BoxFit.cover,
                      errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                          StoreMonogram(name: line.productName, radius: 0),
                    ),
            ),
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Text(
              t.lineQuantity(line.qty, line.productName),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: DeliveryColors.ink,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Text(
            line.lineTotal.toStringAsFixed(2),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ where it came from

  Widget _shopCard(DeliveryStrings t, DeliveryOrder order) {
    final String name = order.storeName ?? t.tabShop;
    final String? address = _store?.address;
    final bool canOpen = order.storeId != null;

    return YdCard(
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(DeliveryRadius.sheet),
            child: StoreAvatar(name: name, logoUrl: _store?.logoUrl, size: 48),
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
                if (address != null && address.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    address,
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
          if (canOpen) ...<Widget>[
            const SizedBox(width: DeliverySpacing.sm),
            _circleAction(
              // The design's 36px tinted circle, carrying the action this app actually has: open
              // the shop. Calling a merchant needs a number the order does not carry and a
              // telephony intent nothing in the app has yet.
              icon: Directionality.of(context) == TextDirection.rtl
                  ? Icons.chevron_left_rounded
                  : Icons.chevron_right_rounded,
              semanticLabel: t.openStore(name),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => StorePageScreen(
                  storeApi: widget.storeApi,
                  orderApi: widget.orderApi,
                  cart: widget.cart,
                  storeId: order.storeId!,
                  preview: _store?.toCard(),
                ),
              )),
            ),
          ],
        ],
      ),
    );
  }

  /// The 36px brand-tinted circular action the design puts at the end of the shop card.
  Widget _circleAction({
    required IconData icon,
    required String semanticLabel,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: DeliveryColors.brandSoft,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: 36,
            child: Icon(icon, size: 16, color: DeliveryColors.brand),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ what it cost (kept)

  Widget _receiptCard(DeliveryStrings t, DeliveryOrder order) {
    return YdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            _timestampLine(t, order),
            style: const TextStyle(fontSize: 12, color: DeliveryColors.faint, height: 1.3),
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          _money(t.subtotal, order.goodsSubtotal),
          const SizedBox(height: DeliverySpacing.sm),
          _money(
            t.deliveryCharge,
            // What was CHARGED, not what it cost. Rendering the cost here against a total that
            // excludes it produced a receipt that did not add up. The waived fee is still shown,
            // as the word "free", below.
            order.deliveryFeeCharged,
            // The fee is set per shop, and a customer comparing two shops is comparing exactly
            // this line — so it says where it came from rather than appearing as a mystery.
            info: order.deliveryFeeWaived
                ? t.deliveryWasFree(order.deliveryFee.toStringAsFixed(2))
                : t.setByStoreCharged(order.storeName ?? ''),
            override: order.deliveryFeeCharged == 0 ? t.free : null,
          ),
          // The promo code's line, only on orders that carried one — null means no code, which
          // is not the same receipt as a code worth zero.
          if (order.discountAmount != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Row(
              children: <Widget>[
                Text(
                  order.promoCode ?? t.custDiscounts,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: DeliveryColors.muted,
                    height: 1.3,
                  ),
                ),
                const Spacer(),
                Text(
                  '-${order.discountAmount!.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DeliveryAccent.positive.color,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: DeliverySpacing.md - DeliverySpacing.xs),
            child: Divider(height: 1, thickness: 1, color: DeliveryColors.border),
          ),
          _money(t.total, order.totalAmount, emphasised: true),
          // How it is being paid, on the receipt rather than only at checkout: a customer opening
          // an order that has not arrived yet is often checking exactly whether they need cash
          // ready at the door.
          const SizedBox(height: DeliverySpacing.sm),
          Row(
            children: <Widget>[
              const Icon(Icons.payments_outlined, size: 16, color: DeliveryColors.muted),
              const SizedBox(width: DeliverySpacing.xs + 2),
              Expanded(
                child: Text(
                  // Non-cash means the DEV provider held nothing real, and the receipt says so —
                  // a dev authorisation must never read as a live charge.
                  order.paymentMethod.needsProvider
                      ? '${order.paymentMethod == PaymentMethod.wallet ? t.paymentWallet : order.paymentMethod.labelIn(t)} · ${t.custTestPayment}'
                      : order.paymentMethod.labelIn(t),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.muted,
                    height: 1.3,
                  ),
                ),
              ),
              Text(
                order.paymentStatus.labelIn(t),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: order.paymentStatus.isSettled
                      ? DeliveryAccent.positive.color
                      : DeliveryColors.muted,
                  height: 1.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.place_outlined, size: 16, color: DeliveryColors.muted),
              const SizedBox(width: DeliverySpacing.xs + 2),
              Expanded(
                child: Text(
                  order.deliveryAddress,
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
      ),
    );
  }

  Widget _money(String label, double amount,
      {bool emphasised = false, String? override, String? info}) {
    final TextStyle style = TextStyle(
      fontSize: emphasised ? 15 : 13,
      fontWeight: emphasised ? FontWeight.w700 : FontWeight.w500,
      color: emphasised ? DeliveryColors.ink : DeliveryColors.muted,
      height: 1.3,
    );
    return Row(
      children: <Widget>[
        Text(label, style: style),
        if (info != null) ...<Widget>[
          const SizedBox(width: DeliverySpacing.xs + 2),
          Tooltip(
            message: info,
            triggerMode: TooltipTriggerMode.tap,
            showDuration: const Duration(seconds: 4),
            child: const Icon(Icons.info_outline_rounded,
                size: 15, color: DeliveryColors.faint),
          ),
        ],
        const Spacer(),
        Text(override ?? amount.toStringAsFixed(2),
            style: style.copyWith(color: DeliveryColors.ink)),
      ],
    );
  }

  /// "Delivered on: Wednesday, 23 April, 09:42 PM", or the equivalent for whatever state it is in.
  String _timestampLine(DeliveryStrings t, DeliveryOrder order) {
    final DateTime? when = order.deliveredAt ?? order.placedAt;
    if (when == null) {
      return order.status.labelIn(t);
    }
    final String when12 = _formatWhen(context, when);
    return order.deliveredAt != null ? t.deliveredOn(when12) : t.placedOn(when12);
  }

  /// Formatted through `intl` against the active locale, which brings the ordering and numerals
  /// Arabic actually uses rather than English ones rearranged.
  static String _formatWhen(BuildContext context, DateTime when) {
    final String locale = Localizations.localeOf(context).toLanguageTag();
    return intl.DateFormat.yMMMEd(locale).add_jm().format(when);
  }

  // ------------------------------------------------------------------ shell

  Widget _errorState(DeliveryStrings t) {
    return YdEmptyState(
      icon: Icons.cloud_off_rounded,
      title: t.couldNotLoadOrder,
      action: YdPillButton(
        label: t.tryAgain,
        expand: false,
        size: YdPillButtonSize.compact,
        onPressed: _load,
      ),
    );
  }
}

/// The redesign's status pill: a 12%-tint fill, radius 12, 12/6 padding, SemiBold 12 label.
///
/// The *colour* is not chosen here. It comes from [OrderStatusBadge.colorFor], the single place the
/// platform maps an order status onto a colour — Appendix A requires a status to mean the same
/// thing in the backoffice tables, the merchant portal and in-app tracking, so this widget owns the
/// geometry the design drew and nothing else. (The frames paint every pill in the brand rose; that
/// would make "preparing" and "on the way" indistinguishable, so the shared mapping wins.)
class CustomerStatusPill extends StatelessWidget {
  const CustomerStatusPill({super.key, required this.statusWire, required this.label});

  /// The wire value, e.g. `PREPARING`.
  final String statusWire;

  /// Already localised by the caller.
  final String label;

  @override
  Widget build(BuildContext context) {
    final Color color = OrderStatusBadge.colorFor(statusWire);

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: DeliverySpacing.md - DeliverySpacing.xs,
        vertical: DeliverySpacing.sm - 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
          height: 1.2,
        ),
      ),
    );
  }
}
