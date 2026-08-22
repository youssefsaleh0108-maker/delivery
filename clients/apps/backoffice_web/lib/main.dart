import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
// Safe to import directly: this target is only ever compiled for the web.
import 'package:web/web.dart' as web;

import 'src/banners_screen.dart';
import 'src/catalog_screen.dart';
import 'src/categories_screen.dart';
import 'src/dashboard_screen.dart';
import 'src/offers_screen.dart';
import 'src/onboarding_screen.dart';
import 'src/providers_screen.dart';
import 'src/reconciliation_screen.dart';
import 'src/settings_screen.dart';
import 'src/zones_screen.dart';

/// Backoffice Web App — `BACKOFFICE` role only (Section 9).
///
/// Phase 1 surface: the platform-wide category taxonomy (which only BACKOFFICE may change) and a
/// read-only view of every merchant's live catalog. The monitoring dashboard arrives in Phase 2,
/// Connector Settings in Phase 3, reconciliation in Phase 4.
void main() {
  runApp(const BackofficeApp());
}

/// Must match `KEYCLOAK_PUBLIC_URL` in `infra/.env` — see merchant_portal/lib/main.dart.
const String _issuer = String.fromEnvironment(
  'KEYCLOAK_ISSUER',
  defaultValue: 'http://127.0.0.1:8180/realms/delivery-platform',
);
const String _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8100',
);

/// The app's own origin, read at runtime — see merchant_portal/lib/main.dart for why this is not a
/// hardcoded constant. Port 5011, not 8081: the lending stack already holds 8080-8095.
String _redirectUrl() {
  const String override = String.fromEnvironment('OIDC_REDIRECT_URL');
  if (override.isNotEmpty) {
    return override;
  }
  return '${web.window.location.origin}/';
}

class BackofficeApp extends StatefulWidget {
  const BackofficeApp({super.key});

  @override
  State<BackofficeApp> createState() => _BackofficeAppState();
}

class _BackofficeAppState extends State<BackofficeApp> {
  late final AuthService _authService = AuthService(
    config: AuthConfig(
      issuer: _issuer,
      clientId: 'backoffice-web',
      redirectUrl: _redirectUrl(),
    ),
  );

  late final Dio _dio = ApiClient.create(
    baseUrl: _apiBaseUrl,
    authService: _authService,
  );

  late final CatalogApi _catalogApi = CatalogApi(_dio);
  late final OrderApi _orderApi = OrderApi(_dio);
  late final ConnectorSettingsApi _settingsApi = ConnectorSettingsApi(_dio);
  late final AccountingApi _accountingApi = AccountingApi(_dio);
  late final DeliveryRateApi _rateApi = DeliveryRateApi(_dio);
  late final BannerApi _bannerApi = BannerApi(_dio);
  late final DeliveryProviderApi _providerApi = DeliveryProviderApi(_dio);
  late final DeliveryZoneApi _zoneApi = DeliveryZoneApi(_dio);
  late final OfferApi _offerApi = OfferApi(_dio);
  late final OnboardingApi _onboardingApi = OnboardingApi(_dio);

  late Future<AuthSession?> _bootstrap = _authService.restore();
  bool _signingIn = false;

