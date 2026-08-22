import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
// Safe to import directly: this target is only ever compiled for the web.
import 'package:web/web.dart' as web;

import 'src/dashboard_screen.dart';
import 'src/delivery_screen.dart';
import 'src/orders_screen.dart';
import 'src/store_screen.dart';
import 'src/zones_screen.dart';
import 'src/product_list_screen.dart';
import 'src/whatsapp_screen.dart';

/// Merchant Web Portal — `MERCHANT` role only (Section 9).
///
/// Phase 1 MVP: sign in with Keycloak, then register and manage your own products including their
/// images. Order management arrives with Order Manager in Phase 2.
void main() {
  runApp(const MerchantPortalApp());
}

/// Must match `KEYCLOAK_PUBLIC_URL` in `infra/.env` — that is the issuer Keycloak stamps into
/// tokens, and the backend rejects anything else.
///
/// 127.0.0.1, not a LAN IP and not `localhost`: a LAN IP moves with DHCP and needs an inbound
/// firewall rule, and `localhost` resolves to ::1 first, where Docker Desktop's wslredirector
/// shadows the port and resets the connection. Loopback avoids all three.
///
/// Physical-device testing needs the LAN IP instead — see clients/README.md, and override with
/// --dart-define rather than editing this.
const String _issuer = String.fromEnvironment(
  'KEYCLOAK_ISSUER',
  defaultValue: 'http://127.0.0.1:8180/realms/delivery-platform',
);
const String _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8100',
);

/// The app's own origin, read at runtime rather than hardcoded.
///
/// On web the redirect lands back on the app itself and `AuthService.restore` redeems the
/// authorization code from the URL on that next load, so no separate callback page is needed.
///
/// Deriving this from `window.location.origin` means the app works on whichever host you actually
/// opened it with — `127.0.0.1:5010`, `localhost:5010`, or the LAN IP — instead of failing with
/// `invalid redirect_uri` whenever that differs from a baked-in constant. Every host you intend to
/// use still has to be registered on the `merchant-portal` Keycloak client, because Keycloak
/// matches redirect URIs against an allow-list and its wildcards only work at the END of a URI.
String _redirectUrl() {
  const String override = String.fromEnvironment('OIDC_REDIRECT_URL');
  if (override.isNotEmpty) {
    return override;
  }
  return '${web.window.location.origin}/';
}

class MerchantPortalApp extends StatefulWidget {
  const MerchantPortalApp({super.key});

  @override
  State<MerchantPortalApp> createState() => _MerchantPortalAppState();
}

class _MerchantPortalAppState extends State<MerchantPortalApp> {
  late final AuthService _authService = AuthService(
    config: AuthConfig(
      issuer: _issuer,
      clientId: 'merchant-portal',
      redirectUrl: _redirectUrl(),
    ),
  );

  /// Built once and shared: the auth interceptor holds the refresh queue, so a second Dio would
  /// mean two independent refresh races on the same session.
  late final Dio _dio = ApiClient.create(
    baseUrl: _apiBaseUrl,
    authService: _authService,
  );

  late final CatalogApi _catalogApi = CatalogApi(_dio);
  late final OrderApi _orderApi = OrderApi(_dio);
  late final StoreApi _storeApi = StoreApi(_dio);
  late final DeliveryProviderApi _providerApi = DeliveryProviderApi(_dio);
  late final DeliveryZoneApi _zoneApi = DeliveryZoneApi(_dio);
  late final WhatsAppApi _whatsAppApi = WhatsAppApi(_dio);

  /// The chosen language, remembered across sessions.
  ///
  /// Kept in secure storage alongside the session for the same reason the customer app does it:
  /// there is nowhere else on web that survives a reload, and a merchant who picked Arabic once
  /// should not have to pick it again every morning.
  late final LocaleController _locale = LocaleController(
    read: () => const FlutterSecureStorage().read(key: 'delivery.locale'),
    write: (String code) =>
        const FlutterSecureStorage().write(key: 'delivery.locale', value: code),
  );

  late Future<AuthSession?> _bootstrap = _authService.restore();
  bool _signingIn = false;

  @override
  void initState() {
    super.initState();
    // Not awaited: the first frame renders in the device language and switches when the saved
    // preference arrives, rather than holding the app on a blank screen for a disk read.
    _locale.load();
  }

  Future<void> _signIn() async {
    setState(() => _signingIn = true);
    try {
      await _authService.signIn();
      setState(() {
        _bootstrap = Future<AuthSession?>.value(_authService.session);
        _signingIn = false;
      });
    } catch (e) {
      setState(() => _signingIn = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(DeliveryStrings.of(context).signInFailedShort)));
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
    return AnimatedBuilder(
      animation: _locale,
      builder: (BuildContext context, _) => MaterialApp(
      onGenerateTitle: (BuildContext context) => DeliveryStrings.of(context).merchantPortal,
      theme: DeliveryTheme.light(),
      debugShowCheckedModeBanner: false,
      // Null follows the device; an explicit choice overrides it. Flutter flips the whole tree to
      // RTL from the locale alone, so nothing below has to know about direction.
      locale: _locale.locale,
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: FutureBuilder<AuthSession?>(
        future: _bootstrap,
        builder: (BuildContext context, AsyncSnapshot<AuthSession?> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }

          final AuthSession? session = snapshot.data;
          if (session == null) {
            return _SignInScreen(onSignIn: _signIn, busy: _signingIn);
          }

          // Server-side, Product Service enforces both the MERCHANT role and per-row ownership
          // against the `sub` claim. This check only avoids showing a shell whose every request
          // would come back 403.
          if (!session.hasRole(DeliveryRole.merchant)) {
            return _NotAMerchantScreen(onSignOut: _signOut);
          }

          return _PortalShell(
            api: _catalogApi,
            orderApi: _orderApi,
            storeApi: _storeApi,
            providerApi: _providerApi,
            zoneApi: _zoneApi,
            whatsAppApi: _whatsAppApi,
            session: session,
            locale: _locale,
            onSignOut: _signOut,
          );
        },
      ),
      ),
    );
  }
}

