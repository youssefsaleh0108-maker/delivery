import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:flutter/material.dart';

import 'notification_inbox.dart';
import 'notifications_screen.dart' show NotificationPrefsScreen, NotificationsScreen;
import 'services_shop_bootstrap.dart';
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
/// A services provider — a print shop, a tailor — gets services mode (docs/figma-services-designs.md,
/// "The provider app experience"): Dashboard, Orders, Offers, Settings. A shop that makes things to
/// order has no till and no stock ledger, so POS and Inventory are not drawn, and its dashboard,
/// queue and offers are the services ones (Figma 126:51, 126:200, 126:133). Which mode is read from
/// the shop itself — its vertical — and nothing is drawn until it is known, so a provider is never
/// shown a till and a shop is never shown Offers, not even for a frame. A shop that is not a services
/// shop gets exactly the five tabs it always had.
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
    this.catalogScanApi,
    this.demandApi,
    this.shopChatApi,
    this.chatSocket,
    this.notificationApi,
    this.zoneApi,
    this.orderAttachmentApi,
    required this.session,
    required this.locale,
    this.pendingApproval = false,
    this.onboardingApi,
    this.servicesProviderMemory,
    this.onSwitchToShopping,
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

  /// Merchant Blitz, behind the Inventory header and a Settings row. Null draws neither. Handed on
  /// only to an account carrying MERCHANT — see [_MerchantShellState._mayScan].
  final CatalogScanApi? catalogScanApi;

  /// How busy the neighbourhoods around the shop are. Null leaves the Demand Radar's doors undrawn.
  /// Opened for the owner only: the density is order-backed, and Order Manager refuses staff tokens.
  final DemandApi? demandApi;

  /// Customers' conversations with the shop, behind Settings' Customer messages row. Null leaves
  /// the row undrawn.
  final ShopChatApi? shopChatApi;

  /// App Notification's socket, so a customer's message refreshes the inbox as it arrives.
  final UserQueueSocket? chatSocket;

  /// The account's in-app notifications, behind the services dashboard's bell (126:51). Null draws no
  /// bell. The goods dashboard has never had one, and does not get one here.
  final NotificationApi? notificationApi;

  /// The shop's delivery areas, which decide whether a service offer may be delivered. Null leaves
  /// that to the shop's pin, and to the server.
  final DeliveryZoneApi? zoneApi;

  /// A service order's files, for the provider's order detail: Order Manager's attachment read, which
  /// the order's shop may make. Null draws no files section.
  final OrderAttachmentApi? orderAttachmentApi;

  final AuthSession session;

  /// Drives the EN/AR toggle on the Settings tab.
  final LocaleController locale;

  /// True while the application behind this account is still being decided.
  final bool pendingApproval;

  /// The account's own application, for opening an approved services provider's shop on their first
  /// entry ([ServicesShopBootstrap]). Null skips that, which is where every shell stood before
  /// services existed.
  final OnboardingApi? onboardingApi;

  /// What the app already learned this session about the account's application, so a goods merchant
  /// is not asked about again on every entry ([ServicesProviderMemory]). Owned by the app rather than
  /// the shell, because the shell is built afresh on every entry. Null remembers nothing.
  final ServicesProviderMemory? servicesProviderMemory;

  /// Takes an owner who is also a customer to the customer app — the Settings row of the role switch.
  /// Null hides the row.
  final VoidCallback? onSwitchToShopping;

  final Future<void> Function() onSignOut;

  @override
  State<MerchantShell> createState() => _MerchantShellState();
}

/// The tabs, named. The dashboard's pending card jumps to Orders and says so by name, and the
/// visibility rules below read far better against a name than against an index.
///
/// Offers is appended rather than slotted in beside Orders: nothing reads these by index, but a name
/// that moved would be one more thing a merge had to notice.
enum MerchantTab { dashboard, pos, inventory, orders, settings, offers }

class _MerchantShellState extends State<MerchantShell> {
  MerchantTab _tab = MerchantTab.dashboard;

  /// Which tabs have been opened at least once. Only those are built; see the class doc.
  final Set<MerchantTab> _visited = <MerchantTab>{MerchantTab.dashboard};

  /// The shop this person is standing in. Resolved once from the store API; the register and the
  /// shelves cannot open without it, so they show a waiting state until it lands.
  String? _storeId;

  /// Whether this is a services shop's shell: true for a services shop and for a services applicant
  /// still waiting for approval, false for everybody else. Null until the shop has been read, and
  /// the shell draws nothing but a spinner until then — see the class doc.
  bool? _servicesMode;

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

  /// Customers' unread messages, on Settings' messages row. Owner-only, like the row.
  ShopUnreadCount? _shopUnread;

