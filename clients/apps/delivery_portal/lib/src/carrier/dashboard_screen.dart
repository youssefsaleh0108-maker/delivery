import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import '../shell/console_controls.dart';
import '../shell/shell.dart';

/// The delivery company's own page — Figma `carrier-dashboard` (3:3429), "Carrier Control Tower".
///
/// Four KPI cards over a split row: the day's dispatch shape on the left, what has just happened on
/// the right. The rule applied throughout is unchanged — a number is either derived from something
/// loaded or is not shown at all — but far more of the design is answerable than it was:
///
/// * **Total Assigned Riders** is the fleet list's length. Nothing records how large a fleet was
///   yesterday, so the card still shows no fleet movement; what it shows instead is real and about
///   the same population — how many of those riders have delivered something today, from the
///   carrier-scoped delivered-today endpoint.
/// * **Active Right Now** counts the distinct riders holding a job that has not finished, out of
///   the loaded page of work. Labelled as what it is rather than as presence.
/// * **Deliveries Today** and **Today's Revenue** carry both movements the design draws: the
///   day-over-day from [CarrierSummary], and a week-over-week computed here from the carrier-scoped
///   daily series (deliveries) and the summary's own day list (money). Neither is precomputed
///   server-side — the contract is explicit that DoD/WoW is client arithmetic.
///
/// The hourly chart is now the design's two series. Orders carry a delivery tier since the express
/// wave, so every column splits into Standard and Express out of the same jobs the single series
/// was drawn from — no second endpoint, and no invented number on either side of the split.
///
/// Money on this page is the carrier's, never the customer's: the express surcharge is platform
/// revenue and is deliberately absent from every figure here.
class CarrierDashboardScreen extends StatefulWidget {
  const CarrierDashboardScreen({
    super.key,
    required this.api,
    required this.providerApi,
    this.aggregatesApi,
    this.performanceApi,
    this.onShowJobs,
  });

  final OrderApi api;

  /// For the company's name in the page subtitle and the fleet count in the first KPI. The design's
  /// header names the carrier, and "Operational health dashboard for" with nothing after it would
  /// be worse than no subtitle.
  final DeliveryProviderApi providerApi;

  /// The carrier-scoped daily series, for the week-over-week line the design draws. Optional
  /// because the portal shell has not been rewired to pass it yet; absent, the cards show their
  /// day-over-day alone rather than a movement nothing measured.
  final AggregatesApi? aggregatesApi;

  /// Per-rider delivered-today counts, carrier-scoped. Optional for the same reason.
  final RiderPerformanceApi? performanceApi;

  /// Today's work leads to the job board. A count with nowhere to go is decoration.
  final VoidCallback? onShowJobs;

  @override
  State<CarrierDashboardScreen> createState() => _CarrierDashboardScreenState();
}

class _CarrierDashboardScreenState extends State<CarrierDashboardScreen> {
  static const Duration _pollInterval = Duration(seconds: 60);

  /// Enough to cover a busy day for the chart and the feed without asking for a second page. Both
  /// are explicitly described on screen as being drawn from recent work rather than from all of it.
  static const int _jobsWindow = 100;

  /// Two whole weeks, so "this week against the one before" is a comparison of two equal windows
  /// rather than of a week against whatever else the server happened to send.
  static const int _seriesDays = 14;