class _PortalShell extends StatefulWidget {
  const _PortalShell({
    required this.api,
    required this.orderApi,
    required this.storeApi,
    required this.providerApi,
    required this.zoneApi,
    required this.whatsAppApi,
    required this.session,
    required this.locale,
    required this.onSignOut,
  });

  final CatalogApi api;
  final OrderApi orderApi;
  final StoreApi storeApi;
  final DeliveryProviderApi providerApi;
  final DeliveryZoneApi zoneApi;
  final WhatsAppApi whatsAppApi;
  final AuthSession session;
  final LocaleController locale;
  final Future<void> Function() onSignOut;

  @override
  State<_PortalShell> createState() => _PortalShellState();
}

class _PortalShellState extends State<_PortalShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: DeliveryWordmark(title: t.merchantPortal),
        actions: <Widget>[
          // In the bar rather than buried in a settings page: this portal has no settings page, and
          // a merchant who cannot read the English one cannot navigate to where the switch would be.
          PopupMenuButton<String>(
            icon: const Icon(Icons.language),
            tooltip: t.language,
            initialValue: widget.locale.isArabic ? 'ar' : 'en',
            onSelected: widget.locale.setLanguage,
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              // Each language is named in its own script, which is what makes the menu readable to
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
              // First, and ahead of the catalog that used to be. A shop opening the portal wants to
              // know what came in overnight and whether yesterday was any good; the menu is what
              // they came to edit only on the days they are editing it.
              NavigationRailDestination(
                icon: const Icon(Icons.insights_outlined),
                selectedIcon: const Icon(Icons.insights, color: DeliveryColors.brand),
                label: Text(t.navDashboard),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.inventory_2_outlined),
                selectedIcon: const Icon(Icons.inventory_2, color: DeliveryColors.brand),
                label: Text(t.navProducts),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.receipt_long_outlined),
                selectedIcon: const Icon(Icons.receipt_long, color: DeliveryColors.brand),
                label: Text(t.navOrders),
              ),
              // Immediately after Orders, because for most shops here it is where orders come
              // from. A merchant already spends their day in this thread; the portal's job is to
              // put the catalog and the rider next to it, not to move them somewhere else.
              NavigationRailDestination(
                icon: const Icon(Icons.chat_outlined),
                selectedIcon: const Icon(Icons.chat, color: DeliveryColors.brand),
                label: Text(t.navWhatsApp),
              ),
              // Between Orders and the shop itself: choosing a carrier is an operating decision
              // about orders, not a detail of the shopfront.
              NavigationRailDestination(
                icon: const Icon(Icons.local_shipping_outlined),
                selectedIcon: const Icon(Icons.local_shipping, color: DeliveryColors.brand),
                label: Text(t.navDelivery),
              ),
              // Next to Delivery, because they answer two halves of one question: who carries the
              // order, and how far you are willing to send them.
              NavigationRailDestination(
                icon: const Icon(Icons.map_outlined),
                selectedIcon: const Icon(Icons.map, color: DeliveryColors.brand),
                label: Text(t.deliveryAreas),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.storefront_outlined),
                selectedIcon: const Icon(Icons.storefront, color: DeliveryColors.brand),
                label: Text(t.navMyShop),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: switch (_index) {
              0 => MerchantDashboardScreen(
                    api: widget.orderApi,
                    onShowOrders: () => setState(() => _index = 2),
                  ),
              1 => ProductListScreen(api: widget.api),
              2 => OrdersScreen(api: widget.orderApi),
              3 => WhatsAppScreen(api: widget.whatsAppApi, catalogApi: widget.api),
              4 => DeliveryScreen(api: widget.providerApi),
              5 => ZonesScreen(api: widget.zoneApi, storeApi: widget.storeApi),
              _ => StoreScreen(api: widget.storeApi),
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
                    child: const Icon(Icons.storefront, size: 32, color: DeliveryColors.brand),
                  ),
                  const SizedBox(height: DeliverySpacing.md),
                  Text(DeliveryStrings.of(context).merchantPortal,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: DeliverySpacing.xs),
                  Text(DeliveryStrings.of(context).manageYourCatalog,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: DeliverySpacing.xl),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: busy ? null : onSignIn,
                      child: Text(busy ? DeliveryStrings.of(context).signingIn : DeliveryStrings.of(context).signIn),
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

class _NotAMerchantScreen extends StatelessWidget {
  const _NotAMerchantScreen({required this.onSignOut});

  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(DeliverySpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.lock_outline, size: 40, color: DeliveryColors.muted),
              const SizedBox(height: DeliverySpacing.md),
              Text(DeliveryStrings.of(context).notAMerchant,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: DeliverySpacing.md),
              OutlinedButton(
                onPressed: onSignOut,
                child: Text(DeliveryStrings.of(context).signInAsSomeoneElse),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
