import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'rider_job_card.dart';
import 'rider_settings_widgets.dart';
import 'rider_statement_screen.dart';

/// What the rider has earned — Figma `rider-earnings` (3:1486).
///
/// Wired to the Accounting rider-earnings API when [moneyApi] is provided: the headline figures,
/// the day-by-day chart, the job history with its tips and reimbursements, the balance line and a
/// real cash-out button all come from the ledger, in one call so the arithmetic on screen adds up.
/// Tips are rendered from the API even though nothing can collect one online yet — a day with no
/// tips reads "0.00 tips", honestly, rather than wearing a chip.
///
/// The three stats under the headline are all real now, and none of them comes from the ledger:
///
/// * **Deliveries** — the period's finished jobs, from the ledger.
/// * **Completed** — the rider-performance endpoint's 30-day completion rate. Deliberately not
///   labelled "accept rate": nothing anywhere records a *declined* offer (the board is claim-only,
///   so a job a rider scrolls past is indistinguishable from one they never saw), and putting the
///   completion rate under an acceptance label would be a lie about a different measurement. Null
///   when the rider has claimed nothing in the window, and rendered "—" then, never 0% or 100%.
/// * **Rating** — the rider's own standing, "new" (never zero) while nobody has rated them.
///
/// **Hours online** is the duty-hours report, bucketed in the *server's* zone rather than the
/// phone's: the report echoes which zone split its days and this screen reads today's row out of
/// it by that label instead of guessing which midnight a night shift belonged to.
///
/// All three ride alongside the money and none of them can sink it — a rider whose rating service
/// is down still needs to see what they earned today, so each failure degrades to its own stat and
/// no further.
///
/// Without [moneyApi] the screen keeps its pre-wiring behaviour: figures derived from the rider's
/// own delivered orders, labelled as derived. The stats above are wired in that flavour too.
class RiderEarningsScreen extends StatefulWidget {
  const RiderEarningsScreen({
    super.key,
    required this.api,
    this.moneyApi,
    this.trackingApi,
    this.performanceApi,
    this.statementsApi,
  });

  final OrderApi api;

  /// The accounting ledger. Null keeps the derived-from-orders fallback.
  final RiderMoneyApi? moneyApi;

  /// The duty half of the tracking service, behind the HOURS ONLINE figure. Null keeps that one
  /// stat inert; everything else on the screen is unaffected.
  final TrackingApi? trackingApi;

  /// The rider-performance endpoint, behind the completion rate. Null keeps that one stat inert.
  final RiderPerformanceApi? performanceApi;

  /// The counterparty-statements client, behind the row that opens [RiderStatementScreen].
  ///
  /// Null draws no row at all rather than an inert one. The statement is a whole screen with its
  /// own network call, and a row that opens an empty version of it is worse than no row: this
  /// screen's own figures are still true without it.
  final StatementsApi? statementsApi;

  @override
  State<RiderEarningsScreen> createState() => _RiderEarningsScreenState();
}

/// The design's two periods.
enum _Period { today, week }

/// Everything the wired screen renders, fetched together so a pull-to-refresh moves all of it —
/// including a cash-out that has just been decided.
class _LedgerData {
  const _LedgerData({
    required this.earnings,
    required this.jobs,
    required this.cashOuts,
  });

  final RiderEarnings earnings;
  final List<RiderJob> jobs;

  /// Newest first. What the cash-out sheet lists, and where a decided request shows PAID or
  /// REJECTED after a refresh.
  final List<CashOut> cashOuts;
}

/// The three facts about the *rider* rather than about their money, fetched from three different
/// services and held together only because the design draws them in one row.
///
/// Every field is nullable and every one is loaded independently: a service that does not answer
/// costs its own stat and nothing else. That is why they are not part of [_LedgerData] — a single
/// failed rating call must not take the earnings down with it.
class _RiderStats {
  const _RiderStats({this.standing, this.performance, this.hours});

  /// Null when the rating service could not answer. Distinct from an unrated rider, which is a
  /// successful answer with no average in it.
  final RiderStanding? standing;

  /// The 30-day claimed/delivered record. Null when no performance API was handed in, or the call
  /// failed.
  final RiderPerformance? performance;

  /// Days with on-duty time in the window, in the server's own day zone. Null when no tracking API
  /// was handed in, or the call failed. An empty [HoursOnline.days] is NOT null — it is a rider
  /// who was never online, and reads as 0.00.
  final HoursOnline? hours;
}

