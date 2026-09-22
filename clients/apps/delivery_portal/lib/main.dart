import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// Safe to import directly: this target is only ever compiled for the web.
import 'package:web/web.dart' as web;

import 'src/portal_shell.dart';
import 'src/sign_in_screen.dart';

/// The Delivery Portal — one web app for Merchant, Carrier and Backoffice.
///
/// It replaces merchant_portal, carrier_portal and backoffice_web, which were three Flutter
/// targets, three Keycloak clients, three builds and three sets of redirect URIs to keep in step.
/// They differed in their destination list and in nothing else: same auth, same Dio, same design
/// system, same shell shape.
///
/// What decides what a user sees is the realm roles in their token, read by [TokenRoles]. Nothing
/// here is a security control — every request is authorised again server-side against the same
/// claim (Section 3). A user with the wrong role sees no navigation for it; a user who forges one
/// sees a rail whose every request comes back 403.
void main() {
  runApp(const DeliveryPortalApp());
}

/// Must match `KEYCLOAK_PUBLIC_URL` in `infra/.env` — that is the issuer Keycloak stamps into
/// tokens, and the backend rejects anything else.
///
/// 127.0.0.1, not a LAN IP and not `localhost`: a LAN IP moves with DHCP and needs an inbound
/// firewall rule, and `localhost` resolves to ::1 first, where Docker Desktop's wslredirector
/// shadows the port and resets the connection.
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
/// opened it with instead of failing with `invalid redirect_uri` whenever that differs from a
/// baked-in constant. Every host you intend to use still has to be registered on the
/// `delivery-portal` Keycloak client, because Keycloak matches redirect URIs against an allow-list
/// and its wildcards only work at the END of a URI.
String _redirectUrl() {
  const String override = String.fromEnvironment('OIDC_REDIRECT_URL');
  if (override.isNotEmpty) {
    return override;
  }
  return '${web.window.location.origin}/';
}

class DeliveryPortalApp extends StatefulWidget {
  const DeliveryPortalApp({super.key});

  @override
  State<DeliveryPortalApp> createState() => _DeliveryPortalAppState();
}

class _DeliveryPortalAppState extends State<DeliveryPortalApp> {
  /// One client for all three audiences, where there used to be three.
  ///
  /// This id has to be in `delivery.security.allowed-client-ids` — the azp allow-list from finding
  /// 1 of the security review — or every request is refused platform-wide. It is seeded in
  /// `infra/postgres/init/03-config-properties.sql`.
  late final AuthService _authService = AuthService(
    config: AuthConfig(
      issuer: _issuer,
      clientId: 'delivery-portal',
      redirectUrl: _redirectUrl(),
    ),
  );

  /// Built once and shared: the auth interceptor holds the refresh queue, so a second Dio would
  /// mean two independent refresh races on the same session.
  late final Dio _dio = ApiClient.create(
    baseUrl: _apiBaseUrl,
    authService: _authService,
  );

  /// Every API the three former portals used, constructed once. A section that a user's roles do
  /// not grant is never built, so the unused ones cost a field and no requests.
  late final PortalApis _apis = PortalApis(
    catalog: CatalogApi(_dio),
    order: OrderApi(_dio),
    store: StoreApi(_dio),
    provider: DeliveryProviderApi(_dio),
    zone: DeliveryZoneApi(_dio),
    whatsApp: WhatsAppApi(_dio),
    settings: ConnectorSettingsApi(_dio),
    accounting: AccountingApi(_dio),
    rate: DeliveryRateApi(_dio),
    banner: BannerApi(_dio),
    offer: OfferApi(_dio),
    onboarding: OnboardingApi(_dio),
    tracking: TrackingApi(_dio),
    promo: PromoApi(_dio),
    documents: DocumentsApi(_dio),
    notification: NotificationApi(_dio),
    aggregates: AggregatesApi(_dio),
    activity: ActivityApi(_dio),
    riderPerformance: RiderPerformanceApi(_dio),
    partnerManagement: PartnerManagementApi(_dio),
    autoApproval: AutoApprovalApi(_dio),
    statements: StatementsApi(_dio),
    pos: PosApi(_dio),
    inventory: InventoryApi(_dio),
    staff: StoreStaffApi(_dio),
    reports: ReportsApi(_dio),
    catalogScan: CatalogScanApi(_dio),
    demand: DemandApi(_dio),
    menuInsights: MenuInsightsApi(_dio),
    shopChat: ShopChatApi(_dio),
    moderation: ChatModerationApi(_dio),
    attachments: OrderAttachmentApi(_dio),
    offerModeration: BackofficeCatalogApi(_dio),
    geocoding: GeocodingApi(_dio),
  );

