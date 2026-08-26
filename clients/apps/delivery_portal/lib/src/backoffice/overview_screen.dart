import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

import '../shell/shell.dart';

/// The Backoffice's opening screen: the four numbers, the week's shape, and what just happened.
///
/// Figma `backoffice-dashboard` (3:2487). New in the 2026-08 redesign — the portal had no overview
/// before, only the ledger, and "how is the platform doing" was a question you answered by reading
/// a table.
///
/// **Everything on this page is computed on the client**, because the platform has no aggregation
/// endpoint: `/api/orders/stats` returns counts by status and nothing else, and there is no
/// week-over-week, no revenue and no event stream anywhere on the API surface. So the rule this
/// screen is written to is: *state the window*. Every figure derived from the loaded page of orders
/// says how many orders it was derived from, right underneath itself, in the caption slot the
/// design draws for "vs last week". A number whose scope is invisible is a number that will be
/// quoted in a meeting as though it were the whole platform.
///
/// Nothing here is invented. Where the design draws a movement the platform cannot measure, the
/// slot carries the real caption instead, and the affordance that would need a backend carries a
/// [ConsoleComingSoonChip].
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({
    super.key,
    required this.api,
    required this.storeApi,
    this.onShowOrders,
  });

  final OrderApi api;

  /// Only ever asked for a count — `browse(size: 1).totalElements`, which is how many storefronts
  /// are live. There is no "merchants" endpoint on the platform; the store list is the closest true
  /// answer to the design's "Active Merchants".
  final StoreApi storeApi;

  /// Moves the rail to the Orders ledger. The design draws the KPI cards as plain cards, so this is
  /// an invisible affordance — the card looks exactly as drawn and clicking it goes to the rows the
  /// number came from.
  final VoidCallback? onShowOrders;

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  /// Slower than the ledger's 10s. This page reads three endpoints and one of them is a 100-row
  /// page; polling it as fast as a single table would be three times the traffic for a screen
  /// nobody watches second by second.
  static const Duration _pollInterval = Duration(seconds: 30);

  /// How much of the ledger the derived figures are computed over. Not a page the user can turn —
  /// it is the sample, and its real size is printed on every figure that comes out of it.
  static const int _window = 100;

  Timer? _poll;
  OrderStats? _stats;
  List<DeliveryOrder> _orders = <DeliveryOrder>[];

  /// Null when the store count could not be read. Deliberately separate from [_error]: a storefront
  /// count that failed must blank its own card, not the whole page.
  int? _storefronts;

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

    // The storefront count is fetched beside the orders but never allowed to fail the page — see
    // [_storefronts].
    final Future<int?> storefronts = widget.storeApi
        .browse(size: 1)
        .then<int?>((Paged<StoreCard> p) => p.totalElements)
        .catchError((Object _) => null);

    try {
      final List<Object> results = await Future.wait(<Future<Object>>[
        widget.api.stats(),
        widget.api.all(size: _window),
      ]);
      final int? stores = await storefronts;
      if (!mounted) return;
      setState(() {
        _stats = results[0] as OrderStats;
        _orders = (results[1] as Paged<DeliveryOrder>).content;
        _storefronts = stores;
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

  // ------------------------------------------------------------------ figures

  /// Riders who appear on the loaded window. Not "riders online" — the platform has no presence
  /// signal — and the caption under the number says so.
  int get _riders => _orders
      .where((DeliveryOrder o) => o.riderId != null)
      .map((DeliveryOrder o) => o.riderId!)
      .toSet()
      .length;

  List<DeliveryOrder> get _placedToday {
    final DateTime start = _startOfDay(DateTime.now());
    return _orders
        .where((DeliveryOrder o) =>
            o.placedAt != null &&
            !o.placedAt!.isBefore(start) &&
            o.status != OrderStatus.cancelled)
        .toList();
  }

  /// What today's orders are worth. Cancelled orders are excluded — an order nobody is going to
  /// deliver is not revenue, and counting it would flatter the number in exactly the situation
  /// somebody is looking at this page to notice.
  double get _revenueToday => _placedToday.fold<double>(
      0, (double sum, DeliveryOrder o) => sum + o.totalAmount);

  @override
  Widget build(BuildContext context) {
    final OrderStats? stats = _stats;
    final int loaded = _orders.length;
    final String sample = 'from the $loaded most recent orders';

    return ConsolePage(
      header: ConsoleTopbar(
        title: 'Operations Dashboard',
        subtitle: 'Real-time control tower overview for YouDrop',
        actions: <Widget>[
          // Drawn on every console frame; there is no cross-module search endpoint behind it.
          const ConsoleSearchField.global(
            hintText: 'Search backoffice...',
            enabled: false,
          ),
          const ConsoleComingSoonChip(),
          const ConsoleIconAction(
            icon: Icons.notifications_none,
            tooltip: 'Notifications — coming soon',
          ),
          ConsoleIconAction(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            onPressed: () => _refresh(),
          ),
        ],
      ),
      children: <Widget>[
        if (_error != null) _ErrorBanner(error: _error!, onRetry: () => _refresh()),
        ConsoleKpiRow(
          cards: <Widget>[
            ConsoleKpiCard(
              label: 'Total Orders',
              value: stats == null ? '—' : _grouped(stats.total),
              icon: Icons.shopping_bag_outlined,
              onTap: widget.onShowOrders,
              footnote: _Caption(
                stats == null ? 'Loading…' : '${_grouped(stats.active)} in flight now',
              ),
            ),
            ConsoleKpiCard(
              label: 'Active Merchants',
              value: _storefronts == null ? '—' : _grouped(_storefronts!),
              icon: Icons.storefront,
              footnote: _Caption(
                _storefronts == null ? 'Unavailable' : 'live storefronts',
              ),
            ),
            ConsoleKpiCard(
              label: 'Active Riders',
              value: _loading && _orders.isEmpty ? '—' : _grouped(_riders),
              icon: Icons.person_outline,
              footnote: _Caption(sample),
            ),
            ConsoleKpiCard(
              label: "Today's Revenue",
              // No currency symbol anywhere on this platform — see the note on [_money].
              value: _loading && _orders.isEmpty ? '—' : _money(_revenueToday),
              icon: Icons.payments_outlined,
              footnote: _Caption('${_placedToday.length} orders today, $sample'),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Widget chart = _WeeklyOrdersCard(days: _week(), loaded: loaded);
            final Widget activity = _ActivityCard(events: _activity());

            // The design's fixed 380px right card only works while the content column is wide
            // enough to leave the chart room to be a chart. Below that the two stack.
            if (constraints.maxWidth < 780) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  chart,
                  const SizedBox(height: ConsoleMetrics.pageGap),
                  activity,
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: chart),
                  const SizedBox(width: ConsoleMetrics.pageGap),
                  SizedBox(width: _ActivityCard.width, child: activity),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // -------------------------------------------------------------- derivations

  /// The last seven days, oldest first, each with what the loaded window says about it.
  ///
  /// Both series are real: orders placed that day, and orders delivered that day. The design's two
  /// series are Food and Groceries — a split the platform does not record on an order — so the
  /// chart keeps the design's shape and plots the two numbers that exist.
  List<_Day> _week() {
    final DateTime today = _startOfDay(DateTime.now());
    return <_Day>[
      for (int i = 6; i >= 0; i--)
        () {
          final DateTime day = today.subtract(Duration(days: i));
          final DateTime next = day.add(const Duration(days: 1));
          bool within(DateTime? t) => t != null && !t.isBefore(day) && t.isBefore(next);
          return _Day(
            label: _weekday(day),
            placed: _orders.where((DeliveryOrder o) => within(o.placedAt)).length,
            delivered: _orders.where((DeliveryOrder o) => within(o.deliveredAt)).length,
          );
        }(),
    ];
  }

  /// The activity rows, built from the only events on the API that carry their own timestamp: an
  /// order was placed, an order was delivered.
  ///
  /// The design's feed also carries merchant applications, rider presence changes and merchant
  /// status changes — none of which the platform emits anywhere a client can read. Those are what
  /// the card's "Coming soon" chip is about; the rows below are real, and so are their times.
  List<_Event> _activity() {
    final List<_Event> events = <_Event>[];
    for (final DeliveryOrder o in _orders) {
      if (o.deliveredAt != null) {
        events.add(_Event('Order #${o.shortId} was delivered.', o.deliveredAt!));
      }
      if (o.placedAt != null) {
        final String where = o.storeName ?? _short(o.merchantId);
        events.add(_Event('Order #${o.shortId} placed at $where.', o.placedAt!));
      }
    }
    events.sort((_Event a, _Event b) => b.at.compareTo(a.at));
    return events.take(6).toList();
  }
}

// ------------------------------------------------------------------ the chart

/// Figma `trend-chart-card` (3:2595): title opposite a legend, then a 130px band of paired bars.
class _WeeklyOrdersCard extends StatelessWidget {
  const _WeeklyOrdersCard({required this.days, required this.loaded});

  final List<_Day> days;
  final int loaded;

  @override
  Widget build(BuildContext context) {
    // The header is built here rather than handed to [ConsoleCard.title], because the legend has to
    // be allowed to wrap: at a 1024 window this card is ~500px wide and a legend that insists on one
    // line pushes the title off the end of it.
    return ConsoleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: Text('Weekly Orders Trend', style: ConsoleText.cardTitle)),
              const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
              Flexible(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: DeliverySpacing.md - DeliverySpacing.xs,
                  runSpacing: DeliverySpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    const _LegendSwatch(color: DeliveryColors.brand, label: 'Placed'),
                    _LegendSwatch(color: DeliveryAccent.info.color, label: 'Delivered'),
                    // The bars are counted on the client — the caption under them says over what.
                    const ConsoleComingSoonChip(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: ConsoleMetrics.kpiGap),
          _BarBand(days: days, loaded: loaded),
        ],
      ),
    );
  }
}

class _BarBand extends StatelessWidget {
  const _BarBand({required this.days, required this.loaded});

  static const double bandHeight = 130;
  static const double barWidth = 16;

  final List<_Day> days;
  final int loaded;

  @override
  Widget build(BuildContext context) {
    final int peak = days.fold<int>(
        0, (int m, _Day d) => <int>[m, d.placed, d.delivered].reduce((int a, int b) => a > b ? a : b));

    if (peak == 0) {
      return const SizedBox(
        height: bandHeight,
        child: Center(
          child: Text(
            'No orders in the last seven days.',
            style: ConsoleText.pageSubtitle,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (int i = 0; i < days.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: DeliverySpacing.lg),
                _Column(day: days[i], peak: peak),
              ],
            ],
          ),
        ),
        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        Text('Counted from the $loaded most recent orders.', style: ConsoleText.meta),
      ],
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.day, required this.peak});

  final _Day day;
  final int peak;

  double _height(int value) {
    if (value == 0) return 0;
    // Floor of 3: a day with one order must not render as an empty slot.
    final double h = value / peak * _BarBand.bandHeight;
    return h < 3 ? 3 : h;
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${day.label} · ${day.placed} placed · ${day.delivered} delivered',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: _BarBand.bandHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                _Bar(height: _height(day.placed), color: DeliveryColors.brand),
                const SizedBox(width: DeliverySpacing.xs),
                _Bar(height: _height(day.delivered), color: DeliveryAccent.info.color),
              ],
            ),
          ),
          const SizedBox(height: DeliverySpacing.sm),
          Text(day.label, style: const TextStyle(fontSize: 12, color: DeliveryColors.faint)),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _BarBand.barWidth,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(DeliverySpacing.xs)),
      ),
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: DeliveryColors.muted)),
      ],
    );
  }
}

