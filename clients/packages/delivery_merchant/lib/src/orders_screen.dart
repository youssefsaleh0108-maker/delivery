import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'order_detail_screen.dart';

/// The merchant's incoming order queue — Figma `merchant-orders` (3:1822), "Order Flow".
///
/// Polls rather than holding a socket: Section 9 specifies WebSocket/STOMP for live order tracking,
/// but that belongs to Order Tracking and the customer's map. A merchant queue refreshing every few
/// seconds is indistinguishable in practice and avoids a second realtime transport for one screen.
///
/// One widget, two hosts. The portal gives it most of a window; the phone gives it 402dp and a
/// thumb. The redesign settles that with one column at the design's own measure, centred in
/// whatever room the host has — a queue that accepts and rejects orders is exactly the page that
/// must not exist in two versions, because the second one is where a state transition eventually
/// goes missing.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, required this.api});

  final OrderApi api;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

/// The four buckets the design's tab strip splits the queue into.
///
/// Derived from the order's own status rather than fetched per tab: the list is loaded once and
/// counted client-side, so the numbers in the tabs and the rows underneath them can never disagree
/// — which is what happens when four filtered requests come back at four different moments.
///
/// Nothing falls between the buckets. `PICKED_UP` sits with `ready` rather than in `completed`
/// because the shop's part is done but the order is not, and an order that vanished from every tab
/// the moment a rider took it would look to a merchant exactly like an order that was lost.
enum _Bucket {
  fresh(<OrderStatus>[OrderStatus.placed]),
  preparing(<OrderStatus>[OrderStatus.accepted, OrderStatus.preparing]),
  ready(<OrderStatus>[OrderStatus.ready, OrderStatus.pickedUp]),
  completed(<OrderStatus>[OrderStatus.delivered, OrderStatus.cancelled]);

  const _Bucket(this.statuses);

  final List<OrderStatus> statuses;

  bool holds(DeliveryOrder order) => statuses.contains(order.status);

  String labelIn(DeliveryStrings t) => switch (this) {
        _Bucket.fresh => t.merchTabNew,
        _Bucket.preparing => t.stepPreparing,
        _Bucket.ready => t.stepReady,
        _Bucket.completed => t.merchTabCompleted,
      };
}

class _OrdersScreenState extends State<OrdersScreen> {
  static const Duration _pollInterval = Duration(seconds: 5);

  /// Under this width the whole page scrolls instead of pinning its header.
  ///
  /// 640 rather than a phone's 360: the question is not "is this a phone" but "is there room to
  /// spend on a header that never moves", and there is not once the window is narrow enough that
  /// the title band and the tab strip are a meaningful share of the height.
  static const double _narrowWidth = 640;

  /// Under this height a pinned header is not worth what it costs.
  ///
  /// A phone turned sideways is wide and about 360dp tall. The title band and the tab strip take
  /// roughly a third of that, which leaves the queue a single truncated row — so below this the
  /// header scrolls away with everything else, whatever the width says.
  static const double _shortHeight = 560;

  /// The padding the design puts around the card list.
  static const double _listPad = DeliverySpacing.md + DeliverySpacing.xs;

  Timer? _poll;
  List<DeliveryOrder> _orders = <DeliveryOrder>[];
  Object? _error;
  bool _loading = true;
  String? _busyOrderId;

