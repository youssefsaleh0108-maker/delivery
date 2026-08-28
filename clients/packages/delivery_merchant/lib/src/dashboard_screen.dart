import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'order_detail_screen.dart';

/// The shop's own page — Figma `merchant-dashboard` (3:1742): how today is going, whether the shop
/// is live, and what is waiting for them.
///
/// The portal could already answer everything about one order and nothing about the shop. A
/// merchant closing up wants to know whether it was a good day, and a merchant opening up wants to
/// know what came in overnight — neither question survives a list of orders sorted by time.
///
/// Ordered by urgency, not by importance. What needs accepting comes first because it is the only
/// thing here somebody has to *do*; the money is beside it, because a shop that reads its takings
/// while an order sits unaccepted is a shop losing the next one.
///
/// The redesign draws four things: the header with the publish switch, today's two figures, the
/// pending-orders card and a recent-orders feed. Everything the portal's dashboard already showed —
/// the fortnight chart, the window totals, the best sellers — is kept underneath in the same visual
/// language rather than dropped, because a figure a merchant used to be able to see and now cannot
/// is a regression however clean the frame it left.
class MerchantDashboardScreen extends StatefulWidget {
  const MerchantDashboardScreen({
    super.key,
    required this.api,
    this.storeApi,
    this.aggregates,
    this.pendingApproval = false,
    this.onShowOrders,
  });

  final OrderApi api;

  /// The tier-split daily series for this shop, which is what the window figures are compared
  /// against.
  ///
  /// Optional, and the window tiles simply carry no comparison without it — a dashboard that
  /// cannot fetch the previous fortnight says nothing about it rather than guessing. The series is
  /// also the only source here that can answer "compared with what?": [MerchantSummary] carries
  /// today and yesterday and then one flat total for the window, with nothing behind it.
  final AggregatesApi? aggregates;

  /// Drives the header's publish switch and supplies the shop's name.
  ///
  /// Optional because the portal mounts this screen without one and has its own "My Shop" page
  /// with the same controls; when it is null the header simply has no switch, rather than a switch
  /// that cannot do anything.
  final StoreApi? storeApi;

  /// True while the application behind this account is still being decided. The server is what
  /// refuses the committing act, but saying so up front beats letting somebody flip a switch and
  /// discover the refusal from a snackbar.
  final bool pendingApproval;

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

  /// How many orders the design's "Recent Orders" feed holds.
  static const int _recentCount = 5;

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

  /// The design's recent-orders feed. Loaded beside the summary and allowed to fail on its own:
  /// the aggregate query and the order page are two calls, and losing the feed is no reason to
  /// replace a working page of figures with an error.
  List<DeliveryOrder> _recent = <DeliveryOrder>[];
  bool _recentLoaded = false;

  Store? _store;
  bool _publishing = false;

  /// Twice the dashboard's own window, so the fortnight on screen has a fortnight behind it to be
  /// compared with. 28 is inside the server's 1..30 clamp, so nothing is quietly truncated.
  static const int _comparisonDays = 28;

