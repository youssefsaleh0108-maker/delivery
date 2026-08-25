import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// The merchant's incoming order queue (Phase 2).
///
/// Polls rather than holding a socket: Section 9 specifies WebSocket/STOMP for live order tracking,
/// but that belongs to Order Tracking and the customer's map. A merchant queue refreshing every few
/// seconds is indistinguishable in practice and avoids a second realtime transport for one screen.
///
/// One widget, two hosts. The portal gives it a wide window next to a rail; the Android app gives
/// it 360dp and a thumb. The difference is a layout branch rather than a second screen — a queue
/// that accepts and cancels orders is exactly the page that must not exist in two versions, because
/// the second one is where a state transition eventually goes missing.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, required this.api});

  final OrderApi api;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  static const Duration _pollInterval = Duration(seconds: 5);

  /// Under this width the header stacks and the cards go to one column.
  ///
  /// 640 rather than a phone's 360: the point is not "is this a phone" but "does the title, the
  /// completed-orders toggle and a refresh button still fit on one line", and in Arabic they stop
  /// fitting well before a tablet.
  static const double _narrowWidth = 640;

  /// Under this height a pinned header is not worth what it costs.
  ///
  /// A phone turned sideways is wide and about 360dp tall. The title and the four counters take
  /// roughly 280 of that, which leaves the list a single truncated row — so below this the header
  /// scrolls away with everything else, whatever the width says.
  static const double _shortHeight = 560;

  Timer? _poll;
  List<DeliveryOrder> _orders = <DeliveryOrder>[];
  Object? _error;
  bool _loading = true;
  String? _busyOrderId;

  /// Terminal orders are hidden by default: a merchant cares about what still needs work, and a
  /// day's delivered orders would bury the two that don't.
  bool _showCompleted = false;

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
    try {
      // Not translated: the reason is stored against the order and read by Backoffice staff and
      // support, not shown back to the merchant who triggered it.
      await widget.api.act(order.id, action,
          reason: action == OrderAction.cancel ? 'Cancelled by merchant' : null);
      await _refresh(silent: true);
    } on DioException catch (e) {
      if (!mounted) return;
      // 422 means the order moved on since this list was drawn - someone else acted first.
      final String message = e.response?.statusCode == 422
          ? DeliveryStrings.of(context).orderAlreadyMovedRefreshing
          : DeliveryStrings.of(context)
              .actionFailed(action.labelIn(DeliveryStrings.of(context)).toLowerCase());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      await _refresh(silent: true);
    } finally {
      if (mounted) setState(() => _busyOrderId = null);
    }
  }

  /// The four numbers a merchant opens this page to see.
  ///
  /// Counted from everything loaded, not from the filtered view: hiding completed orders should
  /// change which rows are listed, not whether today's deliveries happened.
  Widget _counters(DeliveryStrings t) {
    int of(OrderStatus s) => _orders.where((DeliveryOrder o) => o.status == s).length;
    final int waiting = of(OrderStatus.placed);
    final int making = of(OrderStatus.preparing) + of(OrderStatus.accepted);
    final int ready = of(OrderStatus.ready);
    final int done = of(OrderStatus.delivered);

    // StatRow already reflows to whatever columns fit, so four tiles become two rows of two on a
    // phone without this screen having to say so.
    return StatRow(tiles: <Widget>[
      StatTile(
        value: '$waiting',
        label: t.columnToAccept,
        icon: Icons.notifications_active_outlined,
        // The only genuinely urgent one: a customer is waiting to hear back.
        accent: waiting == 0 ? DeliveryAccent.positive : DeliveryAccent.caution,
      ),
      StatTile(
        value: '$making',
        label: t.columnPreparing,
        icon: Icons.soup_kitchen_outlined,
        accent: DeliveryAccent.info,
      ),
      StatTile(
        value: '$ready',
        label: t.columnAwaitingRider,
        icon: Icons.pedal_bike_rounded,
        accent: ready == 0 ? DeliveryAccent.positive : DeliveryAccent.neutral,
      ),
      StatTile(
        value: '$done',
        label: t.columnDelivered,
        icon: Icons.check_circle_outline_rounded,
        accent: DeliveryAccent.positive,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<DeliveryOrder> visible = _showCompleted
        ? _orders
        : _orders.where((DeliveryOrder o) => !o.status.isTerminal).toList();

    // Measured rather than asked of MediaQuery: the portal hands this widget the space left beside
    // a navigation rail, which is narrower than the window, and a phone host may put it beside
    // nothing at all.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < _narrowWidth;
        final bool pageScrolls = narrow || constraints.maxHeight < _shortHeight;
        final EdgeInsets pad =
            EdgeInsets.all(narrow ? DeliverySpacing.md : DeliverySpacing.lg);
        final Widget? placeholder = _placeholder(t, visible);

        // The wide shape the portal has always had: header pinned, only the list scrolls.
        if (!pageScrolls) {
          return Padding(
            padding: pad,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ..._header(t, narrow: narrow),
                const SizedBox(height: DeliverySpacing.lg),
                SectionLabel(t.liveOrders),
                Expanded(child: placeholder ?? _list(visible, narrow: narrow)),
              ],
            ),
          );
        }

        return RefreshIndicator(
          // Pull-to-refresh, since the refresh button now scrolls away with the header — and it is
          // the gesture a thumb reaches for on a list that is supposed to be live anyway.
          onRefresh: () => _refresh(),
          color: DeliveryColors.brand,
          child: CustomScrollView(
            // Always scrollable, or the pull is dead on exactly the two states where a merchant
            // most wants to retry: nothing loaded, and nothing to show.
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverPadding(
                padding: pad.copyWith(bottom: 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      ..._header(t, narrow: narrow),
                      const SizedBox(height: DeliverySpacing.lg),
                      SectionLabel(t.liveOrders),
                    ],
                  ),
                ),
              ),
              if (placeholder != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: pad.left),
                    child: placeholder,
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, pad.bottom),
                  sliver: SliverList.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: DeliverySpacing.sm),
                    itemBuilder: (BuildContext context, int i) =>
                        _card(visible[i], narrow: narrow),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Everything above the list: the title line, the poll note and the counters.
  ///
  /// A list rather than a Column so both layouts can place the same pieces — the wide one above a
  /// scrolling list, the narrow one inside the page's own scroll.
  List<Widget> _header(DeliveryStrings t, {required bool narrow}) {
    return <Widget>[
      Row(
        children: <Widget>[
          Expanded(
            child: Row(
              children: <Widget>[
                // Flexible, not fixed: a headline that cannot shrink is what pushes a refresh
                // button off the side of a 320dp screen.
                Flexible(
                  child: Text(
                    t.navOrders,
                    style: Theme.of(context).textTheme.headlineMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_loading) ...<Widget>[
                  const SizedBox(width: DeliverySpacing.md),
                  const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ],
            ),
          ),
          // On a wide window the toggle sits on the title line where it always has. On a phone it
          // gets its own row below, where the label itself is a tap target.
          if (!narrow) ...<Widget>[
            Text(t.showCompleted),
            Switch(
              value: _showCompleted,
              activeThumbColor: DeliveryColors.brand,
              onChanged: (bool v) => setState(() => _showCompleted = v),
            ),
          ],
          IconButton(
            onPressed: () => _refresh(),
            icon: const Icon(Icons.refresh),
            // A tooltip is a hover affordance on the web and a long-press one on Android, so it
            // survives the move to a phone. It is not the only way to refresh either — see the
            // pull-to-refresh on the narrow layout.
            tooltip: t.refresh,
          ),
        ],
      ),
      Text(t.updatesEvery(_pollInterval.inSeconds),
          style: Theme.of(context).textTheme.bodySmall),
      if (narrow)
        SwitchListTile(
          value: _showCompleted,
          onChanged: (bool v) => setState(() => _showCompleted = v),
          activeThumbColor: DeliveryColors.brand,
          contentPadding: EdgeInsets.zero,
          title: Text(t.showCompleted, style: Theme.of(context).textTheme.bodyMedium),
        ),
      const SizedBox(height: DeliverySpacing.md),
      _counters(t),
    ];
  }

  /// What to show instead of a list, or null when there are orders to draw.
  ///
  /// Returned rather than rendered because the two layouts place it differently: the wide one fills
  /// the space under a pinned header, the narrow one fills what is left of the page's scroll.
  Widget? _placeholder(DeliveryStrings t, List<DeliveryOrder> visible) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('${t.couldNotLoadOrdersShort}\n$_error', textAlign: TextAlign.center),
            const SizedBox(height: DeliverySpacing.sm),
            // A button, not just the message. On a phone the header may have been scrolled past,
            // and a dead end that only says what went wrong is a dead end.
            TextButton(onPressed: () => _refresh(), child: Text(t.tryAgain)),
          ],
        ),
      );
    }
    if (_loading && _orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (visible.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.receipt_long_outlined, size: 40, color: DeliveryColors.muted),
            const SizedBox(height: DeliverySpacing.sm),
            Text(
              _showCompleted ? t.noOrdersYetMerchant : t.noOrdersNeedingAttention,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return null;
  }

  Widget _list(List<DeliveryOrder> visible, {required bool narrow}) => ListView.separated(
        itemCount: visible.length,
        separatorBuilder: (_, __) => const SizedBox(height: DeliverySpacing.sm),
        itemBuilder: (BuildContext context, int i) => _card(visible[i], narrow: narrow),
      );

  Widget _card(DeliveryOrder order, {required bool narrow}) => _OrderCard(
        order: order,
        busy: _busyOrderId == order.id,
        compact: narrow,
        onAction: (OrderAction a) => _act(order, a),
      );
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.busy,
    required this.compact,
    required this.onAction,
  });

  final DeliveryOrder order;
  final bool busy;

  /// One column, and buttons big enough for a thumb.
  final bool compact;

  final void Function(OrderAction) onAction;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return SoftCard(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _headline(context, t),
            // A waiver on this order is the merchant's own money, so it is said on the row rather
            // than left to be noticed in a payout statement at the end of the month.
            if (order.merchantFeeWaived || order.deliveryFeeWaived) ...<Widget>[
              const SizedBox(height: DeliverySpacing.xs),
              Row(
                children: <Widget>[
                  const Icon(Icons.redeem_rounded, size: 15, color: DeliveryColors.brand),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.merchantFeeWaived
                          ? t.noCommissionOnThisOrder
                          : t.deliveryPaidByPlatform,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: DeliveryColors.brand),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: DeliverySpacing.sm),
            for (final OrderLine line in order.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(t.lineQuantity(line.qty, line.productName),
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
            const SizedBox(height: DeliverySpacing.sm),
            _where(context, t),
            if (order.notes != null && order.notes!.isNotEmpty) ...<Widget>[
              const SizedBox(height: DeliverySpacing.xs),
              Text(t.noteWithText(order.notes!), style: Theme.of(context).textTheme.bodySmall),
            ],

            // Buttons come from availableActions, which the SERVICE computed. Rendering anything
            // else would offer a merchant a transition the state machine would refuse.
            if (order.availableActions.isNotEmpty) ...<Widget>[
              const Divider(height: DeliverySpacing.lg),
              // Wrap, not Row: three actions and a translated label overflow a 360dp card, and a
              // Wrap also spaces its children symmetrically, which the trailing right-padding it
              // replaces did not do in Arabic.
              Wrap(
                spacing: DeliverySpacing.sm,
                runSpacing: DeliverySpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  for (final OrderAction action in order.availableActions)
                    action == OrderAction.cancel
                        ? OutlinedButton(
                            style: _touch,
                            onPressed: busy ? null : () => onAction(action),
                            child: Text(action.labelIn(t)))
                        : ElevatedButton(
                            style: _touch,
                            onPressed: busy ? null : () => onAction(action),
                            child: Text(action.labelIn(t))),
                  if (busy)
                    const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            ],
          ],
        ),
    );
  }

  /// Status, order id and total — the line the merchant scans down.
  ///
  /// Three pieces on one line only works while two of them can be measured and the third given
  /// what is left. On a 320dp card there is nothing left: a translated status badge and a
  /// four-figure total are both intrinsically sized and together they are wider than the card, so
  /// the id's Expanded collapses to zero and the row overflows off the right edge — invisibly, in
  /// a release build. Compact therefore gives the badge a line of its own, which also gives the
  /// longer Arabic statuses room to be read rather than wrapped inside their own pill.
  Widget _headline(BuildContext context, DeliveryStrings t) {
    // The badge carries its own English label unless it is given one, which is how a translated
    // screen ends up with an English status on every row.
    final Widget badge =
        OrderStatusBadge(statusWire: order.status.wire, label: order.status.labelIn(t));
    final Widget id = Text('#${order.shortId}',
        style: Theme.of(context).textTheme.titleMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis);
    // Never ellipsised and never flexible: a total cut to "123…" is worse than no total at all.
    final Widget total = Text(order.totalAmount.toStringAsFixed(2),
        style: Theme.of(context).textTheme.titleLarge, maxLines: 1);

    if (!compact) {
      // Expanded rather than a Spacer: the id is the part that can afford to be cut when a
      // translated status badge and a four-figure total leave it nothing.
      return Row(
        children: <Widget>[
          badge,
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(child: id),
          const SizedBox(width: DeliverySpacing.sm),
          total,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: id),
            const SizedBox(width: DeliverySpacing.sm),
            total,
          ],
        ),
        const SizedBox(height: DeliverySpacing.xs),
        badge,
      ],
    );
  }

  /// Where it is going, and whether anybody is taking it.
  ///
  /// Side by side on a wide window. On a phone the rider note goes underneath instead: sharing the
  /// line leaves the address about half a screen, and an address ellipsised at "12 Rue de…" tells a
  /// merchant nothing they can act on.
  Widget _where(BuildContext context, DeliveryStrings t) {
    final Widget address = Row(
      children: <Widget>[
        const Icon(Icons.place_outlined, size: 16, color: DeliveryColors.muted),
        const SizedBox(width: 4),
        Expanded(
          child: Text(order.deliveryAddress,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: compact ? 2 : 1,
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );

    if (order.riderId == null) return address;

    final Widget rider = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.two_wheeler, size: 16, color: DeliveryColors.muted),
        const SizedBox(width: 4),
        Text(t.riderAssigned, style: Theme.of(context).textTheme.bodySmall),
      ],
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          address,
          const SizedBox(height: DeliverySpacing.xs),
          rider,
        ],
      );
    }
    return Row(children: <Widget>[Expanded(child: address), rider]);
  }

  /// 48dp minimum on a phone.
  ///
  /// Material's default button is 40 high. That is fine under a mouse and not fine for the control
  /// that accepts or cancels somebody's dinner, tapped in a hurry behind a counter.
  ButtonStyle? get _touch => compact
      ? const ButtonStyle(minimumSize: WidgetStatePropertyAll<Size>(Size(64, 48)))
      : null;
}