  Timer? _poll;
  CarrierSummary? _summary;
  DeliveryProviderInfo? _company;
  List<String>? _riders;
  List<DeliveryOrder>? _jobs;
  TierTradeSeries? _series;
  List<RiderDeliveredToday>? _deliveredToday;
  Object? _error;

  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(_pollInterval, (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    try {
      // The summary is the page. Everything else enriches it, so each of the others is allowed to
      // fail on its own and leave its card saying "—" rather than taking the screen down.
      final CarrierSummary summary = await widget.api.carrierSummary();
      final DeliveryProviderInfo? company = await _tryLoad(widget.providerApi.myCompany);
      final List<String>? riders = await _tryLoad(widget.providerApi.myRiders);
      final Paged<DeliveryOrder>? jobs =
          await _tryLoad(() => widget.api.forCarrier(size: _jobsWindow));
      final AggregatesApi? aggregates = widget.aggregatesApi;
      final TierTradeSeries? series = aggregates == null
          ? null
          : await _tryLoad(() => aggregates.carrierDaily(days: _seriesDays));
      final RiderPerformanceApi? performance = widget.performanceApi;
      final List<RiderDeliveredToday>? deliveredToday =
          performance == null ? null : await _tryLoad(performance.deliveredToday);

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _company = company;
        _riders = riders;
        _jobs = jobs?.content;
        _series = series;
        _deliveredToday = deliveredToday;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      // A background poll that fails leaves the last good numbers up. Replacing a working screen
      // with an error because one refresh missed is a worse answer than slightly old figures.
      if (!silent) setState(() => _error = e);
    }
  }

  static Future<T?> _tryLoad<T>(Future<T> Function() load) async {
    try {
      return await load();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return switch ((_summary, _error)) {
      // Belonging to no company is a provisioning gap, not a failure — the same expected state the
      // earnings screen handles, worded the same way so it does not read as two bugs.
      (null, final Object? e) when e != null => _noCompany(t),
      (null, _) => Container(
          color: DeliveryColors.background,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(color: DeliveryColors.brand),
        ),
      (final CarrierSummary s, _) => _body(s, t),
    };
  }

  Widget _noCompany(DeliveryStrings t) {
    return Container(
      color: DeliveryColors.background,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(DeliverySpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.help_outline, size: 40, color: DeliveryColors.faint),
            const SizedBox(height: DeliverySpacing.md),
            Text(t.noCompanyYet, style: ConsoleText.cardTitle),
            const SizedBox(height: DeliverySpacing.xs),
            Text(t.askThePlatformToAttachYou,
                textAlign: TextAlign.center, style: ConsoleText.pageSubtitle),
          ],
        ),
      ),
    );
  }

  Widget _body(CarrierSummary s, DeliveryStrings t) {
    final List<DeliveryOrder> jobs = _jobs ?? const <DeliveryOrder>[];

    return ConsolePage(
      header: ConsoleTopbar(
        title: 'Carrier Control Tower',
        subtitle: _company == null
            ? 'Operational health dashboard'
            : 'Operational health dashboard for ${_company!.name}',
        actions: <Widget>[
          // Live, and over the one population this page holds: the recent jobs the chart and the
          // feed are both drawn from.
          ConsoleSearchField.global(
            hintText: 'Search recent jobs...',
            controller: _search,
            onChanged: (String value) => setState(() => _query = value.trim()),
          ),
          ConsoleIconAction(
            icon: Icons.refresh,
            tooltip: t.refresh,
            onPressed: () => _refresh(),
          ),
          // FINISH-WAVE NOTE: this slot is the console bell's. `ConsoleBell` is not exported from
          // `shell/shell.dart` yet, so the topbar keeps the drawn control and compiles against the
          // barrel as it stands; swapping this one line is all the mount takes.
          const ConsoleIconAction(
            icon: Icons.notifications_none,
            tooltip: 'Notifications',
          ),
        ],
      ),
      children: <Widget>[
        ConsoleKpiRow(cards: _kpis(s)),
        _split(s, jobs),
      ],
    );
  }

  List<Widget> _kpis(CarrierSummary s) {
    final int fleet = _riders?.length ?? 0;
    final int onJob = _ridersOnAJob;

    return <Widget>[
      ConsoleKpiCard(
        label: 'Total Assigned Riders',
        value: _riders == null ? '—' : '$fleet Riders',
        icon: Icons.groups_outlined,
        // No endpoint records how large this fleet was yesterday, so the design's "+4 new" has
        // nowhere to come from. What the platform does know about the same riders today does.
        footnote: _fleetFootnote(fleet),
      ),
      ConsoleKpiCard(
        label: 'Active Right Now',
        value: _jobs == null ? '—' : '$onJob Active',
        icon: Icons.near_me_outlined,
        // Deliberately not a movement: an arrow beside a share would read as one, and this is a
        // proportion of the fleet at one moment.
        footnote: Text(
          _riders == null || _jobs == null
              ? 'Riders on an unfinished job'
              : fleet == 0
                  ? 'No riders on the fleet yet'
                  : '${(onJob / fleet * 100).round()}% of the fleet, on a job now',
          style: const TextStyle(fontSize: 13, color: DeliveryColors.faint),
        ),
      ),
      ConsoleKpiCard(
        label: 'Deliveries Today',
        value: '${s.today.delivered} Completed',
        icon: Icons.check_circle_outline,
        // Both movements in one slot: the design draws a single trend line, and the week is the
        // sentence under it rather than a second card nobody asked for.
        footnote: _Movement(
          trend: _trend(s.today.delivered, s.yesterday.delivered),
          fallback: 'Nothing delivered yesterday to compare with',
          note: _weekNote(
            current: _weekDelivered(recent: true),
            previous: _weekDelivered(recent: false),
            noun: 'delivered',
          ),
        ),
        onTap: widget.onShowJobs,
      ),
      ConsoleKpiCard(
        label: "Today's Revenue",
        value: s.today.money.toStringAsFixed(2),
        icon: Icons.payments_outlined,
        footnote: _Movement(
          trend: _trend(s.today.money, s.yesterday.money),
          fallback: 'Nothing taken yesterday to compare with',
          // The summary's own day list, not the tier series: that series is gross customer spend
          // and carries the express surcharge, which is platform revenue and never a carrier's.
          note: _weekNote(
            current: _weekMoney(s, recent: true),
            previous: _weekMoney(s, recent: false),
            noun: 'earned on delivery fees',
            money: true,
          ),
        ),
      ),
    ];
  }

  /// What the platform knows about this fleet today, where the design draws a fleet movement.
  Widget _fleetFootnote(int fleet) {
    final List<RiderDeliveredToday>? today = _deliveredToday;
    if (today == null) {
      return const Text(
        'Fleet size is not recorded day by day',
        style: TextStyle(fontSize: 13, color: DeliveryColors.faint),
      );
    }

    // Riders with nothing delivered are absent from that endpoint by design, so this is a count of
    // who appears, narrowed to the fleet when the roster loaded.
    final Set<String> roster = (_riders ?? const <String>[]).toSet();
    final int delivering = today
        .where((RiderDeliveredToday r) =>
            r.delivered > 0 && (roster.isEmpty || roster.contains(r.riderId)))
        .length;

    return Text(
      _riders == null
          ? '$delivering delivered something today'
          : '$delivering of $fleet delivered something today',
      style: const TextStyle(fontSize: 13, color: DeliveryColors.faint),
    );
  }

  /// The design's green movement line, but only where a real comparison exists.
  ///
  /// A percentage against zero is not a percentage, so "yesterday was nothing" returns null and the
  /// card says that in words instead of printing an infinity.
  ConsoleKpiTrend? _trend(num today, num yesterday) {
    if (yesterday == 0) return null;
    if (today == yesterday) {
      return const ConsoleKpiTrend(
        delta: 'Level',
        caption: 'vs yesterday',
        accent: DeliveryAccent.info,
      );
    }

    final double percent = (today - yesterday) / yesterday * 100;
    final bool up = percent > 0;
    return ConsoleKpiTrend(
      delta: '${up ? '+' : '−'}${percent.abs().toStringAsFixed(1)}%',
      caption: 'vs yesterday',
      accent: up ? DeliveryAccent.positive : DeliveryAccent.critical,
      rising: up,
    );
  }

  /// Deliveries over one of the two weeks in the series, both tiers together.
  ///
  /// Null when the series is not loaded or is shorter than the fourteen days the comparison needs —
  /// half a window compared against the other half would be a made-up movement.
  int? _weekDelivered({required bool recent}) {
    final TierTradeSeries? series = _series;
    if (series == null || series.days.length < 14) return null;
    final List<TierTradeDay> days = series.days;
    final List<TierTradeDay> week = recent
        ? days.sublist(days.length - 7)
        : days.sublist(days.length - 14, days.length - 7);
    return week.fold<int>(0, (int sum, TierTradeDay d) => sum + d.delivered);
  }

  /// The same two weeks of the carrier's own money, from the summary's day list.
  double? _weekMoney(CarrierSummary s, {required bool recent}) {
    if (s.days.length < 14) return null;
    final List<TradingDay> week = recent
        ? s.days.sublist(s.days.length - 7)
        : s.days.sublist(s.days.length - 14, s.days.length - 7);
    return week.fold<double>(0, (double sum, TradingDay d) => sum + d.money);
  }

  /// "This week: 54 delivered, +12.5% on the week before" — or nothing at all when either week is
  /// missing, and no percentage when the week before was empty.
  String? _weekNote({
    required num? current,
    required num? previous,
    required String noun,
    bool money = false,
  }) {
    if (current == null) return null;
    final String amount = money ? current.toDouble().toStringAsFixed(2) : '$current';
    if (previous == null || previous == 0) {
      return 'This week: $amount $noun';
    }

    final double percent = (current - previous) / previous * 100;
    if (percent.abs() < 0.05) return 'This week: $amount $noun, level on the week before';
    final String sign = percent > 0 ? '+' : '−';
    return 'This week: $amount $noun, '
        '$sign${percent.abs().toStringAsFixed(1)}% on the week before';
  }

  /// How many distinct riders are holding work that has not finished.
  int get _ridersOnAJob {
    final List<DeliveryOrder> jobs = _jobs ?? const <DeliveryOrder>[];
    return jobs
        .where((DeliveryOrder j) => !j.status.isTerminal && j.riderId != null)
        .map((DeliveryOrder j) => j.riderId!)
        .toSet()
        .length;
  }

  /// The design's `dashboard-split` (3:3517): a flexible chart card beside a fixed 380px feed.
  ///
  /// Wraps below 1100 rather than squeezing — at that width the seven chart columns and a 380px
  /// card cannot both be the size they are drawn at, and the chart is the one that stops reading.
  Widget _split(CarrierSummary s, List<DeliveryOrder> jobs) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Widget chart = _chartCard(jobs);
        final Widget feed = _feedCard(jobs);

        if (constraints.maxWidth < 1100) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              chart,
              const SizedBox(height: ConsoleMetrics.pageGap),
              feed,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: chart),
            const SizedBox(width: ConsoleMetrics.pageGap),
            SizedBox(width: 380, child: feed),
          ],
        );
      },
    );
  }

  Widget _chartCard(List<DeliveryOrder> jobs) {
    final List<_TierColumn> columns = _hourlyColumns(jobs);

    return ConsoleCard(
      title: 'Hourly Dispatch Volume',
      // The design's two swatches, and both are now real: an order carries the tier it was placed
      // at, so the split is read off the same jobs rather than modelled.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const ConsoleLegendSwatch(label: 'Standard', color: DeliveryColors.brand),
          const SizedBox(width: DeliverySpacing.sm),
          ConsoleLegendSwatch(label: 'Express', color: _expressColor),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _TierBarChart(
            columns: columns,
            // The design's 130px plot. Passed rather than defaulted so the one number that decides
            // the card's height sits beside the card it decides.
            height: 130,
            emptyLabel: 'No jobs placed today yet',
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          Text(
            _jobs == null
                ? 'Could not read the job board just now.'
                : 'Jobs placed today, in two-hour blocks, split by the tier each was placed at, '
                    'from the most recent $_jobsWindow jobs.',
            style: ConsoleText.meta,
          ),
        ],
      ),
    );
  }

  /// The design's seven columns — 08:00 to 20:00 in two-hour steps — filled with today's real
  /// placements, each split into the two tiers the platform now sells.
  ///
  /// Work outside that window is not folded into the end columns: a 03:00 job counted under 08:00
  /// would be a wrong number in a chart about when the day is busy. The caption says which jobs
  /// these are.
  List<_TierColumn> _hourlyColumns(List<DeliveryOrder> jobs) {
    final DateTime now = DateTime.now();
    final List<int> standard = List<int>.filled(7, 0);
    final List<int> express = List<int>.filled(7, 0);

    for (final DeliveryOrder job in jobs) {
      final DateTime? at = job.placedAt;
      if (at == null) continue;
      if (at.year != now.year || at.month != now.month || at.day != now.day) continue;
      final int slot = (at.hour - 8) ~/ 2;
      if (slot < 0 || slot >= standard.length) continue;
      if (job.deliveryTier == DeliveryTier.express) {
        express[slot]++;
      } else {
        standard[slot]++;
      }
    }

    return <_TierColumn>[
      for (int i = 0; i < standard.length; i++)
        _TierColumn(
          label: '${(8 + i * 2).toString().padLeft(2, '0')}:00',
          standard: standard[i],
          express: express[i],
          window: '${(8 + i * 2).toString().padLeft(2, '0')}:00 and '
              '${(10 + i * 2).toString().padLeft(2, '0')}:00',
        ),
    ];
  }

  /// The design's `activity-card` (3:3565), built from the job board rather than from an event bus.
  ///
  /// Every line here is a fact the app already holds — a job that was delivered, cancelled, or is
  /// on the road — with the timestamp the server stamped on it.
  Widget _feedCard(List<DeliveryOrder> jobs) {
    final List<DeliveryOrder> matching = jobs.where(_matches).toList();
    final List<_Event> events = _events(matching);

    return ConsoleCard(
      title: 'Live Active Feed',
      // The count is the real one: how much of the loaded board this card is showing.
      trailing: _jobs == null
          ? null
          : ConsoleCountChip(_query.isEmpty
              ? '${events.length} of ${jobs.length} recent'
              : '${events.length} of ${matching.length} matching'),
      child: events.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.md),
              child: Text(
                _jobs == null
                    ? 'Could not read the job board just now.'
                    : _query.isEmpty
                        ? 'Nothing has happened on the job board yet.'
                        : 'No recent job matches that.',
                style: ConsoleText.pageSubtitle,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < events.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(height: DeliverySpacing.md),
                  ConsoleActivityRow(
                    message: events[i].message,
                    when: _ago(events[i].at),
                    accent: events[i].accent,
                  ),
                ],
              ],
            ),
    );
  }

  bool _matches(DeliveryOrder job) {
    if (_query.isEmpty) return true;
    final String needle = _query.toLowerCase();
    return job.shortId.toLowerCase().contains(needle) ||
        (job.storeName ?? '').toLowerCase().contains(needle) ||
        job.status.label.toLowerCase().contains(needle) ||
        job.deliveryAddress.toLowerCase().contains(needle);
  }

  List<_Event> _events(List<DeliveryOrder> jobs) {
    final List<_Event> events = <_Event>[];

    for (final DeliveryOrder job in jobs) {
      final DateTime? at = job.deliveredAt ?? job.placedAt;
      if (at == null) continue;

      final String where = job.storeName == null ? '' : ' from ${job.storeName}';
      final (String message, DeliveryAccent accent) = switch (job.status) {
        OrderStatus.delivered => ('Job #${job.shortId} delivered$where.', DeliveryAccent.positive),
        OrderStatus.cancelled => ('Job #${job.shortId} was cancelled.', DeliveryAccent.critical),
        OrderStatus.pickedUp => ('Job #${job.shortId} is on the way$where.', DeliveryAccent.info),
        _ => ('Job #${job.shortId} is ${job.status.label.toLowerCase()}$where.',
            DeliveryAccent.caution),
      };
      events.add(_Event(at: at, message: message, accent: accent));
    }

    events.sort((_Event a, _Event b) => b.at.compareTo(a.at));
    // Four rows in the design; five here, because the card is the taller of the split at most
    // widths and a fifth line costs nothing.
    return events.take(5).toList();
  }

  /// "Just now", "4 mins ago" — the design's own relative wording.
  static String _ago(DateTime at) {
    final Duration since = DateTime.now().difference(at);
    if (since.inMinutes < 1) return 'Just now';
    if (since.inMinutes < 60) return '${since.inMinutes} mins ago';
    if (since.inHours < 24) return '${since.inHours} hours ago';
    if (since.inDays == 1) return 'Yesterday';
    return '${since.inDays} days ago';
  }
}

