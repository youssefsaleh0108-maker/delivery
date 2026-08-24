import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';

import 'src/customer_shell.dart';
import 'src/partner_application_screen.dart';
import 'src/partner_choice_screen.dart';
import 'src/sign_in_screen.dart';
import 'src/sign_up_screen.dart';
import 'src/splash_screen.dart';
import 'src/welcome_screen.dart';
import 'src/merchant_home_screen.dart';
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

/// Which signed-out screen is showing.
///
/// A tiny state machine rather than a Navigator: there are three screens, they are mutually
/// exclusive, and the whole gate disappears the moment a session exists. A route stack here would
/// mean guarding against a back gesture landing on a login screen behind a signed-in app.
enum _Gate { welcome, signIn, signUp }

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
  /// Which of the signed-out screens is showing. The sign-in and sign-up screens own their own
  /// busy and error state, because both are forms somebody is actively working in.
  _Gate _gate = _Gate.welcome;

  /// True while the Google round trip is in flight.
  bool _brokering = false;

  /// Signs in through Keycloak's Google broker. Opens a browser, unlike the passcode path — an
  /// external consent screen cannot be rendered inside the app, and any app that tried would be
  /// asking for somebody's Google password directly.
  Future<void> _signInWithGoogle() async {
    setState(() => _brokering = true);
    try {
      final AuthSession? session =
          await _authService.signInWithBroker(AuthService.googleBroker);
      // Null means the user backed out of the browser, which is not an error worth a message.
      if (session != null) {
        _adoptSession(session);
        return;
      }
    } catch (e, stack) {
      // The screen says one sentence; without this the cause never leaves the device.
      debugPrint('GOOGLE SIGN-IN FAILED: ');
      debugPrintStack(stackTrace: stack, label: 'google-sign-in');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(DeliveryStrings.of(context).couldNotSignInWithGoogle),
        ));
      }
    }
    if (mounted) setState(() => _brokering = false);
  }

  /// Set when somebody with no account is applying to sell or to ride.
  ///
  /// Two fields rather than a fourth [_Gate] because this is reachable from the welcome screen and
  /// returns there, and because it is the one path that ends in an application rather than a
  /// session. Null kind means the choice screen is showing and they have not picked yet.
  bool _applyingAsPartner = false;
  PartnerKind? _partnerKind;

  /// Adopts a session from either form. Shared so the two screens cannot drift on what "signed in"
  /// means — sign-up signs the new account in directly rather than sending them back to a login.
  void _adoptSession(AuthSession session) {
    setState(() {
      // Block body, not an arrow: `() => x = Future...` RETURNS that Future, and setState asserts
      // its callback returns nothing. The assignment still lands, so the symptom is a thrown error
      // immediately after a SUCCESSFUL sign-in — which any enclosing catch then reports as the
      // sign-in having failed.
      _bootstrap = Future<AuthSession?>.value(session);
      _gate = _Gate.welcome;
    });
  }

  @override
  void initState() {
    super.initState();
    // Fire and forget: the app renders in the device language and switches the moment the saved
    // preference arrives, rather than holding the first frame for a disk read.
    _locale.load();
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
            // NOT an automatic redirect any more.
            //
            // This used to fire the Keycloak browser tab on its own, a frame after the splash. That
            // is right for somebody who already has an account and wrong for everybody else: there
            // was no way to create one from the app at all, and a first-time user's introduction to
            // the platform was a browser showing a bare IP address asking for a password.
            //
            // The gate is a choice now, and every branch of it stays inside the app.
            if (_applyingAsPartner) {
              // The choice first, then the form for whichever they picked. Back from the form
              // returns to the choice rather than all the way out, because picking the wrong one
              // is an easy mistake and should cost one tap.
              if (_partnerKind == null) {
                return PartnerChoiceScreen(
                  onChoose: (PartnerKind kind) => setState(() => _partnerKind = kind),
                  onClose: () => setState(() => _applyingAsPartner = false),
                );
              }
              return PartnerApplicationScreen(
                api: _onboardingApi,
                kind: _partnerKind!,
                onClose: () => setState(() => _partnerKind = null),
              );
            }
            switch (_gate) {
              case _Gate.signIn:
                return SignInScreen(
                  authService: _authService,
                  onSignedIn: _adoptSession,
                  onBack: () => setState(() => _gate = _Gate.welcome),
                  onCreateAccount: () => setState(() => _gate = _Gate.signUp),
                );
              case _Gate.signUp:
                return SignUpScreen(
                  api: _onboardingApi,
                  authService: _authService,
                  onSignedIn: _adoptSession,
                  onBack: () => setState(() => _gate = _Gate.welcome),
                );
              case _Gate.welcome:
                return WelcomeScreen(
                  busy: _brokering,
                  onGoogle: _signInWithGoogle,
                  onSignIn: () => setState(() => _gate = _Gate.signIn),
                  onSignUp: () => setState(() => _gate = _Gate.signUp),
                  onJoinAsPartner: () => setState(() {
                    _applyingAsPartner = true;
                    _partnerKind = null;
                  }),
                );
            }
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
          // A merchant gets their queue, not a basket. Before this the branch knew only about
          // riders and treated everyone else as a shopper, so the person running the shop landed
          // in the storefront with no way to see their own orders.
          if (session.hasRole(DeliveryRole.merchant)) {
            return MerchantHomeScreen(
              orderApi: _orderApi,
              session: session,
              onSignOut: _signOut,
            );
          }
          return CustomerShell(
            // Keyed by the account. Without it Flutter may reuse the previous session's State when
            // one user signs out and another signs in, and the screen would keep the first
            // person's basket, address and inbox — the same class of bug as the shared storage key.
            key: ValueKey<String?>(session.subject),
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