// --------------------------------------------------------------- the activity

/// Figma `activity-card` (3:2642): a fixed 380px card of bulleted, timestamped lines.
class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.events});

  static const double width = 380;

  final List<_Event> events;

  @override
  Widget build(BuildContext context) {
    return ConsoleCard(
      title: 'Live Activity Log',
      trailing: const ConsoleComingSoonChip(label: 'Live feed coming soon'),
      child: events.isEmpty
          ? const Text('Nothing has happened yet.', style: ConsoleText.body)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < events.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(height: DeliverySpacing.md),
                  _ActivityRow(event: events[i]),
                ],
              ],
            ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.event});

  final _Event event;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          // Nudged down to sit on the first line's baseline rather than its cap height.
          margin: const EdgeInsets.only(top: 6),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: DeliveryColors.brand,
            borderRadius: BorderRadius.circular(DeliverySpacing.xs),
          ),
        ),
        const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(event.message, style: ConsoleText.body),
              const SizedBox(height: 2),
              Text(_ago(event.at), style: ConsoleText.meta),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- plumbing

/// The design's faint line under a KPI number, carrying what the figure is measured over.
///
/// Occupies the slot the design gives to "+14.3% vs last week". The green movement is not drawn,
/// because the platform cannot measure a movement: there is no historical aggregate to compare
/// today against, and a delta is exactly the kind of number that must never be guessed.
class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13, color: DeliveryColors.faint),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ConsoleMetrics.cardPadding),
      decoration: ConsoleSurface.card(),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline, size: 18, color: DeliveryAccent.critical.color),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Text('Could not load the overview. $error', style: ConsoleText.cellMuted),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _Day {
  const _Day({required this.label, required this.placed, required this.delivered});

  final String label;
  final int placed;
  final int delivered;
}

