import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'rider_job_card.dart';

/// What the rider has earned — Figma `rider-earnings` (3:1486).
///
/// New in the redesign, and the screen where the design and the platform disagree most. The design
/// assumes a gig rider with a personal wallet: tips, guaranteed pay, hours online, an acceptance
/// rate, a star rating and a cash-out button. None of those exist — money on this platform is
/// tracked per delivery *company*, and a rider's account carries no ledger at all.
///
/// So this screen is built to the design's layout and fills it only from facts that are already
/// true: the rider's own delivered orders, and the delivery fee on each. Every figure it shows is
/// derived from that list and labelled as derived; every figure it cannot derive is drawn in its
/// designed slot and marked inert rather than invented. A rider who is shown a number here must be
/// able to count it back out of their own deliveries.
class RiderEarningsScreen extends StatefulWidget {
  const RiderEarningsScreen({super.key, required this.api});

  final OrderApi api;

  @override
  State<RiderEarningsScreen> createState() => _RiderEarningsScreenState();
}

/// The design's two periods.
enum _Period { today, week }

class _RiderEarningsScreenState extends State<RiderEarningsScreen> {
  _Period _period = _Period.today;
  late Future<List<DeliveryOrder>> _delivered = _load();

  /// The rider's own finished work.
  ///
  /// `/api/orders/assigned` is the rider's list — the same call the board already makes — and it
  /// returns terminal orders too, which is why the board filters them out and this screen keeps
  /// exactly those. There is no rider-scoped money endpoint to call instead.
  Future<List<DeliveryOrder>> _load() async {
    final Paged<DeliveryOrder> page = await widget.api.assigned(size: 100);
    return page.content
        .where((DeliveryOrder o) => o.status == OrderStatus.delivered)
        .toList();
  }

  void _reload() => setState(() => _delivered = _load());

  /// Midnight today, which is where "Today" starts and the 7-day window ends.
  static DateTime _startOfToday() {
    final DateTime now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// When an order counts as earned: when it was delivered, falling back to when it was placed for
  /// rows old enough to predate `deliveredAt`.
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

  @override
  Widget build(BuildContext context) {
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
                onRefresh: () async => _reload(),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: <Widget>[
                    _periodSelector(t),
                    const SizedBox(height: DeliverySpacing.md),
                    _statsCard(t, period),
                    const SizedBox(height: DeliverySpacing.md),
                    _weeklyCard(t, all),
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

  /// The white 56px bar. The design's right-hand action is "Payout"; there is no wallet to pay out
  /// of and no cash-out endpoint, so it is drawn as an inert chip rather than a live link.
  Widget _header(DeliveryStrings t) {
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
          YdComingSoon(label: t.riderPayout),
        ],
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

  /// `stats-card`: the headline figure, then three stats across.
  ///
  /// Two of the design's three stats — acceptance rate and star rating — have no source anywhere in
  /// the platform. They keep their columns and wear a "coming soon" chip where the number would be.
  /// The same is true of hours online: there is no presence or shift tracking.
  Widget _statsCard(DeliveryStrings t, List<DeliveryOrder> period) {
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
                  YdComingSoon(label: t.riderComingSoon),
                ],
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.sm),
          // Says where the headline number came from, because a rider is entitled to know it is the
          // sum of their own delivery fees and not a figure the platform decided.
          Text(
            t.riderEarningsDerived,
            style: const TextStyle(
              fontSize: 11,
              color: DeliveryColors.faint,
              height: 1.4,
            ),
          ),
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
                  value: YdComingSoon(label: t.riderComingSoon),
                  label: t.riderAcceptRate,
                ),
              ),
              Expanded(
                child: _stat(
                  value: YdComingSoon(label: t.riderComingSoon),
                  label: t.riderRating,
                ),
              ),
            ],
          ),
        ],
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

  /// `weekly-chart-card`: seven days of real delivery-fee totals, today highlighted.
  ///
  /// The bars are scaled against the best day in the window rather than a fixed maximum, so a quiet
  /// week still reads as a shape instead of seven stubs. A day with nothing earned draws no bar,
  /// which is what the design does with its two future days.
  Widget _weeklyCard(DeliveryStrings t, List<DeliveryOrder> all) {
    final DateTime start =
        _startOfToday().subtract(const Duration(days: 6));

    final List<double> totals = List<double>.filled(7, 0);
    for (final DeliveryOrder order in all) {
      final DateTime? at = _earnedAt(order);
      if (at == null) continue;
      final int index =
          DateTime(at.year, at.month, at.day).difference(start).inDays;
      if (index >= 0 && index < 7) totals[index] += order.deliveryFee;
    }
    final double best = totals.fold<double>(0, (double m, double v) => v > m ? v : m);

    // Localised, and the platform already carries them for every supported locale — a hand-written
    // list of day letters would be English-only and wrong in Arabic.
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
                      // narrowWeekdays is indexed Sunday-first; DateTime.weekday is Monday..Sunday
                      // as 1..7, so Sunday (7) folds back to 0.
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
