import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'order_detail_screen.dart';

/// Shop Analytics — the settings frame's row, now a screen.
///
/// The row was drawn inert for a real reason: nothing aggregated a shop's trade beyond the flat
/// window totals the dashboard already showed. `GET /api/orders/merchant/daily` changed that. It
/// answers with the shop's own daily series, split by how fast the customer asked for the
/// delivery, complete and zero-filled, and with no percentages — every comparison on this screen
/// is arithmetic done here.
///
/// What it deliberately does not do is restate the dashboard. The dashboard says how the shop is
/// doing today and over the window; this says how the days sit against each other and what share
/// of them was Express.
///
/// One honesty note runs through the whole screen. The series' money is the **order value** — the
/// whole bill the customer paid, delivery fee and any express premium included. The shop is
/// settled on the goods, so this figure is not a payout and is never labelled as one.
class MerchantAnalyticsScreen extends StatefulWidget {
  const MerchantAnalyticsScreen({
    super.key,
    required this.api,
    this.days = 14,
    this.onBack,
  });

  final AggregatesApi api;

  /// The window to ask for. Clamped server-side to 1..30 with no error, so an out-of-range value
  /// quietly comes back shortened rather than failing — which is why every heading below reads the
  /// length off the response instead of off this field.
  final int days;

  /// Drawn as the header's back button when the host has somewhere to go back to.
  final VoidCallback? onBack;

  @override
  State<MerchantAnalyticsScreen> createState() => _MerchantAnalyticsScreenState();
}

class _MerchantAnalyticsScreenState extends State<MerchantAnalyticsScreen> {
  /// The narrowest a day's slice of the chart can be and still read as a bar with a letter under
  /// it — the same figure the dashboard's chart uses, for the same reason.
  static const double _roomForADay = 22;