  Future<void> _signIn() async {
    setState(() => _signingIn = true);
    try {
      // On web this navigates away and never returns; the session appears via restore() on the
      // next load. On mobile/desktop it completes here.
      final AuthSession? session = await _authService.signIn();
      if (session != null && mounted) {
        setState(() {
          _bootstrap = Future<AuthSession?>.value(session);
          _signingIn = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _signingIn = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sign-in failed')));
    }
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    setState(() {
      // Block body, not an arrow: `() => x = Future...` RETURNS that Future, and setState
      // asserts its callback returns nothing.
      _bootstrap = Future<AuthSession?>.value(null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Delivery Backoffice',
      theme: DeliveryTheme.light(),
      debugShowCheckedModeBanner: false,
      home: FutureBuilder<AuthSession?>(
        future: _bootstrap,
        builder: (BuildContext context, AsyncSnapshot<AuthSession?> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return _MessageScreen(
              icon: Icons.error_outline,
              message: 'Sign-in failed: ${snapshot.error}',
              actionLabel: 'Try again',
              onAction: _signIn,
            );
          }

          final AuthSession? session = snapshot.data;
          if (session == null) {
            return _SignInScreen(onSignIn: _signIn, busy: _signingIn);
          }

          // Product Service and (from Phase 3) Connector Settings enforce this server-side. The
          // check here only avoids showing a shell whose every request would come back 403.
          if (!session.hasRole(DeliveryRole.backoffice)) {
            return _MessageScreen(
              icon: Icons.lock_outline,
              message: 'This account does not have Backoffice access.',
              actionLabel: 'Sign in as someone else',
              onAction: _signOut,
            );
          }

          return _BackofficeShell(
            api: _catalogApi,
            orderApi: _orderApi,
            settingsApi: _settingsApi,
            accountingApi: _accountingApi,
            rateApi: _rateApi,
            bannerApi: _bannerApi,
            providerApi: _providerApi,
            zoneApi: _zoneApi,
            offerApi: _offerApi,
            onboardingApi: _onboardingApi,
            onSignOut: _signOut,
          );
        },
      ),
    );
  }
}

class _BackofficeShell extends StatefulWidget {
  const _BackofficeShell({
    required this.api,
    required this.orderApi,
    required this.settingsApi,
    required this.accountingApi,
    required this.rateApi,
    required this.bannerApi,
    required this.providerApi,
    required this.zoneApi,
    required this.offerApi,
    required this.onboardingApi,
    required this.onSignOut,
  });

  final CatalogApi api;
  final OrderApi orderApi;
  final ConnectorSettingsApi settingsApi;
  final AccountingApi accountingApi;
  final DeliveryRateApi rateApi;
  final BannerApi bannerApi;
  final DeliveryProviderApi providerApi;
  final DeliveryZoneApi zoneApi;
  final OfferApi offerApi;
  final OnboardingApi onboardingApi;
  final Future<void> Function() onSignOut;

  @override
  State<_BackofficeShell> createState() => _BackofficeShellState();
}

class _BackofficeShellState extends State<_BackofficeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const DeliveryWordmark(title: 'Delivery Backoffice'),
        actions: <Widget>[
          IconButton(
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
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
            destinations: const <NavigationRailDestination>[
              // Orders first: monitoring live operations is what a Backoffice user opens this for.
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard, color: DeliveryColors.brand),
                label: Text('Orders'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.category_outlined),
                selectedIcon: Icon(Icons.category, color: DeliveryColors.brand),
                label: Text('Categories'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.inventory_2_outlined),
                selectedIcon: Icon(Icons.inventory_2, color: DeliveryColors.brand),
                label: Text('Catalog'),
              ),
              // Next to Categories, because the two pages edit the same home screen: what the
              // strip is made of, and what sits above it.
              NavigationRailDestination(
                icon: Icon(Icons.view_carousel_outlined),
                selectedIcon: Icon(Icons.view_carousel, color: DeliveryColors.brand),
                label: Text('Banners'),
              ),
              // Before Carriers, because this is where a carrier — or a shop — comes from.
              // A waiting application is the only thing in this rail with somebody on the other end
              // of it, so it sits above the pages that manage what they become.
              NavigationRailDestination(
                icon: Icon(Icons.how_to_reg_outlined),
                selectedIcon: Icon(Icons.how_to_reg, color: DeliveryColors.brand),
                label: Text('Onboarding'),
              ),
              // Beside Finance: who carries orders is an operating question, and the money split
              // that follows from it is right next door.
              NavigationRailDestination(
                icon: Icon(Icons.local_shipping_outlined),
                selectedIcon: Icon(Icons.local_shipping, color: DeliveryColors.brand),
                label: Text('Carriers'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.map_outlined),
                selectedIcon: Icon(Icons.map, color: DeliveryColors.brand),
                label: Text('Areas'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.account_balance_outlined),
                selectedIcon: Icon(Icons.account_balance, color: DeliveryColors.brand),
                label: Text('Finance'),
              ),
              // Immediately after Finance, because that is what an offer spends. Its budget is read
              // off the same revenue the reconciliation page reports.
              NavigationRailDestination(
                icon: Icon(Icons.redeem_outlined),
                selectedIcon: Icon(Icons.redeem, color: DeliveryColors.brand),
                label: Text('Offers'),
              ),
              // Last, and deliberately so: it is the least-used and most consequential page here.
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings, color: DeliveryColors.brand),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: switch (_index) {
              0 => DashboardScreen(api: widget.orderApi),
              1 => CategoriesScreen(api: widget.api),
              2 => CatalogScreen(api: widget.api),
              3 => BannersScreen(api: widget.bannerApi, catalogApi: widget.api),
              4 => OnboardingScreen(api: widget.onboardingApi),
              5 => ProvidersScreen(api: widget.providerApi),
              6 => ZonesScreen(api: widget.zoneApi),
              7 => ReconciliationScreen(api: widget.accountingApi),
              8 => OffersScreen(api: widget.offerApi),
              _ => SettingsScreen(api: widget.settingsApi, rateApi: widget.rateApi),
            },
          ),
        ],
      ),
    );
  }
}

class _SignInScreen extends StatelessWidget {
  const _SignInScreen({required this.onSignIn, required this.busy});

  final Future<void> Function() onSignIn;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: SoftCard(
            padding: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(DeliverySpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(DeliverySpacing.md),
                    decoration: const BoxDecoration(
                      color: DeliveryColors.brandSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.admin_panel_settings,
                        size: 32, color: DeliveryColors.brand),
                  ),
                  const SizedBox(height: DeliverySpacing.md),
                  Text('Backoffice', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: DeliverySpacing.xs),
                  Text('Platform administration',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: DeliverySpacing.xl),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: busy ? null : onSignIn,
                      child: Text(busy ? 'Signing in…' : 'Sign in'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageScreen extends StatelessWidget {
  const _MessageScreen({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(DeliverySpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 40, color: DeliveryColors.muted),
              const SizedBox(height: DeliverySpacing.md),
              Text(message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: DeliverySpacing.md),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}
