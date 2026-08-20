import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';

import 'src/customer_shell.dart';
import 'src/ride_with_us_screen.dart';
import 'src/splash_screen.dart';
import 'src/rider_home_screen.dart';

/// One codebase, two very different users.
///
/// Section 9: the Mobile App serves both Customer and Delivery Rider and branches navigation on the
/// Keycloak role claim after login. Phase 1 gives the Customer side a real catalog to browse;
/// checkout, tracking and the rider queue arrive with Order Manager in Phase 2.
void main() {
  runApp(const DeliveryMobileApp());
}

/// HOST ADDRESS: this machine's LAN IP, so a physical phone on the same Wi-Fi can reach it.
///
/// Must match `KEYCLOAK_PUBLIC_URL` in `infra/.env`. Keycloak stamps exactly one issuer into every
/// token, and a token whose `iss` differs from what the services expect is rejected at the Gateway
/// — which presents as an auth failure rather than an addressing one, so these two drifting apart
/// is expensive to diagnose.
///
/// **DHCP moves this address.** When it changes, run `infra/set-host-address.ps1` (it rewrites
/// .env, re-registers the Keycloak redirect URIs and restarts the affected services), then pass the
/// new value here via Android Studio > Run > Edit Configurations > Additional run args rather than
/// editing this file:
///
///   --dart-define=API_BASE_URL=http://NEW.IP:8100
///   --dart-define=KEYCLOAK_ISSUER=http://NEW.IP:8180/realms/delivery-platform
///
/// Symptom of a stale value: sign-in hangs for ~30s, then "site cannot be reached" — that is a TCP
/// timeout against an address nothing answers on, not a slow login.
const String _issuer = String.fromEnvironment(
  'KEYCLOAK_ISSUER',
  defaultValue: 'http://192.168.10.24:8180/realms/delivery-platform',
);
const String _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://192.168.10.24:8100',
);
const String _redirectUrl = String.fromEnvironment(
  'OIDC_REDIRECT_URL',
  defaultValue: 'com.delivery.app://oauth2redirect',
);

class DeliveryMobileApp extends StatefulWidget {
  const DeliveryMobileApp({super.key});

  @override
  State<DeliveryMobileApp> createState() => _DeliveryMobileAppState();
}

class _DeliveryMobileAppState extends State<DeliveryMobileApp> {
  late final AuthService _authService = AuthService(
    config: const AuthConfig(
      issuer: _issuer,
      clientId: 'mobile-app',
      redirectUrl: _redirectUrl,
    ),
  );

  late final Dio _dio = ApiClient.create(
    baseUrl: _apiBaseUrl,
    authService: _authService,
  );

  late final StoreApi _storeApi = StoreApi(_dio);
  late final OrderApi _orderApi = OrderApi(_dio);
  late final OfferApi _offerApi = OfferApi(_dio);
  late final OnboardingApi _onboardingApi = OnboardingApi(_dio);
  late final NotificationApi _notificationApi = NotificationApi(_dio);
  late final ButlerApi _butlerApi = ButlerApi(_dio);
  /// The area list the address sheet offers. Nullable nowhere: a deployment with no areas
  /// configured simply gets an empty list and no picker.
  late final DeliveryZoneApi _zoneApi = DeliveryZoneApi(_dio);

  late Future<AuthSession?> _bootstrap = _authService.restore();

  /// The chosen language, persisted next to the tokens so it survives a restart. Secure storage is
  /// overkill for a language code, but it is already here and adds no dependency.
  late final LocaleController _locale = LocaleController(
    read: () => const FlutterSecureStorage().read(key: 'delivery.locale'),
    write: (String code) =>
        const FlutterSecureStorage().write(key: 'delivery.locale', value: code),
  );
  // No busy flag: sign-in is no longer a button you can watch spin. The app redirects on its own,
  // so the only states a reader ever sees are "going to Keycloak" and "that failed".
  Object? _signInError;

  /// Set when somebody with no account is applying to ride. While it is true the app must not
  /// try to sign them in again — the whole point is that they have nothing to sign in with.
  bool _applyingToRide = false;

  /// Guards the automatic redirect. Without it a failed sign-in re-triggers on every rebuild and
  /// the app ping-pongs to Keycloak forever.
  bool _autoSignInAttempted = false;

  @override
  void initState() {
    super.initState();
    // Fire and forget: the app renders in the device language and switches the moment the saved
    // preference arrives, rather than holding the first frame for a disk read.
    _locale.load();
  }

  Future<void> _signIn() async {
    setState(() => _signInError = null);
    try {
      // On web this navigates away and never returns; the session arrives via restore() on the
      // next load. Null means the user backed out of the flow on a platform where it can return.
      final AuthSession? session = await _authService.signIn();
      if (!mounted || session == null) return;
      setState(() => _bootstrap = Future<AuthSession?>.value(session));
    } catch (e) {
      if (!mounted) return;
      setState(() => _signInError = e);
    }
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    setState(() => _bootstrap = Future<AuthSession?>.value(null));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _locale,
      builder: (BuildContext context, _) => MaterialApp(
      // onGenerateTitle rather than title: the app name shown in the OS task switcher is resolved
      // after the localisations are in place, so it follows the chosen language too.
      onGenerateTitle: (BuildContext context) => DeliveryStrings.of(context).appTitle,
      theme: DeliveryTheme.light(),
      // Null follows the device; an explicit choice overrides it. Flutter flips the whole tree to
      // RTL for Arabic on its own — no per-widget work, provided layouts use directional insets.
      locale: _locale.locale,
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      home: FutureBuilder<AuthSession?>(
        future: _bootstrap,
        builder: (BuildContext context, AsyncSnapshot<AuthSession?> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SplashScreen();
          }

          final AuthSession? session = snapshot.data;
          if (session == null) {
            if (!_autoSignInAttempted) {
              _autoSignInAttempted = true;
              // After this frame, not during build: signIn() calls setState, and on web it
              // navigates the page away entirely.
              //
              // Held for SplashScreen.hold so the intro actually plays. Bootstrap resolves in
              // well under a second, so without the floor the redirect fires mid-animation and
              // the brand screen is a red flicker. Only this path waits — a restored session goes
              // straight through, and Try again below is immediate, because by then the customer
              // has already seen the screen and is asking for something.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Future<void>.delayed(SplashScreen.hold, () {
                  if (mounted) _signIn();
                });
              });
            }
            if (_applyingToRide) {
              return RideWithUsScreen(
                api: _onboardingApi,
                onClose: () => setState(() => _applyingToRide = false),
              );
            }
            return SplashScreen(
              error: _signInError,
              onRetry: () {
                _autoSignInAttempted = true;
                _signIn();
              },
              onApply: () => setState(() => _applyingToRide = true),
            );
          }

          // The role branch. A rider's queue wins when an account holds both, because the delivery
          // flow is the one with a time-critical task attached.
          if (session.hasRole(DeliveryRole.delivery)) {
            return RiderHomeScreen(
              api: _orderApi,
              butlerApi: _butlerApi,
              session: session,
              onSignOut: _signOut,
            );
          }
          return CustomerShell(
            storeApi: _storeApi,
            orderApi: _orderApi,
            offerApi: _offerApi,
            notificationApi: _notificationApi,
            butlerApi: _butlerApi,
            zoneApi: _zoneApi,
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
