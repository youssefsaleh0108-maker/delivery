import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// The shop's own page: how today is going, and what is waiting for them.
///
/// The portal could already answer everything about one order and nothing about the shop. A
/// merchant closing up wants to know whether it was a good day, and a merchant opening up wants to
/// know what came in overnight — neither question survives a list of orders sorted by time.
///
/// Ordered by urgency, not by importance. What needs accepting comes first because it is the only
/// thing here somebody has to *do*; the money is underneath it, because a shop that reads its
/// takings while an order sits unaccepted is a shop losing the next one.
class MerchantDashboardScreen extends StatefulWidget {
  const MerchantDashboardScreen({super.key, required this.api, this.onShowOrders});

  final OrderApi api;

  /// Tapping the queue goes to the orders list. Numbers you cannot act on are decoration.
  final VoidCallback? onShowOrders;

  @override
  State<MerchantDashboardScreen> createState() => _MerchantDashboardScreenState();
}

class _MerchantDashboardScreenState extends State<MerchantDashboardScreen> {
  /// Slower than the orders screen's poll. Nobody watches a fortnight of trade change in real time,
  /// and this query does real aggregation — refreshing it every ten seconds would cost the database
  /// far more than the freshness is worth.
  static const Duration _pollInterval = Duration(seconds: 60);