  /// The two halves of [_comparisonDays], summed. Null until the series arrives, and null again if
  /// it will not — never a zero standing in for an unknown.
  _PeriodPair? _periods;

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
    await Future.wait<void>(<Future<void>>[
      _refreshSummary(silent: silent),
      _refreshRecent(),
      _refreshStore(),
      _refreshPeriods(),
    ]);
  }

  /// The fortnight-on-fortnight comparison, from the shop's own daily series.
  ///
  /// The server sends no percentages by design — the arithmetic is the client's, and it is done
  /// once here so the tiles cannot each do it slightly differently.
  Future<void> _refreshPeriods() async {
    final AggregatesApi? api = widget.aggregates;
    if (api == null) return;
    try {
      final TierTradeSeries series = await api.merchantDaily(days: _comparisonDays);
      if (!mounted) return;
      setState(() => _periods = _PeriodPair.split(series));
    } catch (_) {
      // The comparison disappears rather than the page. It is a footnote under a figure that is
      // still correct without it.
      if (!mounted) return;
      setState(() => _periods = null);
    }
  }

  Future<void> _refreshSummary({bool silent = false}) async {
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

  Future<void> _refreshRecent() async {
    try {
      final Paged<DeliveryOrder> page =
          await widget.api.forMerchant(size: _recentCount);
      if (!mounted) return;
      setState(() {
        _recent = page.content;
        _recentLoaded = true;
      });
    } catch (_) {
      // The section disappears rather than showing an apology in the middle of a dashboard. The
      // queue is one tap away and says the same thing at full length.
      if (!mounted) return;
      setState(() => _recentLoaded = false);
    }
  }

  Future<void> _refreshStore() async {
    final StoreApi? api = widget.storeApi;
    if (api == null) return;
    try {
      // One page is plenty: this header names a single shop, and a merchant with several sees the
      // first — the same shop "My Shop" edits.
      final List<Store> mine = (await api.mine(size: 1)).content;
      if (!mounted) return;
      setState(() => _store = mine.isEmpty ? null : mine.first);
    } catch (_) {
      // No switch rather than a broken switch.
    }
  }

  /// Whether the shop is on the storefront, read the same way "My Shop" reads it.
  bool get _published {
    final Store? store = _store;
    if (store == null) return false;
    return store.availability != StoreAvailability.closed || store.closesAt != null;
  }

  Future<void> _setPublished(bool value) async {
    final StoreApi? api = widget.storeApi;
    final Store? store = _store;
    if (api == null || store == null) return;

    final DeliveryStrings t = DeliveryStrings.of(context);
    setState(() => _publishing = true);
    try {
      final Store updated =
          value ? await api.publish(store.id) : await api.suspend(store.id);
      if (!mounted) return;
      setState(() => _store = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(value ? t.yourShopIsLive : t.merchShopHidden)),
      );
    } catch (e) {
      if (!mounted) return;
      // Surfaces the server's own explanation — "a store needs opening hours before it can be
      // listed" is the whole reason publish fails, and hiding it leaves the merchant guessing.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_serverMessage(e)),
        backgroundColor: DeliveryColors.brandDark,
      ));
      await _refreshStore();
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  static String _serverMessage(Object error) {
    final RegExpMatch? detail =
        RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(error.toString());
    return detail?.group(1) ?? error.toString();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: SafeArea(
        bottom: false,
        child: switch ((_summary, _error)) {
          (null, final Object? e) when e != null => _failed(t, e),
          (null, _) =>
            const Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
          (final MerchantSummary s, _) => _body(s, t),
        },
      ),
    );
  }

  Widget _failed(DeliveryStrings t, Object error) {
    return YdEmptyState(
      icon: Icons.cloud_off_rounded,
      title: t.couldNotLoadOrdersShort,
      message: _serverMessage(error),
      action: YdPillButton.secondary(
        label: t.tryAgain,
        onPressed: () => _refresh(),
        size: YdPillButtonSize.compact,
        expand: false,
      ),
    );
  }

  Widget _body(MerchantSummary s, DeliveryStrings t) {
    return RefreshIndicator(
      onRefresh: () => _refresh(),
      color: DeliveryColors.brand,
      child: Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: merchantMaxContentWidth),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: <Widget>[
              _header(t),
              _summarySection(s, t),
              _queueSection(s, t),
              _recentSection(t),
              _extras(s, t),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ header

  /// The white block the design opens with: who this is, whether they are live, and — when the
  /// application is still being decided — why the switch will not move.
  Widget _header(DeliveryStrings t) {
    return Container(
      color: DeliveryColors.white,
      padding: const EdgeInsetsDirectional.fromSTEB(
        DeliverySpacing.lg,
        DeliverySpacing.md,
        DeliverySpacing.lg,
        DeliverySpacing.lg - DeliverySpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      t.welcomeBack,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: DeliveryColors.faint,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: DeliverySpacing.xs),
                    Text(
                      // No shop, no invented name: the dashboard says what page this is instead.
                      _store?.name ?? t.navDashboard,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.ink,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              // The design's header carries only the switch. The explicit refresh is kept because
              // it is what the portal has always had, and pull-to-refresh is a gesture a mouse has
              // to discover.
              IconButton(
                onPressed: () => _refresh(),
                icon: const Icon(Icons.refresh, size: 20),
                color: DeliveryColors.muted,
                tooltip: t.refresh,
                // Material 3 sizes a bare IconButton at 40x40, which is under the 48dp a thumb
                // needs. The glyph stays the design's 20px — only the hit box grows.
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
              if (widget.storeApi != null) _publishToggle(t),
            ],
          ),
          if (widget.pendingApproval) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            _pendingBanner(t),
          ],
        ],
      ),
    );
  }

  /// The 48×26 switch the design draws, wired to the real publish/suspend calls.
  Widget _publishToggle(DeliveryStrings t) {
    final bool on = _published;
    final bool enabled = _store != null && !_publishing && !widget.pendingApproval;

    return Semantics(
      label: t.merchPublishShop,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            on ? t.merchActive : t.merchInactive,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.faint,
              height: 1.2,
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          SizedBox(
            width: 48,
            height: 26,
            child: FittedBox(
              fit: BoxFit.contain,
              child: Switch(
                value: on,
                onChanged: enabled ? _setPublished : null,
                activeThumbColor: DeliveryColors.white,
                activeTrackColor: DeliveryColors.brand,
                inactiveThumbColor: DeliveryColors.white,
                inactiveTrackColor: DeliveryColors.border,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingBanner(DeliveryStrings t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: DeliverySpacing.md,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: DeliveryAccent.caution.tint,
        border: Border.all(color: DeliveryAccent.caution.color),
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 16, color: DeliveryAccent.caution.color),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              t.pendingBannerMerchant,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: DeliveryAccent.caution.color,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- today

  Widget _summarySection(MerchantSummary s, DeliveryStrings t) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        DeliverySpacing.lg,
        DeliverySpacing.lg - DeliverySpacing.xs,
        DeliverySpacing.lg,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _sectionTitle(t.merchTodaySummary),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          MerchantTileGrid(tiles: <Widget>[
            MerchantMetricCard.brand(
              icon: Icons.receipt_long_outlined,
              label: t.ordersToday,
              value: '${s.today.orders}',
              trend: _trend(s.today.orders, s.yesterday.orders, t),
            ),
            MerchantMetricCard.accent(
              icon: Icons.payments_outlined,
              label: t.salesToday,
              value: merchantMoney(s.today.money),
              accent: DeliveryAccent.positive,
              trend: _trend(s.today.money, s.yesterday.money, t),
            ),
          ]),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          _pendingCard(s, t),
        ],
      ),
    );
  }

  /// The arrow and the words under one of today's figures.
  ///
  /// Kept as a [Row] of a [TrendDirection] glyph and the already-worded comparison so the two can
  /// never disagree: the arrow is read from the same pair of numbers the sentence is.
  ///
  /// The colour comes from [TrendDirection] too, which paints a fall in [DeliveryColors.muted] and
  /// never in red. A quiet Tuesday is not a fault, and a dashboard that shows alarm every time
  /// trade dips is one people stop reading — red stays reserved for things that need doing.
  Widget _trend(num today, num yesterday, DeliveryStrings t) {
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

  /// The comparison, worded.
  ///
  /// A percentage against zero is not a percentage, so the two cases where yesterday was nothing
  /// are worded rather than computed — "up 100%" from a standing start says less than "nothing
  /// yesterday", and dividing by it says nothing at all: it puts `Infinity` or `NaN` on a
  /// merchant's dashboard, which nothing downstream would ever have caught.
  static String _compare(num today, num yesterday, DeliveryStrings t) {
    if (today == 0 && yesterday == 0) return t.nothingYetToday;
    if (yesterday == 0) return t.noneYesterday;
    if (today == yesterday) return t.sameAsYesterday;

    final double change = ((today - yesterday) / yesterday * 100).abs();
    final int percent = change.round();
    return today > yesterday ? t.upOnYesterday(percent) : t.downOnYesterday(percent);
  }

  /// The same arrow-and-words pair as [_trend], but against the fortnight before this one.
  ///
  /// Null — no line at all — until the series has arrived, so a tile never briefly claims a
  /// comparison it has not made yet.
  Widget? _periodTrend(double Function(_PeriodTotals) read, DeliveryStrings t) {
    final _PeriodPair? periods = _periods;
    if (periods == null) return null;

    final double now = read(periods.current);
    final double before = read(periods.previous);
    final TrendDirection direction = TrendDirection.between(now, before);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(direction.icon, size: 14, color: direction.color),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            _compareToPrevious(now, before, periods.days, t),
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

  /// The period comparison, worded the same way the day comparison is.
  ///
  /// The zero cases are said rather than divided, for the reason [_compare] gives: a percentage
  /// against nothing is `Infinity` or `NaN` on a merchant's dashboard, and "up 100%" from a
  /// standing start says less than "nothing in the fortnight before".
  static String _compareToPrevious(num now, num before, int days, DeliveryStrings t) {
    if (now == 0 && before == 0) return t.merchNothingEitherPeriod;
    if (before == 0) return t.merchNonePrevious(days);
    if (now == before) return t.merchSameAsPrevious(days);

    final double change = ((now - before) / before * 100).abs();
    final int percent = change.round();
    return now > before
        ? t.merchUpOnPrevious(percent, days)
        : t.merchDownOnPrevious(percent, days);
  }

  /// "3 New Orders", with the one affordance on this screen that is a job rather than a fact.
  Widget _pendingCard(MerchantSummary s, DeliveryStrings t) {
    final bool anything = s.awaitingYou > 0;

    return YdCard.bordered(
      onTap: widget.onShowOrders,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  t.merchPendingOrders,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DeliveryColors.faint,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    Text(
                      '${s.awaitingYou}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        // Amber only while it is not zero. A permanent warning colour stops
                        // being one.
                        color: anything
                            ? DeliveryAccent.caution.color
                            : DeliveryAccent.positive.color,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(width: DeliverySpacing.xs + 2),
                    Flexible(
                      child: Text(
                        anything ? t.merchNewOrders : t.allCaughtUp,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: anything
                              ? DeliveryAccent.caution.color
                              : DeliveryAccent.positive.color,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.onShowOrders != null) ...<Widget>[
            const SizedBox(width: DeliverySpacing.sm),
            Container(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: DeliverySpacing.md - DeliverySpacing.xs,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: DeliveryAccent.caution.tint,
                borderRadius: BorderRadius.circular(DeliveryRadius.sm),
              ),
              child: Text(
                t.merchView,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DeliveryAccent.caution.color,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ queue

  /// The rest of what is open right now. Not windowed: an order placed three weeks ago that nobody
  /// accepted is exactly the thing a fortnight's window would hide.
  ///
  /// The design's own pending card covers "to accept"; these are the three states after it, which
  /// the portal has always shown and which are the difference between a shop that knows it has
  /// something on a bike and one that does not.
  Widget _queueSection(MerchantSummary s, DeliveryStrings t) {
    if (s.preparing == 0 && s.readyForPickup == 0 && s.onTheWay == 0) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        DeliverySpacing.lg,
        DeliverySpacing.lg,
        DeliverySpacing.lg,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _sectionTitle(t.needsYouNow),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          MerchantTileGrid(tiles: <Widget>[
            MerchantMetricCard.accent(
              icon: Icons.soup_kitchen_outlined,
              label: t.preparingNow,
              value: '${s.preparing}',
              accent: DeliveryAccent.caution,
              onTap: widget.onShowOrders,
            ),
            MerchantMetricCard.accent(
              icon: Icons.shopping_bag_outlined,
              label: t.readyForPickup,
              value: '${s.readyForPickup}',
              accent: DeliveryAccent.info,
              onTap: widget.onShowOrders,
            ),
            MerchantMetricCard.accent(
              icon: Icons.two_wheeler,
              label: t.outForDelivery,
              value: '${s.onTheWay}',
              accent: DeliveryAccent.info,
              onTap: widget.onShowOrders,
            ),
          ]),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- recent

  Widget _recentSection(DeliveryStrings t) {
    if (!_recentLoaded || _recent.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          YdSectionHeader(
            title: t.merchRecentOrders,
            actionLabel: widget.onShowOrders == null ? null : t.merchViewAll,
            onAction: widget.onShowOrders,
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          for (int i = 0; i < _recent.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            _recentRow(_recent[i], t),
          ],
        ],
      ),
    );
  }

  Widget _recentRow(DeliveryOrder order, DeliveryStrings t) {
    // The design's meta line names the customer. The order payload carries a customer id and no
    // name, so it says what is actually known: how many lines, and what they came to.
    final String meta = <String>[
      t.itemCount(order.items.length),
      merchantMoney(order.totalAmount),
    ].join(' • ');

    return YdCard.bordered(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => MerchantOrderDetailScreen(
          api: widget.api,
          order: order,
          onChanged: (_) => _refresh(silent: true),
        ),
      )),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '#${order.shortId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: DeliverySpacing.xs),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DeliveryColors.faint,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          MerchantStatusTag(status: order.status, label: order.status.labelIn(t)),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- extras

  /// Everything the portal's dashboard showed that the phone frame does not draw, in the frame's
  /// own card language.
  Widget _extras(MerchantSummary s, DeliveryStrings t) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        DeliverySpacing.lg,
        0,
        DeliverySpacing.lg,
        DeliverySpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _chart(s, t),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          MerchantTileGrid(tiles: <Widget>[
            MerchantMetricCard.accent(
              icon: Icons.receipt_long_outlined,
              label: t.ordersInWindow,
              value: '${s.window.orders}',
              accent: DeliveryAccent.neutral,
              footnote: t.lastDaysHeading(s.windowDays),
              trend: _periodTrend(
                (_PeriodTotals p) => p.orders.toDouble(),
                t,
              ),
            ),
            MerchantMetricCard.accent(
              icon: Icons.check_circle_outline,
              label: t.deliveredInWindow,
              value: '${s.window.delivered}',
              accent: DeliveryAccent.positive,
              trend: _periodTrend(
                (_PeriodTotals p) => p.delivered.toDouble(),
                t,
              ),
            ),
            // No period comparison on this one, deliberately. The summary's `money` is the goods a
            // shop is paid on; the series' `gross` is the whole bill the customer paid, delivery
            // and any express premium included. A percentage worked out from the second and
            // printed under the first would be a true number about the wrong figure.
            MerchantMetricCard.accent(
              icon: Icons.payments_outlined,
              label: t.salesInWindow,
              value: merchantMoney(s.window.money),
              accent: DeliveryAccent.positive,
            ),
            // Shown plainly rather than hidden. A shop that cannot see what the platform charges
            // has to reconstruct it from a settlement statement, and one that has to do that stops
            // trusting it.
            MerchantMetricCard.accent(
              icon: Icons.percent_rounded,
              label: t.feesInWindow,
              value: merchantMoney(s.platformFees),
              accent: DeliveryAccent.info,
              footnote: t.feesInWindowNote(s.commissionPercentage.toStringAsFixed(1)),
            ),
            // Only when there is something to say: a zero here is a line about a benefit they never
            // got, which reads as one being withheld.
            if (s.savedByOffers > 0)
              MerchantMetricCard.accent(
                icon: Icons.redeem_rounded,
                label: t.savedForYou,
                value: merchantMoney(s.savedByOffers),
                accent: DeliveryAccent.positive,
                footnote: t.savedForYouNote,
              ),
          ]),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          _bestSellers(s, t),
        ],
      ),
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

    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          YdSectionHeader(
            title: t.lastDaysHeading(s.windowDays),
            // Each bar carries its day's figures in a tooltip, which a mouse gets by hovering and a
            // finger is supposed to get by long-pressing. On a quiet day the bar is five pixels
            // tall, so there is nothing to press: the tooltip is a desktop affordance wearing a
            // touch gesture. This is the same numbers somewhere a thumb can land.
            actionLabel: s.days.isEmpty ? null : t.dayByDay,
            onAction: s.days.isEmpty ? null : () => _showDayByDay(s, t),
          ),
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
          Text(
            t.barChartLegend,
            style: const TextStyle(fontSize: 11, color: DeliveryColors.faint, height: 1.35),
          ),
        ],
      ),
    );
  }

  void _showDayByDay(MerchantSummary s, DeliveryStrings t) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: DeliveryColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(DeliveryRadius.sheet)),
      ),
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

  Widget _bestSellers(MerchantSummary s, DeliveryStrings t) {
    return YdCard.bordered(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // One line where the name still has room to be a name, two where it does not. Squeezing
          // the three of them onto a phone leaves about sixteen characters for the product, which
          // is where a best-seller list stops naming its best sellers.
          final bool stacked = constraints.maxWidth < _roomForASellerLine;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              YdSectionHeader(title: t.bestSellers),
              const SizedBox(height: DeliverySpacing.sm),
              if (s.topProducts.isEmpty)
                Text(
                  t.nothingSoldYet,
                  style: const TextStyle(
                      fontSize: 12, color: DeliveryColors.muted, height: 1.35),
                )
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
          child: Text(
            product.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: DeliveryColors.ink),
          ),
        ),
        const SizedBox(width: DeliverySpacing.sm),
        Text(
          t.soldQty(product.qty),
          style: const TextStyle(fontSize: 12, color: DeliveryColors.muted),
        ),
        const SizedBox(width: DeliverySpacing.md),
        SizedBox(
          width: 84,
          child: Text(
            merchantMoney(product.revenue),
            textAlign: TextAlign.end,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: DeliveryColors.ink),
          ),
        ),
      ],
    );
  }

  Widget _sellerStacked(TopProduct product, DeliveryStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          product.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: DeliveryColors.ink),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            // Both halves are flexible so that at Android's largest text setting the row shrinks
            // instead of running off the card. At the default size neither is anywhere near its
            // allowance, so the layout is unchanged.
            Flexible(
              child: Text(
                t.soldQty(product.qty),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: DeliveryColors.muted),
              ),
            ),
            const SizedBox(width: DeliverySpacing.sm),
            // No fixed column width down here: with the name on its own line the figure has the
            // whole row to sit at the end of, and an 84dp box would only reintroduce the
            // truncation this layout exists to avoid.
            Flexible(
              child: Text(
                merchantMoney(product.revenue),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: DeliveryColors.ink),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
            height: 1.25,
          ),
        ),
      );

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

