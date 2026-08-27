import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:flutter/material.dart';

import 'settings_screen.dart';

/// The shop owner's surface: the four-tab app the redesign draws.
///
/// Figma `merchant-dashboard` (3:1742), `merchant-orders` (3:1822), `merchant-products` (3:1893)
/// and `merchant-settings` (3:2194) all share one `bottom-nav` (3:1799) — Dashboard, Orders,
/// Products, Settings, with a live count badge on Orders. That is the whole navigation, and it is
/// the owner's explicit ask: the menus the web portal has, on the phone.
///
/// Before this a merchant on a phone got one screen — an order queue and nothing else — so a shop
/// that had only a phone could not add a product, set its hours or change its language without
/// finding a desktop. The screens themselves are not new and are not copies: they live in
/// `delivery_merchant` and the portal mounts the same ones, so a change to the catalogue page
/// lands in both. This file is only the framing that package deliberately does not carry.
class MerchantShell extends StatefulWidget {
  const MerchantShell({
    super.key,
    required this.orderApi,
    required this.storeApi,
    required this.catalogApi,
    required this.session,
    required this.locale,
    this.pendingApproval = false,
    required this.onSignOut,
  });

  final OrderApi orderApi;

  /// The shop record behind the dashboard's publish switch and the shop-configuration page.
  final StoreApi storeApi;

  /// The catalogue behind the Products tab.
  final CatalogApi catalogApi;

  final AuthSession session;

  /// Drives the EN/AR toggle on the Settings tab.
  final LocaleController locale;

  /// True while the application behind this account is still being decided.
  ///
  /// Passed to the dashboard, which is where the design puts the banner (`pending-banner`, 3:1758)
  /// and which is the tab this shell opens on. The server is what refuses the committing act; this
  /// only means nobody discovers that from a snackbar after building a whole shop.
  final bool pendingApproval;

  final Future<void> Function() onSignOut;

  @override
  State<MerchantShell> createState() => _MerchantShellState();
}

class _MerchantShellState extends State<MerchantShell> {
  /// The tab order, named — the same discipline the customer bar keeps. The dashboard's pending
  /// card jumps to Orders, and it says so by name.
  static const int _dashboardTab = 0;
  static const int _ordersTab = 1;
  static const int _productsTab = 2;
  static const int _settingsTab = 3;
  static const int _tabCount = 4;

  int _tab = _dashboardTab;

  /// Orders placed and not yet accepted — the number on the Orders badge.
  ///
  /// Real, not decorative: it is `awaitingYou` off the merchant summary the dashboard already
  /// reads, so the badge and the dashboard's own "Pending Orders" card cannot disagree. Null until
  /// the first read lands, and left alone on a failure — a badge that invents a zero because the
  /// network blinked is worse than a badge that has not appeared yet.
  int? _awaitingYou;

  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refreshBadge();
    // Slower than the rider's board on purpose: this is a count on a tab, not a job somebody is
    // racing another rider for, and the queue itself refreshes when it is opened.
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _refreshBadge());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
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

  void _open(int tab) {
    setState(() => _tab = tab);
    // Opening the queue is the moment the count stops being true, so re-ask rather than waiting
    // out the rest of the interval.
    if (tab == _ordersTab) _refreshBadge();
  }

  Widget _tabAt(int tab) {
    switch (tab) {
      case _dashboardTab:
        return MerchantDashboardScreen(
          api: widget.orderApi,
          storeApi: widget.storeApi,
          pendingApproval: widget.pendingApproval,
          onShowOrders: () => _open(_ordersTab),
        );
      case _ordersTab:
        return OrdersScreen(api: widget.orderApi);
      case _productsTab:
        return ProductListScreen(
          api: widget.catalogApi,
          storeApi: widget.storeApi,
        );
      case _settingsTab:
        return MerchantSettingsScreen(
          locale: widget.locale,
          accountName: widget.session.displayName,
          accountContact: widget.session.email ?? widget.session.username,
          // The frame's Edit chip. There is no merchant profile endpoint to edit against, so it
          // opens the account preferences this app does own — language and fingerprint unlock.
          // That route existed on the old single-screen merchant surface and would otherwise have
          // disappeared with it, taking the only way to turn the lock on or off with it.
          onEditAccount: _openAccountPreferences,
          onShopProfile: _openShopProfile,
          // Null on purpose: no notification preferences exist for a merchant on any service, and
          // the screen draws the row as "Soon" rather than as a control that does nothing.
          onNotificationSettings: null,
          onSignOut: () => widget.onSignOut(),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _openAccountPreferences() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(
        locale: widget.locale,
        userId: widget.session.subject,
      ),
    ));
  }

  void _openShopProfile() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StoreScreen(api: widget.storeApi),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: IndexedStack(
        index: _tab,
        children: <Widget>[
          for (int tab = 0; tab < _tabCount; tab++) _tabAt(tab),
        ],
      ),
      bottomNavigationBar: YdBottomNav(
        currentIndex: _tab,
        onTap: _open,
        items: <YdBottomNavItem>[
          YdBottomNavItem(
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded,
            label: t.navDashboard,
          ),
          YdBottomNavItem(
            icon: Icons.receipt_long_outlined,
            activeIcon: Icons.receipt_long,
            label: t.navOrders,
            badgeCount: _awaitingYou,
          ),
          YdBottomNavItem(
            icon: Icons.shopping_bag_outlined,
            activeIcon: Icons.shopping_bag,
            label: t.navProducts,
          ),
          YdBottomNavItem(
            icon: Icons.person_outline_rounded,
            activeIcon: Icons.person_rounded,
            label: t.navSettings,
          ),
        ],
      ),
    );
  }
}
