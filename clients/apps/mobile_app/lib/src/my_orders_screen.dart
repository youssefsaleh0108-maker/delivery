import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'cart.dart';
import 'order_details_screen.dart';
import 'store_page_screen.dart';

/// The customer's orders, and live tracking for the one currently out for delivery.
///
/// Drawn in the redesign's customer language: the 56px white screen header every root tab carries,
/// then a 24px list of white radius-16 cards — the same card, pill and row treatment as
/// `customer-order-details` (node 3:542), so an order looks like itself in the list and on its own
/// page.
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({
    super.key,
    required this.api,
    required this.storeApi,
    this.trackingApi,
    this.chatApi,
    required this.cart,
  });

  final OrderApi api;

  /// Both are handed to the details page, which resolves the shop and can rebuild the basket.
  final StoreApi storeApi;

  /// Handed to the details page too: the live ETA and the chat with the rider live there, and
  /// this list is the road every order takes to reach it.
  final TrackingApi? trackingApi;
  final ChatApi? chatApi;
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
        trackingApi: widget.trackingApi,
        chatApi: widget.chatApi,
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(DeliveryStrings.of(context).keepIt)),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(DeliveryStrings.of(context).cancelOrder)),
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

  /// Which of the frame's two tabs is showing: false = Active, true = Past.
  bool _past = false;

  List<DeliveryOrder> get _active =>
      _orders.where((DeliveryOrder o) => !o.status.isTerminal).toList();

  List<DeliveryOrder> get _pastOrders =>
      _orders.where((DeliveryOrder o) => o.status.isTerminal).toList();

  /// "Reorder": back into the shop the order came from, basket-ready. The frame's button
  /// re-starts the purchase; the shop page IS where that happens, one tap from the past order.
  void _reorder(DeliveryOrder order) {
    final String? storeId = order.storeId;
    if (storeId == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StorePageScreen(
        storeApi: widget.storeApi,
        orderApi: widget.api,
        cart: widget.cart,
        storeId: storeId,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Container(
      color: DeliveryColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SafeArea(bottom: false, child: YdScreenHeader(title: t.custYourOrders)),
          _tabBar(t),
          Expanded(child: _body(t)),
        ],
      ),
    );
  }

  /// The frame's underlined pair: "Active Orders (N)" and "Past Orders", the showing one in
  /// brand with a 2px underline, the other muted.
  Widget _tabBar(DeliveryStrings t) {
    return Container(
      color: DeliveryColors.white,
      child: Row(
        children: <Widget>[
          _tab(t.custActiveOrdersTab(_active.length), selected: !_past,
              onTap: () => setState(() => _past = false)),
          _tab(t.custPastOrdersTab, selected: _past,
              onTap: () => setState(() => _past = true)),
        ],
      ),
    );
  }

  Widget _tab(String label, {required bool selected, required VoidCallback onTap}) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.md - 2),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? DeliveryColors.brand : DeliveryColors.border,
                  width: selected ? 2 : 1,
                ),
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: selected ? DeliveryColors.brand : DeliveryColors.muted,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(DeliveryStrings t) {
    if (_error != null) {
      return YdEmptyState(
        icon: Icons.cloud_off_rounded,
        title: t.couldNotLoadOrders,
        message: t.pullDownToTryAgain,
        action: YdPillButton(
          label: t.tryAgain,
          expand: false,
          size: YdPillButtonSize.compact,
          onPressed: () => _refresh(),
        ),
      );
    }
    if (_loading && _orders.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
    }
    final List<DeliveryOrder> showing = _past ? _pastOrders : _active;
    if (showing.isEmpty) {
      return YdEmptyState(
        icon: Icons.receipt_long_outlined,
        title: t.noOrdersYet,
        message: t.browseAndPlaceFirst,
      );
    }

    return RefreshIndicator(
      color: DeliveryColors.brand,
      onRefresh: () => _refresh(),
      child: ListView.separated(
        padding: const EdgeInsets.all(DeliverySpacing.lg),
        itemCount: showing.length,
        separatorBuilder: (_, __) =>
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        itemBuilder: (BuildContext context, int i) {
          final DeliveryOrder order = showing[i];
          return _OrderCard(
            order: order,
            position: _positions[order.id],
            onTap: () => _openDetails(order),
            onCancel: order.availableActions.contains(OrderAction.cancel)
                ? () => _cancel(order)
                : null,
            onReorder:
                order.status.isTerminal ? () => _reorder(order) : null,
          );
        },
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard(
      {required this.order, this.position, this.onCancel, this.onTap, this.onReorder});

  final DeliveryOrder order;
  final RiderPosition? position;
  final VoidCallback? onCancel;
  final VoidCallback? onTap;

  /// The frame's Reorder button, drawn on the past-order cards only.
  final VoidCallback? onReorder;

  /// "8:45 PM" today, "Yesterday, 8:45 PM", then plain short dates — the way the frame stamps
  /// its cards, without pretending to a fuzzier memory than the data has.
  String _placedLabel(BuildContext context, DeliveryStrings t) {
    final DateTime? at = order.placedAt?.toLocal();
    if (at == null) return t.orderRefWithAddress(order.shortId, order.deliveryAddress);
    final MaterialLocalizations dates = MaterialLocalizations.of(context);
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime day = DateTime(at.year, at.month, at.day);
    final String time = dates.formatTimeOfDay(TimeOfDay.fromDateTime(at));
    if (day == today) return time;
    if (day == today.subtract(const Duration(days: 1))) {
      return t.custYesterdayAt(time);
    }
    return dates.formatShortDate(at);
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return YdCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      order.storeName ?? t.tabShop,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.ink,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _placedLabel(context, t),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: DeliveryColors.faint,
                        height: 1.35,
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
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          const Divider(height: 1, color: DeliveryColors.borderFaint),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          // The frame sums the basket to one line — "2 items" over the dual-priced total — with
          // Reorder beside it on the cards whose story is over. The full item list lives one tap
          // away on the details page.
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      t.custItemsCountLine(order.items.length),
                      style: const TextStyle(
                        fontSize: 12,
                        color: DeliveryColors.muted,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: '\$${order.totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: DeliveryColors.ink,
                              height: 1.25,
                            ),
                          ),
                          if (MarketRates.instance.lbpParen(order.totalAmount)
                              case final String lbp)
                            TextSpan(
                              text: ' $lbp',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
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
              if (onReorder != null) ...<Widget>[
                const SizedBox(width: DeliverySpacing.sm),
                YdPillButton(
                  label: t.custReorder,
                  expand: false,
                  size: YdPillButtonSize.compact,
                  onPressed: onReorder,
                ),
              ],
            ],
          ),

          // The live tracking payoff: only meaningful once a rider actually has the food.
          if (position != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            Container(
              padding: const EdgeInsetsDirectional.all(
                  DeliverySpacing.md - DeliverySpacing.xs),
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
                      t.riderAtShort(
                        position!.lat.toStringAsFixed(4),
                        position!.lng.toStringAsFixed(4),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DeliveryColors.ink,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (onCancel != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: YdPillButton.secondary(
                label: t.cancel,
                expand: false,
                size: YdPillButtonSize.compact,
                onPressed: onCancel,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