  /// The account's notifications, behind the services dashboard's bell. Services mode only.
  NotificationInbox? _inbox;

  /// True while an approved services provider's shop is being opened: the one moment the shell shows
  /// nothing else, because every tab needs the shop.
  bool _openingServicesShop = false;

  /// Opening that shop failed. The shell says so and offers a retry rather than tabs that cannot work.
  bool _servicesShopFailed = false;

  /// The server will not open that shop, because its category is not offered right now. Final: the
  /// shell says so and points to support, with no retry, because none could succeed.
  bool _servicesCategoryClosed = false;

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
    final ShopChatApi? shopChat = widget.shopChatApi;
    if (_access.isOwner && shopChat != null) {
      // From the start, not from the first visit to the inbox. Without it a customer's message
      // showed nowhere until the merchant happened to open that page — and, since it is reading the
      // inbox that tells the server who owns the shop, it never arrived live before then either.
      _shopUnread = ShopUnreadCount(api: shopChat, socket: widget.chatSocket)..start();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _shopUnread?.dispose();
    _inbox?.removeListener(_inboxChanged);
    _inbox?.dispose();
    super.dispose();
  }

  Future<void> _resolveStore() async {
    String? storeId;
    bool services = false;
    final OnboardingApi? onboarding = widget.onboardingApi;
    if (onboarding != null && widget.session.hasRole(DeliveryRole.merchant)) {
      // An approved services provider's shop is opened here, before anything else, from their
      // application (see [ServicesShopBootstrap]). Everybody else gets the shop `mine` always gave
      // them, and the shell carries on exactly as before.
      final ServicesShopOutcome outcome = await ServicesShopBootstrap(
        stores: widget.storeApi,
        onboarding: onboarding,
        memory: widget.servicesProviderMemory,
        account: widget.session.subject,
      ).run(onOpening: () {
        if (mounted) setState(() => _openingServicesShop = true);
      });
      if (!mounted) return;
      switch (outcome) {
        case ServicesShopReady(:final Store store):
          storeId = store.id;
          services = true;
        case NotServicesProvider(storeId: final String? standing):
          storeId = standing;
        case ServicesApplicationPending():
          // Nothing is opened before a decision, and a waiting provider owns no shop to stand in —
          // but they applied to offer services, so they wait in the services shell, not at a till.
          storeId = null;
          services = true;
        case ServicesShopFailed():
          setState(() {
            _openingServicesShop = false;
            _servicesShopFailed = true;
          });
          return;
        case ServicesCategoryNotOffered():
          setState(() {
            _openingServicesShop = false;
            _servicesCategoryClosed = true;
          });
          return;
      }
      if (_openingServicesShop) setState(() => _openingServicesShop = false);
    } else {
      try {
        final Paged<Store> mine = await widget.storeApi.mine(size: 1);
        if (mine.content.isNotEmpty) {
          storeId = mine.content.first.id;
          services = mine.content.first.vertical == StoreVertical.services;
        }
      } catch (_) {
        // Left null: the screens that need a shop say "no shop yet" rather than guessing one.
      }
    }
    if (storeId == null && !services && widget.staffApi != null) {
      // An employee owns no store, so `mine` is empty for them; their membership names the shop.
      try {
        final StaffMembership membership = await widget.staffApi!.myMembership();
        storeId = membership.storeId;
      } catch (_) {
        // Same contract as above.
      }
    }
    if (!mounted) return;
    setState(() {
      _storeId = storeId;
      _servicesMode = services;
      if (!_visibleTabs().contains(_tab)) _tab = _visibleTabs().first;
    });
    if (services) _startInbox();

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

  /// The bell's notifications, for the owner of a services shop when the host wired the client.
  void _startInbox() {
    final NotificationApi? api = widget.notificationApi;
    if (api == null || _inbox != null || !_access.isOwner) return;
    setState(() => _inbox = NotificationInbox(api)
      ..addListener(_inboxChanged)
      ..start());
  }

  /// Redraws the bell's count as the inbox changes, once the frame that changed it has finished.
  ///
  /// Not a builder listening to the inbox: the notifications page loads the inbox from its own
  /// initState, so the inbox changes while that page is being built, and the framework refuses a
  /// rebuild marked then anywhere outside the page being built.
  void _inboxChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// The goods shop's five tabs, in nav order, exactly as they have always been.
  static const List<MerchantTab> _goodsTabs = <MerchantTab>[
    MerchantTab.dashboard,
    MerchantTab.pos,
    MerchantTab.inventory,
    MerchantTab.orders,
    MerchantTab.settings,
  ];

  /// The tabs this person may see, in nav order.
  ///
  /// Owners see all five. An employee sees the register if they may sell, the shelves if they may
  /// touch stock, and always Settings — which is where the language toggle and sign-out live, so
  /// nobody is ever handed an app with no way out of it.
  ///
  /// A services shop's owner sees Dashboard, Orders, Offers and Settings. Its employees see Settings:
  /// the permissions a staff record grants open the register and the shelves, which a services shop
  /// does not have, and its orders are the owner's for the same reason a goods shop's are.
  List<MerchantTab> _visibleTabs() {
    if (_servicesMode == true) {
      return <MerchantTab>[
        if (_access.isOwner) ...<MerchantTab>[
          MerchantTab.dashboard,
          MerchantTab.orders,
          MerchantTab.offers,
        ],
        MerchantTab.settings,
      ];
    }
    if (_access.isOwner) return _goodsTabs;
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

  /// The Demand Radar's door, or null when this person gets none.
  ///
  /// The owner only: the density behind it is order-backed, and Order Manager answers MERCHANT and
  /// refuses the MERCHANT_STAFF token an employee carries — the same reason Orders is owner-only.
  /// And only when the host wired the client, so an unwired build draws no door rather than a dead
  /// one.
  VoidCallback? get _demandRadarDoor =>
      _access.isOwner && widget.demandApi != null ? _openDemandRadar : null;

  void _openDemandRadar() {
    final NavigatorState navigator = Navigator.of(context);
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => DemandRadarScreen(
        api: widget.demandApi!,
        storeId: _storeId,
        onBack: navigator.pop,
      ),
    ));
  }