/// One period of the daily series, added up.
///
/// Both tiers together: a shop is paid on the goods either way, and the express premium is the
/// platform's revenue rather than the shop's, so splitting the count here would suggest a
/// distinction the merchant's takings do not have. The split is on the analytics screen, where it
/// is labelled for what it is.
class _PeriodTotals {
  const _PeriodTotals({required this.orders, required this.delivered});

  final int orders;
  final int delivered;

  static _PeriodTotals of(Iterable<TierTradeDay> days) {
    int orders = 0;
    int delivered = 0;
    for (final TierTradeDay day in days) {
      orders += day.orders;
      delivered += day.delivered;
    }
    return _PeriodTotals(orders: orders, delivered: delivered);
  }
}

/// The window on screen and the window before it, cut out of one series.
class _PeriodPair {
  const _PeriodPair({
    required this.current,
    required this.previous,
    required this.days,
  });

  final _PeriodTotals current;
  final _PeriodTotals previous;

  /// How long each half is — the number the comparison names, rather than the 14 this screen
  /// happens to ask for. The server clamps `days`, so what came back is the only honest length.
  final int days;

  /// Splits an ascending, zero-filled series down the middle: the newer half is "now".
  ///
  /// Null when there are fewer than two days to split, which is the case where there is no
  /// previous period to compare against and therefore nothing to say.
  static _PeriodPair? split(TierTradeSeries series) {
    final List<TierTradeDay> days = series.days;
    if (days.length < 2) return null;

    // Both halves are exactly the same length. An odd-length series drops its oldest day rather
    // than comparing fourteen days with thirteen and calling the difference trade.
    final int half = days.length ~/ 2;
    return _PeriodPair(
      current: _PeriodTotals.of(days.sublist(days.length - half)),
      previous: _PeriodTotals.of(
        days.sublist(days.length - 2 * half, days.length - half),
      ),
      days: half,
    );
  }
}

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
        padding: const EdgeInsetsDirectional.fromSTEB(
            DeliverySpacing.lg, 0, DeliverySpacing.lg, DeliverySpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            YdSectionHeader(title: strings.lastDaysHeading(days.length)),
            const SizedBox(height: DeliverySpacing.sm),
            _heading(),
            const MerchantDivider(),
            const SizedBox(height: DeliverySpacing.sm),
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
                    money: merchantMoney(day.money),
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
    // Sentence case, not small caps: "DELIVERED" with letter spacing is half again as wide as its
    // own column on a phone, and a truncated column heading makes the numbers under it guesswork.
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
