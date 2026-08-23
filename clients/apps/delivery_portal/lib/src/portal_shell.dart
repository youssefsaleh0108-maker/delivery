import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'backoffice/banners_screen.dart';
import 'backoffice/catalog_screen.dart';
import 'backoffice/categories_screen.dart';
import 'backoffice/dashboard_screen.dart';
import 'backoffice/offers_screen.dart';
import 'backoffice/onboarding_screen.dart';
import 'backoffice/providers_screen.dart';
import 'backoffice/reconciliation_screen.dart';
import 'backoffice/settings_screen.dart';
// Prefixed: both areas have a ZonesScreen, and they are different pages — the Backoffice one
// administers platform-wide areas, the merchant one picks which of them a shop delivers to.
import 'backoffice/zones_screen.dart' as backoffice;
import 'carrier/applicants_screen.dart';
import 'carrier/company_screen.dart';
import 'carrier/dashboard_screen.dart';
import 'carrier/earnings_screen.dart';
import 'carrier/jobs_screen.dart';
import 'merchant/dashboard_screen.dart';
import 'merchant/delivery_screen.dart';
import 'merchant/orders_screen.dart';
import 'merchant/product_list_screen.dart';
import 'merchant/store_screen.dart';
import 'merchant/whatsapp_screen.dart';
import 'merchant/zones_screen.dart' as merchant;

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
    required this.destinations,
  });

  final DeliveryRole role;
  final String Function(DeliveryStrings) title;
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
            merchant.ZonesScreen(api: a.zone, storeApi: a.store),
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
  // we be paid, who is waiting to be hired, and who are we.
  static final PortalArea carrier_ = PortalArea(
    role: DeliveryRole.carrier,
    title: (DeliveryStrings t) => t.carrierPortal,
    destinations: <PortalDestination>[
      PortalDestination(
        icon: Icons.insights_outlined,
        selectedIcon: Icons.insights,
        label: (DeliveryStrings t) => t.navDashboard,
        build: (PortalApis a, _, __, void Function(int) jump) => CarrierDashboardScreen(
          api: a.order,
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
      // Before Company, after the day-to-day pages. Hiring is occasional and must not be missed:
      // somebody is waiting to be told yes or no, which is not true of any other page here.
      PortalDestination(
        icon: Icons.person_search_outlined,
        selectedIcon: Icons.person_search,
        label: (DeliveryStrings t) => t.navApplicants,
        build: (PortalApis a, _, __, ___) =>
            ApplicantsScreen(api: a.onboarding, providerApi: a.provider),
      ),
      PortalDestination(
        icon: Icons.business_outlined,
        selectedIcon: Icons.business,
        label: (DeliveryStrings t) => t.navCompany,
        build: (PortalApis a, LocaleController locale,
                Future<void> Function() onSignOut, ___) =>
            CompanyScreen(api: a.provider, locale: locale, onSignOut: onSignOut),
      ),
    ],
  );

  // ---------------------------------------------------------------- backoffice
  static final PortalArea backoffice_ = PortalArea(
    role: DeliveryRole.backoffice,
    title: (DeliveryStrings t) => t.backoffice,
    destinations: <PortalDestination>[
      // Orders first: monitoring live operations is what a Backoffice user opens this for.
      PortalDestination(
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
        label: (DeliveryStrings t) => t.navOrders,
        build: (PortalApis a, _, __, ___) => DashboardScreen(api: a.order),
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
        build: (PortalApis a, _, __, ___) => OnboardingScreen(api: a.onboarding),
      ),
      // Beside Finance: who carries orders is an operating question, and the money split that
      // follows from it is right next door.
      PortalDestination(
        icon: Icons.local_shipping_outlined,
        selectedIcon: Icons.local_shipping,
        label: (DeliveryStrings t) => t.navCarriers,
        build: (PortalApis a, _, __, ___) => ProvidersScreen(api: a.provider),
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
      // Immediately after Finance, because that is what an offer spends.
      PortalDestination(
        icon: Icons.redeem_outlined,
        selectedIcon: Icons.redeem,
        label: (DeliveryStrings t) => t.navOffers,
        build: (PortalApis a, _, __, ___) => OffersScreen(api: a.offer),
      ),
      // Last, and deliberately so: the least-used and most consequential page here.
      PortalDestination(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: (DeliveryStrings t) => t.navSettings,
        build: (PortalApis a, _, __, ___) =>
            SettingsScreen(api: a.settings, rateApi: a.rate),
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
    required this.onSignOut,
  });

  final List<PortalArea> areas;
  final PortalApis apis;
  final LocaleController locale;
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

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final PortalArea area = widget.areas[_area];

    return Scaffold(
      appBar: AppBar(
        title: DeliveryWordmark(title: area.title(t)),
        actions: <Widget>[
          if (widget.areas.length > 1)
            PopupMenuButton<int>(
              icon: const Icon(Icons.swap_horiz),
              tooltip: t.switchArea,
              initialValue: _area,
              onSelected: _switchArea,
              itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
                for (int i = 0; i < widget.areas.length; i++)
                  PopupMenuItem<int>(value: i, child: Text(widget.areas[i].title(t))),
              ],
            ),
          // In the bar rather than buried in a settings page: two of the three areas have no
          // settings page, and someone who cannot read the English one cannot navigate to where
          // the switch would be.
          PopupMenuButton<String>(
            icon: const Icon(Icons.language),
            tooltip: t.language,
            initialValue: widget.locale.isArabic ? 'ar' : 'en',
            onSelected: widget.locale.setLanguage,
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              // Each language named in its own script, which is what makes the menu readable to
              // somebody who cannot read the language currently on screen.
              PopupMenuItem<String>(value: 'en', child: Text(t.english)),
              PopupMenuItem<String>(value: 'ar', child: Text(t.arabic)),
            ],
          ),
          IconButton(
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout),
            tooltip: t.signOut,
          ),
        ],
      ),
      body: Row(
        children: <Widget>[
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (int i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            indicatorColor: DeliveryColors.brandSoft,
            destinations: <NavigationRailDestination>[
              for (final PortalDestination d in area.destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon, color: DeliveryColors.brand),
                  label: Text(d.label(t)),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
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
