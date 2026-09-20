import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
// The merchant pages are not in this app. The Android app mounts these same widgets, so the rail
// below is only the portal's framing around them.
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:flutter/material.dart';

import 'backoffice/banners_screen.dart';
import 'backoffice/catalog_screen.dart';
import 'backoffice/categories_screen.dart';
import 'backoffice/dashboard_screen.dart';
import 'backoffice/moderation_screen.dart';
import 'backoffice/offers_screen.dart';
import 'backoffice/onboarding_screen.dart';
import 'backoffice/overview_screen.dart';
import 'backoffice/promotions_screen.dart';
import 'backoffice/providers_screen.dart';
import 'backoffice/reconciliation_screen.dart';
import 'backoffice/riders_screen.dart';
import 'backoffice/service_offers_screen.dart' as backoffice;
import 'backoffice/settings_screen.dart';
import 'backoffice/shops_screen.dart';
import 'backoffice/statements_screen.dart';
// Prefixed: this and delivery_merchant's ZonesScreen share a name and are different pages — the
// Backoffice one administers platform-wide areas, the merchant one picks which of them a shop
// delivers to. The prefix goes on this one because it is the local file of the two.
import 'backoffice/zones_screen.dart' as backoffice;
import 'carrier/applicants_screen.dart';
import 'carrier/cash_reconciliation_screen.dart';
import 'carrier/dashboard_screen.dart';
import 'carrier/earnings_screen.dart';
import 'carrier/jobs_screen.dart';
import 'carrier/payroll_screen.dart';
import 'carrier/rider_attendance_screen.dart';
import 'carrier/rider_profile_screen.dart';
import 'carrier/riders_directory_screen.dart';
// No prefix needed: this file's class is `CarrierSettingsScreen`, distinct from the Backoffice
// `SettingsScreen` imported above, because the two administer entirely different things.
import 'carrier/settings_screen.dart';
import 'carrier/shift_schedule_screen.dart';
// Likewise `CarrierStatementScreen` — the carrier reads only its own, through /mine, where the
// Backoffice screen reads everybody's.
import 'carrier/statement_screen.dart';
import 'shell/shell.dart';

/// Every API the portal can use, built once in main and handed down.
///
/// A record rather than twelve constructor parameters threaded through two widgets — which is what
/// the Backoffice shell had, and what made adding a page a three-file change.
class PortalApis {
  const PortalApis({
    required this.catalog,
    required this.order,
    required this.store,
    required this.provider,
    required this.zone,
    required this.whatsApp,
    required this.settings,
    required this.accounting,
    required this.rate,
    required this.banner,
    required this.offer,
    required this.onboarding,
    required this.tracking,
    required this.promo,
    required this.documents,
    required this.notification,
    required this.aggregates,
    required this.activity,
    required this.riderPerformance,
    required this.partnerManagement,
    required this.autoApproval,
    required this.statements,
    required this.pos,
    required this.inventory,
    required this.staff,
    required this.reports,
    required this.catalogScan,
    required this.demand,
    required this.shopChat,
    required this.moderation,
    required this.attachments,
    required this.offerModeration,
  });

  final CatalogApi catalog;

  /// Merchant Blitz, behind the Inventory page's "Scan shelves". Required like every client here, so
  /// a host that forgets it does not compile: InventoryScreen draws no button for a null client, and
  /// an optional field would ship the portal without the feature and without one failing test. The
  /// merchant area is MERCHANT-only, which is exactly who the scan endpoints admit. On the web there
  /// is no camera, so the scan offers "Choose photos" only.
  final CatalogScanApi catalogScan;
  final OrderApi order;
  final StoreApi store;
  final DeliveryProviderApi provider;
  final DeliveryZoneApi zone;
  final WhatsAppApi whatsApp;
  final ConnectorSettingsApi settings;
  final AccountingApi accounting;
  final DeliveryRateApi rate;
  final BannerApi banner;
  final OfferApi offer;
  final OnboardingApi onboarding;
  final TrackingApi tracking;
  final PromoApi promo;
  final DocumentsApi documents;

  /// The signed-in operator's own in-app inbox, behind every console header's bell.
  final NotificationApi notification;

  /// The tier-split daily trade series. Backoffice reads the platform scope, a carrier its own.
  final AggregatesApi aggregates;

  /// The Backoffice activity feed — a poll, not a push.
  final ActivityApi activity;

  /// Rider counters: delivered-today, and one rider's thirty-day standing.
  final RiderPerformanceApi riderPerformance;

  /// Corrections, the audit trail, and the suspension switch on a partner who already exists.
  final PartnerManagementApi partnerManagement;

  /// The three approval gates: written from Settings, read by the review queue.
  final AutoApprovalApi autoApproval;

  /// Counterparty statements. The Backoffice reads everybody's and sends them; a carrier reads only
  /// its own, through a route that takes no ref at all.
  final StatementsApi statements;

  /// The merchant suite. The register, the shelves and the reports talk to services that are not
  /// yet deployed and their screens say so calmly; staff is served by product-service today.
  final PosApi pos;
  final InventoryApi inventory;
  final StoreStaffApi staff;
  final ReportsApi reports;

  /// How busy the neighbourhoods around a shop are — the merchant Demand Radar.
  final DemandApi demand;

  /// Customers' conversations with the merchant's shops.
  final ShopChatApi shopChat;

  /// The neighbourhood chat moderation queue. BACKOFFICE-only on the server.
  final ChatModerationApi moderation;

  /// A service order's files. The customer uploads them; the order's shop and back office read them,
  /// and every back-office read is recorded by the server — which is why the ledger lists them only
  /// when the operator asks.
  final OrderAttachmentApi attachments;

  /// Back office's moderation of service offers: every service shop's offers, taking one down or
  /// restoring it with a reason, and the trail. BACKOFFICE-only on the server.
  final BackofficeCatalogApi offerModeration;
}