class _RiderEarningsScreenState extends State<RiderEarningsScreen> {
  _Period _period = _Period.today;

  late Future<List<DeliveryOrder>> _delivered;
  late Future<_LedgerData> _ledger;

  /// The rider's own stats. Starts empty — every stat renders its own honest resting state until
  /// the call behind it lands, and keeps the last answer if a later refresh fails.
  _RiderStats _stats = const _RiderStats();

  /// How many days of duty history the HOURS ONLINE figure covers.
  ///
  /// Seven, to match the WEEK period and the chart beside it: the tracking service refuses a
  /// `days` outside 1..30 with a 400 rather than clamping, so this is a fixed, in-range constant
  /// and never arithmetic on something a screen decided.
  static const int _dutyWindowDays = 7;

  @override
  void initState() {
    super.initState();
    if (widget.moneyApi == null) {
      _delivered = _loadDerived();
    } else {
      _ledger = _loadLedger();
    }
    unawaited(_loadStats());
  }

  // ------------------------------------------------------------------- loading

  Future<_LedgerData> _loadLedger() async {
    final RiderMoneyApi money = widget.moneyApi!;
    final List<Object> parts = await Future.wait(<Future<Object>>[
      money.earnings(days: 7),
      money.recentJobs(limit: 50),
      money.myCashOuts(limit: 10),
    ]);
    return _LedgerData(
      earnings: parts[0] as RiderEarnings,
      jobs: parts[1] as List<RiderJob>,
      cashOuts: parts[2] as List<CashOut>,
    );
  }

  /// The three rider stats, each independently.
  ///
  /// [Future.wait] would be wrong here: it completes with the first error and would throw away two
  /// good answers because the third service was down. Each call is caught on its own instead, and
  /// a failure leaves that stat null while the other two render.
  Future<void> _loadStats() async {
    final _RiderStats loaded = _RiderStats(
      standing: await _quiet<RiderStanding>(() => widget.api.myRiderRating()),
      performance: widget.performanceApi == null
          ? null
          : await _quiet<RiderPerformance>(() => widget.performanceApi!.mine()),
      hours: widget.trackingApi == null
          ? null
          : await _quiet<HoursOnline>(
              () => widget.trackingApi!.myDutyHours(days: _dutyWindowDays)),
    );
    if (!mounted) return;
    setState(() => _stats = loaded);
  }

  /// Runs a call for its answer and treats any refusal as "no answer", which is what every one of
  /// these stats renders as its own inert state.
  static Future<T?> _quiet<T>(Future<T> Function() call) async {
    try {
      return await call();
    } catch (_) {
      return null;
    }
  }

  void _reloadLedger() {
    setState(() => _ledger = _loadLedger());
    unawaited(_loadStats());
  }

  /// The rider's own finished work — the pre-ledger fallback's source.
  Future<List<DeliveryOrder>> _loadDerived() async {
    final Paged<DeliveryOrder> page = await widget.api.assigned(size: 100);
    return page.content
        .where((DeliveryOrder o) => o.status == OrderStatus.delivered)
        .toList();
  }

  void _reloadDerived() {
    setState(() => _delivered = _loadDerived());
    unawaited(_loadStats());
  }

  /// Midnight today, which is where "Today" starts and the 7-day window ends.
  static DateTime _startOfToday() {
    final DateTime now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    return widget.moneyApi == null ? _buildDerived(context) : _buildLedger(context);
  }

  // ==================================================================== ledger

  Widget _buildLedger(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return FutureBuilder<_LedgerData>(
      future: _ledger,
      builder: (BuildContext context, AsyncSnapshot<_LedgerData> snapshot) {
        final _LedgerData? data = snapshot.data;
        return Column(
          children: <Widget>[
            _header(t, balance: data?.earnings.balance),
            Expanded(
              child: switch (snapshot.connectionState) {
                ConnectionState.done when snapshot.hasError => YdEmptyState(
                    icon: Icons.trending_up_rounded,
                    title: t.riderCouldNotLoadEarnings,
                  ),
                ConnectionState.done => _ledgerBody(context, t, data!),
                _ => const Center(
                    child:
                        CircularProgressIndicator(color: DeliveryColors.brand)),
              },
            ),
          ],
        );
      },
    );
  }

