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
import 'backoffice/offers_screen.dart';
import 'backoffice/onboarding_screen.dart';
import 'backoffice/overview_screen.dart';
import 'backoffice/promotions_screen.dart';
import 'backoffice/providers_screen.dart';
import 'backoffice/reconciliation_screen.dart';
import 'backoffice/riders_screen.dart';
import 'backoffice/settings_screen.dart';
import 'backoffice/statements_screen.dart';
// Prefixed: this and delivery_merchant's ZonesScreen share a name and are different pages — the
// Backoffice one administers platform-wide areas, the merchant one picks which of them a shop
// delivers to. The prefix goes on this one because it is the local file of the two.
import 'backoffice/zones_screen.dart' as backoffice;
import 'carrier/applicants_screen.dart';
import 'carrier/company_screen.dart';
import 'carrier/dashboard_screen.dart';
import 'carrier/earnings_screen.dart';
import 'carrier/jobs_screen.dart';
// No prefix needed: this file's class is `CarrierSettingsScreen`, distinct from the Backoffice
// `SettingsScreen` imported above, because the two administer entirely different things.
import 'carrier/settings_screen.dart';
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
  });

  final CatalogApi catalog;
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
}

/// One destination in a rail.
class PortalDestination {
  const PortalDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.build,
  });

  final IconData icon;
  final IconData selectedIcon;

  /// Resolved against the active locale rather than stored, so switching language re-labels the
  /// rail without rebuilding the area list.
  final String Function(DeliveryStrings) label;

  /// `jump` moves the rail — the dashboards use it for "see all orders" style links, which is why
  /// this takes a callback rather than returning a bare widget.
  final Widget Function(PortalApis apis, LocaleController locale,
      Future<void> Function() onSignOut, void Function(int) jump) build;
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
  final String accountRole;

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
    accountRole: 'Merchant partner',
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
        build: (PortalApis a, _, __, ___) => ProductListScreen(api: a.catalog),
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
    ],
  );

  // ------------------------------------------------------------------- carrier
  //
  // In the order a company thinks about its day: how are we doing, what are we carrying, what will
  // we be paid, who rides for us, who is waiting to be hired, and how are we set up.
  //
  // The 2026-08 Figma carrier rail (3:3438) draws four items — Dashboard, Riders, Onboarding,
  // Settings — and this one has six. The two extra are Jobs and Earnings, which answer the two
  // questions a delivery company actually opens the portal to ask and which the design has no
  // frame for; dropping them to match a four-item rail would delete working pages. Their glyphs and
  // the order around them follow the design.
  static final PortalArea carrier_ = PortalArea(
    role: DeliveryRole.carrier,
    title: (DeliveryStrings t) => t.carrierPortal,
    wordmark: 'Carrier Hub',
    accountRole: 'Carrier partner',
    logoIcon: Icons.local_shipping,
    destinations: <PortalDestination>[
      PortalDestination(
        icon: Icons.insights_outlined,
        selectedIcon: Icons.insights,
        label: (DeliveryStrings t) => t.navDashboard,
        build: (PortalApis a, _, __, void Function(int) jump) => CarrierDashboardScreen(
          api: a.order,
          providerApi: a.provider,
          onShowJobs: () => jump(1),
        ),
      ),
      PortalDestination(
        icon: Icons.local_shipping_outlined,
        selectedIcon: Icons.local_shipping,
        label: (DeliveryStrings t) => t.navJobs,
        build: (PortalApis a, _, __, ___) => JobsScreen(api: a.order),
      ),
      PortalDestination(
        icon: Icons.payments_outlined,
        selectedIcon: Icons.payments,
        label: (DeliveryStrings t) => t.navEarnings,
        build: (PortalApis a, _, __, ___) => EarningsScreen(api: a.order),
      ),
      // Immediately after Earnings, because the two are the same money asked about twice: Earnings
      // is the rolling window off the order service, this is the ledger's own arithmetic for a
      // closed period — the figures the platform would actually pay against.
      //
      // An inline English label rather than a [DeliveryStrings] key, matching Riders and Promo Codes
      // in the Backoffice rail: the console screens are English-only in this wave.
      PortalDestination(
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
        label: (DeliveryStrings _) => 'Statement',
        build: (PortalApis a, _, __, ___) => CarrierStatementScreen(api: a.statements),
      ),
      // The design's `users-round` glyph. This is the fleet page — the company's own record is on
      // Settings now, where the design puts it.
      PortalDestination(
        icon: Icons.groups_outlined,
        selectedIcon: Icons.groups,
        label: (DeliveryStrings t) => t.navCompany,
        build: (PortalApis a, _, __, ___) =>
            CompanyScreen(api: a.provider, orderApi: a.order),
      ),
      // Immediately after the fleet, as drawn. Hiring is occasional and must not be missed:
      // somebody is waiting to be told yes or no, which is not true of any other page here.
      PortalDestination(
        icon: Icons.description_outlined,
        selectedIcon: Icons.description,
        label: (DeliveryStrings t) => t.navApplicants,
        build: (PortalApis a, _, __, ___) => ApplicantsScreen(
          api: a.onboarding,
          providerApi: a.provider,
          documentsApi: a.documents,
        ),
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

  // ---------------------------------------------------------------- backoffice
  static final PortalArea backoffice_ = PortalArea(
    role: DeliveryRole.backoffice,
    title: (DeliveryStrings t) => t.backoffice,
    wordmark: 'Backoffice',
    accountRole: 'Backoffice operator',
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
        build: (PortalApis a, _, __, ___) =>
            DashboardScreen(api: a.order, notificationApi: a.notification),
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
        build: (PortalApis a, _, __, ___) => ReconciliationScreen(api: a.accounting),
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
      // Last, and deliberately so: the least-used and most consequential page here.
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
  int _area = 0;
  int _index = 0;

  void _switchArea(int area) {
    setState(() {
      _area = area;
      // Back to the first destination. Carrying the index across would land on whatever page
      // happened to share that position in the other area.
      _index = 0;
    });
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

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final PortalArea area = widget.areas[_area];

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ConsoleSidebar(
            area: ConsoleArea(wordmark: area.wordmark, logoIcon: area.logoIcon),
            areas: <ConsoleArea>[
              for (final PortalArea a in widget.areas)
                ConsoleArea(wordmark: a.wordmark, logoIcon: a.logoIcon),
            ],
            areaIndex: _area,
            onAreaSelected: widget.areas.length > 1 ? _switchArea : null,
            entries: <ConsoleNavEntry>[
              for (final PortalDestination d in area.destinations)
                ConsoleNavEntry(icon: d.icon, label: d.label(t)),
            ],
            selectedIndex: _index,
            onSelected: (int i) => setState(() => _index = i),
            userName: widget.session.displayName,
            userRole: area.accountRole,
            accountMenu: _accountMenu(t),
          ),
          Expanded(
            child: area.destinations[_index].build(
              widget.apis,
              widget.locale,
              widget.onSignOut,
              (int i) => setState(() => _index = i),
            ),
          ),
        ],
      ),
    );
  }
}