/// How a page in the rail is built.
///
/// `jump` moves the rail — the dashboards use it for "see all orders" style links, which is why a
/// page takes a callback rather than being a bare widget.
typedef PortalPageBuilder = Widget Function(PortalApis apis, LocaleController locale,
    Future<void> Function() onSignOut, void Function(int) jump);

/// One destination in a rail.
class PortalDestination {
  const PortalDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.build,
    this.badge,
  }) : pages = const <PortalPage>[];

  /// A heading with pages filed under it — the carrier rail's Reconciliation and Riders HR.
  ///
  /// Tapping the heading opens its first page. Once there are two or more, the rail draws every
  /// page as an indented row under the heading; with one, the heading is simply that page's row.
  /// So a heading is declared the day its first page exists — never before, which would be a menu
  /// item that opens nothing — and grows rows as the others arrive, with no change to the shell.
  ///
  /// A heading carries no [badge]: a count belongs to a row that is a single page.
  PortalDestination.section({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.pages,
  })  : assert(pages.isNotEmpty, 'a heading with no page under it would open nothing'),
        build = pages.first.build,
        badge = null;

  final IconData icon;
  final IconData selectedIcon;

  /// The live number this destination's rail row carries, if any.
  final PortalBadge? badge;

  /// Resolved against the active locale rather than stored, so switching language re-labels the
  /// rail without rebuilding the area list.
  final String Function(DeliveryStrings) label;

  /// This destination's page — for a [PortalDestination.section], its first page.
  final PortalPageBuilder build;

  /// The pages under a heading, in the order their rows are drawn. Empty for a plain destination.
  final List<PortalPage> pages;

  /// The page the rail has open here: the [page]th under a heading, or the destination's own. An
  /// index the heading does not have opens its first page rather than failing.
  Widget buildPage(int page, PortalApis apis, LocaleController locale,
      Future<void> Function() onSignOut, void Function(int) jump) {
    final PortalPageBuilder builder =
        page > 0 && page < pages.length ? pages[page].build : build;
    return builder(apis, locale, onSignOut, jump);
  }
}

/// One page filed under a rail heading — see [PortalDestination.section].
class PortalPage {
  const PortalPage({required this.label, required this.build});

  /// The page's row under its heading, resolved against the active locale.
  final String Function(DeliveryStrings) label;

  final PortalPageBuilder build;
}

/// A live number a rail row can carry.
///
/// Named here rather than handed over as a callback, so the area lists stay plain data and the shell
/// — which owns the requests — decides how each number is kept current and when to stop asking.
enum PortalBadge {
  /// Customers' messages the signed-in merchant has not read (`ShopUnreadCount`).
  shopUnread,
}

/// One of the three former portals, as a role and the destinations it grants.
class PortalArea {
  const PortalArea({
    required this.role,
    required this.title,
    required this.wordmark,
    required this.accountRole,
    required this.logoIcon,
    required this.destinations,
  });

  final DeliveryRole role;
  final String Function(DeliveryStrings) title;

  /// The line under "YouDrop" in the sidebar — the design's per-console wordmark, `BACKOFFICE` and
  /// `CARRIER HUB`.
  ///
  /// An inline English constant rather than a [DeliveryStrings] key, matching the rest of this
  /// portal: the console screens are English-only in this wave and a half-translated rail would be
  /// worse than an untranslated one.
  final String wordmark;

  /// What the signed-in person is, on the sidebar's footer card.
  ///
  /// Their *access*, not their job title — the token carries a realm role and nothing that would
  /// let us print "Super Admin" honestly.
  ///
  /// Resolved against the reader's locale like [title], not an inline constant like [wordmark]. The
  /// wordmark labels a console that is English-only in this wave; this line sits under the name of a
  /// shop that reads its whole portal in Arabic, and it was the one Latin word left on that card.
  final String Function(DeliveryStrings) accountRole;

  /// The glyph in the 32px brand tile. Per the design this is the console's subject — a package for
  /// the Backoffice, a truck for the Carrier Hub — not a company mark.
  final IconData logoIcon;

  final List<PortalDestination> destinations;

  /// The areas a session's token grants, in a fixed order.
  ///
  /// Order is deliberate and not alphabetical: most accounts carry exactly one of these, and for
  /// the rare account with more than one, the day-to-day areas come before the administrative one.
  static List<PortalArea> forSession(AuthSession session) {
    return <PortalArea>[
      if (session.hasRole(DeliveryRole.merchant)) merchant_,
      if (session.hasRole(DeliveryRole.carrier)) carrier_,
      if (session.hasRole(DeliveryRole.backoffice)) backoffice_,
    ];
  }