  Widget _tabAt(MerchantTab tab) {
    if (!_visited.contains(tab)) return const SizedBox.shrink();
    final bool services = _servicesMode == true;
    switch (tab) {
      case MerchantTab.dashboard:
        if (services) return _servicesDashboard();
        return MerchantDashboardScreen(
          api: widget.orderApi,
          storeApi: widget.storeApi,
          aggregates: widget.aggregatesApi,
          pendingApproval: widget.pendingApproval,
          onShowOrders: () => _open(MerchantTab.orders),
          onDemandRadar: _demandRadarDoor,
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
          catalogScanApi: _mayScan ? widget.catalogScanApi : null,
        );
      case MerchantTab.orders:
        if (services) {
          return ServiceOrdersScreen(
            api: widget.orderApi,
            // The order detail's "Chat with customer" opens the shop's conversations, which are the
            // owner's, like the Settings row.
            shopChat: _access.isOwner ? widget.shopChatApi : null,
            chatSocket: widget.chatSocket,
            files: widget.orderAttachmentApi,
          );
        }
        return OrdersScreen(api: widget.orderApi);
      case MerchantTab.offers:
        return ServiceOffersScreen(
          api: widget.catalogApi,
          storeApi: widget.storeApi,
          zoneApi: widget.zoneApi,
          storeId: _storeId,
          pendingApproval: widget.pendingApproval,
        );
      case MerchantTab.settings:
        return MerchantSettingsScreen(
          locale: widget.locale,
          accountName: widget.session.displayName,
          accountContact: widget.session.email ?? widget.session.username,
          onEditAccount: _openAccountPreferences,
          onShopProfile: _access.isOwner ? _openShopProfile : null,
          // Owner-only, like the shop profile above it: which shop's threads a merchant may read is
          // Product Service's "shops you own", so an employee's inbox would always be empty.
          onShopMessages:
              _access.isOwner && widget.shopChatApi != null ? _openShopMessages : null,
          shopMessagesUnread: _shopUnread,
          onNotificationSettings:
              widget.prefsApi == null ? null : _openNotificationPreferences,
          aggregates: _access.isOwner ? widget.aggregatesApi : null,
          documents: _access.isOwner ? widget.documentsApi : null,
          statements: _access.isOwner ? widget.statementsApi : null,
          onDemandRadar: _demandRadarDoor,
          // The suite's three management pages hang off Settings rather than taking a tab each:
          // a shop reorganises its shelves and its roster a few times a year, not a few times a
          // day, and the nav is for the few-times-a-day things.
          //
          // A services shop has no shelves: no shelf sections to arrange, no stock to count, and
          // nothing a shelf photo could list — Product Service refuses an offer without its service
          // terms, so a scan could only fail. Those three doors are not drawn in services mode.
          onCategories: !services && _access.can(StorePermission.modifyInventoryPricing)
              ? _openCategories
              : null,
          onStaff: _access.can(StorePermission.manageStaff) ? _openStaff : null,
          onStockCount: !services &&
                  _access.can(StorePermission.modifyInventoryPricing) &&
                  _storeId != null
              ? _openStockCount
              : null,
          onCatalogScan:
              !services && _mayScan && widget.catalogScanApi != null ? _openBlitz : null,
          onSwitchToShopping: widget.onSwitchToShopping,
          onSignOut: () => widget.onSignOut(),
        );
    }
  }

