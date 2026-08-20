import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

/// Order monitoring across every merchant (Phase 2 deliverable).
///
/// Read-only by design. Backoffice can cancel an order for support reasons, and that is exposed on
/// the row through the server-supplied actions — but there is no way to accept, prepare or deliver
/// on a merchant's or rider's behalf, because doing so would put the platform's name on a claim
/// about the physical world it cannot verify.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.api});

  final OrderApi api;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const Duration _pollInterval = Duration(seconds: 10);

  Timer? _poll;
  OrderStats? _stats;
  List<DeliveryOrder> _orders = <DeliveryOrder>[];
  OrderStatus? _filter;
  Object? _error;
  bool _loading = true;

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
      // Both in parallel: the counters and the list are independent reads, and serialising them
      // would double the latency of a screen that refreshes on a timer.
      final List<Object> results = await Future.wait(<Future<Object>>[
        widget.api.stats(),
        widget.api.all(status: _filter, size: 50),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as OrderStats;
        _orders = (results[1] as Paged<DeliveryOrder>).content;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Fills the width the rail shell gives it. The Center/ConstrainedBox pair that used to wrap
    // this became a no-op when its max width was dropped, and a wrapper that does nothing reads
    // like a constraint someone still depends on.
    return Padding(
          padding: const EdgeInsets.all(DeliverySpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text('Orders', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(width: DeliverySpacing.md),
                  if (_loading)
                    const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => _refresh(),
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
              Text('Across all merchants · updates every ${_pollInterval.inSeconds}s',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: DeliverySpacing.md),
              if (_stats != null) _statTiles(_stats!),
              const SizedBox(height: DeliverySpacing.md),
              _filters(),
              const SizedBox(height: DeliverySpacing.md),
              Expanded(child: _table()),
            ],
          ),
    );
  }

  /// The top-line numbers.
  ///
  /// Deliberately five, not nine. The previous version rendered a tile per status and the row that
  /// mattered — how much work is in flight — was one of nine identical boxes. These are the
  /// questions an operator opens this page to answer; the per-status breakdown is the filter row
  /// underneath, where choosing one actually does something.
  Widget _statTiles(OrderStats stats) {
    final int delivered = stats.countOf(OrderStatus.delivered);
    final int cancelled = stats.countOf(OrderStatus.cancelled);
    final int waiting = stats.countOf(OrderStatus.placed);
    final int onTheWay = stats.countOf(OrderStatus.pickedUp);

    return StatRow(tiles: <Widget>[
      StatTile(
        value: '${stats.active}',
        label: 'In flight',
        icon: Icons.bolt_rounded,
        accent: DeliveryAccent.info,
        footnote: '${stats.total} total',
        onTap: () => _applyFilter(null),
      ),
      StatTile(
        value: '$waiting',
        label: 'Awaiting a shop',
        icon: Icons.hourglass_empty_rounded,
        // Amber only when somebody is actually waiting: a permanent warning colour stops being one.
        accent: waiting == 0 ? DeliveryAccent.positive : DeliveryAccent.caution,
        onTap: () => _applyFilter(OrderStatus.placed),
      ),
      StatTile(
        value: '$onTheWay',
        label: 'On the way',
        icon: Icons.pedal_bike_rounded,
        accent: DeliveryAccent.neutral,
        onTap: () => _applyFilter(OrderStatus.pickedUp),
      ),
      StatTile(
        value: '$delivered',
        label: 'Delivered',
        icon: Icons.check_circle_outline_rounded,
        accent: DeliveryAccent.positive,
        onTap: () => _applyFilter(OrderStatus.delivered),
      ),
      StatTile(
        value: '$cancelled',
        label: 'Cancelled',
        icon: Icons.cancel_outlined,
        accent: cancelled == 0 ? DeliveryAccent.positive : DeliveryAccent.critical,
        onTap: () => _applyFilter(OrderStatus.cancelled),
      ),
    ]);
  }

  /// Tapping a number filters to it — the tile and the chip below are the same control.
  void _applyFilter(OrderStatus? status) {
    setState(() => _filter = status);
    _refresh();
  }

  Widget _filters() {
    return Wrap(
      spacing: DeliverySpacing.sm,
      children: <Widget>[
        ChoiceChip(
          label: const Text('All'),
          selected: _filter == null,
          selectedColor: DeliveryColors.brand,
          labelStyle: TextStyle(
            color: _filter == null ? DeliveryColors.white : DeliveryColors.brandDark,
            fontWeight: FontWeight.w600,
          ),
          onSelected: (_) {
            setState(() => _filter = null);
            _refresh();
          },
        ),
        for (final OrderStatus s in OrderStatus.values)
          ChoiceChip(
            label: Text(s.label),
            selected: _filter == s,
            selectedColor: DeliveryColors.brand,
            labelStyle: TextStyle(
              color: _filter == s ? DeliveryColors.white : DeliveryColors.brandDark,
              fontWeight: FontWeight.w600,
            ),
            onSelected: (_) {
              setState(() => _filter = s);
              _refresh();
            },
          ),
      ],
    );
  }

  Widget _table() {
    if (_error != null) {
      return Center(child: Text('Could not load orders.\n$_error', textAlign: TextAlign.center));
    }
    if (_loading && _orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_orders.isEmpty) {
      return const Center(child: Text('No orders match this filter.'));
    }

    return SoftCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        child: SizedBox(
          width: double.infinity,
          // Horizontally scrollable so a narrow window never forces the page itself to scroll
          // sideways.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const <DataColumn>[
                DataColumn(label: Text('Order')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Items')),
                DataColumn(label: Text('Total')),
                DataColumn(label: Text('Merchant')),
                DataColumn(label: Text('Rider')),
                DataColumn(label: Text('Placed')),
              ],
              rows: _orders.map(_row).toList(),
            ),
          ),
        ),
      ),
    );
  }

  DataRow _row(DeliveryOrder order) {
    return DataRow(cells: <DataCell>[
      DataCell(Text('#${order.shortId}')),
      DataCell(OrderStatusBadge(statusWire: order.status.wire)),
      DataCell(Text(order.items.fold<int>(0, (int a, OrderLine l) => a + l.qty).toString())),
      DataCell(Text(order.totalAmount.toStringAsFixed(2))),
      DataCell(Text(_short(order.merchantId))),
      DataCell(Text(order.riderId == null ? '—' : _short(order.riderId!))),
      DataCell(Text(order.placedAt == null ? '—' : _time(order.placedAt!))),
    ]);
  }

  static String _short(String id) => id.length <= 8 ? id : id.substring(0, 8);

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

// The old bordered tile lived here. Replaced by StatTile from the design system, which every app
// now shares — a metric that looks different in the Backoffice from the merchant portal is a
// metric somebody has to learn twice.