  // ------------------------------------------------------------------ merchant
  static final PortalArea merchant_ = PortalArea(
    role: DeliveryRole.merchant,
    title: (DeliveryStrings t) => t.merchantPortal,
    wordmark: 'Merchant Hub',
    accountRole: (DeliveryStrings t) => t.merchantPartner,
    logoIcon: Icons.storefront,
    destinations: <PortalDestination>[
      // First, and ahead of the catalog. A shop opening the portal wants to know what came in
      // overnight and whether yesterday was any good; the menu is what they edit occasionally.
      PortalDestination(
        icon: Icons.insights_outlined,
        selectedIcon: Icons.insights,
        label: (DeliveryStrings t) => t.navDashboard,
        build: (PortalApis a, _, __, void Function(int) jump) => MerchantDashboardScreen(
          api: a.order,
          onShowOrders: () => jump(2),
        ),
      ),
      PortalDestination(
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2,
        label: (DeliveryStrings t) => t.navProducts,
        // These pages are only built for an account carrying MERCHANT, so the find's camera is
        // offered here as the shelf scan is. On the web there is no camera to open, so its sheet
        // offers the gallery alone.
        build: (PortalApis a, _, __, ___) => ProductListScreen(
              api: a.catalog,
              photoSource: const DeviceShelfPhotoSource(cameraMaxEdge: CatalogApi.photoFindMaxEdge),
            ),
      ),
      PortalDestination(
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
        label: (DeliveryStrings t) => t.navOrders,
        build: (PortalApis a, _, __, ___) => OrdersScreen(api: a.order),
      ),
      PortalDestination(
        icon: Icons.chat_outlined,
        selectedIcon: Icons.chat,
        label: (DeliveryStrings t) => t.navWhatsApp,
        build: (PortalApis a, _, __, ___) =>
            WhatsAppScreen(api: a.whatsApp, catalogApi: a.catalog),
      ),
      PortalDestination(
        icon: Icons.local_shipping_outlined,
        selectedIcon: Icons.local_shipping,
        label: (DeliveryStrings t) => t.navDelivery,
        build: (PortalApis a, _, __, ___) => DeliveryScreen(api: a.provider),
      ),
      PortalDestination(
        icon: Icons.map_outlined,
        selectedIcon: Icons.map,
        label: (DeliveryStrings t) => t.deliveryAreas,
        build: (PortalApis a, _, __, ___) =>
            ZonesScreen(api: a.zone, storeApi: a.store),
      ),
      PortalDestination(
        icon: Icons.store_outlined,
        selectedIcon: Icons.store,
        label: (DeliveryStrings t) => t.navMyShop,
        build: (PortalApis a, _, __, ___) => StoreScreen(api: a.store),
      ),
      // The merchant suite, APPENDED after the seven above and never reordered: the dashboard's
      // "see all orders" link is `jump(2)` and must keep meaning Orders. The portal is owner-only
      // today (the MERCHANT role), so access is the owner's without a lookup.
      PortalDestination(
        icon: Icons.inventory_outlined,
        selectedIcon: Icons.inventory,
        label: (DeliveryStrings t) => t.navInventory,
        build: (PortalApis a, _, __, ___) => _withStore(a, (String? storeId) => InventoryScreen(
          api: a.inventory,
          catalogApi: a.catalog,
          storeApi: a.store,
          storeId: storeId,
          catalogScanApi: a.catalogScan,
          photoSource: const DeviceShelfPhotoSource(cameraMaxEdge: CatalogApi.photoFindMaxEdge),
        )),
      ),
      PortalDestination(
        icon: Icons.point_of_sale_outlined,
        selectedIcon: Icons.point_of_sale,
        label: (DeliveryStrings t) => t.navPos,
        build: (PortalApis a, _, __, ___) => _withStore(a, (String? storeId) => PosTerminalScreen(
          api: a.pos,
          catalogApi: a.catalog,
          storeId: storeId,
          storeApi: a.store,
          inventoryApi: a.inventory,
          onCheckout: (BuildContext ctx, PosSale sale) =>
              PosCheckoutScreen.show(ctx, sale: sale, api: a.pos),
        )),
      ),
      PortalDestination(
        icon: Icons.category_outlined,
        selectedIcon: Icons.category,
        label: (DeliveryStrings t) => t.navCategories,
        build: (PortalApis a, _, __, ___) => _withStore(a,
            (String? storeId) => MerchantCategoriesScreen(api: a.catalog, storeId: storeId)),
      ),
      PortalDestination(
        icon: Icons.badge_outlined,
        selectedIcon: Icons.badge,
        label: (DeliveryStrings t) => t.navStaff,
        build: (PortalApis a, _, __, ___) => _withStore(a, (String? storeId) => StaffScreen(
          api: a.staff,
          storeId: storeId,
          access: const MerchantAccess.owner(),
        )),
      ),
      // The Demand Radar (Figma 121:8): which neighbourhoods around the shop are ordering. Appended
      // like the suite above, never inserted — `jump(2)` must keep meaning Orders. The portal is
      // owner-only (MERCHANT), which is exactly who the density endpoint answers.
      PortalDestination(
        icon: Icons.radar,
        selectedIcon: Icons.radar,
        label: (DeliveryStrings t) => t.heatmapTitle,
        build: (PortalApis a, _, __, ___) => _withStore(
            a, (String? storeId) => DemandRadarScreen(api: a.demand, storeId: storeId)),
      ),
      // Appended, like the suite above, so no earlier index moves. The server decides which shops'
      // conversations the signed-in merchant reads, so the page needs no store id.
      PortalDestination(
        icon: Icons.forum_outlined,
        selectedIcon: Icons.forum,
        label: (DeliveryStrings t) => t.chatShopInboxTitle,
        // The sign that a customer wrote: the portal has no push and no socket.
        badge: PortalBadge.shopUnread,
        build: (PortalApis a, _, __, ___) => ShopInboxScreen(api: a.shopChat, embedded: true),
      ),
    ],
  );

  // ------------------------------------------------------------------ merchant, services mode
  /// The Merchant Hub for a services shop: the phone's services mode, on the web.
  ///
  /// The goods rail with the substitution the phone makes, and never reordered. The dashboard becomes
  /// the services dashboard, Products becomes Offers and Orders the services queue, so index 2 is still
  /// Orders and the dashboard's jump(2) still lands there. The register, the shelves and the shelf
  /// sections, which a print shop does not have, are left out, and so is the staff roster: nobody on
  /// it could work here, because the portal admits MERCHANT alone and an employee's MERCHANT_STAFF token
  /// opens the phone's customer app. Every other page after Orders is the goods rail's own destination,
  /// taken from it in its order, so a page appended to the goods rail joins this one without anybody
  /// having to remember to add it.
  ///
  /// The service screens are handed no store id: each reads the owner's services shop itself, which
  /// a merchant who also owns a goods shop needs.
  static final PortalArea merchantServices_ = PortalArea(
    role: DeliveryRole.merchant,
    title: (DeliveryStrings t) => t.merchantPortal,
    wordmark: 'Merchant Hub',
    accountRole: (DeliveryStrings t) => t.merchantPartner,
    logoIcon: Icons.storefront,
    destinations: <PortalDestination>[
      PortalDestination(
        icon: Icons.insights_outlined,
        selectedIcon: Icons.insights,
        label: (DeliveryStrings t) => t.navDashboard,
        build: (PortalApis a, _, __, void Function(int) jump) => ServiceDashboardScreen(
          orderApi: a.order,
          catalogApi: a.catalog,
          storeApi: a.store,
          zoneApi: a.zone,
          onViewOrders: () => jump(2),
          onShowOffers: () => jump(1),
        ),
      ),
      PortalDestination(
        icon: Icons.design_services_outlined,
        selectedIcon: Icons.design_services,
        label: (DeliveryStrings t) => t.svcNavOffers,
        build: (PortalApis a, _, __, ___) =>
            ServiceOffersScreen(api: a.catalog, storeApi: a.store, zoneApi: a.zone),
      ),
      PortalDestination(
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
        label: (DeliveryStrings t) => t.navOrders,
        build: (PortalApis a, _, __, ___) =>
            ServiceOrdersScreen(api: a.order, shopChat: a.shopChat, files: a.attachments),
      ),
      for (int i = 3; i < merchant_.destinations.length; i++)
        if (!_notForServicesShops.contains(i)) merchant_.destinations[i],
    ],
  );