  /// The chosen language, remembered across sessions. There is nowhere else on web that survives
  /// a reload, and someone who picked Arabic once should not have to pick it again every morning.
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
      // On web this navigates away and never returns; the session appears via restore() on the
      // next load. On mobile/desktop it completes here.
      final AuthSession? session = await _authService.signIn();
      if (session != null && mounted) {
        setState(() {
          _bootstrap = Future<AuthSession?>.value(session);
          _signingIn = false;
        });
      }
    } catch (_) {
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
    return AnimatedBuilder(
      animation: _locale,
      builder: (BuildContext context, _) => MaterialApp(
        onGenerateTitle: (BuildContext context) => DeliveryStrings.of(context).deliveryPortal,
        theme: DeliveryTheme.light(),
        debugShowCheckedModeBanner: false,
        // Content was drawing under the phone's status bar on every screen: titles overlapped the
        // clock/battery row because shells and pushed routes were inconsistent about SafeArea — a
        // few wrapped their body, most did not. Insetting the TOP once here, at the MaterialApp
        // level, wraps every route's child (shells AND pages pushed via Navigator) so individual
        // screens no longer each have to. bottom/left/right stay false: the shells manage their own
        // bottom-nav insets, and adding a bottom inset here would double-pad them. Nested SafeAreas
        // are harmless — inner ones become no-ops — so screens that already wrap themselves are
        // unaffected.
        builder: (BuildContext context, Widget? child) => SafeArea(
          top: true,
          bottom: false,
          left: false,
          right: false,
          child: child ?? const SizedBox.shrink(),
        ),
        locale: _locale.locale,
        supportedLocales: DeliveryStrings.supportedLocales,
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
              return PortalSignInScreen(
                onSignIn: _signIn,
                busy: _signingIn,
                locale: _locale,
              );
            }

            final List<PortalArea> areas = PortalArea.forSession(session);

            // No portal role at all. This is the case the three separate apps each handled with
            // their own "not a merchant" screen; there is one of them now, and it names every role
            // that would have worked rather than only the one app the user happened to open.
            if (areas.isEmpty) {
              return _MessageScreen(
                icon: Icons.lock_outline,
                message: 'This account has no Merchant, Carrier or Backoffice access.',
                actionLabel: 'Sign in as someone else',
                onAction: _signOut,
              );
            }

            return PortalShell(
              areas: areas,
              apis: _apis,
              locale: _locale,
              session: session,
              onSignOut: _signOut,
            );
          },
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
      backgroundColor: DeliveryColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 416),
          child: Container(
            margin: const EdgeInsets.all(DeliverySpacing.lg),
            padding: const EdgeInsets.all(DeliverySpacing.xl),
            decoration: BoxDecoration(
              color: DeliveryColors.white,
              border: Border.all(color: DeliveryColors.border),
              borderRadius: BorderRadius.circular(DeliveryRadius.lg),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(DeliverySpacing.md),
                  decoration: const BoxDecoration(
                    color: DeliveryColors.brandSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 24, color: DeliveryColors.brand),
                ),
                const SizedBox(height: DeliverySpacing.md),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.ink,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: DeliverySpacing.lg),
                OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
