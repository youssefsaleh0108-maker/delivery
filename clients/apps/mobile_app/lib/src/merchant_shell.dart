import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:flutter/material.dart';

import 'notifications_screen.dart' show NotificationPrefsScreen;
import 'settings_screen.dart';

/// The shop's surface: the five-tab app the merchant suite draws.
///
/// Figma `merchant-dashboard` (94:9) and its siblings share one bottom nav — Dashboard, POS,
/// Inventory, Orders, Settings. Inventory is where Products went: the product list with stock on
/// every row is the same list a merchant used to edit, so a sixth tab would have been the same
/// screen twice. The product form is still one tap from any inventory row.
///
/// Two things this shell decides that the screens deliberately do not. First, who is standing at
/// the phone: the owner, or an employee with a subset of the owner's permissions. The screens take
/// that as a value; this file resolves it once, from the staff API, and never lets it regress
/// below "owner" for an account that carries the MERCHANT role. Second, which tabs that person may
/// see. Until order-manager learns about staff (step 22 of the suite plan), its merchant endpoints
/// are keyed on the caller's own subject and refuse every employee token, so Orders and the
/// order-backed dashboard are owner-only — gated on ownership, not on a permission that would only
/// produce a 403.
///
/// Tabs are built on first visit rather than eagerly. The register and the inventory each open a
/// socket and a poll; building all five at start-up would have every merchant paying for screens
/// they may not open that day.
class MerchantShell extends StatefulWidget {
  const MerchantShell({
    super.key,
    required this.orderApi,
    required this.storeApi,
    required this.catalogApi,
    this.aggregatesApi,
    this.documentsApi,
    this.prefsApi,
    this.statementsApi,
    this.posApi,
    this.inventoryApi,
    this.staffApi,
    this.reportsApi,
    required this.session,
    required this.locale,
    this.pendingApproval = false,
    required this.onSignOut,
  });

  final OrderApi orderApi;

  /// The shop record behind the dashboard's publish switch and the shop-configuration page.
  final StoreApi storeApi;

  /// The catalogue behind the Inventory tab and the register's product grid.
  final CatalogApi catalogApi;

  /// The shop's own daily series: the dashboard's period comparisons and the analytics page.
  final AggregatesApi? aggregatesApi;

  /// The onboarding documents-and-payout client, behind the Settings tab bank row.
  final DocumentsApi? documentsApi;

  /// Handed to the settings page's notification-preferences grid; null leaves the row undrawn.
  final NotificationPrefsApi? prefsApi;

  /// The shop's own statement — what the ledger says they are owed for a period they choose.
  final StatementsApi? statementsApi;

  /// The register. Null, or a service that is not deployed yet, gives a calm unavailable state
  /// on the POS tab rather than a crash — the tab is still drawn so the shape of the app is honest.
  final PosApi? posApi;

  /// Stock levels, alerts and counts behind the Inventory tab. Same null contract as [posApi].
  final InventoryApi? inventoryApi;

  /// Who works here and what they may do. Null means "assume the owner", which is the only kind
  /// of account that reached this shell before the suite existed.
  final StoreStaffApi? staffApi;

  /// Sales reports. Wired now so the dashboard can take it the day the service lands.
  final ReportsApi? reportsApi;

  final AuthSession session;

  /// Drives the EN/AR toggle on the Settings tab.
  final LocaleController locale;

  /// True while the application behind this account is still being decided.
  final bool pendingApproval;

  final Future<void> Function() onSignOut;

  @override
  State<MerchantShell> createState() => _MerchantShellState();
}

/// The tabs, named. The dashboard's pending card jumps to Orders and says so by name, and the
/// visibility rules below read far better against a name than against an index.
enum MerchantTab { dashboard, pos, inventory, orders, settings }

class _MerchantShellState extends State<MerchantShell> {
  MerchantTab _tab = MerchantTab.dashboard;

  /// Which tabs have been opened at least once. Only those are built; see the class doc.
  final Set<MerchantTab> _visited = <MerchantTab>{MerchantTab.dashboard};

  /// The shop this person is standing in. Resolved once from the store API; the register and the
  /// shelves cannot open without it, so they show a waiting state until it lands.
  String? _storeId;

  /// What this person may do here. Starts as the owner for a MERCHANT account — the account that
  /// has always reached this shell — and is refined, never demoted below that, once the staff API
  /// answers. An employee's token carries MERCHANT_STAFF instead, starts with nothing, and gains
  /// exactly what the staff record grants.
  late MerchantAccess _access = widget.session.hasRole(DeliveryRole.merchant)
      ? const MerchantAccess.owner()
      : const MerchantAccess.none();

