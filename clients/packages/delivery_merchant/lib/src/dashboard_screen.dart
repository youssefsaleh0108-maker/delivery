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
///
/// Laid out for a phone as well as for a browser window, because since merchants started applying
/// from the handset the phone is the only device some of them have. Every reflow below is one
/// widget measuring the room it was given, not a phone build and a desktop build — two layouts of
/// the same dashboard would disagree about a number within a release.
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

  /// Where the page's own gutter stops being generous and starts being expensive.
  ///
  /// The desktop gutter takes 48dp off a 360dp screen — an eighth of the width of every figure on
  /// the page — to leave whitespace beside a card that is already floating on a tinted background.
  static const double _roomForAGenerousGutter = 480;

  /// What one [TrendHeadline] needs before the sentence under the number starts disappearing.
  ///
  /// The comparison is the entire reason that card is not just a number: "50% up on yesterday"
  /// wants about 140dp of text plus the card's own padding, and below that it truncates to
  /// "50% up on…", which is a fact turned back into a figure.
  static const double _roomForAHeadline = 200;

  /// The narrowest a day's slice of the chart can be and still read as a bar with a letter under it.
  ///
  /// A fortnight shares the width evenly, so this is what decides whether the chart fits the card
  /// or scrolls inside it. Deliberately low: 14 days fit a 360dp phone at this width, and a chart
  /// you have to drag to see the shape of has stopped being a chart you read at a glance.
  static const double _roomForADay = 22;

  /// What a best-seller line needs to stay one line: a name worth reading, plus its two figures.
  static const double _roomForASellerLine = 320;

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
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double gutter = constraints.maxWidth < _roomForAGenerousGutter
              ? DeliverySpacing.md
              : DeliverySpacing.lg;

          return ListView(
            padding: EdgeInsets.symmetric(
                horizontal: gutter, vertical: DeliverySpacing.lg),
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
          );
        },
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
    final Widget orders = TrendHeadline(
      value: '${s.today.orders}',
      label: t.ordersToday,
      icon: Icons.receipt_long_outlined,
      direction: TrendDirection.between(s.today.orders, s.yesterday.orders),
      comparison: _compare(s.today.orders, s.yesterday.orders, t),
    );
    final Widget money = TrendHeadline(
      value: _money(s.today.money),
      label: t.salesToday,
      icon: Icons.payments_outlined,
      direction: TrendDirection.between(s.today.money, s.yesterday.money),
      comparison: _compare(s.today.money, s.yesterday.money, t),
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < _roomForAHeadline * 2 + DeliverySpacing.sm) {
          // Stacked rather than squeezed. Halving a phone's width gives each card about 150dp of
          // text, which loses the comparison line first and the number second.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              orders,
              const SizedBox(height: DeliverySpacing.sm),
              money,
            ],
          );
        }

        // IntrinsicHeight, not CrossAxisAlignment.stretch alone. Inside a ListView the row's height
        // is unbounded, and stretch against an unbounded constraint is an infinite height — which
        // is not a cosmetic problem but a crash on first paint. This measures the taller card and
        // matches it.
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: orders),
              const SizedBox(width: DeliverySpacing.sm),
              Expanded(child: money),
            ],
          ),
        );
      },
    );
  }

  Widget _chart(MerchantSummary s, DeliveryStrings t) {
    final List<TrendPoint> points = s.days
        .map((TradingDay d) => TrendPoint(
              label: _dayLabel(context, d.day),
              total: d.orders,
              completed: d.delivered,
              money: d.money,
            ))
        .toList();

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionLabel(
            t.lastDaysHeading(s.windowDays),
            // Each bar carries its day's figures in a tooltip, which a mouse gets by hovering and a
            // finger is supposed to get by long-pressing. On a quiet day the bar is five pixels
            // tall, so there is nothing to press: the tooltip is a desktop affordance wearing a
            // touch gesture. This is the same numbers somewhere a thumb can land.
            //
            // Shown on the desktop too rather than only on a phone. One affordance both hosts have
            // is one affordance that stays working; a narrow-only button is a control the people
            // who maintain this screen never see.
            trailing: s.days.isEmpty ? null : _dayByDayButton(s, t),
          ),
          const SizedBox(height: DeliverySpacing.md),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget chart = TrendChart(
                points: points,
                emptyLabel: t.quietSoFar,
                formatMoney: _money,
              );

              final double natural = points.length * _roomForADay;
              if (points.isEmpty || natural <= constraints.maxWidth) return chart;

              // Scrolls inside its own card, never by taking the page sideways with it. A
              // dashboard that pans horizontally hides the tiles either side of whatever the
              // finger caught.
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: natural, child: chart),
              );
            },
          ),
          const SizedBox(height: DeliverySpacing.sm),
          Text(t.barChartLegend, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _dayByDayButton(MerchantSummary s, DeliveryStrings t) {
    return TextButton.icon(
      onPressed: () => _showDayByDay(s, t),
      icon: const Icon(Icons.calendar_view_day_outlined, size: 16),
      label: Text(t.dayByDay),
      style: TextButton.styleFrom(
        foregroundColor: DeliveryColors.brand,
        // Held at 48 whatever the text metrics work out to. This is the tap target standing in for
        // a chart whose own bars are under 20dp wide on a phone.
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.sm),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  void _showDayByDay(MerchantSummary s, DeliveryStrings t) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: DeliveryColors.white,
      // isScrollControlled lets a fortnight of rows grow the sheet to the full height of the
      // window, and at full height the drag handle sits behind the status bar on a phone — the
      // one part of this the finger needs to reach.
      useSafeArea: true,
      // A sheet rather than a dialog: most of the people reading this are holding a phone, and a
      // dialog sized for a browser is the control that turns into a letterbox on one. Capped so
      // the portal does not stretch four short columns across a 1400px window, where the eye has
      // to travel further to read a row than the row is worth.
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (BuildContext context) => _DayByDaySheet(days: s.days, strings: t),
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
        value: _money(s.window.money),
        label: t.salesInWindow,
        icon: Icons.payments_outlined,
        accent: DeliveryAccent.positive,
      ),
      // Shown plainly rather than hidden. A shop that cannot see what the platform charges has to
      // reconstruct it from a settlement statement, and one that has to do that stops trusting it.
      StatTile(
        value: _money(s.platformFees),
        label: t.feesInWindow,
        icon: Icons.percent_rounded,
        accent: DeliveryAccent.info,
        footnote: t.feesInWindowNote(s.commissionPercentage.toStringAsFixed(1)),
      ),
      // Only when there is something to say: a zero here is a line about a benefit they never got,
      // which reads as one being withheld.
      if (s.savedByOffers > 0)
        StatTile(
          value: _money(s.savedByOffers),
          label: t.savedForYou,
          icon: Icons.redeem_rounded,
          accent: DeliveryAccent.positive,
          footnote: t.savedForYouNote,
        ),
    ]);
  }

  Widget _bestSellers(MerchantSummary s, DeliveryStrings t) {
    return SoftCard(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // One line where the name still has room to be a name, two where it does not. Squeezing
          // the three of them onto a phone leaves about sixteen characters for the product, which
          // is where a best-seller list stops naming its best sellers.
          final bool stacked = constraints.maxWidth < _roomForASellerLine;

          return Column(
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
                    child: stacked
                        ? _sellerStacked(product, t)
                        : _sellerInline(product, t),
                  ),
            ],
          );
        },
      ),
    );
  }

  Widget _sellerInline(TopProduct product, DeliveryStrings t) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: DeliverySpacing.sm),
        Text(t.soldQty(product.qty), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(width: DeliverySpacing.md),
        SizedBox(
          width: 84,
          child: Text(_money(product.revenue),
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Widget _sellerStacked(TopProduct product, DeliveryStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        Row(
          children: <Widget>[
            Text(t.soldQty(product.qty), style: Theme.of(context).textTheme.bodySmall),
            const Spacer(),
            // No fixed column width down here: with the name on its own line the figure has the
            // whole row to sit at the end of, and a 84dp box would only reintroduce the truncation
            // this layout exists to avoid.
            Text(_money(product.revenue),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ],
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
  /// fortnight of bars is looking for the weekly shape, and the exact date is in the sheet behind
  /// "day by day".
  ///
  /// Taken from Flutter's own localisations rather than a list of letters in this file. Both these
  /// portals run in Arabic, and a hard-coded 'M T W T F S S' would sit unreadably in an otherwise
  /// translated screen — the same trap the shared display enums fell into.
  static String _dayLabel(BuildContext context, DateTime day) {
    // narrowWeekdays is indexed from Sunday; DateTime.weekday runs Monday(1)..Sunday(7).
    return MaterialLocalizations.of(context).narrowWeekdays[day.weekday % 7];
  }
}

/// Two decimal places, in one place.
///
/// Not a currency format: the amounts arrive already in the store's own currency and the symbol
/// belongs to the store, not to this screen.
String _money(double amount) => amount.toStringAsFixed(2);

/// The chart's figures as rows, for whoever cannot hover over a bar.
///
/// Everything here is already on the chart. It exists because the chart says it in a shape and in
/// a tooltip, and on a phone the tooltip's target is a bar a few pixels tall — so on the device
/// most merchants now use, the numbers behind the shape had no way in at all.
class _DayByDaySheet extends StatelessWidget {
  const _DayByDaySheet({required this.days, required this.strings});

  final List<TradingDay> days;
  final DeliveryStrings strings;

  @override
  Widget build(BuildContext context) {
    final MaterialLocalizations dates = MaterialLocalizations.of(context);
    // Most recent first, against the chart's own left-to-right order. Today is the row somebody
    // opened this to see, and read chronologically it is the one off the bottom of a phone.
    final List<TradingDay> newestFirst = days.reversed.toList();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            DeliverySpacing.lg, 0, DeliverySpacing.lg, DeliverySpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionLabel(strings.lastDaysHeading(days.length)),
            _heading(),
            const Divider(height: DeliverySpacing.md, color: DeliveryColors.border),
            // Flexible, so a fortnight scrolls and a slow week does not leave the sheet standing
            // half-empty at full height.
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: newestFirst.length,
                itemBuilder: (BuildContext context, int index) {
                  final TradingDay day = newestFirst[index];
                  return _line(
                    date: dates.formatMediumDate(day.day),
                    orders: '${day.orders}',
                    delivered: '${day.delivered}',
                    money: _money(day.money),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading() {
    // Sentence case, not the small-caps this screen uses for section labels: "DELIVERED" with
    // letter spacing is half again as wide as its own column on a phone, and a truncated column
    // heading makes the numbers under it guesswork.
    const TextStyle style = TextStyle(
        fontSize: 11, fontWeight: FontWeight.w700, color: DeliveryColors.muted);

    return _line(
      date: '',
      orders: strings.ordersInWindow,
      delivered: strings.deliveredInWindow,
      money: strings.salesInWindow,
      style: style,
    );
  }

  /// One row of the four columns, shared by the headings so the two can never drift apart.
  Widget _line({
    required String date,
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
            flex: 5,
            child: Text(date,
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
}