  /// Where the goods rail keeps the shelves, the register, the shelf sections and the staff roster:
  /// the merchant suite's pages, appended after My shop and never moved (see [merchant_]).
  static const Set<int> _notForServicesShops = <int>{7, 8, 9, 10};

  /// The Merchant Hub for an owner who runs a goods shop and a services shop: the goods rail exactly as
  /// it is, with the services shop's queue and offers appended.
  ///
  /// Not the services rail: that would swap out the goods shop's products, till and shelves. And
  /// appended, never slotted in, so every index the goods pages jump to still lands where it did. The
  /// service screens read the owner's services shop themselves, so no store id is handed over.
  static final PortalArea merchantWithServices_ = PortalArea(
    role: DeliveryRole.merchant,
    title: (DeliveryStrings t) => t.merchantPortal,
    wordmark: 'Merchant Hub',
    accountRole: (DeliveryStrings t) => t.merchantPartner,
    logoIcon: Icons.storefront,
    destinations: <PortalDestination>[
      ...merchant_.destinations,
      PortalDestination(
        icon: Icons.assignment_outlined,
        selectedIcon: Icons.assignment,
        label: (DeliveryStrings t) => t.svcServiceOrdersRow,
        build: (PortalApis a, _, __, ___) =>
            ServiceOrdersScreen(api: a.order, shopChat: a.shopChat, files: a.attachments),
      ),
      PortalDestination(
        icon: Icons.design_services_outlined,
        selectedIcon: Icons.design_services,
        label: (DeliveryStrings t) => t.svcServiceOffersRow,
        build: (PortalApis a, _, __, ___) =>
            ServiceOffersScreen(api: a.catalog, storeApi: a.store, zoneApi: a.zone),
      ),
    ],
  );