/// The Express series' colour, from the token scale rather than picked here: amber against the
/// brand crimson, two hues that stay apart for the commonest colour blindness, which two reds
/// would not.
final Color _expressColor = DeliveryAccent.caution.color;

/// One line of the activity feed, before it is sorted.
class _Event {
  const _Event({required this.at, required this.message, required this.accent});

  final DateTime at;
  final String message;
  final DeliveryAccent accent;
}

/// The trend row the design draws, with the week underneath it.
///
/// [ConsoleKpiCard] renders either a trend or a footnote, and this card has both to say, so the
/// movement is drawn here in the footnote slot at the trend row's own proportions.
class _Movement extends StatelessWidget {
  const _Movement({required this.trend, required this.fallback, this.note});

  /// Null when yesterday was nothing — a percentage against zero is not a percentage.
  final ConsoleKpiTrend? trend;

  /// What to say instead of a movement that cannot be computed.
  final String fallback;

  /// The week-over-week line. Null when the series needed for it did not arrive.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final ConsoleKpiTrend? t = trend;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (t == null)
          Text(fallback, style: const TextStyle(fontSize: 13, color: DeliveryColors.faint))
        else
          Row(
            children: <Widget>[
              Icon(
                t.rising ? Icons.arrow_outward : Icons.south_east,
                size: 14,
                color: t.accent.color,
              ),
              const SizedBox(width: DeliverySpacing.xs),
              Flexible(
                child: Text(
                  t.delta,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.accent.color,
                  ),
                ),
              ),
              const SizedBox(width: DeliverySpacing.xs),
              Flexible(
                child: Text(
                  t.caption,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: DeliveryColors.faint),
                ),
              ),
            ],
          ),
        if (note != null) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            note!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: ConsoleText.meta,
          ),
        ],
      ],
    );
  }
}