  Timer? _poll;
  MerchantSummary? _summary;
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
      final MerchantSummary summary = await widget.api.merchantSummary();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      // A failed background poll leaves the last good numbers on screen rather than replacing a
      // working page with an error. They are a minute old, which is what they were anyway.
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
        (null, final Object? e) when e != null => Center(child: Text('$e')),
        (null, _) => const Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
        (final MerchantSummary s, _) => _body(s, t),
      },
    );
  }

  Widget _body(MerchantSummary s, DeliveryStrings t) {
    return RefreshIndicator(
      onRefresh: () => _refresh(),
      color: DeliveryColors.brand,
      child: ListView(
        padding: const EdgeInsets.all(DeliverySpacing.lg),
        children: <Widget>[
          _queue(s, t),
          const SizedBox(height: DeliverySpacing.lg),
          _today(s, t),
          const SizedBox(height: DeliverySpacing.lg),
          _chart(s, t),
          const SizedBox(height: DeliverySpacing.lg),
          _window(s, t),
          const SizedBox(height: DeliverySpacing.lg),
          _bestSellers(s, t),
        ],
      ),
    );
  }

  /// What is open right now. Not windowed: an order placed three weeks ago that nobody accepted is
  /// exactly the thing a fortnight's window would hide.
  Widget _queue(MerchantSummary s, DeliveryStrings t) {
    if (s.awaitingYou == 0 && s.preparing == 0 && s.readyForPickup == 0 && s.onTheWay == 0) {
      return SoftNote(text: t.allCaughtUp, accent: DeliveryAccent.positive, icon: Icons.check_circle_outline);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionLabel(t.needsYouNow),
        const SizedBox(height: DeliverySpacing.sm),
        StatRow(tiles: <Widget>[
          StatTile(
            value: '${s.awaitingYou}',
            label: t.toAccept,
            icon: Icons.notifications_active_outlined,
            // The only tile on this screen that turns amber, and only when it is not zero. A
            // permanent warning colour stops being one.
            accent: s.awaitingYou == 0 ? DeliveryAccent.positive : DeliveryAccent.caution,
            onTap: widget.onShowOrders,
          ),
          StatTile(
            value: '${s.preparing}',
            label: t.preparingNow,
            icon: Icons.soup_kitchen_outlined,
            accent: DeliveryAccent.neutral,
            onTap: widget.onShowOrders,
          ),
          StatTile(
            value: '${s.readyForPickup}',
            label: t.readyForPickup,
            icon: Icons.shopping_bag_outlined,
            accent: DeliveryAccent.info,
            onTap: widget.onShowOrders,
          ),
          StatTile(
            value: '${s.onTheWay}',
            label: t.outForDelivery,
            icon: Icons.pedal_bike_rounded,
            accent: DeliveryAccent.neutral,
            onTap: widget.onShowOrders,
          ),
        ]),
      ],
    );
  }

  Widget _today(MerchantSummary s, DeliveryStrings t) {
    // IntrinsicHeight, not CrossAxisAlignment.stretch. Inside a ListView the row's height is
    // unbounded, and stretch against an unbounded constraint is an infinite height — which is not a
    // cosmetic problem but a crash on first paint. This measures the taller card and matches it.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: TrendHeadline(
              value: '${s.today.orders}',
              label: t.ordersToday,
              icon: Icons.receipt_long_outlined,
              direction: TrendDirection.between(s.today.orders, s.yesterday.orders),
              comparison: _compare(s.today.orders, s.yesterday.orders, t),
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: TrendHeadline(
              value: s.today.money.toStringAsFixed(2),
              label: t.salesToday,
              icon: Icons.payments_outlined,
              direction: TrendDirection.between(s.today.money, s.yesterday.money),
              comparison: _compare(s.today.money, s.yesterday.money, t),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chart(MerchantSummary s, DeliveryStrings t) {
    return SoftCard(
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
            emptyLabel: t.quietSoFar,
            formatMoney: (double m) => m.toStringAsFixed(2),
          ),
          const SizedBox(height: DeliverySpacing.sm),
          Text(t.barChartLegend, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _window(MerchantSummary s, DeliveryStrings t) {
    return StatRow(tiles: <Widget>[
      StatTile(
        value: '${s.window.orders}',
        label: t.ordersInWindow,
        icon: Icons.receipt_long_outlined,
        accent: DeliveryAccent.neutral,
        footnote: t.lastDaysHeading(s.windowDays),
      ),
      StatTile(
        value: '${s.window.delivered}',
        label: t.deliveredInWindow,
        icon: Icons.check_circle_outline,
        accent: DeliveryAccent.positive,
      ),
      StatTile(
        value: s.window.money.toStringAsFixed(2),
        label: t.salesInWindow,
        icon: Icons.payments_outlined,
        accent: DeliveryAccent.positive,
      ),
      // Shown plainly rather than hidden. A shop that cannot see what the platform charges has to
      // reconstruct it from a settlement statement, and one that has to do that stops trusting it.
      StatTile(
        value: s.platformFees.toStringAsFixed(2),
        label: t.feesInWindow,
        icon: Icons.percent_rounded,
        accent: DeliveryAccent.info,
        footnote: t.feesInWindowNote(s.commissionPercentage.toStringAsFixed(1)),
      ),
      // Only when there is something to say: a zero here is a line about a benefit they never got,
      // which reads as one being withheld.
      if (s.savedByOffers > 0)
        StatTile(
          value: s.savedByOffers.toStringAsFixed(2),
          label: t.savedForYou,
          icon: Icons.redeem_rounded,
          accent: DeliveryAccent.positive,
          footnote: t.savedForYouNote,
        ),
    ]);
  }

  Widget _bestSellers(MerchantSummary s, DeliveryStrings t) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionLabel(t.bestSellers),
          const SizedBox(height: DeliverySpacing.sm),
          if (s.topProducts.isEmpty)
            Text(t.nothingSoldYet, style: Theme.of(context).textTheme.bodySmall)
          else
            for (final TopProduct product in s.topProducts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.xs),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: DeliverySpacing.sm),
                    Text(t.soldQty(product.qty),
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(width: DeliverySpacing.md),
                    SizedBox(
                      width: 84,
                      child: Text(product.revenue.toStringAsFixed(2),
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  /// The comparison, worded.
  ///
  /// A percentage against zero is not a percentage, so the two cases where yesterday was nothing
  /// are worded rather than computed — "up 100%" from a standing start says less than "nothing
  /// yesterday", and dividing by it says nothing at all.
  String _compare(num today, num yesterday, DeliveryStrings t) {
    if (today == 0 && yesterday == 0) return t.nothingYetToday;
    if (yesterday == 0) return t.noneYesterday;
    if (today == yesterday) return t.sameAsYesterday;

    final double change = ((today - yesterday) / yesterday * 100).abs();
    final int percent = change.round();
    return today > yesterday ? t.upOnYesterday(percent) : t.downOnYesterday(percent);
  }

  /// A weekday initial, which is all the axis has room for and all it needs: somebody reading a
  /// fortnight of bars is looking for the weekly shape, and the exact date is in the tooltip.
  ///
  /// Taken from Flutter's own localisations rather than a list of letters in this file. Both these
  /// portals run in Arabic, and a hard-coded 'M T W T F S S' would sit unreadably in an otherwise
  /// translated screen — the same trap the shared display enums fell into.
  static String _dayLabel(BuildContext context, DateTime day) {
    // narrowWeekdays is indexed from Sunday; DateTime.weekday runs Monday(1)..Sunday(7).
    return MaterialLocalizations.of(context).narrowWeekdays[day.weekday % 7];
  }
}