  /// Resolves the signed-in merchant's shop once and hands its id to [child].
  ///
  /// The suite's screens are keyed on a store, and the rail builds synchronously; this is the one
  /// place the portal looks the shop up so no screen has to. A merchant with no shop yet gets a
  /// null, which every one of those screens renders as "no shop yet" rather than as a failure.
  static Widget _withStore(PortalApis a, Widget Function(String? storeId) child) {
    return FutureBuilder<Paged<Store>>(
      future: a.store.mine(size: 1),
      builder: (BuildContext context, AsyncSnapshot<Paged<Store>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
        }
        final List<Store>? stores = snap.data?.content;
        return child(stores == null || stores.isEmpty ? null : stores.first.id);
      },
    );
  }

  // ------------------------------------------------------------------- carrier
  //
  // The rail the 2026-09 carrier frames draw (Figma 112:414): Dashboard, Orders, Fleet,
  // Reconciliation, Riders HR, Earnings, Coverage, Settings — in that order, less the two headings
  // with no page behind them yet. Fleet has no page anywhere, and Coverage (the company's delivery
  // areas) is only edited from the phone app today, so neither is drawn: a heading that opens
  // nothing is a dead control. Each joins at its place in that order the day its first page does.
  //
  // Every page the older seven-item rail listed is still one tap away, filed under the design's
  // headings: Jobs is Orders, the statement is the page under Reconciliation, and the riders
  // directory and the applicant queue are the pages under Riders HR. The lists those headings are
  // built from sit under this area — [carrierReconciliationPages], [carrierRidersHrPages], and for
  // pages about one rider [carrierRiderPages] — and they are where the next pages go.
  //
  // Orders has to stay at index 1: the dashboard's "see the job board" is `jump(1)`. Nothing is
  // inserted ahead of it; Fleet, when it exists, goes straight after it.
  static final PortalArea carrier_ = PortalArea(
    role: DeliveryRole.carrier,
    title: (DeliveryStrings t) => t.carrierPortal,
    wordmark: 'Carrier Hub',
    accountRole: (DeliveryStrings t) => t.carrierPartner,
    logoIcon: Icons.local_shipping,
    destinations: <PortalDestination>[
      PortalDestination(
        icon: Icons.grid_view_outlined,
        selectedIcon: Icons.grid_view_rounded,
        label: (DeliveryStrings t) => t.navDashboard,
        // Every client it reads. It was built with two, which left its week-over-week lines and the
        // fleet card's delivered-today count dead in the deployed build — the same withheld-client
        // fault the riders page had — while the screen's own tests, which pass them, stayed green.
        build: (PortalApis a, _, __, void Function(int) jump) => CarrierDashboardScreen(
          api: a.order,
          providerApi: a.provider,
          aggregatesApi: a.aggregates,
          performanceApi: a.riderPerformance,
          onShowJobs: () => jump(1),
        ),
      ),
      // The design's "Orders": the work this company carries.
      PortalDestination(
        icon: Icons.shopping_cart_outlined,
        selectedIcon: Icons.shopping_cart,
        label: (DeliveryStrings t) => t.navOrders,
        build: (PortalApis a, _, __, ___) => JobsScreen(api: a.order),
      ),
      PortalDestination.section(
        icon: Icons.calculate_outlined,
        selectedIcon: Icons.calculate,
        label: (DeliveryStrings t) => t.carrRidersNavReconciliation,
        pages: carrierReconciliationPages,
      ),
      PortalDestination.section(
        icon: Icons.people_outline,
        selectedIcon: Icons.people,
        label: (DeliveryStrings t) => t.carrRidersNavRidersHr,
        pages: carrierRidersHrPages,
      ),
      // The rolling window off the order service — how the work is paying. The ledger's own
      // figures for a closed period are the statement, under Reconciliation.
      PortalDestination(
        icon: Icons.bar_chart_outlined,
        selectedIcon: Icons.bar_chart,
        label: (DeliveryStrings t) => t.navEarnings,
        build: (PortalApis a, _, __, ___) => EarningsScreen(api: a.order),
      ),
      // Last, per the design and for the same reason the Backoffice's is: the least-used page here.
      PortalDestination(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: (DeliveryStrings t) => t.navSettings,
        build: (PortalApis a, LocaleController locale, _, __) => CarrierSettingsScreen(
          api: a.provider,
          locale: locale,
          documentsApi: a.documents,
        ),
      ),
    ],
  );

  /// The pages under the carrier rail's Reconciliation heading, in the order their rows are drawn.
  ///
  /// EXTENSION POINT for the pages that square money between this company, its riders and YouDrop:
  /// append a page here and the heading grows a row for it, with nothing else in the shell to
  /// change. The heading opens whichever page is first.
  ///
  /// The rider cash reconciliation is first, so the heading opens on it: it is the page the design
  /// draws under this heading (Figma 112:9), and each rider's settlement (112:235) opens inside it,
  /// so the heading stays selected there too. Its row carries the page's own title rather than the
  /// design's one-word label, because that word is the heading's, and a row under a heading that
  /// repeats the heading's name tells the reader nothing.
  ///
  /// The statement is here because it is this company's side of that reconciliation: the ledger's
  /// own figures for a closed period, of what YouDrop owes it and what it owes YouDrop.
  static final List<PortalPage> carrierReconciliationPages = <PortalPage>[
    // Every client it reads is passed, as the rail destination it replaces passed them.
    PortalPage(
      label: (DeliveryStrings t) => t.carrCashTitle,
      build: (PortalApis a, _, __, ___) => CarrierCashScreen(
        api: a.accounting.carrierCash,
        notificationApi: a.notification,
        orderApi: a.order,
      ),
    ),
    PortalPage(
      label: (DeliveryStrings t) => t.carrRidersNavStatement,
      build: (PortalApis a, _, __, ___) => CarrierStatementScreen(api: a.statements),
    ),
  ];

  /// The pages under Riders HR, in the order their rows are drawn.
  ///
  /// EXTENSION POINT for pages about the whole fleet's people — attendance across the fleet, and
  /// payroll with its pay runs (Figma 112:1162) — appended after the applicant queue. A page about
  /// ONE rider does not belong here: it opens from that rider's profile, through
  /// [carrierRiderPages].
  static final List<PortalPage> carrierRidersHrPages = <PortalPage>[
    // First, so the heading opens on it (Figma 112:413). Every client it reads is passed: the page
    // it replaced shipped with four of its six withheld, which left names, presence, Add Rider and
    // suspension dead in the deployed build while every test of the screen itself passed.
    PortalPage(
      label: (DeliveryStrings t) => t.carrRidersNavDirectory,
      build: (PortalApis a, _, __, ___) => RidersDirectoryScreen(
        api: a.provider,
        orderApi: a.order,
        onboardingApi: a.onboarding,
        managementApi: a.partnerManagement,
        trackingApi: a.tracking,
        performanceApi: a.riderPerformance,
        documentsApi: a.documents,
        notificationApi: a.notification,
        riderPages: carrierRiderPages(a),
      ),
    ),
    // Beside the directory. Hiring is occasional and must not be missed: somebody is waiting to be
    // told yes or no. The directory's Add Rider approves in place; this is the full review, papers
    // and all.
    PortalPage(
      label: (DeliveryStrings t) => t.navApplicants,
      build: (PortalApis a, _, __, ___) => ApplicantsScreen(
        api: a.onboarding,
        providerApi: a.provider,
        documentsApi: a.documents,
      ),
    ),
    // After the applicant queue, where fleet-wide pages go: the company's shifts and who works
    // which — the part of the attendance frame (Figma 112:945) that it implies but does not draw.
    // Each rider's attendance month opens in place from here as well as from their profile.
    PortalPage(
      label: (DeliveryStrings t) => t.attendanceNavShifts,
      build: (PortalApis a, _, __, ___) => ShiftScheduleScreen(
        api: a.tracking,
        providerApi: a.provider,
        onboardingApi: a.onboarding,
      ),
    ),
    // Last, after the shifts it pays for: rider payroll and its pay runs (Figma 112:1162), which
    // the design files under this heading. A pay run is built from the hours attendance records,
    // and nets off the cash each rider still holds for the company, from Reconciliation above.
    PortalPage(
      label: (DeliveryStrings t) => t.payrollNavLabel,
      build: (PortalApis a, _, __, ___) => CarrierPayrollScreen(
        api: a.accounting.carrierPayroll,
        notificationApi: a.notification,
      ),
    ),
  ];

  /// Pages about ONE rider: each is a button on that rider's profile and opens in place there, with
  /// a way back to the profile — see [RiderPage].
  ///
  /// EXTENSION POINT for per-rider HR pages: their pay history is next. A function of the clients
  /// rather than a list, so an entry can hand its page whatever it reads without threading clients
  /// through the directory and the profile.
  static List<RiderPage> carrierRiderPages(PortalApis apis) => <RiderPage>[
        // The rider's attendance month (Figma 112:945) — the same page the Shifts page opens, here
        // with its way back leading to the profile it was opened from.
        RiderPage(
          icon: Icons.event_available_outlined,
          label: (DeliveryStrings t) => t.attendanceOpenAttendance,
          build: (BuildContext context, RiderPageContext rider, VoidCallback onBack) =>
              RiderAttendanceScreen(
            api: apis.tracking,
            riderId: rider.riderId,
            riderName: rider.name,
            onBack: onBack,
            backTooltip: DeliveryStrings.of(context).attendanceBackToProfile,
          ),
        ),
      ];

  // ---------------------------------------------------------------- backoffice
  static final PortalArea backoffice_ = PortalArea(
    role: DeliveryRole.backoffice,
    title: (DeliveryStrings t) => t.backoffice,
    wordmark: 'Backoffice',
    accountRole: (DeliveryStrings t) => t.backofficeOperator,
    logoIcon: Icons.inventory_2,
    destinations: <PortalDestination>[
      // The overview first, then the ledger it summarises — the order the redesign draws, and the
      // order the two pages are read in: the numbers, then the rows behind them.
      PortalDestination(
        icon: Icons.bar_chart,
        selectedIcon: Icons.bar_chart,
        label: (DeliveryStrings t) => t.navDashboard,
        build: (PortalApis a, _, __, void Function(int) jump) => OverviewScreen(
          api: a.order,
          storeApi: a.store,
          aggregatesApi: a.aggregates,
          activityApi: a.activity,
          notificationApi: a.notification,
          onShowOrders: () => jump(1),
        ),
      ),
      // Monitoring live operations is what a Backoffice user opens this for.
      PortalDestination(
        icon: Icons.shopping_bag_outlined,
        selectedIcon: Icons.shopping_bag,
        label: (DeliveryStrings t) => t.navOrders,
        build: (PortalApis a, _, __, ___) => DashboardScreen(
          api: a.order,
          notificationApi: a.notification,
          // A service order's files, through back office's audited read.
          attachmentApi: a.attachments,
        ),
      ),
      PortalDestination(
        icon: Icons.category_outlined,
        selectedIcon: Icons.category,
        label: (DeliveryStrings t) => t.navCategories,
        build: (PortalApis a, _, __, ___) => CategoriesScreen(api: a.catalog),
      ),
      PortalDestination(
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2,
        label: (DeliveryStrings t) => t.navCatalog,
        build: (PortalApis a, _, __, ___) => CatalogScreen(api: a.catalog),
      ),
      // Next to Categories, because the two pages edit the same home screen: what the strip is
      // made of, and what sits above it.
      PortalDestination(
        icon: Icons.view_carousel_outlined,
        selectedIcon: Icons.view_carousel,
        label: (DeliveryStrings t) => t.navBanners,
        build: (PortalApis a, _, __, ___) =>
            BannersScreen(api: a.banner, catalogApi: a.catalog),
      ),
      // Before Carriers, because this is where a carrier — or a shop — comes from. A waiting
      // application is the only thing in this rail with somebody on the other end of it.
      PortalDestination(
        icon: Icons.how_to_reg_outlined,
        selectedIcon: Icons.how_to_reg,
        label: (DeliveryStrings t) => t.navOnboarding,
        build: (PortalApis a, _, __, ___) => OnboardingScreen(
          api: a.onboarding,
          documentsApi: a.documents,
          managementApi: a.partnerManagement,
          notificationApi: a.notification,
          autoApprovalApi: a.autoApproval,
        ),
      ),
      // Beside Finance: who carries orders is an operating question, and the money split that
      // follows from it is right next door.
      PortalDestination(
        icon: Icons.local_shipping_outlined,
        selectedIcon: Icons.local_shipping,
        label: (DeliveryStrings t) => t.navCarriers,
        build: (PortalApis a, _, __, ___) =>
            ProvidersScreen(api: a.provider, notificationApi: a.notification),
      ),
      // Immediately after Carriers, because a rider is reached through one: the roster is
      // assembled from the same register the page above lists.
      //
      // An inline English label rather than a [DeliveryStrings] key — the console screens are
      // English-only in this wave, and half a translated rail is worse than none.
      PortalDestination(
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
        label: (DeliveryStrings _) => 'Riders',
        build: (PortalApis a, _, __, ___) => RidersScreen(
          api: a.provider,
          trackingApi: a.tracking,
          orderApi: a.order,
          performanceApi: a.riderPerformance,
          notificationApi: a.notification,
        ),
      ),
      PortalDestination(
        icon: Icons.map_outlined,
        selectedIcon: Icons.map,
        label: (DeliveryStrings t) => t.navAreas,
        build: (PortalApis a, _, __, ___) => backoffice.ZonesScreen(api: a.zone),
      ),
      PortalDestination(
        icon: Icons.account_balance_outlined,
        selectedIcon: Icons.account_balance,
        label: (DeliveryStrings t) => t.navFinance,
        // carr-cash: the provider API names the delivery companies holding cash.
        build: (PortalApis a, _, __, ___) =>
            ReconciliationScreen(api: a.accounting, providerApi: a.provider),
      ),
      // Immediately after Finance, and deliberately so: Reconciliation answers "what has not
      // settled" inside our own books, and this answers the question that follows it — who are we
      // square with, and has anybody outside this building actually been told.
      //
      // An inline English label, matching Riders and Promo Codes below.
      PortalDestination(
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
        label: (DeliveryStrings _) => 'Statements',
        build: (PortalApis a, _, __, ___) => StatementsScreen(
          api: a.statements,
          notificationApi: a.notification,
        ),
      ),
      // Immediately after Finance, because that is what an offer spends.
      PortalDestination(
        icon: Icons.redeem_outlined,
        selectedIcon: Icons.redeem,
        label: (DeliveryStrings t) => t.navOffers,
        build: (PortalApis a, _, __, ___) => OffersScreen(api: a.offer),
      ),
      // Beside Offers, because the two are the same act — the platform giving money away — done
      // through two mechanisms: a waiver the customer sees applied, and a code they type.
      //
      // An inline English label rather than a [DeliveryStrings] key — the console screens are
      // English-only in this wave, matching the Riders entry above.
      PortalDestination(
        icon: Icons.sell_outlined,
        selectedIcon: Icons.sell,
        label: (DeliveryStrings _) => 'Promo Codes',
        build: (PortalApis a, _, __, ___) =>
            PromotionsScreen(api: a.promo, notificationApi: a.notification),
      ),
      // Neighbourhood chat's reported messages. Late in the rail, because it is worked in bursts
      // when reports come in, and before Settings, which stays last. Nothing jumps to an index
      // after Orders, so no link moves.
      PortalDestination(
        icon: Icons.shield_outlined,
        selectedIcon: Icons.shield,
        label: (DeliveryStrings t) => t.chatModerationTitle,
        build: (PortalApis a, _, __, ___) => ModerationScreen(api: a.moderation),
      ),
      // The last of the rail's original pages, and deliberately so: the least-used and most
      // consequential page here. Pages added since come after it rather than before it, so that no
      // destination above moves.
      PortalDestination(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: (DeliveryStrings t) => t.navSettings,
        build: (PortalApis a, _, __, ___) => SettingsScreen(
          api: a.settings,
          rateApi: a.rate,
          autoApprovalApi: a.autoApproval,
        ),
      ),
      // The services back office. Appended rather than filed beside Catalog, where it would read
      // best, so every destination above keeps its index: the overview's jump to Orders and anything
      // else that counts rows stay right.
      PortalDestination(
        icon: Icons.design_services_outlined,
        selectedIcon: Icons.design_services,
        label: (DeliveryStrings t) => t.svcBoOffersTitle,
        build: (PortalApis a, _, __, ___) => backoffice.ServiceOffersScreen(
          api: a.offerModeration,
          notificationApi: a.notification,
        ),
      ),
      // Where the Verified Local badge is set, for goods and service shops alike — the one back-office
      // page that can reach a shop (ShopsScreen says why the Merchants Directory cannot).
      PortalDestination(
        icon: Icons.storefront_outlined,
        selectedIcon: Icons.storefront,
        label: (DeliveryStrings t) => t.svcBoShopsTitle,
        build: (PortalApis a, _, __, ___) =>
            ShopsScreen(api: a.store, notificationApi: a.notification),
      ),
    ],
  );
}