/// One column of the tier-split chart: the same hour, counted twice.
class _TierColumn {
  const _TierColumn({
    required this.label,
    required this.standard,
    required this.express,
    required this.window,
  });

  final String label;
  final int standard;
  final int express;

  /// "08:00 and 10:00", for the tooltip's sentence.
  final String window;

  int get total => standard + express;
}

/// The design's `chart-visual` (3:3528): two bars per column, 130px tall, captions in Regular 11.
///
/// A private chart rather than [ConsoleBarChart], which draws one series — the shell component is
/// shared with the Backoffice console and is not this screen's to change. The geometry is the
/// design's: two 8px bars 4px apart inside each column, 32px between columns, a 4px top radius, and
/// a 2px hairline for an empty slot so a reader can see the slot exists and is empty.
class _TierBarChart extends StatelessWidget {
  const _TierBarChart({
    required this.columns,
    required this.height,
    required this.emptyLabel,
  });

  final List<_TierColumn> columns;
  final double height;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final int peak = columns.isEmpty
        ? 0
        : columns
            .map((_TierColumn c) => c.standard > c.express ? c.standard : c.express)
            .reduce((int a, int b) => a > b ? a : b);

    if (columns.isEmpty || peak <= 0) {
      return SizedBox(
        height: height,
        child: Center(child: Text(emptyLabel, style: ConsoleText.pageSubtitle)),
      );
    }

