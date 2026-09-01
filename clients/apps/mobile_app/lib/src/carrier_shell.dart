import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'order_details_screen.dart' show CustomerStatusPill;
import 'settings_screen.dart' show AppLanguageRow;

/// The carrier's app (Figma 87:*): Dashboard, Orders, Fleet, Earnings, Settings.
///
/// Every number on it is a real read — company and score from the provider endpoints, orders and
/// earnings from the carrier's own order surface, the daily bars from the trading series. What
/// the frames draw that the backend cannot yet answer is left OUT rather than faked: rider
/// identities on the fleet tab (the wire carries refs, not names), reassignment, and the live
/// fleet map all wait on their own backend work, and the tab says what it has.
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
        widget.orderApi.carrierSummary(days: 7).then<Object?>((CarrierSummary s) => s).catchError((_) => null),
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
                        color: DeliveryAccent.positive.color),
                  ),
                  const SizedBox(width: DeliverySpacing.sm),
                  Expanded(
                    child: _statCard(
                        t.carrRidersOnline, '${_riders.length}',
                        color: DeliveryColors.brand),
                  ),
                ],
              ),
              const SizedBox(height: DeliverySpacing.sm),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _statCard(
                        t.navOrders, '${earnings?.delivered ?? 0}'),
                  ),
                  const SizedBox(width: DeliverySpacing.sm),
                  Expanded(
                    child: _statCard(
                      t.carrWindowEarned(earnings?.windowDays ?? 7),
                      '\$${(earnings?.earned ?? 0).toStringAsFixed(2)}',
                      color: DeliveryColors.brand,
                    ),
                  ),
                ],
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

  Widget _statCard(String label, String value, {Color? color}) {
    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 12, color: DeliveryColors.muted)),
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
    final List<DeliveryOrder> active =
        _orders.where((DeliveryOrder o) => !o.status.isTerminal).toList();
    final List<DeliveryOrder> done =
        _orders.where((DeliveryOrder o) => o.status.isTerminal).toList();

    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        _header(t),
        Padding(
          padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(t.custActiveOrdersTab(active.length),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: DeliverySpacing.sm),
              if (active.isEmpty)
                YdCard.bordered(
                    child: Text(t.noOrdersYet,
                        style: const TextStyle(
                            fontSize: 13, color: DeliveryColors.muted))),
              for (final DeliveryOrder order in active)
                Padding(
                  padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
                  child: _orderRow(t, order),
                ),
              const SizedBox(height: DeliverySpacing.md),
              Text(t.custPastOrdersTab,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: DeliverySpacing.sm),
              for (final DeliveryOrder order in done.take(20))
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

  Widget _orderRow(DeliveryStrings t, DeliveryOrder order) {
    return YdCard.bordered(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('#${order.shortId} · ${order.storeName ?? t.tabShop}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        height: 1.25)),
                const SizedBox(height: 2),
                Text(order.deliveryAddress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12,
                        color: DeliveryColors.muted,
                        height: 1.3)),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text('\$${order.totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: DeliveryColors.brand)),
              CustomerStatusPill(
                statusWire: order.status.wire,
                label: order.status.labelIn(t),
              ),
            ],
          ),
        ],
      ),
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
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: DeliverySpacing.sm),
              Text(t.custShowingShops(_riders.length),
                  style: const TextStyle(
                      fontSize: 12.5, color: DeliveryColors.muted)),
              const SizedBox(height: DeliverySpacing.sm),
              // The wire carries rider REFS, deliberately: names, photos and ratings for a
              // carrier's own staff panel are their own backend feature, and inventing them
              // here would be lying with confidence. Each row shows the honest handle.
              if (_riders.isEmpty)
                YdCard.bordered(
                    child: Text(t.noOrdersYet,
                        style: const TextStyle(
                            fontSize: 13, color: DeliveryColors.muted))),
              for (final String ref in _riders)
                Padding(
                  padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
                  child: YdCard.bordered(
                    child: Row(
                      children: <Widget>[
                        StoreMonogram(name: ref, size: 40, radius: 20),
                        const SizedBox(
                            width: DeliverySpacing.md - DeliverySpacing.xs),
                        Expanded(
                          child: Text(
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
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: DeliverySpacing.lg),
            ],
          ),
        ),
      ],
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
                      Text(t.riderWeeklyOverview,
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
                    children: <Widget>[
                      _moneyRow(t.navOrders, '${earnings.delivered}'),
                      _moneyRow(t.carrTotalRevenue,
                          '\$${earnings.earned.toStringAsFixed(2)}'),
                      _moneyRow(
                        t.carrCommissionPaid,
                        '-${(earnings.cutPercentage).toStringAsFixed(0)}%',
                        color: DeliveryColors.brand,
                      ),
                      const Divider(
                          height: DeliverySpacing.md * 1.5,
                          color: DeliveryColors.borderFaint),
                      _moneyRow(
                        t.carrNetEarnings,
                        '\$${(earnings.earned * (1 - earnings.cutPercentage / 100)).toStringAsFixed(2)}',
                        bold: true,
                        color: DeliveryAccent.positive.color,
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
              const SizedBox(height: DeliverySpacing.sm),
              AppLanguageRow(
                  locale: widget.locale, label: t.custAppLanguage),
              const SizedBox(height: DeliverySpacing.lg),
              YdPillButton(
                label: t.custLogOutAccount,
                icon: Icons.logout_rounded,
                onPressed: () => widget.onSignOut(),
              ),
              const SizedBox(height: DeliverySpacing.lg),
            ],
          ),
        ),
      ],
    );
  }
}
