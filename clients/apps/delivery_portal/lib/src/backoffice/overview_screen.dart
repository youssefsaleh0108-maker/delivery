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
/// **This page used to compute everything on the client**, because the platform had no aggregation
/// endpoint and no event stream. Both now exist: `GET /api/orders/daily` returns a complete,
/// zero-filled, tier-split daily series, and `GET /api/orders/activity` is the feed. So the
/// movements the design draws ("+14.3% vs last week") are real arithmetic on a real series, the
/// bars are the platform's own days rather than a sample, and the activity log is the platform's
/// own events.
///
/// The client-derived versions are kept underneath as the degradation path, not as the default: if
/// the series or the feed does not answer, the page falls back to what it can count from the loaded
/// page of orders and says so in the same caption slot. The rule the screen is written to is
/// unchanged — *state the window* — and nothing here is ever invented. A movement with no baseline
/// to measure against (a previous week with no orders at all) renders no percentage rather than an
/// infinity dressed up as growth.
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({
    super.key,
    required this.api,
    required this.storeApi,
    this.aggregatesApi,
    this.activityApi,
    this.notificationApi,
    this.onShowOrders,
  });

  final OrderApi api;

  /// Only ever asked for a count — `browse(size: 1).totalElements`, which is how many storefronts
  /// are live. There is no "merchants" endpoint on the platform; the store list is the closest true
  /// answer to the design's "Active Merchants".
  final StoreApi storeApi;

  /// The platform's tier-split daily series, behind the KPI movements and the trend chart. Optional
  /// so the screen still renders standalone; null falls back to the client-derived figures.
  final AggregatesApi? aggregatesApi;

  /// The platform activity feed behind the Live Activity Log. Optional for the same reason.
  final ActivityApi? activityApi;

  /// The operator's own in-app inbox, behind the header's bell.
  final NotificationApi? notificationApi;

  /// Moves the rail to the Orders ledger. The design draws the KPI cards as plain cards, so this is
  /// an invisible affordance — the card looks exactly as drawn and clicking it goes to the rows the
  /// number came from.
  final VoidCallback? onShowOrders;

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  /// Slower than the ledger's 10s. This page reads five endpoints and one of them is a 100-row
  /// page; polling it as fast as a single table would be five times the traffic for a screen
  /// nobody watches second by second.
  static const Duration _pollInterval = Duration(seconds: 30);

  /// How much of the ledger the fallback figures are computed over. Not a page the user can turn —
  /// it is the sample, and its real size is printed on every figure that comes out of it.
  static const int _window = 100;

  /// Fourteen days, so the last seven have seven to be measured against. The server clamps `days`
  /// to 1..30 without complaining, so this is a request it will always honour exactly.
  static const int _seriesDays = 14;

  /// One week per half of the week-over-week comparison.
  static const int _half = 7;

  Timer? _poll;
  OrderStats? _stats;
  List<DeliveryOrder> _orders = <DeliveryOrder>[];

  /// Null when the store count could not be read. Deliberately separate from [_error]: a storefront
  /// count that failed must blank its own card, not the whole page.
  int? _storefronts;

  /// The platform's daily series. Null when it has not landed or did not answer — every figure that
  /// depends on it then falls back to the loaded-orders sample and says so.
  TierTradeSeries? _series;

  /// The feed, newest first. Null means "not answered"; empty means "answered, and nothing has
  /// happened" — two different facts, and only one of them is a fallback.
  List<ActivityEntry>? _feed;

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

    // Three side reads fetched beside the orders and never allowed to fail the page — see the
    // fields' own notes. Each degrades to its own card.
    final Future<int?> storefronts = widget.storeApi
        .browse(size: 1)
        .then<int?>((Paged<StoreCard> p) => p.totalElements)
        .catchError((Object _) => null);
    final Future<TierTradeSeries?> series = widget.aggregatesApi == null
        ? Future<TierTradeSeries?>.value(null)
        : widget.aggregatesApi!
            .platformDaily(days: _seriesDays)
            .then<TierTradeSeries?>((TierTradeSeries s) => s)
            .catchError((Object _) => null);
    final Future<List<ActivityEntry>?> feed = widget.activityApi == null
        ? Future<List<ActivityEntry>?>.value(null)
        : widget.activityApi!
            .feed(size: 20)
            .then<List<ActivityEntry>?>((Paged<ActivityEntry> p) => p.content)
            .catchError((Object _) => null);

    try {
      final List<Object> results = await Future.wait(<Future<Object>>[
        widget.api.stats(),
        widget.api.all(size: _window),
      ]);
      final int? stores = await storefronts;
      final TierTradeSeries? daily = await series;
      final List<ActivityEntry>? activity = await feed;
      if (!mounted) return;
      setState(() {
        _stats = results[0] as OrderStats;
        _orders = (results[1] as Paged<DeliveryOrder>).content;
        _storefronts = stores;
        _series = daily;
        _feed = activity;
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
  /// signal on this endpoint — and the caption under the number says so.
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

  /// The fallback revenue figure: what today's loaded orders are worth. Cancelled orders are
  /// excluded — an order nobody is going to deliver is not revenue.
  double get _revenueToday => _placedToday.fold<double>(
      0, (double sum, DeliveryOrder o) => sum + o.totalAmount);

  /// The last [_half] days of the series and the [_half] before them, or null when there is no
  /// series or it is too short to hold both halves.
  ///
  /// The server zero-fills every day in the window, so these two lists are always the same length
  /// and neither has gaps — which is what makes the comparison below arithmetic rather than a
  /// guess about missing days.
  (List<TierTradeDay>, List<TierTradeDay>)? get _halves {
    final TierTradeSeries? s = _series;
    if (s == null || s.days.length < _half * 2) return null;
    final List<TierTradeDay> all = s.days;
    return (
      all.sublist(all.length - _half),
      all.sublist(all.length - _half * 2, all.length - _half),
    );
  }

  /// Today, as the *server* resolved it in the platform's zone — the last entry of a complete,
  /// ascending series. Never `DateTime.now()`: a console open in another timezone must not decide
  /// which day the platform's revenue belongs to.
  TierTradeDay? get _today {
    final TierTradeSeries? s = _series;
    return s == null || s.days.isEmpty ? null : s.days.last;
  }

  @override
  Widget build(BuildContext context) {
    final OrderStats? stats = _stats;
    final int loaded = _orders.length;
    final String sample = 'from the $loaded most recent orders';
    final (List<TierTradeDay>, List<TierTradeDay>)? halves = _halves;
    final TierTradeDay? today = _today;

    return ConsolePage(
      header: ConsoleTopbar(
        title: 'Operations Dashboard',
        subtitle: 'Real-time control tower overview for YouDrop',
        actions: <Widget>[
          ConsoleBell(api: widget.notificationApi),
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
            _ordersCard(stats, halves),
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
            _revenueCard(today, halves, sample),
          ],
        ),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Widget chart = _WeeklyOrdersCard(
              days: _week(),
              caption: _series == null
                  ? 'Counted from the $loaded most recent orders.'
                  : 'Every order the platform took, day by day.',
            );
            final Widget activity = _ActivityCard(
              events: _events(),
              derived: _feed == null,
            );

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

  // ------------------------------------------------------------------- the KPIs

  /// Total Orders, with the design's movement row filled by the series.
  ///
  /// The value is the platform's lifetime total; the movement is orders *placed* over the last
  /// seven days against the seven before, which is the thing that can actually move week to week.
  /// The caption names that measure rather than leaving "vs last week" to be read as a movement of
  /// the number above it, and the tooltip carries both halves so the percentage can be checked.
  Widget _ordersCard(OrderStats? stats, (List<TierTradeDay>, List<TierTradeDay>)? halves) {
    final int? now = halves == null ? null : _sumOrders(halves.$1);
    final int? before = halves == null ? null : _sumOrders(halves.$2);
    final _Movement? movement =
        now == null || before == null ? null : _Movement.between(now.toDouble(), before.toDouble());

    final Widget card = ConsoleKpiCard(
      label: 'Total Orders',
      value: stats == null ? '—' : _grouped(stats.total),
      icon: Icons.shopping_bag_outlined,
      onTap: widget.onShowOrders,
      trend: movement == null
          ? null
          : ConsoleKpiTrend(
              delta: movement.label,
              caption: 'orders vs last week',
              accent: movement.rising ? DeliveryAccent.positive : DeliveryAccent.critical,
              rising: movement.rising,
            ),
      footnote: movement != null
          ? null
          : _Caption(
              now == null
                  ? (stats == null ? 'Loading…' : '${_grouped(stats.active)} in flight now')
                  // A previous week with no orders at all has no baseline to be a percentage of.
                  : '$now orders in the last 7 days',
            ),
    );

    if (now == null || before == null) return card;
    return Tooltip(
      message: 'Last 7 days: $now orders · the 7 days before: $before',
      child: card,
    );
  }

  /// Today's Revenue.
  ///
  /// Where the series answers, this is the platform's own figure for today — the value of what was
  /// delivered, in the server's zone, summed server-side. Where it does not, it falls back to the
  /// old client sum over the loaded page and the caption says exactly that.
  ///
  /// The two are not the same measure, which is why they never appear together: the series counts
  /// delivered value, the fallback counts what was ordered today and not cancelled.
  Widget _revenueCard(
    TierTradeDay? today,
    (List<TierTradeDay>, List<TierTradeDay>)? halves,
    String sample,
  ) {
    final bool live = today != null;
    final double? now = halves == null ? null : _sumGross(halves.$1);
    final double? before = halves == null ? null : _sumGross(halves.$2);
    final _Movement? movement =
        !live || now == null || before == null ? null : _Movement.between(now, before);

    final Widget card = ConsoleKpiCard(
      label: "Today's Revenue",
      // No currency symbol anywhere on this platform — see the note on [_money].
      value: live
          ? _money(today.gross)
          : (_loading && _orders.isEmpty ? '—' : _money(_revenueToday)),
      icon: Icons.payments_outlined,
      trend: movement == null
          ? null
          : ConsoleKpiTrend(
              delta: movement.label,
              caption: 'delivered value vs last week',
              accent: movement.rising ? DeliveryAccent.positive : DeliveryAccent.critical,
              rising: movement.rising,
            ),
      footnote: movement != null
          ? null
          : _Caption(live
              ? '${today.delivered} delivered today'
              : '${_placedToday.length} orders today, $sample'),
    );

    if (!live) return card;
    return Tooltip(
      message: now == null || before == null
          ? 'Delivered value today, platform-wide'
          : 'Last 7 days: ${_money(now)} · the 7 days before: ${_money(before)}',
      child: card,
    );
  }

  static int _sumOrders(List<TierTradeDay> days) =>
      days.fold<int>(0, (int sum, TierTradeDay d) => sum + d.orders);

  static double _sumGross(List<TierTradeDay> days) =>
      days.fold<double>(0, (double sum, TierTradeDay d) => sum + d.gross);

  // -------------------------------------------------------------- derivations

  /// The last seven days, oldest first.
  ///
  /// From the platform series where there is one — every order the platform took, and how many of
  /// them reached a door. Where there is not, the same two counts derived from the loaded page, and
  /// the caption under the bars says which of the two it is looking at.
  ///
  /// The design's two series are Food and Groceries — a split the platform does not record on an
  /// order — so the chart keeps the design's shape and plots the two numbers that exist. The
  /// tier split the series *does* carry (standard against express) is not drawn here: it belongs
  /// to a chart about delivery speed, not about volume.
  List<_Day> _week() {
    final TierTradeSeries? s = _series;
    if (s != null && s.days.isNotEmpty) {
      final List<TierTradeDay> last =
          s.days.length <= _half ? s.days : s.days.sublist(s.days.length - _half);
      return <_Day>[
        for (final TierTradeDay d in last)
          _Day(label: _weekday(d.day), placed: d.orders, delivered: d.delivered),
      ];
    }

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

  /// The activity rows.
  ///
  /// From the platform feed where it answered — placements, deliveries, cancellations and every
  /// other status change, newest first, exactly as the server ordered them. Entries are immutable
  /// and the feed only ever prepends, so re-reading page zero on the poll is the whole refresh.
  ///
  /// Where the feed did not answer, the old derivation stands in: the only events the orders
  /// endpoint carries with their own timestamp are "placed" and "delivered". The card says which
  /// of the two it is showing.
  List<_Event> _events() {
    final List<ActivityEntry>? feed = _feed;
    if (feed != null) {
      return <_Event>[
        for (final ActivityEntry e in feed.take(6)) _Event(_sentence(e), e.occurredAt),
      ];
    }

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
    events.sort((_Event a, _Event b) => b.at!.compareTo(a.at!));
    return events.take(6).toList();
  }

  /// One feed entry in the card's row language.
  ///
  /// `storeName` is null on Butler errands — there is no shop — so those rows name the errand for
  /// what it is rather than leaving a blank where a name should be. An event this build does not
  /// know keeps the server's own spelling instead of being dropped.
  static String _sentence(ActivityEntry e) {
    final String id = '#${_short(e.orderId)}';
    final String where = e.storeName ?? 'a Butler errand';
    return switch (e.event) {
      ActivityEvent.placed => 'Order $id placed at $where.',
      ActivityEvent.delivered => 'Order $id was delivered.',
      ActivityEvent.cancelled => 'Order $id was cancelled.',
      ActivityEvent.statusChanged => 'Order $id is now ${e.status.label.toLowerCase()}.',
      ActivityEvent.unknown => 'Order $id — ${e.eventWire.isEmpty ? 'activity' : e.eventWire}.',
    };
  }
}

/// A signed movement between two comparable figures.
///
/// [between] returns null when the earlier figure is zero: there is no percentage of nothing, and
/// rendering one would be the single most quotable invented number on this page.
class _Movement {
  const _Movement(this.percent);

  static _Movement? between(double now, double before) {
    if (before <= 0) return null;
    return _Movement((now - before) / before * 100);
  }

  final double percent;

  bool get rising => percent >= 0;

  String get label => '${percent >= 0 ? '+' : '−'}${percent.abs().toStringAsFixed(1)}%';
}

// ------------------------------------------------------------------ the chart

/// Figma `trend-chart-card` (3:2595): title opposite a legend, then a 130px band of paired bars.
class _WeeklyOrdersCard extends StatelessWidget {
  const _WeeklyOrdersCard({required this.days, required this.caption});

  final List<_Day> days;

  /// What the bars were counted over. Always drawn — a figure whose scope is invisible is a figure
  /// that will be quoted in a meeting as though it were the whole platform.
  final String caption;

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
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: ConsoleMetrics.kpiGap),
          _BarBand(days: days, caption: caption),
        ],
      ),
    );
  }
}