  TierTradeSeries? _series;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final TierTradeSeries series = await widget.api.merchantDaily(days: widget.days);
      if (!mounted) return;
      setState(() {
        _series = series;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Surfaces the server's own explanation, the way every other merchant screen does.
  static String _serverMessage(Object error) {
    final RegExpMatch? detail =
        RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(error.toString());
    return detail?.group(1) ?? error.toString();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final TierTradeSeries? series = _series;

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: Column(
        children: <Widget>[
          YdScreenHeader(
            title: t.merchbShopAnalytics,
            subtitle: series == null ? null : t.lastDaysHeading(series.windowDays),
            onBack: widget.onBack,
            backSemanticLabel: t.back,
          ),
          Expanded(child: _body(t, series)),
        ],
      ),
    );
  }

  Widget _body(DeliveryStrings t, TierTradeSeries? series) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
    }
    final Object? error = _error;
    if (error != null) {
      return YdEmptyState(
        icon: Icons.cloud_off_rounded,
        title: t.couldNotLoadOrdersShort,
        message: _serverMessage(error),
        action: YdPillButton.secondary(
          label: t.tryAgain,
          onPressed: _load,
          size: YdPillButtonSize.compact,
          expand: false,
        ),
      );
    }
    if (series == null || series.days.isEmpty) {
      return YdEmptyState(
        icon: Icons.insights_outlined,
        title: t.quietSoFar,
        message: t.merchAnalyticsBlurb,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: DeliveryColors.brand,
      child: Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: merchantMaxContentWidth),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              DeliverySpacing.lg,
              DeliverySpacing.lg - DeliverySpacing.xs,
              DeliverySpacing.lg,
              DeliverySpacing.lg + MediaQuery.paddingOf(context).bottom,
            ),
            children: <Widget>[
              _todaySection(series, t),
              const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
              _chart(series, t),
              const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
              _tierSplit(series, t),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- today

  /// The last day of the series against the one before it.
  ///
  /// The series is ascending and zero-filled, so "the last two entries" is always today and
  /// yesterday in the shop's own zone — no date arithmetic here, and no risk of the viewer's
  /// timezone deciding which day is which.
  Widget _todaySection(TierTradeSeries series, DeliveryStrings t) {
    final TierTradeDay today = series.days.last;
    final TierTradeDay? yesterday =
        series.days.length >= 2 ? series.days[series.days.length - 2] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        YdSectionHeader(title: t.merchTodaySummary),
        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        MerchantTileGrid(tiles: <Widget>[
          MerchantMetricCard.brand(
            icon: Icons.receipt_long_outlined,
            label: t.ordersInWindow,
            value: '${today.orders}',
            trend: _dayTrend(today.orders, yesterday?.orders, t),
          ),
          MerchantMetricCard.accent(
            icon: Icons.check_circle_outline,
            label: t.deliveredInWindow,
            value: '${today.delivered}',
            accent: DeliveryAccent.positive,
            trend: _dayTrend(today.delivered, yesterday?.delivered, t),
          ),
          MerchantMetricCard.accent(
            icon: Icons.payments_outlined,
            label: t.merchOrderValue,
            value: merchantMoney(today.gross),
            accent: DeliveryAccent.info,
            footnote: t.merchOrderValueNote,
            trend: _dayTrend(today.gross, yesterday?.gross, t),
          ),
        ]),
      ],
    );
  }

  /// The arrow and the wording, read from the same pair of numbers so the two cannot disagree.
  ///
  /// Null when there is no yesterday in the window at all — a one-day series has nothing to
  /// compare against, and an arrow pointing at nothing is worse than no arrow.
  Widget? _dayTrend(num today, num? yesterday, DeliveryStrings t) {
    if (yesterday == null) return null;
    final TrendDirection direction = TrendDirection.between(today, yesterday);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(direction.icon, size: 14, color: direction.color),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            _compare(today, yesterday, t),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: direction.color,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  /// The dashboard's own wording, reused rather than reinvented: the two screens say the same
  /// thing about the same pair of days, and a second phrasing would eventually be a second
  /// meaning. The zero cases are worded rather than divided — a percentage against nothing is
  /// `Infinity` or `NaN` on a merchant's screen.
  static String _compare(num today, num yesterday, DeliveryStrings t) {
    if (today == 0 && yesterday == 0) return t.nothingYetToday;
    if (yesterday == 0) return t.noneYesterday;
    if (today == yesterday) return t.sameAsYesterday;

    final double change = ((today - yesterday) / yesterday * 100).abs();
    final int percent = change.round();
    return today > yesterday ? t.upOnYesterday(percent) : t.downOnYesterday(percent);
  }

  // ------------------------------------------------------------------- chart

  Widget _chart(TierTradeSeries series, DeliveryStrings t) {
    final List<TrendPoint> points = series.days
        .map((TierTradeDay d) => TrendPoint(
              label: _dayLabel(context, d.day),
              total: d.orders,
              completed: d.delivered,
              money: d.gross,
            ))
        .toList();

    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          YdSectionHeader(title: t.lastDaysHeading(series.windowDays)),
          const SizedBox(height: DeliverySpacing.md),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget chart = TrendChart(
                points: points,
                emptyLabel: t.quietSoFar,
                formatMoney: merchantMoney,
              );

              final double natural = points.length * _roomForADay;
              if (points.isEmpty || natural <= constraints.maxWidth) return chart;

              // Scrolls inside its own card, never by taking the page sideways with it.
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: natural, child: chart),
              );
            },
          ),
          const SizedBox(height: DeliverySpacing.sm),
          Text(
            t.barChartLegend,
            style: const TextStyle(fontSize: 11, color: DeliveryColors.faint, height: 1.35),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- tier split

  /// Standard against Express, over the whole window.
  ///
  /// The one fact on this screen the dashboard cannot show at all, and the reason the note under
  /// it is not optional: the express premium is the platform's revenue, so a bigger Express row
  /// does not mean a bigger payout.
  Widget _tierSplit(TierTradeSeries series, DeliveryStrings t) {
    final _TierTotals standard =
        _TierTotals.of(series.days.map((TierTradeDay d) => d.standard));
    final _TierTotals express =
        _TierTotals.of(series.days.map((TierTradeDay d) => d.express));

    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          YdSectionHeader(title: t.merchTierSplit),
          const SizedBox(height: DeliverySpacing.sm),
          _row(
            tier: '',
            orders: t.ordersInWindow,
            delivered: t.deliveredInWindow,
            money: t.merchOrderValue,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: DeliveryColors.muted),
          ),
          const MerchantDivider(),
          const SizedBox(height: DeliverySpacing.sm),
          _row(
            tier: t.deliveryTierStandard,
            orders: '${standard.orders}',
            delivered: '${standard.delivered}',
            money: merchantMoney(standard.gross),
          ),
          _row(
            tier: t.deliveryTierExpress,
            orders: '${express.orders}',
            delivered: '${express.delivered}',
            money: merchantMoney(express.gross),
          ),
          const SizedBox(height: DeliverySpacing.sm),
          Text(
            t.merchOrderValueNote,
            style: const TextStyle(fontSize: 11, color: DeliveryColors.faint, height: 1.35),
          ),
        ],
      ),
    );
  }

  /// One row of the four columns, shared with its own heading so the two cannot drift apart.
  Widget _row({
    required String tier,
    required String orders,
    required String delivered,
    required String money,
    TextStyle? style,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.xs + 2),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Text(tier,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style ?? const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            flex: 2,
            child: Text(orders,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style),
          ),
          Expanded(
            flex: 3,
            child: Text(delivered,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style),
          ),
          Expanded(
            flex: 4,
            child: Text(money,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style ?? const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// A weekday initial from Flutter's own localisations, so the axis is translated with the rest
  /// of the screen rather than left as English letters inside an Arabic page.
  static String _dayLabel(BuildContext context, DateTime day) {
    // narrowWeekdays is indexed from Sunday; DateTime.weekday runs Monday(1)..Sunday(7).
    return MaterialLocalizations.of(context).narrowWeekdays[day.weekday % 7];
  }
}

/// One tier across the window, added up.
class _TierTotals {
  const _TierTotals({required this.orders, required this.delivered, required this.gross});

  final int orders;
  final int delivered;
  final double gross;

  static _TierTotals of(Iterable<TierTrade> slices) {
    int orders = 0;
    int delivered = 0;
    double gross = 0;
    for (final TierTrade slice in slices) {
      orders += slice.orders;
      delivered += slice.delivered;
      gross += slice.gross;
    }
    return _TierTotals(orders: orders, delivered: delivered, gross: gross);
  }
}
