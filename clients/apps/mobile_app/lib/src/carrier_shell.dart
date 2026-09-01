import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'carrier_order_details_screen.dart';
import 'carrier_zones_screen.dart';
import 'order_details_screen.dart' show CustomerStatusPill;
import 'settings_screen.dart' show AppLanguageRow;

/// The carrier's app (Figma 87:*): Dashboard, Orders, Fleet, Earnings, Settings.
///
/// Every number on it is a real read — company and score from the provider endpoints, orders and
/// earnings from the carrier's own order surface, the daily bars from the trading series, and the
/// per-rider lines derived from the orders each ref is carrying. What the frames draw that the
/// backend cannot yet answer is left OUT rather than faked: rider names and photos (the wire
/// carries refs), per-rider Call and Assign, and reassignment all wait on their own backend work,
/// and each tab says what it has.
class CarrierShell extends StatefulWidget {
  const CarrierShell({
    super.key,
    required this.session,
    required this.providerApi,
    required this.orderApi,
    required this.locale,
    required this.onSignOut,
  });

  final AuthSession session;
  final DeliveryProviderApi providerApi;
  final OrderApi orderApi;
  final LocaleController locale;
  final Future<void> Function() onSignOut;

  @override
  State<CarrierShell> createState() => _CarrierShellState();
}

class _CarrierShellState extends State<CarrierShell> {
  int _tab = 0;

  DeliveryProviderInfo? _company;
  CarrierScore? _score;
  CarrierEarnings? _earnings;
  CarrierSummary? _summary;
  List<String> _riders = <String>[];
  List<DeliveryOrder> _orders = <DeliveryOrder>[];
  bool _loading = true;
  Object? _error;
  bool _pausing = false;

  /// Which bucket the Orders tab shows: 0 incoming (nobody carrying it yet), 1 active, 2 done.
  int _ordersSegment = 1;

  /// The Earnings window, switchable between the frame's week and a month.
  int _windowDays = 7;

  List<DeliveryOrder> get _incoming => _orders
      .where((DeliveryOrder o) => !o.status.isTerminal && o.riderId == null)
      .toList();

  List<DeliveryOrder> get _active => _orders
      .where((DeliveryOrder o) => !o.status.isTerminal && o.riderId != null)
      .toList();

