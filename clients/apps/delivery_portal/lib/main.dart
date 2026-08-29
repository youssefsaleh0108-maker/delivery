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
              return _SignInScreen(
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

/// The bottom stop of the sign-in panel's gradient.
///
/// Rose-900, and the one value on this screen that no token covers: `DeliveryColors.brandDark` is
/// rose-800 (`#9F1239`), a visibly lighter end than the design draws. Kept local rather than added
/// to `delivery_design_system`, which is being edited elsewhere this wave — it should graduate to a
/// `brandDeep` token the next time that file is opened.
const Color _brandGradientEnd = Color(0xFF881337);

/// Below this the brand panel is dropped and the card takes the whole window.
///
/// 480 of panel plus the design's 120px gutters and a 416 card needs ~1100 before the right-hand
/// column starts eating its own margins.
const double _splitPanelBreakpoint = 1040;

/// The sign-in screen: the design's split panel, with the form replaced by the redirect.
///
/// Figma `carrier-login` (22:1306) — a 480px brand panel down the left, the welcome card on the
/// slate page to its right.
///
/// **The design draws an email and a password field, and this does not.** Authentication is a
/// Keycloak OIDC redirect and stays one: the portal never sees a credential, there is one client
/// and one session for all three consoles, and putting a password box on this page would mean
/// either faking it or moving the platform off SSO. So the right panel carries the design's welcome
/// copy and its primary button, and that button starts the redirect. Everything else on the panel —
/// the geometry, the gradient, the type ramp, the language toggle — is as drawn.
class _SignInScreen extends StatelessWidget {
  const _SignInScreen({
    required this.onSignIn,
    required this.busy,
    required this.locale,
  });

  final Future<void> Function() onSignIn;
  final bool busy;
  final LocaleController locale;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool split = constraints.maxWidth >= _splitPanelBreakpoint;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (split) const _BrandPanel(),
              Expanded(
                child: _SignInPanel(
                  onSignIn: onSignIn,
                  busy: busy,
                  locale: locale,
                  // Without the brand panel there is nothing else on screen, so the card stops
                  // hugging the design's 120px right-hand gutter and simply centres.
                  centred: !split,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The 480px gradient panel: mark at the top, the promise in the middle, the small print at the
/// bottom.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 480,
      padding: const EdgeInsets.all(DeliverySpacing.xxl),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[DeliveryColors.brand, _brandGradientEnd],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: DeliveryColors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.inventory_2,
                    size: 20, color: DeliveryColors.brand),
              ),
              const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'YouDrop',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: DeliveryColors.white,
                      height: 1.2,
                    ),
                  ),
                  // Deliberately does not name a role. The same page serves all three consoles, and
                  // telling someone which one they are on before they have signed in is a guess.
                  Text(
                    'PARTNER CONSOLE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: DeliveryColors.onBrandSoft,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Run your whole operation from one console.',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.white,
                  height: 42 / 32,
                ),
              ),
              SizedBox(height: DeliverySpacing.lg),
              Opacity(
                opacity: 0.8,
                child: Text(
                  'Shops, delivery companies and the platform team sign in here. Live orders, '
                  'dispatch, catalogue and settlement — the same account, whichever of them you '
                  'are.',
                  style: TextStyle(
                    fontSize: 16,
                    color: DeliveryColors.onBrandSoft,
                    height: 24 / 16,
                  ),
                ),
              ),
            ],
          ),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Opacity(
                opacity: 0.7,
                child: Text(
                  'Merchants · Carriers · Backoffice',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: DeliveryColors.onBrandSoft,
                  ),
                ),
              ),
              SizedBox(height: DeliverySpacing.sm),
              Opacity(
                opacity: 0.5,
                child: Text(
                  '© 2026 YouDrop Technologies Inc.',
                  style: TextStyle(fontSize: 12, color: DeliveryColors.onBrandSoft),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The right-hand column: language toggle at the top, the 416px welcome card in the middle.
class _SignInPanel extends StatelessWidget {
  const _SignInPanel({
    required this.onSignIn,
    required this.busy,
    required this.locale,
    required this.centred,
  });

  final Future<void> Function() onSignIn;
  final bool busy;
  final LocaleController locale;
  final bool centred;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: centred ? DeliverySpacing.lg : 120,
        vertical: 64,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(
            alignment: Alignment.centerRight,
            child: _LanguageToggle(locale: locale),
          ),
          // Scrolls rather than overflows. The design is drawn at 800 tall; a browser window with
          // three toolbars open is shorter than the card, and a clipped sign-in button is a user
          // who cannot sign in.
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 416),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text(
                        'Welcome back',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: DeliveryColors.ink,
                        ),
                      ),
                      const SizedBox(height: DeliverySpacing.sm),
                      Text(
                        t.signInPrompt,
                        style: const TextStyle(fontSize: 14, color: DeliveryColors.muted),
                      ),
                      const SizedBox(height: DeliverySpacing.xl),
                      // The design's primary button, at the design's weight — it just does the one
                      // thing this screen can do.
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: busy ? null : onSignIn,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DeliveryColors.brand,
                            foregroundColor: DeliveryColors.white,
                            disabledBackgroundColor: DeliveryColors.brandLine,
                            disabledForegroundColor: DeliveryColors.white,
                            elevation: 0,
                            padding: const EdgeInsets.all(14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: Text(busy ? '${t.signIn}…' : t.signIn),
                        ),
                      ),
                      const SizedBox(height: DeliverySpacing.md),
                      // Says where the button goes. The redirect is the architecture, not an
                      // accident, and a button that navigates away from the app should say so.
                      const Text(
                        'You will be taken to the YouDrop identity service to sign in, then brought '
                        'straight back here.',
                        style: TextStyle(fontSize: 13, color: DeliveryColors.faint, height: 1.5),
                      ),
                      const SizedBox(height: DeliverySpacing.xl),
                      const Text(
                        'New merchant or delivery partner? Apply in the YouDrop app — your console '
                        'opens as soon as the application is approved.',
                        style: TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The design's bordered `AR / EN` toggle — a real switch, not a label.
class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle({required this.locale});

  final LocaleController locale;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return PopupMenuButton<String>(
      tooltip: t.language,
      position: PopupMenuPosition.under,
      initialValue: locale.isArabic ? 'ar' : 'en',
      onSelected: locale.setLanguage,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'en', child: Text(t.english)),
        PopupMenuItem<String>(value: 'ar', child: Text(t.arabic)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DeliverySpacing.md - DeliverySpacing.xs,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: DeliveryColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.language, size: 16, color: DeliveryColors.muted),
            SizedBox(width: DeliverySpacing.xs),
            Text(
              'AR / EN',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.muted,
              ),
            ),
          ],
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