class _Event {
  const _Event(this.message, this.at);

  final String message;
  final DateTime at;
}

DateTime _startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);

String _weekday(DateTime day) => const <String>[
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ][day.weekday - 1];

String _short(String id) => id.length <= 8 ? id : id.substring(0, 8);

/// Thousands separators, as the design draws them ("12,847").
String _grouped(int value) {
  final String digits = value.abs().toString();
  final StringBuffer out = StringBuffer(value < 0 ? '-' : '');
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Money, grouped and to the cent.
///
/// No currency symbol: the platform sends amounts as bare numbers and names a currency nowhere on
/// the wire, so the design's "$" would be this screen asserting a currency the server never stated.
/// Cents are kept where the design rounds — a revenue figure that quietly loses its pennies is a
/// figure that will not reconcile against the Finance page.
String _money(double amount) {
  final String fixed = amount.toStringAsFixed(2);
  final int dot = fixed.indexOf('.');
  return '${_grouped(int.parse(fixed.substring(0, dot)))}${fixed.substring(dot)}';
}

/// Relative time, in the design's words ("Just now", "4 mins ago").
String _ago(DateTime at) {
  final Duration d = DateTime.now().difference(at);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min${d.inMinutes == 1 ? '' : 's'} ago';
  if (d.inHours < 24) return '${d.inHours} hour${d.inHours == 1 ? '' : 's'} ago';
  if (d.inDays == 1) return 'Yesterday';
  return '${d.inDays} days ago';
}