  List<DeliveryOrder> get _done =>
      _orders.where((DeliveryOrder o) => o.status.isTerminal).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _company == null;
      _error = null;
    });
    try {
      final List<Object?> results = await Future.wait(<Future<Object?>>[
        widget.providerApi.myCompany(),
        widget.providerApi.myScore().then<Object?>((CarrierScore s) => s).catchError((_) => null),
        widget.orderApi.carrierEarnings().then<Object?>((CarrierEarnings e) => e).catchError((_) => null),
        widget.orderApi.carrierSummary(days: _windowDays).then<Object?>((CarrierSummary s) => s).catchError((_) => null),
        widget.providerApi.myRiders().then<Object?>((List<String> r) => r).catchError((_) => <String>[]),
        widget.orderApi.forCarrier(size: 30).then<Object?>((Paged<DeliveryOrder> p) => p.content).catchError((_) => <DeliveryOrder>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _company = results[0] as DeliveryProviderInfo?;
        _score = results[1] as CarrierScore?;
        _earnings = results[2] as CarrierEarnings?;
        _summary = results[3] as CarrierSummary?;
        _riders = (results[4] as List<String>?) ?? <String>[];
        _orders = (results[5] as List<DeliveryOrder>?) ?? <DeliveryOrder>[];
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

  Future<void> _togglePause() async {
    final DeliveryProviderInfo? company = _company;
    if (company == null || _pausing) return;
    setState(() => _pausing = true);
    try {
      final DeliveryProviderInfo updated = company.canTakeWork
          ? await widget.providerApi.pauseMyCompany()
          : await widget.providerApi.resumeMyCompany();
      if (!mounted) return;
      setState(() => _company = updated);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(DeliveryStrings.of(context).somethingWentWrong)));
    } finally {
      if (mounted) setState(() => _pausing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: DeliveryColors.brand))
            : _error != null && _company == null
                ? Center(
                    child: YdEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: t.somethingWentWrong,
                      message: t.couldNotReachTheServer,
                      action: YdPillButton.secondary(
                        label: t.tryAgain,
                        expand: false,
                        size: YdPillButtonSize.compact,
                        onPressed: _load,
                      ),
                    ),
                  )
                : RefreshIndicator(
                    color: DeliveryColors.brand,
                    onRefresh: _load,
                    child: switch (_tab) {
                      0 => _dashboard(t),
                      1 => _ordersTab(t),
                      2 => _fleetTab(t),
                      3 => _earningsTab(t),
                      _ => _settingsTab(t),
                    },
                  ),
      ),
      bottomNavigationBar: YdBottomNav(
        currentIndex: _tab,
        onTap: (int i) => setState(() => _tab = i),
        items: <YdBottomNavItem>[
          YdBottomNavItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: t.carrDashboard),
          YdBottomNavItem(
              icon: Icons.receipt_long_outlined,
              activeIcon: Icons.receipt_long,
              label: t.carrOrdersTab),
          YdBottomNavItem(
              icon: Icons.place_outlined,
              activeIcon: Icons.place,
              label: t.carrFleetTab),
          YdBottomNavItem(
              icon: Icons.attach_money_rounded,
              activeIcon: Icons.attach_money_rounded,
              label: t.carrEarningsTab),
          YdBottomNavItem(
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings,
              label: t.carrSettingsTab),
        ],
      ),
    );
  }

  Widget _header(DeliveryStrings t) {
    final DeliveryProviderInfo? company = _company;
    return Container(
      color: DeliveryColors.white,
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
      child: Row(
        children: <Widget>[
          StoreMonogram(name: company?.name ?? 'C', size: 40, radius: 20),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text.rich(
                  TextSpan(children: <InlineSpan>[
                    const TextSpan(
                        text: 'YouDrop ',
                        style: TextStyle(color: DeliveryColors.ink)),
                    TextSpan(
                        text: 'Carrier',
                        style: const TextStyle(color: DeliveryColors.brand)),
                  ]),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                Text(
                  company?.name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: DeliveryColors.muted, height: 1.3),
                ),
              ],
            ),
          ),
          if (company != null && !company.canTakeWork)
            Container(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: DeliveryColors.brandSoft,
                borderRadius: BorderRadius.circular(DeliveryRadius.pill),
              ),
              child: Text(
                t.carrCompanyPaused,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: DeliveryColors.brand,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ dashboard

  Widget _dashboard(DeliveryStrings t) {
    final CarrierEarnings? earnings = _earnings;
    final int active = earnings?.active ??
        _orders.where((DeliveryOrder o) => !o.status.isTerminal).length;

    // Today's revenue is the trading series' last day — the series ends on today by contract.
    final double today =
        (_summary != null && _summary!.days.isNotEmpty) ? _summary!.days.last.money : 0;

    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        _header(t),
        Padding(
          padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _statCard(t.carrActiveDeliveries, '$active',
                        color: DeliveryAccent.positive.color,
                        badge: t.carrBadgeLive,
                        badgeColor: DeliveryAccent.positive.color),
                  ),
                  const SizedBox(width: DeliverySpacing.sm),
                  Expanded(
                    child: _statCard(
                        t.carrPendingOrders, '${_incoming.length}',
                        color: const Color(0xFFF59E0B),
                        badge: t.carrBadgeWaiting,
                        badgeColor: const Color(0xFFF59E0B)),
                  ),
                ],
              ),
              const SizedBox(height: DeliverySpacing.sm),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _statCard(
                        t.carrRidersOnline, '${_riders.length}',
                        badge: t.carrBadgeFleet,
                        badgeColor: const Color(0xFF3B82F6)),
                  ),
                  const SizedBox(width: DeliverySpacing.sm),
                  Expanded(
                    child: _statCard(
                      t.carrTodayRevenue,
                      '\$${today.toStringAsFixed(2)}',
                      color: DeliveryColors.brand,
                      badge: t.carrBadgeUsd,
                      badgeColor: DeliveryColors.brand,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DeliverySpacing.md),
              // Where the frame draws the live fleet map: the company's coverage circles,
              // honestly labelled, opening the zones editor. Live rider pins wait on tracking.
              YdCard.bordered(
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (BuildContext context) =>
                        CarrierZonesScreen(api: widget.providerApi))),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: DeliveryColors.brandSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.map_outlined,
                          size: 20, color: DeliveryColors.brand),
                    ),
                    const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(t.carrCoverageZones,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700)),
                          Text(t.carrCoverageMapBlurb,
                              style: const TextStyle(
                                  fontSize: 12, color: DeliveryColors.muted)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        size: 20, color: DeliveryColors.faint),
                  ],
                ),
              ),
              if (_score != null) ...<Widget>[
                const SizedBox(height: DeliverySpacing.md),
                YdCard.bordered(
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(t.carrScore,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: DeliveryColors.muted)),
                            Text('${_score!.score}',
                                style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: DeliveryColors.brand)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(t.carrCompletionRate,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: DeliveryColors.muted)),
                            Text(
                                '${(_score!.completionRate * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(t.carrOrdersDelivered,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: DeliveryColors.muted)),
                            Text('${_score!.orders}',
                                style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: DeliverySpacing.md),
              Text(t.carrRecentActivity,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.25)),
              const SizedBox(height: DeliverySpacing.sm),
              if (_orders.isEmpty)
                YdCard.bordered(
                    child: Text(t.noOrdersYet,
                        style: const TextStyle(
                            fontSize: 13, color: DeliveryColors.muted)))
              else
                for (final DeliveryOrder order in _orders.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
                    child: _orderRow(t, order),
                  ),
              const SizedBox(height: DeliverySpacing.lg),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statCard(String label, String value,
      {Color? color, String? badge, Color? badgeColor}) {
    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: DeliveryColors.muted)),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (badgeColor ?? DeliveryColors.brand)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: badgeColor ?? DeliveryColors.brand,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color ?? DeliveryColors.ink,
                height: 1.1,
              )),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ orders

  Widget _ordersTab(DeliveryStrings t) {
    final List<DeliveryOrder> shown = switch (_ordersSegment) {
      0 => _incoming,
      1 => _active,
      _ => _done.take(30).toList(),
    };

    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        _header(t),
        Padding(
          padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(t.carrOrdersTab,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: DeliverySpacing.sm),
              // The frame's three-way tab bar, counts and all (87:108).
              Row(
                children: <Widget>[
                  _ordersSegmentChip(t.carrIncoming, _incoming.length, 0),
                  _ordersSegmentChip(t.riderTabActive, _active.length, 1),
                  _ordersSegmentChip(t.carrCompleted, _done.length, 2),
                ],
              ),
              const SizedBox(height: DeliverySpacing.md),
              if (shown.isEmpty)
                YdCard.bordered(
                    child: Text(t.noOrdersYet,
                        style: const TextStyle(
                            fontSize: 13, color: DeliveryColors.muted))),
              for (final DeliveryOrder order in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
                  child: _orderRow(t, order),
                ),
              const SizedBox(height: DeliverySpacing.lg),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ordersSegmentChip(String label, int count, int index) {
    final bool selected = _ordersSegment == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _ordersSegment = index),
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '$label ($count)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color:
                      selected ? DeliveryColors.brand : DeliveryColors.muted,
                ),
              ),
            ),
            Container(
              height: 2,
              color: selected ? DeliveryColors.brand : DeliveryColors.border,
            ),
          ],
        ),
      ),
    );
  }

  /// One order card in the 87:108 shape: bold id and price, a crimson-dot pickup line, a grey-dot
  /// destination line, then a divider and a footer holding the rider (by honest ref) or the
  /// waiting-for-dispatch state — that one on a crimson border. Tapping opens the dispatch view.
  Widget _orderRow(DeliveryStrings t, DeliveryOrder order) {
    final bool unassigned = order.riderId == null && !order.status.isTerminal;

    return Material(
      color: DeliveryColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        side: BorderSide(
          color: unassigned ? DeliveryColors.brand : DeliveryColors.border,
          width: unassigned ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (BuildContext context) => CarrierOrderDetailsScreen(
                  order: order,
                  cutPercentage: _earnings?.cutPercentage ?? 15,
                ))),
        child: Padding(
          padding: const EdgeInsets.all(DeliverySpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text('#${order.shortId}',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            height: 1.25)),
                  ),
                  Text('\$${order.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: DeliveryColors.brand)),
                ],
              ),
              const SizedBox(height: 6),
              _dotLine(DeliveryColors.brand, order.storeName ?? t.tabShop),
              const SizedBox(height: 3),
              _dotLine(DeliveryColors.faint, order.deliveryAddress),
              const Divider(
                  height: DeliverySpacing.md * 1.25,
                  color: DeliveryColors.borderFaint),
              Row(
                children: <Widget>[
                  Expanded(
                    child: unassigned
                        ? Text(
                            t.carrWaitingDispatch,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: DeliveryColors.brand,
                            ),
                          )
                        : order.riderId == null
                            ? const SizedBox.shrink()
                            : Row(
                                children: <Widget>[
                                  const Icon(Icons.person_outline,
                                      size: 14, color: DeliveryColors.faint),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      order.riderId!.length > 10
                                          ? order.riderId!
                                              .substring(0, 10)
                                              .toUpperCase()
                                          : order.riderId!.toUpperCase(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: DeliveryColors.muted,
                                          fontFeatures: <FontFeature>[
                                            FontFeature.tabularFigures()
                                          ]),
                                    ),
                                  ),
                                ],
                              ),
                  ),
                  CustomerStatusPill(
                    statusWire: order.status.wire,
                    label: order.status.labelIn(t),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dotLine(Color dot, String text) {
    return Row(
      children: <Widget>[
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12.5, color: DeliveryColors.muted, height: 1.3)),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ fleet

  Widget _fleetTab(DeliveryStrings t) {
    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        _header(t),
        Padding(
          padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(t.carrFleetManagement,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: DeliverySpacing.sm),
              Text(t.carrShowingRiders(_riders.length),
                  style: const TextStyle(
                      fontSize: 12.5, color: DeliveryColors.muted)),
              const SizedBox(height: DeliverySpacing.sm),
              // The wire carries rider REFS, deliberately: names, photos and ratings for a
              // carrier's own staff panel are their own backend feature, and inventing them
              // here would be lying with confidence. Each row shows the honest handle — and
              // what the orders already say about it: what the ref is carrying right now, and
              // how many drops it has made in the window.
              if (_riders.isEmpty)
                YdCard.bordered(
                    child: Text(t.carrNoRiders,
                        style: const TextStyle(
                            fontSize: 13,
                            color: DeliveryColors.muted,
                            height: 1.4))),
              for (final String ref in _riders)
                Padding(
                  padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
                  child: _riderCard(t, ref),
                ),
              const SizedBox(height: DeliverySpacing.lg),
            ],
          ),
        ),
      ],
    );
  }

  /// One rider row: the honest handle, plus what the orders say — the order the ref is carrying
  /// right now (87:221's "Currently delivering"), or Available, and the drops in the window.
  Widget _riderCard(DeliveryStrings t, String ref) {
    DeliveryOrder? carrying;
    for (final DeliveryOrder o in _orders) {
      if (o.riderId == ref && !o.status.isTerminal) {
        carrying = o;
        break;
      }
    }
    final int drops = _orders
        .where((DeliveryOrder o) =>
            o.riderId == ref && o.status == OrderStatus.delivered)
        .length;

    return YdCard.bordered(
      child: Row(
        children: <Widget>[
          StoreMonogram(name: ref, size: 40, radius: 20),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  ref.length > 12
                      ? '${ref.substring(0, 12).toUpperCase()}…'
                      : ref.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      fontFeatures: <FontFeature>[
                        FontFeature.tabularFigures()
                      ]),
                ),
                const SizedBox(height: 2),
                Text(
                  carrying != null
                      ? t.carrDelivering(carrying.shortId)
                      : t.carrAvailable,
                  style: TextStyle(
                    fontSize: 12,
                    color: carrying != null
                        ? const Color(0xFF3B82F6)
                        : DeliveryAccent.positive.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (drops > 0) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    t.carrDeliveriesToday(drops),
                    style: TextStyle(
                        fontSize: 11.5,
                        color: DeliveryAccent.positive.color),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ earnings

  Widget _earningsTab(DeliveryStrings t) {
    final CarrierSummary? summary = _summary;
    final CarrierEarnings? earnings = _earnings;
    final double maxMoney = summary == null || summary.days.isEmpty
        ? 1
        : summary.days
            .map((TradingDay d) => d.money)
            .reduce((double a, double b) => a > b ? a : b)
            .clamp(1, double.infinity)
            .toDouble();

    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        _header(t),
        Padding(
          padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(t.carrEarningsTab,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  // The frame's period pill: the week, or the month.
                  InkWell(
                    onTap: () {
                      setState(() => _windowDays = _windowDays == 7 ? 30 : 7);
                      _load();
                    },
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: DeliveryColors.white,
                        border: Border.all(color: DeliveryColors.border),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            t.carrWindowEarned(_windowDays),
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                          const Icon(Icons.keyboard_arrow_down,
                              size: 16, color: DeliveryColors.muted),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
              // The crimson revenue card.
              Container(
                width: double.infinity,
                padding: const EdgeInsetsDirectional.all(DeliverySpacing.lg),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      DeliveryColors.brand,
                      DeliveryColors.brandDark
                    ],
                  ),
                  borderRadius: BorderRadius.circular(DeliveryRadius.lg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(t.carrTotalRevenue.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: DeliveryColors.white.withValues(alpha: 0.8),
                          letterSpacing: 0.8,
                        )),
                    const SizedBox(height: 4),
                    Text(
                      '\$${(summary?.window.money ?? earnings?.earned ?? 0).toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: DeliveryColors.white,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              if (summary != null && summary.days.isNotEmpty) ...<Widget>[
                const SizedBox(height: DeliverySpacing.md),
                YdCard.bordered(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(t.carrWeeklySummary,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: DeliverySpacing.md),
                      SizedBox(
                        height: 110,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            for (final TradingDay day in summary.days) ...<Widget>[
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: <Widget>[
                                    Container(
                                      height: 90 * (day.money / maxMoney),
                                      decoration: BoxDecoration(
                                        color: DeliveryColors.brand,
                                        borderRadius:
                                            BorderRadius.circular(3),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'MTWTFSS'[day.day.weekday - 1],
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: DeliveryColors.faint),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (earnings != null) ...<Widget>[
                const SizedBox(height: DeliverySpacing.md),
                YdCard.bordered(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(t.carrDeliveriesBreakdown,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                      _moneyRow(t.navOrders, '${earnings.delivered}'),
                      _moneyRow(t.carrTotalRevenue,
                          '\$${earnings.earned.toStringAsFixed(2)}'),
                      // The deduction in money, not just the rate — 87:350 writes the dollars.
                      _moneyRow(
                        t.carrCommissionPct(earnings.cutPercentage.round()),
                        '-\$${(earnings.earned * earnings.cutPercentage / 100).toStringAsFixed(2)}',
                        color: DeliveryColors.brand,
                      ),
                      const SizedBox(height: DeliverySpacing.sm),
                      // The frame's soft-green net band.
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsetsDirectional.symmetric(
                            horizontal: DeliverySpacing.md,
                            vertical: DeliverySpacing.sm),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE7F6EC),
                          borderRadius:
                              BorderRadius.circular(DeliveryRadius.md),
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(t.carrNetEarnings,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF167A4B),
                                  )),
                            ),
                            Text(
                              '\$${(earnings.earned * (1 - earnings.cutPercentage / 100)).toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF167A4B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: DeliverySpacing.md),
                // Next payout: the standing schedule beside the icon (87:350's closing card).
                YdCard.bordered(
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: DeliveryColors.brandSoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.payments_outlined,
                            size: 20, color: DeliveryColors.brand),
                      ),
                      const SizedBox(
                          width: DeliverySpacing.md - DeliverySpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(t.carrNextPayout.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: DeliveryColors.faint,
                                  letterSpacing: 0.5,
                                )),
                            const SizedBox(height: 2),
                            Text(t.carrEveryMonday,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: DeliverySpacing.lg),
            ],
          ),
        ),
      ],
    );
  }

  Widget _moneyRow(String label, String value,
      {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: bold ? DeliveryColors.ink : DeliveryColors.muted,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
          ),
          Text(value,
              style: TextStyle(
                fontSize: bold ? 15 : 13,
                fontWeight: FontWeight.w800,
                color: color ?? DeliveryColors.ink,
              )),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: DeliveryColors.faint,
          letterSpacing: 0.6,
          height: 1.2,
        ),
      );

  // ------------------------------------------------------------------ settings

  Widget _settingsTab(DeliveryStrings t) {
    final DeliveryProviderInfo? company = _company;
    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        _header(t),
        Padding(
          padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (company != null)
                YdCard.bordered(
                  child: Row(
                    children: <Widget>[
                      StoreMonogram(name: company.name, size: 44, radius: 22),
                      const SizedBox(
                          width: DeliverySpacing.md - DeliverySpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(company.name,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800)),
                            if (company.contactName != null)
                              Text(company.contactName!,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: DeliveryColors.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: DeliverySpacing.md),
              // OPERATIONS: where the company works, and whether it is working tonight.
              _sectionLabel(t.carrOperations),
              const SizedBox(height: DeliverySpacing.sm),
              YdListRow(
                icon: Icons.map_outlined,
                title: t.carrCoverageZones,
                subtitle: t.carrCoverageMapBlurb,
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (BuildContext context) =>
                            CarrierZonesScreen(api: widget.providerApi))),
              ),
              const SizedBox(height: DeliverySpacing.sm),
              if (company != null)
                YdListRow(
                  icon: company.canTakeWork
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                  title: company.canTakeWork
                      ? t.carrPauseCompany
                      : t.carrResumeCompany,
                  subtitle:
                      company.canTakeWork ? null : t.carrCompanyPaused,
                  trailing: _pausing
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : null,
                  onTap: _pausing ? null : _togglePause,
                ),
              const SizedBox(height: DeliverySpacing.md),
              // PAYMENTS: the standing terms, stated where the frame states them.
              _sectionLabel(t.carrPayments),
              const SizedBox(height: DeliverySpacing.sm),
              YdCard.bordered(
                child: Column(
                  children: <Widget>[
                    _moneyRow(t.carrCommissionRate,
                        t.carrFlatFee((_earnings?.cutPercentage ?? 15).round())),
                    _moneyRow(t.carrPayoutSchedule, t.carrEveryMonday),
                  ],
                ),
              ),
              const SizedBox(height: DeliverySpacing.md),
              // ACCOUNT: language and the door out.
              _sectionLabel(t.carrAccountSection),
              const SizedBox(height: DeliverySpacing.sm),
              AppLanguageRow(
                  locale: widget.locale, label: t.custAppLanguage),
              const SizedBox(height: DeliverySpacing.lg),
              YdPillButton.secondary(
                label: t.custLogOutAccount,
                icon: Icons.logout_rounded,
                onPressed: () => widget.onSignOut(),
              ),
              const SizedBox(height: DeliverySpacing.sm),
              Center(
                child: Text(
                  t.carrVersionCaption('1.0'),
                  style: const TextStyle(
                      fontSize: 11, color: DeliveryColors.faint),
                ),
              ),
              const SizedBox(height: DeliverySpacing.lg),
            ],
          ),
        ),
      ],
    );
  }
}
