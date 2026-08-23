import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// The delivery company's own page: how today went, and how the fortnight is going.
///
/// Deliberately not a copy of the merchant's. This portal already answers "what are we owed" on the
/// earnings page and "how are we doing" on the company page, so a dashboard that restated either
/// would be a third place to read the same number and a third place for it to be stale. What
/// neither page has is time: every figure in this app is a running total, and none of them can tell
/// a company whether this week is better than last.
///
/// So the day and the trend are the whole screen, and the two numbers that already exist elsewhere
/// — the score, the payout — are left where they are.
class CarrierDashboardScreen extends StatefulWidget {
  const CarrierDashboardScreen({super.key, required this.api, this.onShowJobs});

  final OrderApi api;

  /// Today's work leads to the job board. A count with nowhere to go is decoration.
  final VoidCallback? onShowJobs;

  @override
  State<CarrierDashboardScreen> createState() => _CarrierDashboardScreenState();
}

class _CarrierDashboardScreenState extends State<CarrierDashboardScreen> {
  static const Duration _pollInterval = Duration(seconds: 60);

  Timer? _poll;
  CarrierSummary? _summary;
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
      final CarrierSummary summary = await widget.api.carrierSummary();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      // A background poll that fails leaves the last good numbers up. Replacing a working screen
      // with an error because one refresh missed is a worse answer than slightly old figures.
      if (!silent) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.navDashboard),
        actions: <Widget>[
          IconButton(
            onPressed: () => _refresh(),
            icon: const Icon(Icons.refresh),
            tooltip: t.refresh,
          ),
        ],
      ),
      body: switch ((_summary, _error)) {
        // Belonging to no company is a provisioning gap, not a failure — the same expected state
        // the earnings screen handles, worded the same way so it does not read as two bugs.
        (null, final Object? e) when e != null => _noCompany(t),
        (null, _) => const Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
        (final CarrierSummary s, _) => _body(s, t),
      },
    );
  }

  Widget _noCompany(DeliveryStrings t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DeliverySpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.help_outline, size: 40, color: DeliveryColors.muted),
            const SizedBox(height: DeliverySpacing.md),
            Text(t.noCompanyYet, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: DeliverySpacing.xs),
            Text(t.askThePlatformToAttachYou,
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _body(CarrierSummary s, DeliveryStrings t) {
    return RefreshIndicator(
      onRefresh: () => _refresh(),
      color: DeliveryColors.brand,
      child: ListView(
        padding: const EdgeInsets.all(DeliverySpacing.lg),
        children: <Widget>[
          // IntrinsicHeight, not a bare stretch. Inside a ListView the row's height is unbounded,
          // and stretching against an unbounded constraint is an infinite height — a crash on the
          // first paint rather than a cosmetic problem.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: TrendHeadline(
                    value: '${s.today.orders}',
                    label: t.jobsToday,
                    icon: Icons.local_shipping_outlined,
                    direction: TrendDirection.between(s.today.orders, s.yesterday.orders),
                    comparison: _compare(s.today.orders, s.yesterday.orders, t),
                  ),
                ),
                const SizedBox(width: DeliverySpacing.sm),
                Expanded(
                  child: TrendHeadline(
                    // Gross of the platform's cut, unlike the earnings page, and labelled as the
                    // day's takings rather than as earnings so the two cannot be mistaken for each
                    // other. The net figure for the window is in the tiles below.
                    value: s.today.money.toStringAsFixed(2),
                    label: t.earnedToday,
                    icon: Icons.payments_outlined,
                    direction: TrendDirection.between(s.today.money, s.yesterday.money),
                    comparison: _compare(s.today.money, s.yesterday.money, t),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: DeliverySpacing.lg),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionLabel(t.lastDaysHeading(s.windowDays)),
                const SizedBox(height: DeliverySpacing.md),
                TrendChart(
                  points: s.days.map((TradingDay d) => TrendPoint(
                        label: _dayLabel(context, d.day),
                        total: d.orders,
                        completed: d.delivered,
                        money: d.money,
                      )).toList(),
                  emptyLabel: t.noJobsSoFar,
                  formatMoney: (double m) => m.toStringAsFixed(2),
                ),
                const SizedBox(height: DeliverySpacing.sm),
                Text(t.barChartLegend, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: DeliverySpacing.lg),
          StatRow(tiles: <Widget>[
            StatTile(
              value: '${s.window.orders}',
              label: t.ordersInWindow,
              icon: Icons.local_shipping_outlined,
              accent: DeliveryAccent.neutral,
              footnote: t.lastDaysHeading(s.windowDays),
              onTap: widget.onShowJobs,
            ),
            StatTile(
              value: '${s.window.delivered}',
              label: t.deliveredInWindow,
              icon: Icons.check_circle_outline,
              accent: DeliveryAccent.positive,
            ),
            StatTile(
              value: s.earned.toStringAsFixed(2),
              label: t.earned,
              icon: Icons.payments_outlined,
              accent: DeliveryAccent.positive,
              footnote: t.feesInWindowNote(s.cutPercentage.toStringAsFixed(0)),
            ),
            if (s.savedByOffers > 0)
              StatTile(
                value: s.savedByOffers.toStringAsFixed(2),
                label: t.savedByOffers,
                icon: Icons.redeem_rounded,
                accent: DeliveryAccent.positive,
                footnote: t.savedForYouNote,
              ),
          ]),
        ],
      ),
    );
  }

  /// A percentage against zero is not a percentage, so both "yesterday was nothing" cases are
  /// worded instead of computed.
  String _compare(num today, num yesterday, DeliveryStrings t) {
    if (today == 0 && yesterday == 0) return t.nothingYetToday;
    if (yesterday == 0) return t.noneYesterday;
    if (today == yesterday) return t.sameAsYesterday;

    final int percent = ((today - yesterday) / yesterday * 100).abs().round();
    return today > yesterday ? t.upOnYesterday(percent) : t.downOnYesterday(percent);
  }

  static String _dayLabel(BuildContext context, DateTime day) {
    // narrowWeekdays is indexed from Sunday; DateTime.weekday runs Monday(1)..Sunday(7).
    return MaterialLocalizations.of(context).narrowWeekdays[day.weekday % 7];
  }
}