  _Bucket _bucket = _Bucket.fresh;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(_pollInterval, (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final Paged<DeliveryOrder> page = await widget.api.forMerchant(size: 50);
      if (!mounted) return;
      setState(() {
        _orders = page.content;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // A failed background poll must not wipe the list the merchant is looking at.
      setState(() {
        if (!silent) _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _act(DeliveryOrder order, OrderAction action) async {
    setState(() => _busyOrderId = order.id);
    final DeliveryStrings t = DeliveryStrings.of(context);
    try {
      // Not translated: the reason is stored against the order and read by Backoffice staff and
      // support, not shown back to the merchant who triggered it.
      await widget.api.act(order.id, action,
          reason: action == OrderAction.cancel ? 'Cancelled by merchant' : null);
      await _refresh(silent: true);
    } on DioException catch (e) {
      if (!mounted) return;
      // 422 means the order moved on since this list was drawn — someone else acted first.
      final String message = e.response?.statusCode == 422
          ? t.orderAlreadyMovedRefreshing
          : t.actionFailed(merchantActionLabel(action, t).toLowerCase());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      await _refresh(silent: true);
    } finally {
      if (mounted) setState(() => _busyOrderId = null);
    }
  }

  void _open(DeliveryOrder order) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MerchantOrderDetailScreen(
        api: widget.api,
        order: order,
        // The detail screen can move an order along too, so the queue behind it reloads rather
        // than sitting on a status the merchant has just changed.
        onChanged: (_) => _refresh(silent: true),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<DeliveryOrder> visible =
        _orders.where(_bucket.holds).toList(growable: false);

    // The white bands run edge to edge, as the design draws them and as a hairline under a 1400px
    // window has to; only the content column is held to the design's measure.
    final Widget header = MerchantScreenHeader(
      title: t.merchOrderFlow,
      subtitle: t.merchManagerView,
      // The design's header end is empty; the portal has always had an explicit refresh
      // and losing it would leave a mouse with only a drag gesture to reload a live queue.
      trailing: IconButton(
        onPressed: () => _refresh(),
        icon: const Icon(Icons.refresh, size: 20),
        color: DeliveryColors.muted,
        tooltip: t.refresh,
      ),
    );

    return ColoredBox(
      color: DeliveryColors.background,
      // Measured rather than asked of MediaQuery: the portal hands this widget the space left
      // beside a navigation rail, which is narrower than the window, and a phone host may put it
      // beside nothing at all.
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // On a phone the header and the counted tabs scroll away with the queue. Pinning them
          // spends a third of a 640dp screen on a title the merchant has already read, and on a
          // handset turned sideways it leaves the list a single truncated row.
          final bool pageScrolls = constraints.maxWidth < _narrowWidth ||
              constraints.maxHeight < _shortHeight;

          if (!pageScrolls) {
            // The wide shape the portal has always had: header pinned, only the list scrolls.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                header,
                _tabs(t),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _refresh(),
                    color: DeliveryColors.brand,
                    child: _capped(_body(t, visible)),
                  ),
                ),
              ],
            );
          }

          return RefreshIndicator(
            // Pull-to-refresh, since the refresh button now scrolls away with the header — and it
            // is the gesture a thumb reaches for on a list that is supposed to be live anyway.
            onRefresh: () => _refresh(),
            color: DeliveryColors.brand,
            child: CustomScrollView(
              // One scroll view for the page, not a pinned block above a second one: two
              // scrollables stacked is how a thumb ends up dragging the wrong one.
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: <Widget>[
                SliverToBoxAdapter(child: header),
                SliverToBoxAdapter(child: _tabs(t)),
                _bodySliver(t, visible, constraints.maxWidth),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Holds the phone design at its own measure and centres it, so the same widget reads the same
  /// way in 402dp of handset and in the portal's window.
  Widget _capped(Widget child) => Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: merchantMaxContentWidth),
          child: child,
        ),
      );

  // -------------------------------------------------------------------- tabs

  /// The design's tab strip — four pills, and the counts that used to be four tiles.
  ///
  /// A [Wrap] and not the horizontal scroller the frame implies. Four translated labels carrying
  /// their counts are wider than 320dp, and a sideways scroller on a phone is the worst of the
  /// three ways to handle that: it hides "Completed" off the edge with nothing to say so, it takes
  /// a horizontal drag on top of the vertical one the queue already wants, and under a wide window
  /// it is dead weight. Wrapping to a second run costs one line on the narrowest phone, is
  /// invisible everywhere the strip fits, and cannot overflow.
  Widget _tabs(DeliveryStrings t) {
    return Container(
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(
        DeliverySpacing.lg,
        DeliverySpacing.md - DeliverySpacing.xs,
        DeliverySpacing.lg,
        DeliverySpacing.md - DeliverySpacing.xs,
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: <Widget>[
          for (final _Bucket bucket in _Bucket.values) _tab(bucket, t),
        ],
      ),
    );
  }

  Widget _tab(_Bucket bucket, DeliveryStrings t) {
    final bool selected = bucket == _bucket;
    // Counted from everything loaded, not from the tab in view: switching tabs changes which rows
    // are listed, not whether today's orders happened.
    final int count = _orders.where(bucket.holds).length;
    // The design draws the count only where there is one — "New (3)", but a bare "Ready".
    final String label =
        count == 0 ? bucket.labelIn(t) : '${bucket.labelIn(t)} ($count)';

    final BorderRadius corners = BorderRadius.circular(DeliveryRadius.pill);

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? DeliveryColors.brand : DeliveryColors.background,
        shape: RoundedRectangleBorder(borderRadius: corners),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: selected ? null : () => setState(() => _bucket = bucket),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: DeliverySpacing.md,
              vertical: DeliverySpacing.sm,
            ),
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? DeliveryColors.white : DeliveryColors.muted,
                height: 1.25,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------- body

  /// The wide host's body: a list under a pinned header.
  Widget _body(DeliveryStrings t, List<DeliveryOrder> visible) {
    const EdgeInsetsGeometry pad = EdgeInsetsDirectional.all(_listPad);

    final Widget? standIn = _standIn(t, visible);
    if (standIn != null) {
      // Always scrollable, or the pull is dead on exactly the two states where a merchant most
      // wants to retry: nothing loaded, and nothing to show.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pad,
        children: <Widget>[standIn],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: pad,
      itemCount: visible.length,
      separatorBuilder: (_, __) => const SizedBox(height: DeliverySpacing.md),
      itemBuilder: (BuildContext context, int i) => _card(visible[i]),
    );
  }

  /// The same body as [_body], as a sliver, so the phone's header scrolls with it.
  ///
  /// Deliberately the same pieces rather than a second rendering of the queue: the two hosts differ
  /// in what scrolls, and nothing else.
  Widget _bodySliver(DeliveryStrings t, List<DeliveryOrder> visible, double width) {
    // The design's measure, held here instead of in [_capped]: a sliver list centres itself with
    // padding, and the white bands above it still run edge to edge.
    final double side = width > merchantMaxContentWidth
        ? (width - merchantMaxContentWidth) / 2
        : 0;
    final EdgeInsets pad =
        EdgeInsets.fromLTRB(_listPad + side, _listPad, _listPad + side, _listPad);

    final Widget? standIn = _standIn(t, visible);
    if (standIn != null) {
      return SliverPadding(padding: pad, sliver: SliverToBoxAdapter(child: standIn));
    }

    return SliverPadding(
      padding: pad,
      sliver: SliverList.separated(
        itemCount: visible.length,
        separatorBuilder: (_, __) => const SizedBox(height: DeliverySpacing.md),
        itemBuilder: (BuildContext context, int i) => _card(visible[i]),
      ),
    );
  }

  Widget _card(DeliveryOrder order) => _OrderCard(
        order: order,
        busy: _busyOrderId == order.id,
        onAction: (OrderAction a) => _act(order, a),
        onOpen: () => _open(order),
      );

  /// What stands in for the list — loading, failed, or an empty bucket — or null when there are
  /// rows to draw.
  ///
  /// Returned rather than rendered because the two layouts place it differently: one inside a
  /// ListView, one inside the page's own scroll.
  Widget? _standIn(DeliveryStrings t, List<DeliveryOrder> visible) {
    final Widget? placeholder = _placeholder(t);
    if (placeholder != null) return placeholder;
    if (visible.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(height: DeliverySpacing.xl),
          YdEmptyState(
            icon: Icons.receipt_long_outlined,
            title: _bucket == _Bucket.completed
                ? t.noOrdersYetMerchant
                : t.noOrdersNeedingAttention,
            message: t.merchNothingInThisList,
          ),
        ],
      );
    }
    return null;
  }

  /// What to show instead of the list, or null when the list can be drawn.
  Widget? _placeholder(DeliveryStrings t) {
    if (_error != null) {
      return YdEmptyState(
        icon: Icons.cloud_off_rounded,
        title: t.couldNotLoadOrdersShort,
        message: '$_error',
        // A button, not just the message: the header may have scrolled past on a phone, and a
        // dead end that only says what went wrong is a dead end.
        action: YdPillButton.secondary(
          label: t.tryAgain,
          onPressed: () => _refresh(),
          size: YdPillButtonSize.compact,
          expand: false,
        ),
      );
    }
    if (_loading && _orders.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(DeliverySpacing.xl),
        child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
      );
    }
    return null;
  }
}

/// One row of the queue — Figma `new-order-card` (3:1844) and `preparing-order-card` (3:1858).
///
/// The two are the same card with two differences the design is precise about: an order still
/// waiting to be accepted is ringed in [DeliveryColors.brand], and the action row holds whatever
/// the server says is possible rather than a fixed pair.
class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.busy,
    required this.onAction,
    required this.onOpen,
  });

  final DeliveryOrder order;
  final bool busy;
  final void Function(OrderAction) onAction;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool isNew = order.status == OrderStatus.placed;
    final String age = merchantTimeAgo(order.placedAt, t);

    return YdCard.bordered(
      onTap: onOpen,
      borderColor: isNew ? DeliveryColors.brand : DeliveryColors.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '#${order.shortId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
              ),
              if (age.isNotEmpty) ...<Widget>[
                const SizedBox(width: DeliverySpacing.sm),
                Text(
                  age,
                  maxLines: 1,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DeliveryColors.faint,
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          // The design leads this block with the customer's name. The order payload has a customer
          // *id* and no name, so the state goes in that slot instead — which the tab strip only
          // implies, and stops implying the moment somebody looks at "Completed" and cannot tell a
          // delivered order from a cancelled one.
          MerchantStatusTag(status: order.status, label: order.status.labelIn(t)),
          const SizedBox(height: DeliverySpacing.xs),
          Text(
            order.items
                .map((OrderLine line) => t.lineQuantity(line.qty, line.productName))
                .join(', '),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: DeliveryColors.muted,
              height: 1.4,
            ),
          ),
          if (order.deliveryAddress.isNotEmpty) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.place_outlined, size: 14, color: DeliveryColors.faint),
                const SizedBox(width: DeliverySpacing.xs),
                Expanded(
                  child: Text(
                    order.deliveryAddress,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DeliveryColors.faint,
                      height: 1.35,
                    ),
                  ),
                ),
                if (order.riderId != null) ...<Widget>[
                  const SizedBox(width: DeliverySpacing.sm),
                  const Icon(Icons.two_wheeler, size: 14, color: DeliveryColors.faint),
                  const SizedBox(width: DeliverySpacing.xs),
                  Text(
                    t.riderAssigned,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DeliveryColors.faint,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ],
          // A waiver on this order is the merchant's own money, so it is said on the row rather
          // than left to be noticed in a payout statement at the end of the month.
          if (order.merchantFeeWaived || order.deliveryFeeWaived) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            Row(
              children: <Widget>[
                const Icon(Icons.redeem_rounded, size: 14, color: DeliveryColors.brand),
                const SizedBox(width: DeliverySpacing.xs),
                Expanded(
                  child: Text(
                    order.merchantFeeWaived
                        ? t.noCommissionOnThisOrder
                        : t.deliveryPaidByPlatform,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DeliveryColors.brand,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: DeliverySpacing.xs),
          Text(
            merchantMoney(order.totalAmount),
            maxLines: 1,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.brand,
              height: 1.25,
            ),
          ),
          // Buttons come from availableActions, which the SERVICE computed. Rendering anything
          // else would offer a merchant a transition the state machine would refuse.
          if (order.availableActions.isNotEmpty) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            const MerchantDivider(),
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            Row(
              children: <Widget>[
                for (int i = 0; i < order.availableActions.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: DeliverySpacing.sm),
                  Expanded(
                    child: MerchantActionButton(
                      label: merchantActionLabel(order.availableActions[i], t),
                      onPressed:
                          busy ? null : () => onAction(order.availableActions[i]),
                      primary: order.availableActions[i] != OrderAction.cancel,
                      busy: busy,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