  /// Orders placed and not yet accepted — the number on the Orders badge.
  int? _awaitingYou;

  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _resolveStore();
    if (_access.isOwner) {
      _refreshBadge();
      // Slower than the rider's board on purpose: this is a count on a tab, not a job somebody is
      // racing another rider for, and the queue itself refreshes when it is opened.
      _poll = Timer.periodic(const Duration(seconds: 30), (_) => _refreshBadge());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _resolveStore() async {
    String? storeId;
    try {
      final Paged<Store> mine = await widget.storeApi.mine(size: 1);
      if (mine.content.isNotEmpty) storeId = mine.content.first.id;
    } catch (_) {
      // Left null: the screens that need a shop say "no shop yet" rather than guessing one.
    }
    if (storeId == null && widget.staffApi != null) {
      // An employee owns no store, so `mine` is empty for them; their membership names the shop.
      try {
        final StaffMembership membership = await widget.staffApi!.myMembership();
        storeId = membership.storeId;
      } catch (_) {
        // Same contract as above.
      }
    }
    if (!mounted) return;
    setState(() => _storeId = storeId);

    if (storeId == null || widget.staffApi == null) return;
    try {
      final StoreStaffAccess resolved = await widget.staffApi!.access(storeId);
      if (!mounted) return;
      setState(() {
        // Never demote an owner on the word of a failed or partial lookup: the worst outcome of
        // a bad answer here is a shop locked out of its own register.
        _access = (_access.isOwner && !resolved.isOwner) ? _access : resolved;
        if (!_visibleTabs().contains(_tab)) _tab = _visibleTabs().first;
      });
    } catch (_) {
      // Keep whatever we started with.
    }
  }

  Future<void> _refreshBadge() async {
    try {
      final MerchantSummary summary = await widget.orderApi.merchantSummary();
      if (!mounted) return;
      setState(() => _awaitingYou = summary.awaitingYou);
    } catch (_) {
      // Deliberately silent. The dashboard tab surfaces the same failure with a message and a
      // retry; a second copy of it on top of whatever tab is showing would be noise.
    }
  }

  /// The tabs this person may see, in nav order.
  ///
  /// Owners see all five. An employee sees the register if they may sell, the shelves if they may
  /// touch stock, and always Settings — which is where the language toggle and sign-out live, so
  /// nobody is ever handed an app with no way out of it.
  List<MerchantTab> _visibleTabs() {
    if (_access.isOwner) return MerchantTab.values;
    return <MerchantTab>[
      if (_access.can(StorePermission.posSales)) MerchantTab.pos,
      if (_access.can(StorePermission.modifyInventoryPricing)) MerchantTab.inventory,
      MerchantTab.settings,
    ];
  }

  void _open(MerchantTab tab) {
    setState(() {
      _tab = tab;
      _visited.add(tab);
    });
    // Opening the queue is the moment the count stops being true, so re-ask rather than waiting
    // out the rest of the interval.
    if (tab == MerchantTab.orders) _refreshBadge();
  }

  Widget _tabAt(MerchantTab tab) {
    if (!_visited.contains(tab)) return const SizedBox.shrink();
    switch (tab) {
      case MerchantTab.dashboard:
        return MerchantDashboardScreen(
          api: widget.orderApi,
          storeApi: widget.storeApi,
          aggregates: widget.aggregatesApi,
          pendingApproval: widget.pendingApproval,
          onShowOrders: () => _open(MerchantTab.orders),
        );
      case MerchantTab.pos:
        return PosTerminalScreen(
          api: widget.posApi,
          catalogApi: widget.catalogApi,
          storeId: _storeId,
          storeApi: widget.storeApi,
          inventoryApi: widget.inventoryApi,
          // The register runs full-screen and hands the tender step to a pushed route, so the nav
          // is out of thumb's reach during the one moment a mis-tap costs money.
          onCheckout: (BuildContext ctx, PosSale sale) => PosCheckoutScreen.show(
            ctx,
            sale: sale,
            api: widget.posApi,
          ),
          onExit: () => _open(_access.isOwner ? MerchantTab.dashboard : MerchantTab.settings),
        );
      case MerchantTab.inventory:
        return InventoryScreen(
          api: widget.inventoryApi,
          catalogApi: widget.catalogApi,
          storeApi: widget.storeApi,
          storeId: _storeId,
          onOpenAlerts: _openStockAlerts,
        );
      case MerchantTab.orders:
        return OrdersScreen(api: widget.orderApi);
      case MerchantTab.settings:
        return MerchantSettingsScreen(
          locale: widget.locale,
          accountName: widget.session.displayName,
          accountContact: widget.session.email ?? widget.session.username,
          onEditAccount: _openAccountPreferences,
          onShopProfile: _access.isOwner ? _openShopProfile : null,
          onNotificationSettings:
              widget.prefsApi == null ? null : _openNotificationPreferences,
          aggregates: _access.isOwner ? widget.aggregatesApi : null,
          documents: _access.isOwner ? widget.documentsApi : null,
          statements: _access.isOwner ? widget.statementsApi : null,
          // The suite's three management pages hang off Settings rather than taking a tab each:
          // a shop reorganises its shelves and its roster a few times a year, not a few times a
          // day, and the nav is for the few-times-a-day things.
          onCategories: _access.can(StorePermission.modifyInventoryPricing)
              ? _openCategories
              : null,
          onStaff: _access.can(StorePermission.manageStaff) ? _openStaff : null,
          onStockCount: _access.can(StorePermission.modifyInventoryPricing) && _storeId != null
              ? _openStockCount
              : null,
          onSignOut: () => widget.onSignOut(),
        );
    }
  }

  // ---------------------------------------------------------------- pushed routes

  void _openAccountPreferences() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(
        locale: widget.locale,
        userId: widget.session.subject,
        prefsApi: widget.prefsApi,
      ),
    ));
  }

  void _openNotificationPreferences() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NotificationPrefsScreen(api: widget.prefsApi!),
    ));
  }

  void _openShopProfile() {
    final NavigatorState navigator = Navigator.of(context);
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => StoreScreen(api: widget.storeApi, onBack: navigator.pop),
    ));
  }

  void _openStockAlerts() {
    final NavigatorState navigator = Navigator.of(context);
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => StockAlertsScreen(
        api: widget.inventoryApi,
        storeId: _storeId,
        onBack: navigator.pop,
      ),
    ));
  }

  void _openStockCount() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StockCountScreen(
        api: widget.inventoryApi,
        storeId: _storeId!,
        catalogApi: widget.catalogApi,
      ),
    ));
  }

  void _openCategories() {
    final NavigatorState navigator = Navigator.of(context);
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => MerchantCategoriesScreen(
        api: widget.catalogApi,
        storeId: _storeId,
        onBack: navigator.pop,
      ),
    ));
  }

  void _openStaff() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StaffScreen(
        api: widget.staffApi,
        storeId: _storeId,
        access: _access,
      ),
    ));
  }

  // ---------------------------------------------------------------- layout

  YdBottomNavItem _itemFor(MerchantTab tab, DeliveryStrings t) {
    switch (tab) {
      case MerchantTab.dashboard:
        return YdBottomNavItem(
          icon: Icons.home_outlined,
          activeIcon: Icons.home_rounded,
          label: t.navDashboard,
        );
      case MerchantTab.pos:
        return YdBottomNavItem(
          icon: Icons.point_of_sale_outlined,
          activeIcon: Icons.point_of_sale,
          label: t.navPos,
        );
      case MerchantTab.inventory:
        return YdBottomNavItem(
          icon: Icons.inventory_2_outlined,
          activeIcon: Icons.inventory_2,
          label: t.navInventory,
        );
      case MerchantTab.orders:
        return YdBottomNavItem(
          icon: Icons.receipt_long_outlined,
          activeIcon: Icons.receipt_long,
          label: t.navOrders,
          badgeCount: _awaitingYou,
        );
      case MerchantTab.settings:
        return YdBottomNavItem(
          icon: Icons.person_outline_rounded,
          activeIcon: Icons.person_rounded,
          label: t.navSettings,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<MerchantTab> tabs = _visibleTabs();
    final int current = tabs.indexOf(_tab).clamp(0, tabs.length - 1);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      // Edge-to-edge: the shell paints its background behind the now-transparent status bar, and
      // this keeps every tab's content clear of it. The bottom stays open — the nav bar below
      // handles that edge.
      body: SafeArea(
        top: true,
        bottom: false,
        child: IndexedStack(
          index: current,
          children: <Widget>[for (final MerchantTab tab in tabs) _tabAt(tab)],
        ),
      ),
      bottomNavigationBar: YdBottomNav(
        currentIndex: current,
        onTap: (int index) => _open(tabs[index]),
        items: <YdBottomNavItem>[for (final MerchantTab tab in tabs) _itemFor(tab, t)],
      ),
    );
  }
}
