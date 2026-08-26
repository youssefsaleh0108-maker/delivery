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
/// the right. The design draws figures this platform does not all keep, and the rule applied
/// throughout is that a number is either derived from something loaded or is not shown at all:
///
/// * **Total Assigned Riders** is the fleet list's length. Real. The design's "+4 new vs yesterday"
///   is not — nothing records a fleet's size yesterday — so that card carries a Coming-soon chip
///   where the movement would be.
/// * **Active Right Now** counts the distinct riders holding a job that has not finished, out of
///   the loaded page of work. Real, and labelled as what it is rather than as presence: the
///   platform has no idea who has the rider app open.
/// * **Deliveries Today** and **Today's Revenue** come from [CarrierSummary], which already carries
///   today and yesterday — so those two get the design's real green movement line.
///
/// The hourly chart is one series. The design splits every column into Express and Standard; there
/// are no service tiers on this platform, and inventing a split would be inventing the numbers on
/// both sides of it.
class CarrierDashboardScreen extends StatefulWidget {
  const CarrierDashboardScreen({
    super.key,
    required this.api,
    required this.providerApi,
    this.onShowJobs,
  });

  final OrderApi api;

  /// For the company's name in the page subtitle and the fleet count in the first KPI. The design's
  /// header names the carrier, and "Operational health dashboard for" with nothing after it would
  /// be worse than no subtitle.
  final DeliveryProviderApi providerApi;

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

  Timer? _poll;
  CarrierSummary? _summary;
  DeliveryProviderInfo? _company;
  List<String>? _riders;
  List<DeliveryOrder>? _jobs;
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
    try {
      // The summary is the page. Everything else enriches it, so each of the other three is allowed
      // to fail on its own and leave its card saying "—" rather than taking the screen down.
      final CarrierSummary summary = await widget.api.carrierSummary();
      final DeliveryProviderInfo? company = await _tryLoad(widget.providerApi.myCompany);
      final List<String>? riders = await _tryLoad(widget.providerApi.myRiders);
      final Paged<DeliveryOrder>? jobs =
          await _tryLoad(() => widget.api.forCarrier(size: _jobsWindow));

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _company = company;
        _riders = riders;
        _jobs = jobs?.content;
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
          const ConsoleSearchField.global(
            hintText: 'Search console...',
            enabled: false,
          ),
          const ConsoleComingSoonChip(),
          ConsoleIconAction(
            icon: Icons.refresh,
            tooltip: t.refresh,
            onPressed: () => _refresh(),
          ),
          const ConsoleIconAction(
            icon: Icons.notifications_none,
            tooltip: 'Notifications — coming soon',
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
        // nowhere to come from. The chip says so rather than the card inventing a movement.
        footnote: const ConsoleComingSoonChip(label: 'Day-over-day soon'),
      ),
      ConsoleKpiCard(
        label: 'Active Right Now',
        value: _jobs == null ? '—' : '$onJob Active',
        icon: Icons.near_me_outlined,
        // Deliberately not a [ConsoleKpiTrend]: an arrow beside a share would read as a movement,
        // and this is a proportion of the fleet at one moment.
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
        trend: _trend(s.today.delivered, s.yesterday.delivered),
        footnote: _trend(s.today.delivered, s.yesterday.delivered) == null
            ? const Text('Nothing delivered yesterday to compare with',
                style: TextStyle(fontSize: 13, color: DeliveryColors.faint))
            : null,
        onTap: widget.onShowJobs,
      ),
      ConsoleKpiCard(
        label: "Today's Revenue",
        value: s.today.money.toStringAsFixed(2),
        icon: Icons.payments_outlined,
        trend: _trend(s.today.money, s.yesterday.money),
        footnote: _trend(s.today.money, s.yesterday.money) == null
            ? const Text('Nothing taken yesterday to compare with',
                style: TextStyle(fontSize: 13, color: DeliveryColors.faint))
            : null,
      ),
    ];
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
    final List<ConsoleBar> bars = _hourlyBars(jobs);

    return ConsoleCard(
      title: 'Hourly Dispatch Volume',
      // One swatch, not the design's two. The second series would be the Standard tier of a
      // service-tier system that does not exist here; see the class doc.
      trailing: const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ConsoleLegendSwatch(label: 'Jobs', color: DeliveryColors.brand),
          SizedBox(width: DeliverySpacing.sm),
          ConsoleComingSoonChip(label: 'Tier split soon'),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ConsoleBarChart(
            bars: bars,
            emptyLabel: 'No jobs placed today yet',
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          Text(
            _jobs == null
                ? 'Could not read the job board just now.'
                : 'Jobs placed today, in two-hour blocks, from the most recent $_jobsWindow jobs.',
            style: ConsoleText.meta,
          ),
        ],
      ),
    );
  }

  /// The design's seven columns — 08:00 to 20:00 in two-hour steps — filled with today's real
  /// placements.
  ///
  /// Work outside that window is not folded into the end columns: a 03:00 job counted under 08:00
  /// would be a wrong number in a chart about when the day is busy. The caption says which jobs
  /// these are.
  List<ConsoleBar> _hourlyBars(List<DeliveryOrder> jobs) {
    final DateTime now = DateTime.now();
    final List<int> counts = List<int>.filled(7, 0);

    for (final DeliveryOrder job in jobs) {
      final DateTime? at = job.placedAt;
      if (at == null) continue;
      if (at.year != now.year || at.month != now.month || at.day != now.day) continue;
      final int slot = (at.hour - 8) ~/ 2;
      if (slot < 0 || slot >= counts.length) continue;
      counts[slot]++;
    }

    return <ConsoleBar>[
      for (int i = 0; i < counts.length; i++)
        ConsoleBar(
          label: '${(8 + i * 2).toString().padLeft(2, '0')}:00',
          value: counts[i],
          tooltip: '${counts[i]} placed between '
              '${(8 + i * 2).toString().padLeft(2, '0')}:00 and '
              '${(10 + i * 2).toString().padLeft(2, '0')}:00',
        ),
    ];
  }

  /// The design's `activity-card` (3:3565), built from the job board rather than from an event bus.
  ///
  /// Every line here is a fact the app already holds — a job that was delivered, cancelled, or is
  /// on the road — with the timestamp the server stamped on it. The design's other two event kinds,
  /// rider assignments and operational alerts, are not emitted by anything, which the chip says.
  Widget _feedCard(List<DeliveryOrder> jobs) {
    final List<_Event> events = _events(jobs);

    return ConsoleCard(
      title: 'Live Active Feed',
      trailing: const ConsoleComingSoonChip(label: 'Alerts soon'),
      child: events.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.md),
              child: Text(
                _jobs == null
                    ? 'Could not read the job board just now.'
                    : 'Nothing has happened on the job board yet.',
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

/// One line of the activity feed, before it is sorted.
class _Event {
  const _Event({required this.at, required this.message, required this.accent});

  final DateTime at;
  final String message;
  final DeliveryAccent accent;
}