  Widget _ledgerBody(BuildContext context, DeliveryStrings t, _LedgerData data) {
    final EarningsTotal total =
        _period == _Period.today ? data.earnings.today : data.earnings.thisWeek;
    final List<RiderJob> jobs = _jobsInPeriod(data.jobs);

    return RefreshIndicator(
      onRefresh: () async => _reloadLedger(),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          _periodSelector(t),
          const SizedBox(height: DeliverySpacing.md),
          _ledgerStatsCard(t, data, total),
          if (_statementRow(context, t) case final Widget row) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            row,
          ],
          const SizedBox(height: DeliverySpacing.md),
          _ledgerWeeklyCard(t, data.earnings.series),
          const SizedBox(height: DeliverySpacing.md),
          Text(
            _period == _Period.today
                ? t.riderTodaysDeliveries
                : t.riderThisWeeksDeliveries,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
              height: 1.3,
            ),
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          if (jobs.isEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: DeliverySpacing.md),
              child: Text(
                t.riderNothingDeliveredYet,
                style: const TextStyle(
                  fontSize: 13,
                  color: DeliveryColors.muted,
                  height: 1.4,
                ),
              ),
            )
          else
            for (final RiderJob job in jobs)
              Padding(
                padding: const EdgeInsets.only(
                    bottom: DeliverySpacing.md - DeliverySpacing.xs),
                child: _jobRow(context, t, job),
              ),
        ],
      ),
    );
  }

  List<RiderJob> _jobsInPeriod(List<RiderJob> jobs) {
    final DateTime from = _period == _Period.today
        ? _startOfToday()
        : _startOfToday().subtract(const Duration(days: 6));
    return jobs
        .where((RiderJob j) =>
            j.deliveredAt != null && !j.deliveredAt!.isBefore(from))
        .toList()
      ..sort((RiderJob a, RiderJob b) =>
          (b.deliveredAt ?? DateTime(0)).compareTo(a.deliveredAt ?? DateTime(0)));
  }

  /// `stats-card`, fed by the ledger: the period's total, its delivery-pay/tips split, the
  /// balance line, and the three stats — of which deliveries and rating are real now.
  Widget _ledgerStatsCard(DeliveryStrings t, _LedgerData data, EarningsTotal total) {
    final RiderBalance balance = data.earnings.balance;
    // Newest first, so the head of the history is the most recent decision.
    final bool lastWasRefused = data.cashOuts.isNotEmpty &&
        data.cashOuts.first.status == CashOutStatus.rejected;

    return YdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      t.riderTotalEarnings.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        color: DeliveryColors.faint,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      total.total.toStringAsFixed(2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.ink,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    t.riderHoursOnline.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      color: DeliveryColors.faint,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: DeliverySpacing.xs),
                  _hoursOnlineValue(t),
                ],
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.sm),
          // Where the headline came from: the ledger's own split. Tips show even at zero —
          // "0.00 tips" is a fact, a hidden line is a question.
          Text(
            t.riderEarningsBreakdown(
              total.earnings.toStringAsFixed(2),
              total.tips.toStringAsFixed(2),
            ),
            style: const TextStyle(
              fontSize: 11,
              color: DeliveryColors.faint,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            t.riderBalanceLine(
              balance.balance.toStringAsFixed(2),
              balance.available.toStringAsFixed(2),
            ),
            style: const TextStyle(
              fontSize: 11,
              color: DeliveryColors.faint,
              height: 1.4,
            ),
          ),
          if (balance.openCashOut != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              t.riderCashOutOpenLine(
                  balance.openCashOut!.amount.toStringAsFixed(2)),
              style: TextStyle(
                fontSize: 11,
                color: DeliveryAccent.caution.color,
                height: 1.4,
              ),
            ),
          ] else if (lastWasRefused) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              t.riderCashOutLastRefused,
              style: TextStyle(
                fontSize: 11,
                color: DeliveryAccent.critical.color,
                height: 1.4,
              ),
            ),
          ],
          // The counts behind the completion stat below, so the percentage is checkable rather
          // than a figure the platform asserts about somebody's work.
          if (_performanceCaption(t) case final Widget counts) ...<Widget>[
            const SizedBox(height: 2),
            counts,
          ],
          const SizedBox(height: DeliverySpacing.md),
          const RiderHairline(),
          const SizedBox(height: DeliverySpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _stat(
                  value: Text(
                    '${total.jobs}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: DeliveryColors.ink,
                      height: 1.2,
                    ),
                  ),
                  label: t.deliveries,
                ),
              ),
              Expanded(
                child: _stat(
                  // Deliberately the completion rate under a completion label. Nothing records a
                  // declined offer — the board is claim-only, so an offer a rider scrolled past
                  // is indistinguishable from one they never saw — and there is therefore no
                  // acceptance rate on this platform to put here.
                  value: _completionValue(t),
                  label: t.riderCompletionRate,
                ),
              ),
              Expanded(
                child: _stat(
                  value: _ratingValue(t),
                  label: t.riderRating,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// `weekly-chart-card`, fed by the ledger's per-day series. Same bars, real buckets — the
  /// server already added tips into each day's total.
  Widget _ledgerWeeklyCard(DeliveryStrings t, List<EarningsDay> series) {
    final double best = series.fold<double>(
        0, (double m, EarningsDay d) => d.total > m ? d.total : m);
    final List<String> narrow = MaterialLocalizations.of(context).narrowWeekdays;

    return YdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            t.riderWeeklyOverview.toUpperCase(),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
              height: 1.3,
            ),
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          SizedBox(
            height: 90 + 6 + 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (int i = 0; i < series.length; i++)
                  Expanded(
                    child: _bar(
                      // narrowWeekdays is indexed Sunday-first; DateTime.weekday is
                      // Monday..Sunday as 1..7, so Sunday (7) folds back to 0.
                      letter: narrow[series[i].day.weekday % DateTime.daysPerWeek],
                      amount: series[i].total,
                      fraction: best <= 0 ? 0 : series[i].total / best,
                      // The series ends on the day the server bucketed as today.
                      isToday: i == series.length - 1,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// `txn-card` from a ledger job: the reference and time, then the money — pay, tip and
  /// reimbursement as their own lines, and whose money it is when it is not the platform's.
  Widget _jobRow(BuildContext context, DeliveryStrings t, RiderJob job) {
    final String shortId =
        job.orderId.length <= 8 ? job.orderId : job.orderId.substring(0, 8);
    final String meta = job.deliveredAt == null
        ? t.riderOrderRef(shortId)
        : MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(job.deliveredAt!),
            alwaysUse24HourFormat:
                MediaQuery.of(context).alwaysUse24HourFormat);

    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
      decoration: BoxDecoration(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: DeliveryColors.brandSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shopping_bag_outlined,
                size: 16, color: DeliveryColors.brand),
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  t.riderOrderRef(shortId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: DeliveryColors.faint,
                    height: 1.3,
                  ),
                ),
                // A figure the rider's own company owes must not read as money the platform
                // will hand over.
                if (job.payableBy != EarningsPayer.platform) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    riderPayerLabel(t, job.payableBy),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: DeliveryColors.muted,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                job.earned.toStringAsFixed(2),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.ink,
                  height: 1.2,
                ),
              ),
              if (job.tip > 0)
                Text(
                  t.riderTipLine(job.tip.toStringAsFixed(2)),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: DeliveryAccent.positive.color,
                    height: 1.3,
                  ),
                ),
              if (job.reimbursement > 0)
                Text(
                  t.riderReimbursedLine(job.reimbursement.toStringAsFixed(2)),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: DeliveryAccent.positive.color,
                    height: 1.3,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- cash-out

  Future<void> _openCashOut(_LedgerData data) async {
    final bool? changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DeliveryColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(DeliveryRadius.lg)),
      ),
      builder: (BuildContext context) => _CashOutSheet(
        moneyApi: widget.moneyApi!,
        balance: data.earnings.balance,
        history: data.cashOuts,
      ),
    );
    if (changed == true && mounted) _reloadLedger();
  }

  // ==================================================================== shared

  /// The white 56px bar. The design's "Payout" slot is the cash-out entry: a live control while
  /// there is money to ask for, and the REQUESTED tag while a request is in flight.
  ///
  /// The slot is left empty rather than chipped when this screen was built without a ledger. The
  /// cash-out shipped — it is the `else` branch below, and it is what every rider in the app
  /// reaches — so a "coming soon" chip here would describe a delivered feature as unbuilt. An
  /// empty slot says the truth for a shell that was handed no ledger: there is nothing here to
  /// press.
  Widget _header(DeliveryStrings t, {RiderBalance? balance}) {
    Widget? trailing;
    if (widget.moneyApi == null) {
      trailing = null;
    } else if (balance != null) {
      final CashOut? open = balance.openCashOut;
      trailing = Semantics(
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(DeliveryRadius.sm),
          onTap: () async {
            final _LedgerData data = await _ledger;
            if (mounted) await _openCashOut(data);
          },
          child: open != null
              ? RiderTag(
                  label: t.cashOutRequested,
                  color: DeliveryAccent.caution.color,
                  background: DeliveryAccent.caution.tint,
                )
              : Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: DeliverySpacing.xs,
                    vertical: DeliverySpacing.xs,
                  ),
                  child: Text(
                    t.riderCashOutTitle,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: DeliveryColors.brand,
                      height: 1.2,
                    ),
                  ),
                ),
        ),
      );
    }

    return Container(
      height: 56,
      width: double.infinity,
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: DeliverySpacing.lg),
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              t.riderMyEarnings,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: DeliveryColors.ink,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  /// The way through to the rider's own statement.
  ///
  /// It sits directly under the stats card because it answers the question that card raises and
  /// cannot answer: this screen shows what a rider has *earned*, and the statement shows where that
  /// leaves them with the platform once the cash they collected at the door is counted. Two very
  /// different numbers, and a rider who only ever sees the first one is surprised by the second.
  ///
  /// Null [RiderEarningsScreen.statementsApi] draws nothing — see that field.
  Widget? _statementRow(BuildContext context, DeliveryStrings t) {
    final StatementsApi? statements = widget.statementsApi;
    if (statements == null) return null;

    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    return RiderSettingRow(
      icon: Icons.receipt_long_outlined,
      tint: DeliveryColors.brandSoft,
      iconColour: DeliveryColors.brand,
      label: t.riderStatementTitle,
      subtitle: t.riderStatementRowSubtitle,
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => RiderStatementScreen(api: statements),
      )),
      trailing: Icon(
        rtl ? Icons.chevron_left : Icons.chevron_right,
        size: 16,
        color: DeliveryColors.faint,
      ),
    );
  }

  /// `period-selector`: a border-filled track with a white selected segment.
  Widget _periodSelector(DeliveryStrings t) {
    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.xs),
      decoration: BoxDecoration(
        color: DeliveryColors.border,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: _segment(t.riderPeriodToday, _Period.today)),
          const SizedBox(width: DeliverySpacing.xs),
          Expanded(child: _segment(t.riderPeriodWeekly, _Period.week)),
        ],
      ),
    );
  }

  Widget _segment(String label, _Period value) {
    final bool selected = _period == value;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? DeliveryColors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(DeliveryRadius.sm),
          onTap: selected ? null : () => setState(() => _period = value),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: DeliverySpacing.md,
              vertical: DeliverySpacing.sm,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? DeliveryColors.ink : DeliveryColors.muted,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The 16px figure every stat in this screen renders itself as.
  static const TextStyle _statValue = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: DeliveryColors.ink,
    height: 1.2,
  );

  /// HOURS ONLINE, from the duty-hours report — the same figure in both flavours of the screen.
  ///
  /// The window's days are labelled in the *server's* zone, echoed on the report, so "today" is
  /// the report's own `to` date rather than the phone's midnight: a 23:00–01:00 shift is split by
  /// the zone that recorded it and this screen must not re-split it by a different one.
  ///
  /// Today reads the server's rounded per-day figure; the week sums the exact seconds and rounds
  /// once, because adding seven rounded numbers is how a week comes to 39.99 hours. A date absent
  /// from the report is a day with no on-duty time — the report carries only the days that had
  /// some — so it reads 0.00 rather than going missing.
  ///
  /// No report yet — not loaded, or the service did not answer — reads "—", for the reason the
  /// rating below gives: on-duty hours are a shipped, working figure, and a "coming soon" chip
  /// would tell a rider their own timesheet was never built.
  Widget _hoursOnlineValue(DeliveryStrings t) {
    final HoursOnline? hours = _stats.hours;
    if (hours == null) return Text('—', style: _statValue);

    final double figure = _period == _Period.today
        ? _hoursOn(hours, hours.to)
        : hours.totalSecondsOnline / Duration.secondsPerHour;
    return Text(
      t.riderHoursValue(figure.toStringAsFixed(2)),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _statValue,
    );
  }

  static double _hoursOn(HoursOnline hours, DateTime day) {
    for (final DutyDay entry in hours.days) {
      if (entry.date.year == day.year &&
          entry.date.month == day.month &&
          entry.date.day == day.day) {
        return entry.hoursOnline;
      }
    }
    return 0;
  }

  /// The completion rate: delivered as a percentage of claimed over the server's own window.
  ///
  /// Null exactly when the rider has claimed nothing in the window, and rendered "—" then. Not
  /// 0%, which reads as a rider who fails everything, and not 100%, which reads as an invented
  /// success — both are lies about somebody's livelihood told by a screen with no data.
  ///
  /// A report that has not arrived reads "—" for the same reason: the figure is measured and
  /// shipped, so the honest thing to say about a missing one is nothing, not "coming soon".
  Widget _completionValue(DeliveryStrings t) {
    final RiderPerformance? performance = _stats.performance;
    if (performance == null) return Text('—', style: _statValue);

    final double? rate = performance.completionRate;
    return Text(
      rate == null ? '—' : '${rate.toStringAsFixed(2)}%',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _statValue,
    );
  }

  /// The rider's own standing. Unrated is "new", never zero.
  ///
  /// A rating service that did not answer renders "—" rather than a "coming soon" chip: ratings
  /// shipped, and a chip would describe the feature as unbuilt instead of the call as failed.
  Widget _ratingValue(DeliveryStrings t) {
    final RiderStanding? standing = _stats.standing;
    if (standing == null) return const Text('—', style: _statValue);
    return Text(
      standing.isRated ? standing.average!.toStringAsFixed(1) : t.ratingNewRider,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _statValue,
    );
  }

  /// The counts the completion rate is computed from, in the caption language the stats card
  /// already uses for "where this number came from" lines.
  ///
  /// Null when there is no performance answer, which draws no line at all — the card's other
  /// caption lines are conditional in exactly the same way.
  Widget? _performanceCaption(DeliveryStrings t) {
    final RiderPerformance? performance = _stats.performance;
    if (performance == null) return null;

    final String dropped = performance.cancelledAfterClaim > 0
        ? t.riderPerformanceDropped(performance.cancelledAfterClaim)
        : '';
    return Text(
      t.riderPerformanceLine(performance.delivered, performance.claimed,
              performance.windowDays) +
          dropped,
      style: const TextStyle(
        fontSize: 11,
        color: DeliveryColors.faint,
        height: 1.4,
      ),
    );
  }

  Widget _stat({required Widget value, required String label}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        value,
        const SizedBox(height: DeliverySpacing.xs),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            color: DeliveryColors.faint,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  Widget _bar({
    required String letter,
    required double amount,
    required double fraction,
    required bool isToday,
  }) {
    return Semantics(
      label: letter,
      value: amount.toStringAsFixed(2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Container(
            width: 16,
            height: (90 * fraction).clamp(0, 90),
            decoration: BoxDecoration(
              color: isToday
                  ? DeliveryAccent.positive.color
                  : DeliveryColors.brand,
              borderRadius: BorderRadius.circular(DeliveryRadius.sm / 2),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            letter,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
              color: isToday ? DeliveryColors.ink : DeliveryColors.muted,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================ derived legacy

  /// When an order counts as earned: when it was delivered, falling back to when it was placed
  /// for rows old enough to predate `deliveredAt`.
  static DateTime? _earnedAt(DeliveryOrder order) =>
      order.deliveredAt ?? order.placedAt;

  List<DeliveryOrder> _inPeriod(List<DeliveryOrder> all) {
    final DateTime from = _period == _Period.today
        ? _startOfToday()
        : _startOfToday().subtract(const Duration(days: 6));
    return all.where((DeliveryOrder o) {
      final DateTime? at = _earnedAt(o);
      return at != null && !at.isBefore(from);
    }).toList()
      ..sort((DeliveryOrder a, DeliveryOrder b) =>
          (_earnedAt(b) ?? DateTime(0)).compareTo(_earnedAt(a) ?? DateTime(0)));
  }

  static double _sum(List<DeliveryOrder> orders) => orders.fold<double>(
      0, (double total, DeliveryOrder o) => total + o.deliveryFee);

  Widget _buildDerived(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Column(
      children: <Widget>[
        _header(t),
        Expanded(
          child: FutureBuilder<List<DeliveryOrder>>(
            future: _delivered,
            builder: (BuildContext context,
                AsyncSnapshot<List<DeliveryOrder>> snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                    child: CircularProgressIndicator(
                        color: DeliveryColors.brand));
              }
              if (snapshot.hasError) {
                return YdEmptyState(
                  icon: Icons.trending_up_rounded,
                  title: t.riderCouldNotLoadEarnings,
                );
              }

              final List<DeliveryOrder> all = snapshot.data!;
              final List<DeliveryOrder> period = _inPeriod(all);

              return RefreshIndicator(
                onRefresh: () async => _reloadDerived(),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: <Widget>[
                    _periodSelector(t),
                    const SizedBox(height: DeliverySpacing.md),
                    _derivedStatsCard(t, period),
                    if (_statementRow(context, t) case final Widget row) ...<Widget>[
                      const SizedBox(height: DeliverySpacing.md),
                      row,
                    ],
                    const SizedBox(height: DeliverySpacing.md),
                    _derivedWeeklyCard(t, all),
                    const SizedBox(height: DeliverySpacing.md),
                    Text(
                      _period == _Period.today
                          ? t.riderTodaysDeliveries
                          : t.riderThisWeeksDeliveries,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.ink,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                    if (period.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: DeliverySpacing.md),
                        child: Text(
                          t.riderNothingDeliveredYet,
                          style: const TextStyle(
                            fontSize: 13,
                            color: DeliveryColors.muted,
                            height: 1.4,
                          ),
                        ),
                      )
                    else
                      for (final DeliveryOrder order in period)
                        Padding(
                          padding: const EdgeInsets.only(
                              bottom: DeliverySpacing.md - DeliverySpacing.xs),
                          child: _transaction(context, t, order),
                        ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// `stats-card`, derived flavour: the sum of the rider's own delivery fees, labelled as such.
  Widget _derivedStatsCard(DeliveryStrings t, List<DeliveryOrder> period) {
    return YdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      t.riderTotalEarnings.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        color: DeliveryColors.faint,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _sum(period).toStringAsFixed(2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.ink,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    t.riderHoursOnline.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      color: DeliveryColors.faint,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: DeliverySpacing.xs),
                  _hoursOnlineValue(t),
                ],
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.sm),
          // Says where the headline number came from, because a rider is entitled to know it is
          // the sum of their own delivery fees and not a figure the platform decided.
          Text(
            t.riderEarningsDerived,
            style: const TextStyle(
              fontSize: 11,
              color: DeliveryColors.faint,
              height: 1.4,
            ),
          ),
          if (_performanceCaption(t) case final Widget counts) ...<Widget>[
            const SizedBox(height: 2),
            counts,
          ],
          const SizedBox(height: DeliverySpacing.md),
          const RiderHairline(),
          const SizedBox(height: DeliverySpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _stat(
                  value: Text(
                    '${period.length}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: DeliveryColors.ink,
                      height: 1.2,
                    ),
                  ),
                  label: t.deliveries,
                ),
              ),
              Expanded(
                child: _stat(
                  value: _completionValue(t),
                  label: t.riderCompletionRate,
                ),
              ),
              Expanded(
                child: _stat(
                  value: _ratingValue(t),
                  label: t.riderRating,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// `weekly-chart-card`, derived flavour: seven days of delivery-fee totals.
  Widget _derivedWeeklyCard(DeliveryStrings t, List<DeliveryOrder> all) {
    final DateTime start = _startOfToday().subtract(const Duration(days: 6));

    final List<double> totals = List<double>.filled(7, 0);
    for (final DeliveryOrder order in all) {
      final DateTime? at = _earnedAt(order);
      if (at == null) continue;
      final int index =
          DateTime(at.year, at.month, at.day).difference(start).inDays;
      if (index >= 0 && index < 7) totals[index] += order.deliveryFee;
    }
    final double best =
        totals.fold<double>(0, (double m, double v) => v > m ? v : m);

    final List<String> narrow = MaterialLocalizations.of(context).narrowWeekdays;

    return YdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            t.riderWeeklyOverview.toUpperCase(),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
              height: 1.3,
            ),
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          SizedBox(
            height: 90 + 6 + 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (int i = 0; i < 7; i++)
                  Expanded(
                    child: _bar(
                      letter: narrow[
                          start.add(Duration(days: i)).weekday % DateTime.daysPerWeek],
                      amount: totals[i],
                      fraction: best <= 0 ? 0 : totals[i] / best,
                      isToday: i == 6,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// `txn-card`: the compact radius-12 row, one per delivered order.
  Widget _transaction(
      BuildContext context, DeliveryStrings t, DeliveryOrder order) {
    final DateTime? at = _earnedAt(order);
    final String meta = at == null
        ? t.riderOrderRef(order.shortId)
        : MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(at),
            alwaysUse24HourFormat:
                MediaQuery.of(context).alwaysUse24HourFormat);

    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
      decoration: BoxDecoration(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: DeliveryColors.brandSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shopping_bag_outlined,
                size: 16, color: DeliveryColors.brand),
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  order.storeName?.isNotEmpty == true
                      ? order.storeName!
                      : t.riderOrderRef(order.shortId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: DeliveryColors.faint,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Text(
            order.deliveryFee.toStringAsFixed(2),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// The cash-out sheet: what can be asked for, the form that asks, and where past requests got to.
///
/// Pops `true` when a request landed, so the screen behind it refetches the ledger — the header
/// tag flips to REQUESTED off the server's answer, never off local optimism.
class _CashOutSheet extends StatefulWidget {
  const _CashOutSheet({
    required this.moneyApi,
    required this.balance,
    required this.history,
  });

  final RiderMoneyApi moneyApi;
  final RiderBalance balance;

  /// Newest first — where a decided request shows PAID or REFUSED.
  final List<CashOut> history;

  @override
  State<_CashOutSheet> createState() => _CashOutSheetState();
}

class _CashOutSheetState extends State<_CashOutSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.balance.available > 0
        ? widget.balance.available.toStringAsFixed(2)
        : '',
  );
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final double? amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) return;

    setState(() => _busy = true);
    try {
      await widget.moneyApi.requestCashOut(amount);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      if (!mounted) return;
      // 409 is good news wearing an error status: a request is already on its way.
      final String message = e.response?.statusCode == 409
          ? t.riderCashOutAlreadyOpen
          : t.riderCashOutFailed;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      if (e.response?.statusCode == 409) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.riderCashOutFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final RiderBalance balance = widget.balance;
    final CashOut? open = balance.openCashOut;

    return Padding(
      // Keyboard-aware: the amount field must not disappear under the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                t.riderCashOutTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.ink,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: DeliverySpacing.md),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      t.riderCashOutAvailable,
                      style: const TextStyle(
                        fontSize: 13,
                        color: DeliveryColors.muted,
                        height: 1.3,
                      ),
                    ),
                  ),
                  Text(
                    balance.available.toStringAsFixed(2),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: DeliveryColors.ink,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DeliverySpacing.xs),
              Text(
                t.riderCashOutMinimum(
                    balance.minimumCashOut.toStringAsFixed(2)),
                style: const TextStyle(
                  fontSize: 11,
                  color: DeliveryColors.faint,
                  height: 1.4,
                ),
              ),
              // False today, and the screen must promise a manual hand-over rather than an
              // instant transfer.
              if (!balance.payoutIsAutomated) ...<Widget>[
                const SizedBox(height: DeliverySpacing.xs),
                Text(
                  t.riderCashOutManualNote,
                  style: const TextStyle(
                    fontSize: 11,
                    color: DeliveryColors.faint,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: DeliverySpacing.md),
              if (open != null)
                // One request at a time — the server answers 409 to a second, so the form does
                // not offer one.
                SoftNote(
                  icon: Icons.hourglass_top_rounded,
                  text: t.riderCashOutOpenLine(open.amount.toStringAsFixed(2)),
                )
              else ...<Widget>[
                TextField(
                  controller: _amount,
                  enabled: !_busy,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: t.riderCashOutAmountLabel,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DeliveryRadius.md),
                    ),
                  ),
                ),
                const SizedBox(height: DeliverySpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: RiderButton(
                    label: t.riderCashOutRequest,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    verticalPadding: 14,
                    busy: _busy,
                    onPressed: _busy ? null : _request,
                  ),
                ),
              ],
              if (widget.history.isNotEmpty) ...<Widget>[
                const SizedBox(height: DeliverySpacing.lg),
                Text(
                  t.riderCashOutHistory.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.faint,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: DeliverySpacing.sm),
                for (final CashOut entry in widget.history) ...<Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: DeliverySpacing.xs),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            entry.amount.toStringAsFixed(2),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: DeliveryColors.ink,
                              height: 1.3,
                            ),
                          ),
                        ),
                        RiderTag(
                          label: riderCashOutStatusLabel(t, entry.status),
                          color: switch (entry.status) {
                            CashOutStatus.paid => DeliveryAccent.positive.color,
                            CashOutStatus.rejected =>
                              DeliveryAccent.critical.color,
                            _ => DeliveryAccent.caution.color,
                          },
                          background: switch (entry.status) {
                            CashOutStatus.paid => DeliveryAccent.positive.tint,
                            CashOutStatus.rejected =>
                              DeliveryAccent.critical.tint,
                            _ => DeliveryAccent.caution.tint,
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