/// The rail, and an area switcher when the token grants more than one.
///
/// The switcher rather than one long rail: concatenating all three areas would be a 22-destination
/// rail with three pages called Dashboard in it. Almost every account has exactly one area, and for
/// those this renders exactly what the old single-purpose portal did.
class PortalShell extends StatefulWidget {
  const PortalShell({
    super.key,
    required this.areas,
    required this.apis,
    required this.locale,
    required this.session,
    required this.onSignOut,
  });

  final List<PortalArea> areas;
  final PortalApis apis;
  final LocaleController locale;

  /// Only ever read for what it can say about the person signed in — their display name for the
  /// sidebar's footer card. Nothing here is a security decision; every request is authorised again
  /// server-side.
  final AuthSession session;

  final Future<void> Function() onSignOut;

  @override
  State<PortalShell> createState() => _PortalShellState();
}

class _PortalShellState extends State<PortalShell> {
  /// The areas as the signed-in merchant's shop decides them: for a services shop the Merchant Hub is
  /// its services rail ([PortalArea.merchantServices_]). Starts as handed over, and is swapped once
  /// the shop has been read.
  late List<PortalArea> _areas = widget.areas;

  /// True while the merchant's shops are being read. Nothing is drawn meanwhile: the goods rail in
  /// front of a print shop would offer it a till for a moment, and a click on it.
  late bool _readingShop = widget.areas.contains(PortalArea.merchant_);

