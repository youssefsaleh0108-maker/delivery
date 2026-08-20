import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'cart.dart';
import 'order_details_screen.dart';

/// The customer's orders, and live tracking for the one currently out for delivery.
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({
    super.key,
    required this.api,
    required this.storeApi,
    required this.cart,
  });

  final OrderApi api;

  /// Both are handed to the details page, which resolves the shop and can rebuild the basket.
  final StoreApi storeApi;
  final Cart cart;

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  static const Duration _pollInterval = Duration(seconds: 5);

  Timer? _poll;
  List<DeliveryOrder> _orders = <DeliveryOrder>[];
  final Map<String, RiderPosition> _positions = <String, RiderPosition>{};
  bool _loading = true;
  Object? _error;

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
      final Paged<DeliveryOrder> page = await widget.api.mine(size: 30);
      if (!mounted) return;
      setState(() {
        _orders = page.content;
        _error = null;
        _loading = false;
      });

      // Only fetch positions for orders actually in transit. Polling tracking for a delivered
      // order would be pure waste on the busiest endpoint in the platform.
      for (final DeliveryOrder o in page.content.where(
          (DeliveryOrder o) => o.status == OrderStatus.pickedUp)) {
        unawaited(_loadPosition(o.id));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadPosition(String orderId) async {
    try {
      final RiderPosition? pos = await widget.api.currentPosition(orderId);
      if (!mounted || pos == null) return;
      setState(() => _positions[orderId] = pos);
    } catch (_) {
      // No fix yet, or tracking is briefly unavailable. The card just omits the location line.
    }
  }

  /// Opens the full order. The tapped row is passed through so the page renders straight away
  /// instead of flashing a spinner over data the list already has.
  void _openDetails(DeliveryOrder order) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => OrderDetailsScreen(
        orderApi: widget.api,
        storeApi: widget.storeApi,
        cart: widget.cart,
        orderId: order.id,
        preview: order,
      ),
    )).then((_) => _refresh());
  }

  Future<void> _cancel(DeliveryOrder order) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(DeliveryStrings.of(context).cancelThisOrder),
        content: Text(DeliveryStrings.of(context).cancelBeforeAccepted),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(DeliveryStrings.of(context).keepIt)),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(DeliveryStrings.of(context).cancelOrder)),
        ],
      ),
    );
    if (ok != true) return;

    try {
      // Not translated: this is the audit reason stored against the order and read by merchants
      // and Backoffice staff, not a sentence shown to the customer who typed it.
      await widget.api.act(order.id, OrderAction.cancel, reason: 'Cancelled by customer');
      await _refresh(silent: true);
    } on DioException catch (e) {
      if (!mounted) return;
      final String message = e.response?.statusCode == 422
          ? DeliveryStrings.of(context).tooLateToCancel
          : DeliveryStrings.of(context).couldNotCancelOrder;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      await _refresh(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DeliverySpacing.lg),
          child: Text('${DeliveryStrings.of(context).couldNotLoadOrders}\n$_error',
              textAlign: TextAlign.center),
        ),
      );
    }
    if (_loading && _orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.receipt_long_outlined, size: 44, color: DeliveryColors.muted),
            const SizedBox(height: DeliverySpacing.sm),
            Text(DeliveryStrings.of(context).noOrdersYet, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(DeliveryStrings.of(context).browseAndPlaceFirst,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _refresh(),
      child: ListView.separated(
        padding: const EdgeInsets.all(DeliverySpacing.md),
        itemCount: _orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: DeliverySpacing.sm),
        itemBuilder: (BuildContext context, int i) {
          final DeliveryOrder order = _orders[i];
          return _OrderCard(
            order: order,
            position: _positions[order.id],
            onTap: () => _openDetails(order),
            onCancel: order.availableActions.contains(OrderAction.cancel)
                ? () => _cancel(order)
                : null,
          );
        },
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, this.position, this.onCancel, this.onTap});

  final DeliveryOrder order;
  final RiderPosition? position;
  final VoidCallback? onCancel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: EdgeInsets.zero,
      child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(DeliverySpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                OrderStatusBadge(statusWire: order.status.wire),
                const Spacer(),
                Text(order.totalAmount.toStringAsFixed(2),
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: DeliverySpacing.sm),
            for (final OrderLine line in order.items)
              Text(DeliveryStrings.of(context).lineQuantity(line.qty, line.productName),
                  style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: DeliverySpacing.xs),
            Text(DeliveryStrings.of(context).orderRefWithAddress(order.shortId, order.deliveryAddress),
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1, overflow: TextOverflow.ellipsis),

            // The live tracking payoff: only meaningful once a rider actually has the food.
            if (position != null) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              Container(
                padding: const EdgeInsets.all(DeliverySpacing.sm),
                decoration: BoxDecoration(
                  color: DeliveryColors.brandSoft,
                  borderRadius: BorderRadius.circular(DeliveryRadius.md),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.two_wheeler, size: 18, color: DeliveryColors.brand),
                    const SizedBox(width: DeliverySpacing.sm),
                    Expanded(
                      child: Text(
                        DeliveryStrings.of(context).riderAtShort(
                            position!.lat.toStringAsFixed(4),
                            position!.lng.toStringAsFixed(4)),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (onCancel != null) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: OutlinedButton(onPressed: onCancel, child: Text(DeliveryStrings.of(context).cancel)),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}