class _BarBand extends StatelessWidget {
  const _BarBand({required this.days, required this.caption});

  static const double bandHeight = 130;
  static const double barWidth = 16;

  final List<_Day> days;
  final String caption;

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
        Text(caption, style: ConsoleText.meta),
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
  const _ActivityCard({required this.events, required this.derived});

  static const double width = 380;

  final List<_Event> events;

  /// True when the feed endpoint did not answer and these rows were derived from the loaded orders
  /// instead. Said once, under the rows — a feed showing two of the four kinds of event it normally
  /// carries has to say which two.
  final bool derived;

  @override
  Widget build(BuildContext context) {
    return ConsoleCard(
      title: 'Live Activity Log',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (events.isEmpty)
            const Text('Nothing has happened yet.', style: ConsoleText.body)
          else
            for (int i = 0; i < events.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: DeliverySpacing.md),
              _ActivityRow(event: events[i]),
            ],
          if (derived) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            const Text(
              'The activity feed did not answer. These rows are placements and deliveries read '
              'off the loaded orders.',
              style: ConsoleText.meta,
            ),
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
              if (event.at != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(consoleAgo(event.at!), style: ConsoleText.meta),
              ],
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
/// Occupies the slot the design gives to "+14.3% vs last week", for the two cards that still have
/// no series behind them and for the two that do on a day the series could not be read.
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

  /// Null when the server sent an entry with no timestamp — the row still renders, without a time
  /// under it, rather than being dropped or given "just now".
  final DateTime? at;
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