  /// The merchant's shops could not be read. Nothing is guessed: the shell says so, with a retry and
  /// sign-out, because a guessed goods rail would stand in front of a print shop all session.
  bool _shopReadFailed = false;

  int _area = 0;
  int _index = 0;

  /// Which page under the open heading is showing — see [PortalDestination.section]. Zero on a
  /// plain destination, and back to zero whenever the rail moves to another destination, because a
  /// heading opens on its first page.
  int _page = 0;

  /// The merchant's unread customer messages, for the rail. Held only while the area on screen has a
  /// row showing it, so a back-office or carrier session never asks.
  ShopUnreadCount? _shopUnread;

  @override
  void initState() {
    super.initState();
    if (_readingShop) {
      _readShop();
    } else {
      _syncBadges();
    }
  }

  /// Reads the merchant's shops and picks the Merchant Hub they need: the services rail when every shop
  /// is a services shop; the goods rail with the services shop's queue and offers appended when there
  /// is one of each ([PortalArea.merchantWithServices_]); and otherwise the goods rail it always drew.
  ///
  /// A read that fails picks nothing: the shell says so and offers a retry and sign-out. A goods rail
  /// guessed for a print shop would stand there all session, till and shelves and all.
  Future<void> _readShop() async {
    final List<Store> owned;
    try {
      owned = (await widget.apis.store.mine(size: 20)).content;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _readingShop = false;
        _shopReadFailed = true;
      });
      return;
    }
    if (!mounted) return;
    bool isServices(Store store) => store.vertical == StoreVertical.services;
    final PortalArea hub = owned.isNotEmpty && owned.every(isServices)
        ? PortalArea.merchantServices_
        : owned.any(isServices)
            ? PortalArea.merchantWithServices_
            : PortalArea.merchant_;
    setState(() {
      _areas = <PortalArea>[
        for (final PortalArea area in widget.areas)
          identical(area, PortalArea.merchant_) ? hub : area,
      ];
      _readingShop = false;
    });
    _syncBadges();
  }

  void _retryShop() {
    setState(() {
      _readingShop = true;
      _shopReadFailed = false;
    });
    _readShop();
  }

  @override
  void dispose() {
    _shopUnread?.removeListener(_badgeChanged);
    _shopUnread?.dispose();
    super.dispose();
  }

  void _switchArea(int area) {
    setState(() {
      _area = area;
      // Back to the first destination. Carrying the index across would land on whatever page
      // happened to share that position in the other area.
      _index = 0;
      _page = 0;
    });
    _syncBadges();
  }

  void _open(int index, {int page = 0}) {
    setState(() {
      _index = index;
      _page = page;
    });
  }

  /// Starts or stops the numbers the current area's rail shows.
  ///
  /// The portal has no socket, so [ShopUnreadCount] polls: once a minute, and only while the tab is
  /// on screen. Without it a merchant working here had no sign a customer had written until they
  /// opened the inbox and pulled to refresh — a gesture a mouse cannot make.
  void _syncBadges() {
    final bool wanted = _areas[_area].destinations
        .any((PortalDestination d) => d.badge == PortalBadge.shopUnread);
    final ShopUnreadCount? current = _shopUnread;
    if (wanted && current == null) {
      _shopUnread = ShopUnreadCount(api: widget.apis.shopChat)
        ..addListener(_badgeChanged)
        ..start();
    } else if (!wanted && current != null) {
      current.removeListener(_badgeChanged);
      current.dispose();
      _shopUnread = null;
    }
  }

  void _badgeChanged() {
    if (mounted) setState(() {});
  }

  ConsoleNavEntry _entry(PortalDestination destination, DeliveryStrings t) {
    final int? count = switch (destination.badge) {
      PortalBadge.shopUnread => _shopUnread?.value,
      null => null,
    };
    return ConsoleNavEntry(
      icon: destination.icon,
      label: destination.label(t),
      children: <String>[for (final PortalPage p in destination.pages) p.label(t)],
      badgeCount: count,
      badgeLabel: count == null ? null : t.chatShopUnreadCount(count),
    );
  }

  void _select(PortalArea area, int index, {int page = 0}) {
    final bool leavingBadged = area.destinations[_index].badge != null;
    _open(index, page: page);
    // Reading conversations is what changes the count: ask as the merchant leaves them, not a minute
    // later.
    final ShopUnreadCount? unread = _shopUnread;
    if (leavingBadged && unread != null) unawaited(unread.refresh());
  }

  /// The sidebar footer's menu: the two things that used to live in the crimson AppBar.
  ///
  /// The design's footer card is user information and nothing else, and the console has no app bar
  /// to put these back into — the rail *is* the chrome. Hanging them off the card that already
  /// names the account is the closest reading of the design that still leaves a signed-in user a
  /// way to change language or leave.
  Widget _accountMenu(DeliveryStrings t) {
    // Boxed to 24: an unconstrained PopupMenuButton is an IconButton with a 48px minimum, which
    // would push the footer card from the design's 60 to 72.
    return SizedBox(
      width: 24,
      height: 24,
      child: PopupMenuButton<String>(
        tooltip: t.language,
        position: PopupMenuPosition.under,
        icon: const Icon(Icons.unfold_more, size: 16, color: DeliveryColors.onShellMuted),
        padding: EdgeInsets.zero,
        onSelected: (String value) {
          if (value == _signOutValue) {
            widget.onSignOut();
          } else {
            widget.locale.setLanguage(value);
          }
        },
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
          // Each language named in its own script, which is what makes the menu readable to
          // somebody who cannot read the language currently on screen.
          CheckedPopupMenuItem<String>(
            value: 'en',
            checked: !widget.locale.isArabic,
            child: Text(t.english),
          ),
          CheckedPopupMenuItem<String>(
            value: 'ar',
            checked: widget.locale.isArabic,
            child: Text(t.arabic),
          ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: _signOutValue,
            child: Row(
              children: <Widget>[
                const Icon(Icons.logout, size: 16, color: DeliveryColors.muted),
                const SizedBox(width: DeliverySpacing.sm),
                Text(t.signOut),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const String _signOutValue = '__sign_out__';

  /// What stands in for the rail while the merchant's shops are read, and when they could not be: a
  /// spinner, or a plain statement with a retry. Sign-out is on both, so a slow or failing read never
  /// leaves anybody without a way out.
  Widget _shopGate(DeliveryStrings t) {
    final Widget signOut = TextButton(onPressed: () => widget.onSignOut(), child: Text(t.signOut));
    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: Center(
        child: _shopReadFailed
            ? YdEmptyState(
                icon: Icons.storefront_outlined,
                title: t.svcShopReadFailed,
                message: t.thatDidNotGoThrough,
                action: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    YdPillButton(label: t.tryAgain, onPressed: _retryShop, expand: false),
                    const SizedBox(height: DeliverySpacing.sm),
                    signOut,
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CircularProgressIndicator(color: DeliveryColors.brand),
                  const SizedBox(height: DeliverySpacing.lg),
                  signOut,
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    if (_readingShop || _shopReadFailed) return _shopGate(t);
    final PortalArea area = _areas[_area];

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ConsoleSidebar(
            area: ConsoleArea(wordmark: area.wordmark, logoIcon: area.logoIcon),
            areas: <ConsoleArea>[
              for (final PortalArea a in _areas)
                ConsoleArea(wordmark: a.wordmark, logoIcon: a.logoIcon),
            ],
            areaIndex: _area,
            onAreaSelected: _areas.length > 1 ? _switchArea : null,
            entries: <ConsoleNavEntry>[
              for (final PortalDestination d in area.destinations) _entry(d, t),
            ],
            selectedIndex: _index,
            onSelected: (int i) => _select(area, i),
            selectedChild: _page,
            onChildSelected: (int i, int page) => _select(area, i, page: page),
            userName: widget.session.displayName,
            userRole: area.accountRole(t),
            accountMenu: _accountMenu(t),
          ),
          Expanded(
            child: area.destinations[_index].buildPage(
              _page,
              widget.apis,
              widget.locale,
              widget.onSignOut,
              (int i) => _open(i),
            ),
          ),
        ],
      ),
    );
  }
}
