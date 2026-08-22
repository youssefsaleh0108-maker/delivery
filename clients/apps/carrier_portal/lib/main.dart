import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// Safe to import directly: this target is only ever compiled for the web.
import 'package:web/web.dart' as web;

import 'src/carrier_shell.dart';

/// Carrier Portal — `CARRIER` role only.
///
/// The supply side of the marketplace, which until now had no surface at all. A delivery company
/// existed as a row that the Backoffice could edit and the merchant could choose, and the company
/// itself could see none of it: not its own riders, not whether its payout account was usable, not
/// why it was being sent no work.
///
/// Deliberately small. A carrier needs to know how it is doing, who is on its fleet, and how to stop
/// taking orders at closing time — everything else it does happens in the rider app.
void main() {
  runApp(const CarrierPortalApp());
}

const String _issuer = String.fromEnvironment(
  'KEYCLOAK_ISSUER',
  defaultValue: 'http://127.0.0.1:8180/realms/delivery-platform',
);
const String _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8100',
);

/// The app's own origin, read at runtime — see merchant_portal/lib/main.dart for why.
String _redirectUrl() {
  const String override = String.fromEnvironment('OIDC_REDIRECT_URL');
  if (override.isNotEmpty) {
    return override;
  }
  return '${web.window.location.origin}/';
}

class CarrierPortalApp extends StatefulWidget {
  const CarrierPortalApp({super.key});

  @override
  State<CarrierPortalApp> createState() => _CarrierPortalAppState();
}

class _CarrierPortalAppState extends State<CarrierPortalApp> {
  late final AuthService _authService = AuthService(
    config: AuthConfig(
      issuer: _issuer,
      clientId: 'carrier-portal',
      redirectUrl: _redirectUrl(),
    ),
  );

  late final Dio _dio = ApiClient.create(baseUrl: _apiBaseUrl, authService: _authService);
  late final DeliveryProviderApi _providerApi = DeliveryProviderApi(_dio);
  late final OrderApi _orderApi = OrderApi(_dio);
  late final OnboardingApi _onboardingApi = OnboardingApi(_dio);

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
    _locale.load();
  }

  Future<void> _signIn() async {
    setState(() => _signingIn = true);
    try {
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
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DeliveryStrings.of(context).signInFailedShort)));
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
        onGenerateTitle: (BuildContext context) => DeliveryStrings.of(context).carrierPortal,
        theme: DeliveryTheme.light(),
        debugShowCheckedModeBanner: false,
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

            // Order Manager enforces this server-side and scopes every response to the caller's own
            // company. The check here only avoids showing a shell whose every request would 403.
            if (!session.hasRole(DeliveryRole.carrier)) {
              return _NotACarrierScreen(onSignOut: _signOut);
            }

            return CarrierShell(
              providerApi: _providerApi,
              orderApi: _orderApi,
              onboardingApi: _onboardingApi,
              locale: _locale,
              onSignOut: _signOut,
            );
          },
        ),
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
    final DeliveryStrings t = DeliveryStrings.of(context);
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
                        color: DeliveryColors.brandSoft, shape: BoxShape.circle),
                    child: const Icon(Icons.local_shipping_rounded,
                        size: 32, color: DeliveryColors.brand),
                  ),
                  const SizedBox(height: DeliverySpacing.md),
                  Text(t.carrierPortal, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: DeliverySpacing.xs),
                  Text(t.carrierPortalTagline,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: DeliverySpacing.xl),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: busy ? null : onSignIn,
                      child: Text(busy ? t.signingIn : t.signIn),
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

class _NotACarrierScreen extends StatelessWidget {
  const _NotACarrierScreen({required this.onSignOut});

  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(DeliverySpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.lock_outline, size: 40, color: DeliveryColors.muted),
              const SizedBox(height: DeliverySpacing.md),
              Text(t.notACarrier,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: DeliverySpacing.md),
              OutlinedButton(onPressed: onSignOut, child: Text(t.signInAsSomeoneElse)),
            ],
          ),
        ),
      ),
    );
  }
}
