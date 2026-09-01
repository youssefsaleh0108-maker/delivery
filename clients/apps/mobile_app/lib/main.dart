import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/biometric_lock.dart';
import 'src/biometric_lock_screen.dart';
import 'src/carrier_shell.dart';
import 'src/customer_shell.dart';
import 'src/partner_application_screen.dart';
import 'src/partner_choice_screen.dart';
import 'src/partner_intro_screen.dart';
import 'src/pending_application_screen.dart';
import 'src/sign_in_screen.dart';
import 'src/sign_up_screen.dart';
import 'src/splash_screen.dart';
import 'src/welcome_screen.dart';
import 'src/merchant_shell.dart';
import 'src/rider_home_screen.dart';

/// One codebase, two very different users.
///
/// Section 9: the Mobile App serves both Customer and Delivery Rider and branches navigation on the
/// Keycloak role claim after login. Phase 1 gives the Customer side a real catalog to browse;
/// checkout, tracking and the rider queue arrive with Order Manager in Phase 2.
Future<void> main() async {
  // Required before any plugin call, because Firebase is initialised below and that talks to the
  // platform channel.
  WidgetsFlutterBinding.ensureInitialized();

  // The status bar and the navigation bar keep their own reserved space — the app never draws
  // under either. Edge-to-edge was tried and rejected: content and controls sliding beneath the
  // clock and behind the system's back/home buttons read as the app COVERING the phone's own
  // chrome. So no SystemUiMode.edgeToEdge here, and both bars get an opaque white ground with
  // dark glyphs, which sits flush with the app's light surfaces. The splash overrides this to
  // brand-on-brand while it is up (see SplashScreen); everything else inherits the default from
  // the AnnotatedRegion at the MaterialApp builder. On Android 15+, where the OS pushes apps
  // edge-to-edge by default, the themes opt out via windowOptOutEdgeToEdgeEnforcement.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.white,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  try {
    // Reads the config the Gradle plugin generated from google-services.json. Wrapped because a
    // build without that file — a fork, or a developer who has not been given the Firebase project
    // — must still run. Push simply does not work in that case; nothing else is affected.
    await Firebase.initializeApp();
  } catch (error, stack) {
    debugPrint('FIREBASE INIT FAILED, push will not work: $error');
    debugPrintStack(stackTrace: stack, label: 'firebase-init');
  }

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

  /// The shop owner's own catalogue — a different endpoint from the storefront a customer browses,
  /// because a merchant sees their unpublished and archived products too.
  late final CatalogApi _catalogApi = CatalogApi(_dio);
  late final OfferApi _offerApi = OfferApi(_dio);
  late final OnboardingApi _onboardingApi = OnboardingApi(_dio);
  late final ProfileApi _profileApi = ProfileApi(_dio);
  late final PointsApi _pointsApi = PointsApi(_dio);
  late final TransferApi _transferApi = TransferApi(_dio);
  late final SplitApi _splitApi = SplitApi(_dio);
  late final DeliveryProviderApi _deliveryProviderApi = DeliveryProviderApi(_dio);

  /// The applicant's documents and payout details — the wizard sends them right after the account
  /// exists, and the pending screen reads and corrects them while the application waits.
  late final DocumentsApi _documentsApi = DocumentsApi(_dio);
  late final NotificationApi _notificationApi = NotificationApi(_dio);

  // The capability APIs. Every screen takes these as OPTIONAL parameters — null renders the
  // feature's honest inert state — which is what let the screens land in parallel without breaking
  // each other's compile. The cost of that pattern is that nothing fails when the wiring is
  // forgotten: the first installed build of the wired app shipped with all of these missing HERE,
  // every screen quietly fell back to its "coming soon" chip, and analyze, tests and the build
  // were green throughout because tests inject their own. This block is the single point where
  // the app decides those features exist. Removing a line here turns the feature off everywhere,
  // silently — treat it like the release switch it is.
  late final TrackingApi _trackingApi = TrackingApi(_dio);
  late final PromoApi _promoApi = PromoApi(_dio);
  late final GeocodingApi _geocodingApi = GeocodingApi(_dio);
  late final AggregatesApi _aggregatesApi = AggregatesApi(_dio);
  late final RiderMoneyApi _riderMoneyApi = RiderMoneyApi(_dio);

  /// The rider's own completion rate and claimed/delivered counts, behind the Earnings tab.
  ///
  /// It was written, threaded through two screens and never built here — exactly the failure the
  /// block comment above describes, caught by grepping for the chip it left on screen rather than
  /// by anything that could go red.
  late final RiderPerformanceApi _performanceApi = RiderPerformanceApi(_dio);

  /// Counterparty statements. In this app only `/mine` is ever called — a rider reading their own
  /// standing with the platform from the Earnings tab. The Backoffice routes on the same client are
  /// BACKOFFICE-gated server-side and are not reachable from any screen here.
  late final StatementsApi _statementsApi = StatementsApi(_dio);
  late final ChatApi _chatApi = ChatApi(_dio);
  late final NotificationPrefsApi _prefsApi = NotificationPrefsApi(_dio);

  /// One socket for the session's live frames (chat, and whatever joins it later). Lazy, so a
  /// build that never reaches a chat screen never opens a connection.
  late final UserQueueSocket _socket =
      UserQueueSocket(apiBaseUrl: Uri.parse(_apiBaseUrl), auth: _authService);
  late final ButlerApi _butlerApi = ButlerApi(_dio);
  /// The area list the address sheet offers. Nullable nowhere: a deployment with no areas
  /// configured simply gets an empty list and no picker.
  late final DeliveryZoneApi _zoneApi = DeliveryZoneApi(_dio);

  late Future<AuthSession?> _bootstrap = _restoreAfterSplash();

  /// Restores the stored session, but not before the splash has had its full [SplashScreen.hold].
  /// A device with no session to restore answers in a few milliseconds, so without this the branded
  /// welcome is a flicker on the way to Sign In. The read and the hold run together, so the wait is
  /// the hold — not the hold plus the read.
  Future<AuthSession?> _restoreAfterSplash() async {
    final Future<void> minimum = Future<void>.delayed(SplashScreen.hold);
    final AuthSession? session = await _authService.restore();
    await minimum;
    return session;
  }

  /// Writes this device's push token onto the signed-in account.
  late final DeviceTokenRegistrar _deviceTokens =
      DeviceTokenRegistrar(dio: _dio, issuer: _issuer);

  final BiometricLock _biometrics = BiometricLock();

  /// Counts returns from the explore route, and is the pending screen's key. See
  /// [_exploreAsCustomer] for why a status screen needs one.
  int _pendingEpoch = 0;

  /// The app's own navigator, so a callback held by a screen can push without a [BuildContext].
  ///
  /// One key, created once and never rebuilt: a GlobalKey that changed identity between frames
  /// would detach and re-attach the whole navigator, losing every route on it.
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

  /// Whether a restored session is still behind the lock screen.
  ///
  /// Starts true and is cleared either by a successful unlock or by finding that this account never
  /// turned the setting on. Starting FALSE would show the app for a frame before locking it, which
  /// is a frame of somebody else's account.
  bool _locked = true;

  /// True while the system prompt is up.
  bool _unlocking = false;
  String? _lockError;

  /// Set once the checks below have run, so the lock decision is made exactly once per session
  /// rather than on every rebuild.
  String? _lockCheckedFor;

  /// Decides whether this session needs unlocking, then unlocks it if so.
  ///
  /// Called from the builder rather than initState because it needs the restored session, which is
  /// not available until the future completes.
  Future<void> _applyLock(AuthSession session) async {
    if (_lockCheckedFor == session.subject) return;
    _lockCheckedFor = session.subject;

    // A restored session registers too. Tokens rotate while the app is closed, and a session that
    // only ever registers at sign-in would keep a stale one for as long as somebody stays signed in.
    _deviceTokens.register();

    final bool enabled = await _biometrics.isEnabledFor(session.subject);
    if (!enabled) {
      if (mounted) setState(() => _locked = false);
      return;
    }
    await _unlock();
  }

  Future<void> _unlock() async {
    setState(() {
      _unlocking = true;
      _lockError = null;
    });
    // The strings live INSIDE the MaterialApp this State builds, so this State's own context
    // sits above them and `DeliveryStrings.of(context)` threw — after _unlocking was already
    // true, which left the lock screen spinning forever the first time anybody enabled the
    // fingerprint. The navigator's context is inside the app; a plain literal covers the one
    // frame where even that does not exist yet.
    final BuildContext? inApp = _navigator.currentContext;
    final DeliveryStrings? t =
        inApp == null ? null : Localizations.of<DeliveryStrings>(inApp, DeliveryStrings);
    final BiometricResult result;
    try {
      result = await _biometrics
          .authenticate(t?.unlockWithFingerprint ?? 'Unlock YouDrop')
          // The OS prompt normally answers or is dismissed; a hung platform channel must not
          // hold the lock screen's spinner hostage.
          .timeout(const Duration(seconds: 45),
              onTimeout: () => BiometricResult.refused);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _unlocking = false;
        _lockError = t?.couldNotVerifyYou ?? 'Could not verify you.';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _unlocking = false;
      switch (result) {
        case BiometricResult.ok:
          _locked = false;
        case BiometricResult.unavailable:
          // The enrolment went away since this was turned on. Locking somebody out of their own
          // session over a setting they cannot satisfy would be worse than letting them in — the
          // phone's own lock screen is still between a stranger and this app.
          _locked = false;
        case BiometricResult.refused:
          _lockError = t?.couldNotVerifyYou ?? 'Could not verify you.';
      }
    });
  }


  /// The chosen language, persisted next to the tokens so it survives a restart. Secure storage is
  /// overkill for a language code, but it is already here and adds no dependency.
  late final LocaleController _locale = LocaleController(
    read: () => const FlutterSecureStorage().read(key: 'delivery.locale'),
    write: (String code) =>
        const FlutterSecureStorage().write(key: 'delivery.locale', value: code),
  );
  /// Which of the signed-out screens is showing. The sign-in and sign-up screens own their own
  /// busy and error state, because both are forms somebody is actively working in.
  _Gate _gate = _Gate.signIn;

  /// True while the Google round trip is in flight.
  bool _brokering = false;

  // Kept, not deleted: the broker round trip is written and correct, and it is wired back in by
  // passing it to WelcomeScreen again once Google credentials exist. Deleting it would mean
  // rewriting it later from nothing.
  /// Signs in through Keycloak's Google broker. Opens a browser, unlike the passcode path — an
  /// external consent screen cannot be rendered inside the app, and any app that tried would be
  /// asking for somebody's Google password directly.
  // ignore: unused_element
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

  /// Whether the role's intro has been passed. Once a kind is known the intro sells that role
  /// (Figma `rider-signup-intro` / `merchant-signup-intro`), then the application form follows.
  bool _partnerIntroDone = false;

  /// True when the fork was shown on the way in.
  ///
  /// Decides where Back from the application form goes: to the fork if they came through it, and
  /// all the way out to the welcome screen if they did not. Sending somebody back to a screen they
  /// never saw is worse than one extra tap.
  bool _forkedByChoice = false;

  /// Enters the partner application. A null [kind] shows the fork; a kind skips straight to that
  /// application's intro, which is what the redesigned welcome screen's role cards do.
  void _applyAs(PartnerKind? kind) => setState(() {
        _applyingAsPartner = true;
        _partnerKind = kind;
        _forkedByChoice = kind == null;
        // The generic intro speaks rider and merchant; the carrier wizard opens on its own
        // For-Carriers pitch, so the extra screen would just say the wrong things first.
        _partnerIntroDone = kind == PartnerKind.carrier;
      });

  /// Adopts a session from either form. Shared so the two screens cannot drift on what "signed in"
  /// means — sign-up signs the new account in directly rather than sending them back to a login.
  void _adoptSession(AuthSession session) {
    // Register this device for push as soon as there is an account to attach it to. Fire and
    // forget: it asks for a permission, and somebody who says no still gets a working app.
    _deviceTokens.register();
    setState(() {
      // They just proved who they are with a passcode, so there is nothing to unlock. Leaving this
      // true would show the lock screen for a moment immediately after a successful sign-in.
      _locked = false;
      _lockCheckedFor = session.subject;
      _lockError = null;
      // Block body, not an arrow: `() => x = Future...` RETURNS that Future, and setState asserts
      // its callback returns nothing. The assignment still lands, so the symptom is a thrown error
      // immediately after a SUCCESSFUL sign-in — which any enclosing catch then reports as the
      // sign-in having failed.
      _bootstrap = Future<AuthSession?>.value(session);
      _gate = _Gate.signIn;
    });
  }

  @override
  void initState() {
    super.initState();
    // Fire and forget: the app renders in the device language and switches the moment the saved
    // preference arrives, rather than holding the first frame for a disk read.
    _locale.load();
    // Likewise the LBP display rate: prices render USD-only until it lands, then twice.
    MarketRates.instance.load(_dio);
  }

  Future<void> _signOut() async {
    // The fingerprint toggle is the user's standing consent to a sign-out that keeps a way back:
    // with it on, the refresh token moves into the biometric stash instead of being revoked, and
    // the sign-in screen offers "Continue as {name}" behind the system prompt. Toggle off means
    // sign-out is a revocation, exactly as before.
    final bool keep =
        await _biometrics.isEnabledFor(_authService.session?.subject);
    await _authService.signOut(keepForBiometrics: keep);
    setState(() {
      // Re-armed. Without this the next person to sign in on this phone walks straight past the
      // lock, because _locked would still be false from the session that just ended.
      _locked = true;
      _lockError = null;
      _lockCheckedFor = null;
      // Block body, not an arrow: `() => x = Future...` RETURNS that Future, and setState
      // asserts its callback returns nothing.
      _bootstrap = Future<AuthSession?>.value(null);
    });
  }

  /// The shopping surface, for whoever is entitled to it.
  ///
  /// A method rather than a literal in the branch below because two places build it: the role
  /// branch, which is the whole app for a customer, and [_exploreAsCustomer], which pushes it over
  /// the pending screen for somebody whose application has not been decided yet.
  ///
  /// [onSignOut] is a parameter for the same reason — see [_exploreAsCustomer].
  Widget _customerShell(AuthSession session, {Future<void> Function()? onSignOut}) {
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
      promoApi: _promoApi,
      geocodingApi: _geocodingApi,
      trackingApi: _trackingApi,
      chatApi: _chatApi,
      prefsApi: _prefsApi,
      profileApi: _profileApi,
      pointsApi: _pointsApi,
      transferApi: _transferApi,
      splitApi: _splitApi,
      session: session,
      locale: _locale,
      onSignOut: onSignOut ?? _signOut,
    );
  }

  /// The pending screen's "Explore Dashboard", made real.
  ///
  /// Everybody who reaches that screen holds APPLICANT and nothing else — a rider or a shop owner
  /// whose application has not been decided. There is no dashboard for them yet: the merchant and
  /// rider services refuse a token without the role, so mounting either shell would be a screenful
  /// of 403s dressed as a product. What they *do* have, from the moment the account exists, is the
  /// shopping surface — so that is where the button goes, and it works.
  ///
  /// Pushed rather than swapped in, so the system back gesture (and iOS's edge swipe, which
  /// [MaterialPageRoute] gives us on that platform) returns to the application status they were
  /// looking at. Signing out from inside pops back to the root first: without that, the route
  /// would still be sitting on the stack above a welcome screen belonging to nobody.
  Future<void> _exploreAsCustomer(AuthSession session) async {
    await _navigator.currentState?.push(MaterialPageRoute<void>(
      builder: (BuildContext context) => _customerShell(
        session,
        onSignOut: () async {
          _navigator.currentState?.popUntil((Route<dynamic> route) => route.isFirst);
          await _signOut();
        },
      ),
    ));
    // Coming back re-asks the server where the application got to.
    //
    // Load-bearing, not a nicety. The pending screen's one button is "Check again" until an
    // Explore Dashboard exists to put there, and wiring this callback takes that button's place —
    // so without a re-check on the way back, giving somebody the dashboard would have quietly
    // taken away their only way to find out they had been approved. Bumping the key rebuilds the
    // screen's State, which is what re-runs `api.mine()`.
    if (mounted) setState(() => _pendingEpoch++);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _locale,
      builder: (BuildContext context, _) => MaterialApp(
      navigatorKey: _navigator,
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
      // No global SafeArea here on purpose. Wrapping every route in one pushed each Scaffold down
      // below the status bar, leaving the bar's ground painted by nobody — the black strip. Going
      // edge-to-edge instead (see main()) lets each Scaffold's own background fill behind the now
      // transparent bar; content is kept clear of it by a SafeArea inside each screen's body, which
      // every full-page screen here now has (or an AppBar, which insets itself).
      //
      // The AnnotatedRegion is the app's DEFAULT system-bar style: opaque white bars with dark
      // glyphs, in their own reserved space the app never draws under. It has to live here and
      // not only in main()'s one-shot SystemChrome call, because the splash sets brand-on-brand
      // bars with an AnnotatedRegion of its own — and a one-shot call is overwritten by that and
      // never reasserted, which once left the wrong style stuck after the splash. Layered regions
      // fix that: the deepest visible region wins, and everything falls back to this default the
      // moment it leaves the tree.
      builder: (BuildContext context, Widget? child) =>
          AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.white,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Colors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: child ?? const SizedBox.shrink(),
      ),
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
                  onChoose: (PartnerKind kind) => setState(() {
                    _partnerKind = kind;
                    // The generic intro speaks rider and merchant; the carrier wizard opens on
                    // its own For-Carriers pitch.
                    _partnerIntroDone = kind == PartnerKind.carrier;
                  }),
                  onClose: () => setState(() => _applyingAsPartner = false),
                );
              }
              if (!_partnerIntroDone) {
                // Sells the role, then Continue hands off to the form. Back returns to the fork if
                // it was shown, otherwise out to the role screen; "Log In" leaves for Sign In.
                return PartnerIntroScreen(
                  kind: _partnerKind!,
                  onContinue: () => setState(() => _partnerIntroDone = true),
                  onBack: () => setState(() {
                    if (_forkedByChoice) {
                      _partnerKind = null;
                    } else {
                      _applyingAsPartner = false;
                    }
                  }),
                  onLogIn: () => setState(() {
                    _applyingAsPartner = false;
                    _partnerKind = null;
                    _gate = _Gate.signIn;
                  }),
                );
              }
              return PartnerApplicationScreen(
                api: _onboardingApi,
                documentsApi: _documentsApi,
                kind: _partnerKind!,
                authService: _authService,
                onSignedIn: (AuthSession session) {
                  // Out of the application flow entirely: they have an account now, and the role
                  // branch below puts them on the pending screen until somebody decides.
                  setState(() {
                    _applyingAsPartner = false;
                    _partnerKind = null;
                  });
                  _adoptSession(session);
                },
                // Back from the form returns to the role's intro, not out of the flow.
                onClose: () => setState(() => _partnerIntroDone = false),
              );
            }
            switch (_gate) {
              case _Gate.signIn:
                // The landing after the splash. Sign In is the hub the Figma draws it as: no back
                // control (there is nothing behind it), and "Create Account" opens the role screen.
                return SignInScreen(
                  authService: _authService,
                  onSignedIn: _adoptSession,
                  onBack: () {},
                  onCreateAccount: () => setState(() => _gate = _Gate.welcome),
                  locale: _locale,
                );
              case _Gate.signUp:
                return SignUpScreen(
                  api: _onboardingApi,
                  authService: _authService,
                  onSignedIn: _adoptSession,
                  // Back returns to the role screen it was reached through, not out to Sign In.
                  onBack: () => setState(() => _gate = _Gate.welcome),
                );
              case _Gate.welcome:
                // The role screen — "Create Account / Join YouDrop". Reached from Sign In, so it
                // carries a back to it; the fork's role cards each lead to that role's sign-up.
                return WelcomeScreen(
                  busy: _brokering,
                  onBack: () => setState(() => _gate = _Gate.signIn),
                  // Null until a Google client id and secret exist. Google refuses to register a
                  // redirect URI on a bare IP over http, which is what this deployment is, so the
                  // round trip cannot work yet and a control that cannot work should not be shown.
                  // Restore this to _signInWithGoogle once the box has a hostname and TLS.
                  onGoogle: null,
                  onSignIn: () => setState(() => _gate = _Gate.signIn),
                  onSignUp: () => setState(() => _gate = _Gate.signUp),
                  onJoinAsPartner: () => _applyAs(null),
                  // A card that already says "rider" goes straight to that application's intro rather
                  // than to a screen asking which one again. The fork is kept for anything that
                  // arrives without a kind.
                  onJoinAsRider: () => _applyAs(PartnerKind.rider),
                  onJoinAsMerchant: () => _applyAs(PartnerKind.merchant),
                  onJoinAsCarrier: () => _applyAs(PartnerKind.carrier),
                );
            }
          }



          // Signed in, but possibly not unlocked. The check runs once per session and the screen
          // below shows nothing about the account it is protecting.
          if (_locked) {
            _applyLock(session);
            return BiometricLockScreen(
              busy: _unlocking,
              error: _lockError,
              onUnlock: _unlock,
              onUsePasscode: _signOut,
            );
          }

          // A pending partner gets their real surface, not a waiting room. They carry the role they
          // applied for, so every screen works and they can set a shop up or read the job board —
          // the server refuses only the committing acts, publishing and claiming, until APPLICANT
          // comes off. The banner on those screens says so.
          //
          // Only somebody carrying APPLICANT and nothing else lands on the status screen, which is
          // the case where there is genuinely no surface to show.
          final bool pending = session.hasRole(DeliveryRole.applicant);
          if (pending &&
              !session.hasRole(DeliveryRole.merchant) &&
              !session.hasRole(DeliveryRole.delivery) &&
              !session.hasRole(DeliveryRole.carrier)) {
            return PendingApplicationScreen(
              // Bumped when the explore route pops, which re-creates the State and re-reads the
              // application. See [_exploreAsCustomer].
              key: ValueKey<int>(_pendingEpoch),
              api: _onboardingApi,
              documentsApi: _documentsApi,
              session: session,
              onSignOut: _signOut,
              onApproved: () => _signOut(),
              onExplore: () => _exploreAsCustomer(session),
            );
          }


          // The role branch. A rider's queue wins when an account holds both, because the delivery
          // flow is the one with a time-critical task attached.
          // The carrier's company surface (Figma 87:*). Before the rider branch: an account
          // holding both runs the company; the rider queue is their staff's job, not theirs.
          if (session.hasRole(DeliveryRole.carrier)) {
            return CarrierShell(
              session: session,
              providerApi: _deliveryProviderApi,
              orderApi: _orderApi,
              locale: _locale,
              onSignOut: _signOut,
            );
          }

          if (session.hasRole(DeliveryRole.delivery)) {
            return RiderHomeScreen(
              api: _orderApi,
              butlerApi: _butlerApi,
              trackingApi: _trackingApi,
              splitApi: _splitApi,
              moneyApi: _riderMoneyApi,
              performanceApi: _performanceApi,
              statementsApi: _statementsApi,
              // Settings' Documents and Bank Details rows. The same client the wizard and the
              // pending screen already use — an approved rider resolves their own application
              // from their token, so the applicant-facing route is the one that answers here.
              documentsApi: _documentsApi,
              chatApi: _chatApi,
              socket: _socket,
              prefsApi: _prefsApi,
              session: session,
              locale: _locale,
              pendingApproval: pending,
              onSignOut: _signOut,
            );
          }
          // A merchant gets their shop, not a basket. Before this the branch knew only about
          // riders and treated everyone else as a shopper, so the person running the shop landed
          // in the storefront with no way to see their own orders; then it gave them a queue and
          // nothing else. The redesign gives them the four-tab app — dashboard, queue, catalogue,
          // settings — mounting the same screens the web portal runs.
          if (session.hasRole(DeliveryRole.merchant)) {
            return MerchantShell(
              orderApi: _orderApi,
              storeApi: _storeApi,
              catalogApi: _catalogApi,
              aggregatesApi: _aggregatesApi,
              documentsApi: _documentsApi,
              prefsApi: _prefsApi,
              // The same client the rider shell is handed two branches down. Its absence here is
              // what left the merchant statement screen unreachable in the shipping app.
              statementsApi: _statementsApi,
              session: session,
              locale: _locale,
              pendingApproval: pending,
              onSignOut: _signOut,
            );
          }
          return _customerShell(session);
        },
      ),
      ),
    );
  }
}