    return SizedBox(
      height: height + 20,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            for (int i = 0; i < columns.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: DeliverySpacing.xl),
              _Pair(column: columns[i], peak: peak, height: height),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pair extends StatelessWidget {
  const _Pair({required this.column, required this.peak, required this.height});

  final _TierColumn column;
  final int peak;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        Tooltip(
          message: '${column.total} placed between ${column.window} — '
              '${column.standard} standard, ${column.express} express',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _bar(column.standard, DeliveryColors.brand),
              const SizedBox(width: DeliverySpacing.xs),
              _bar(column.express, _expressColor),
            ],
          ),
        ),
        const SizedBox(height: DeliverySpacing.sm),
        // Pinned to exactly one font-size of height, as the shell's chart does: the frame budgets
        // 20px under the tallest bar for gap plus label.
        Text(column.label, style: ConsoleText.meta.copyWith(height: 1.0)),
      ],
    );
  }

  Widget _bar(int value, Color color) {
    final double filled = value <= 0 ? 2 : (value / peak) * height;
    return Container(
      width: 8,
      height: filled.clamp(2, height),
      decoration: BoxDecoration(
        color: value <= 0 ? DeliveryColors.border : color,
        // 4px, the only radius on these frames the token scale does not carry.
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      ),
    );
  }
}
