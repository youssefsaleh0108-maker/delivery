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
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, required this.api});

  final OrderApi api;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  static const Duration _pollInterval = Duration(seconds: 5);

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
  Widget _counters() {
    int of(OrderStatus s) => _orders.where((DeliveryOrder o) => o.status == s).length;
    final int waiting = of(OrderStatus.placed);
    final int making = of(OrderStatus.preparing) + of(OrderStatus.accepted);
    final int ready = of(OrderStatus.ready);
    final int done = of(OrderStatus.delivered);

    return StatRow(tiles: <Widget>[
      StatTile(
        value: '$waiting',
        label: DeliveryStrings.of(context).columnToAccept,
        icon: Icons.notifications_active_outlined,
        // The only genuinely urgent one: a customer is waiting to hear back.
        accent: waiting == 0 ? DeliveryAccent.positive : DeliveryAccent.caution,
      ),
      StatTile(
        value: '$making',
        label: DeliveryStrings.of(context).columnPreparing,
        icon: Icons.soup_kitchen_outlined,
        accent: DeliveryAccent.info,
      ),
      StatTile(
        value: '$ready',
        label: DeliveryStrings.of(context).columnAwaitingRider,
        icon: Icons.pedal_bike_rounded,
        accent: ready == 0 ? DeliveryAccent.positive : DeliveryAccent.neutral,
      ),
      StatTile(
        value: '$done',
        label: DeliveryStrings.of(context).columnDelivered,
        icon: Icons.check_circle_outline_rounded,
        accent: DeliveryAccent.positive,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final List<DeliveryOrder> visible = _showCompleted
        ? _orders
        : _orders.where((DeliveryOrder o) => !o.status.isTerminal).toList();

    // Fills the width the rail shell gives it. The Center/ConstrainedBox pair that used to wrap
    // this became a no-op when its max width was dropped.
    return Padding(
          padding: const EdgeInsets.all(DeliverySpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(DeliveryStrings.of(context).navOrders, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(width: DeliverySpacing.md),
                  if (_loading) const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const Spacer(),
                  Row(
                    children: <Widget>[
                      Text(DeliveryStrings.of(context).showCompleted),
                      Switch(
                        value: _showCompleted,
                        activeThumbColor: DeliveryColors.brand,
                        onChanged: (bool v) => setState(() => _showCompleted = v),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => _refresh(),
                    icon: const Icon(Icons.refresh),
                    tooltip: DeliveryStrings.of(context).refresh,
                  ),
                ],
              ),
              Text(DeliveryStrings.of(context).updatesEvery(_pollInterval.inSeconds),
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: DeliverySpacing.md),
              _counters(),
              const SizedBox(height: DeliverySpacing.lg),
              SectionLabel(DeliveryStrings.of(context).liveOrders),
              Expanded(child: _body(visible)),
            ],
          ),
    );
  }

  Widget _body(List<DeliveryOrder> visible) {
    if (_error != null) {
      return Center(child: Text('${DeliveryStrings.of(context).couldNotLoadOrdersShort}\n$_error', textAlign: TextAlign.center));
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
            Text(_showCompleted ? DeliveryStrings.of(context).noOrdersYetMerchant : DeliveryStrings.of(context).noOrdersNeedingAttention,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: visible.length,
      separatorBuilder: (_, __) => const SizedBox(height: DeliverySpacing.sm),
      itemBuilder: (BuildContext context, int i) => _OrderCard(
        order: visible[i],
        busy: _busyOrderId == visible[i].id,
        onAction: (OrderAction a) => _act(visible[i], a),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.busy, required this.onAction});

  final DeliveryOrder order;
  final bool busy;
  final void Function(OrderAction) onAction;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                OrderStatusBadge(statusWire: order.status.wire),
                const SizedBox(width: DeliverySpacing.sm),
                Text('#${order.shortId}',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text(order.totalAmount.toStringAsFixed(2),
                    style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
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
                          ? DeliveryStrings.of(context).noCommissionOnThisOrder
                          : DeliveryStrings.of(context).deliveryPaidByPlatform,
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
                child: Text(DeliveryStrings.of(context).lineQuantity(line.qty, line.productName),
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
            const SizedBox(height: DeliverySpacing.sm),
            Row(
              children: <Widget>[
                const Icon(Icons.place_outlined, size: 16, color: DeliveryColors.muted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(order.deliveryAddress,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (order.riderId != null) ...<Widget>[
                  const Icon(Icons.two_wheeler, size: 16, color: DeliveryColors.muted),
                  const SizedBox(width: 4),
                  Text(DeliveryStrings.of(context).riderAssigned, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
            if (order.notes != null && order.notes!.isNotEmpty) ...<Widget>[
              const SizedBox(height: DeliverySpacing.xs),
              Text(DeliveryStrings.of(context).noteWithText(order.notes!), style: Theme.of(context).textTheme.bodySmall),
            ],

            // Buttons come from availableActions, which the SERVICE computed. Rendering anything
            // else would offer a merchant a transition the state machine would refuse.
            if (order.availableActions.isNotEmpty) ...<Widget>[
              const Divider(height: DeliverySpacing.lg),
              Row(
                children: <Widget>[
                  for (final OrderAction action in order.availableActions)
                    Padding(
                      padding: const EdgeInsets.only(right: DeliverySpacing.sm),
                      child: action == OrderAction.cancel
                          ? OutlinedButton(
                              onPressed: busy ? null : () => onAction(action),
                              child: Text(action.label))
                          : ElevatedButton(
                              onPressed: busy ? null : () => onAction(action),
                              child: Text(action.label)),
                    ),
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
}