  /// The services dashboard. The bell counts the inbox's unread notifications, and the shell redraws
  /// as that changes ([_inboxChanged]).
  Widget _servicesDashboard() {
    final NotificationInbox? inbox = _inbox;
    return ServiceDashboardScreen(
      orderApi: widget.orderApi,
      catalogApi: widget.catalogApi,
      storeApi: widget.storeApi,
      zoneApi: widget.zoneApi,
      storeId: _storeId,
      pendingApproval: widget.pendingApproval,
      onViewOrders: () => _open(MerchantTab.orders),
      onShowOffers: () => _open(MerchantTab.offers),
      onNotifications: inbox == null ? null : _openNotifications,
      unreadNotifications: inbox?.unread,
    );
  }

  // ---------------------------------------------------------------- pushed routes

  void _openNotifications() {
    final NotificationInbox? inbox = _inbox;
    if (inbox == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NotificationsScreen(inbox: inbox),
    ));
  }

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

  /// Whether this person may scan shelves into the catalogue.
  ///
  /// The token's role, not the staff record: the scan endpoints are gated on MERCHANT and refuse a
  /// MERCHANT_STAFF token whatever permissions the store grants it, so an employee who may manage
  /// stock would still only ever get a 403 behind the button. A pending applicant carries MERCHANT
  /// and may scan — everything it keeps is a draft, and publishing stays behind approval.
  bool get _mayScan => widget.session.hasRole(DeliveryRole.merchant);

  void _openBlitz() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MerchantBlitzScreen(
        api: widget.catalogScanApi!,
        catalogApi: widget.catalogApi,
        storeId: _storeId,
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

  Future<void> _openShopMessages() async {
    final ShopChatApi? api = widget.shopChatApi;
    if (api == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ShopInboxScreen(api: api, socket: widget.chatSocket),
    ));
    // Reading conversations is what changes the count: ask as the merchant comes back, not a minute
    // later.
    final ShopUnreadCount? unread = _shopUnread;
    if (mounted && unread != null) unawaited(unread.refresh());
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
      case MerchantTab.offers:
        return YdBottomNavItem(
          icon: Icons.design_services_outlined,
          activeIcon: Icons.design_services,
          label: t.svcNavOffers,
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

    if (_openingServicesShop || _servicesShopFailed || _servicesCategoryClosed) {
      return _ServicesShopGate(
        failed: _servicesShopFailed,
        categoryClosed: _servicesCategoryClosed,
        onRetry: () {
          setState(() => _servicesShopFailed = false);
          _resolveStore();
        },
        onSignOut: widget.onSignOut,
      );
    }

    if (_servicesMode == null) {
      // Which shell this is comes from the shop, and until the shop has been read either answer
      // could be wrong: a till in front of a print shop, or Offers in front of a restaurant.
      return const Scaffold(
        backgroundColor: DeliveryColors.background,
        body: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
      );
    }

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

/// What an approved services provider sees while their shop is being opened, or when it could not be.
///
/// Nothing else is drawn: every tab needs the shop, and a dashboard for a shop that does not exist
/// would only fail five different ways. Sign-out stays in reach, so nobody is trapped behind a retry
/// that keeps failing. And a refusal that no retry can change — the shop's category is not offered
/// right now ([ServicesCategoryNotOffered]) — is said as that, pointing to support, with no retry at
/// all: a "Try again" there would be a button that cannot work.
class _ServicesShopGate extends StatelessWidget {
  const _ServicesShopGate({
    required this.failed,
    required this.categoryClosed,
    required this.onRetry,
    required this.onSignOut,
  });

  final bool failed;
  final bool categoryClosed;
  final VoidCallback onRetry;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final Widget signOut = TextButton(
      onPressed: () => onSignOut(),
      child: Text(t.merchbLogOutAccount),
    );

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: SafeArea(
        child: Center(
          child: categoryClosed
              ? YdEmptyState(
                  icon: Icons.storefront_outlined,
                  title: t.svcShopCategoryClosedTitle,
                  message: t.svcShopCategoryClosedBody,
                  action: signOut,
                )
              : failed
              ? YdEmptyState(
                  icon: Icons.storefront_outlined,
                  title: t.svcOpeningShopFailed,
                  message: t.thatDidNotGoThrough,
                  action: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      YdPillButton(label: t.tryAgain, onPressed: onRetry),
                      const SizedBox(height: DeliverySpacing.sm),
                      signOut,
                    ],
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const CircularProgressIndicator(color: DeliveryColors.brand),
                    const SizedBox(height: DeliverySpacing.md),
                    Text(
                      t.svcOpeningShop,
                      style: const TextStyle(fontSize: 14, color: DeliveryColors.muted),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
