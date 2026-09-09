import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_app/main.dart' as app;
import 'package:mobile_app/src/customer_nav_bar.dart';
import 'package:mobile_app/src/customer_shell.dart';
import 'package:mobile_app/src/one_time_code.dart';
import 'package:mobile_app/src/sign_in_screen.dart';
import 'package:mobile_app/src/splash_screen.dart';

/// Cold start to a signed-in customer, against the real dev backend.
///
/// <p>The bug report this exists for is one sentence on the sign-in screen — "We could not reach
/// the server." — after a password that is known to be correct. That sentence is the
/// `couldNotReachTheServer` string, and on this screen it is set by the trailing `catch (_)` in
/// `_submit` (sign_in_screen.dart:271-279), which is a *generic* catch: it fires for a dead
/// network, for a TLS refusal, for a cleartext-policy block, and — the interesting case — for
/// anything that throws out of `widget.onSignedIn(session)` on line 261, which runs INSIDE the same
/// try. So the sentence does not actually mean "the server is unreachable". It means "something
/// went wrong somewhere between typing the passcode and the app being signed in".
///
/// <p><strong>Why the test is written as a pair of assertions.</strong> Asserting only that the
/// sentence is absent proves nothing: it is absent on the splash, absent on the untouched form, and
/// absent on a blank screen after a crash. The load-bearing half is
/// `expect(find.byType(CustomerShell), findsOneWidget)` — the app got a token, decoded a role claim
/// out of it, and mounted the customer surface. The negative assertion is what names the bug; the
/// positive one is what stops the negative from being a lie. Neither line is redundant and neither
/// should be deleted as such.
///
/// <p><strong>This test is deliberately network-dependent.</strong> There is no way to prove "the
/// app can talk to the backend" without the backend. A red run here means investigate — the dev
/// environment, the defines, or the app — it does not mean revert.
///
/// <p><strong>How to run it.</strong> The defines are not optional. Without them main.dart falls
/// back to `http://192.168.10.24:8100`, which is not in
/// `android/app/src/main/res/xml/network_security_config.xml`, so Android blocks the request as
/// cleartext, the block lands in that same generic catch, and the test fails on the exact string it
/// is asserting against — for a build-configuration reason rather than a product one.
///
/// ```
/// adb uninstall com.delivery.mobile_app
/// flutter test integration_test/boot_and_reach_test.dart \
///   --flavor dev \
///   --dart-define=API_BASE_URL=https://api-dev.youdrop.shop \
///   --dart-define=KEYCLOAK_ISSUER=https://iam-dev.youdrop.shop/realms/delivery-platform
/// ```
///
/// <p>The uninstall is part of the test, not housekeeping around it. A successful sign-in writes
/// `delivery.refresh_token` into secure storage, and on the next cold start `restore()` returns a
/// session, main.dart takes the signed-in branch and [SignInScreen] never renders — so every step
/// below the gate fails. The same wipe clears `delivery.locale` (a stale Arabic preference would
/// fail every `find.text` here) and the biometric stash (which would draw a "Continue as" card
/// above the fields). This is a fresh-install journey by nature; that is why there is exactly one
/// test in this file and not two.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Read out of packages/delivery_l10n/lib/l10n/app_en.arb rather than typed from memory. The keys
  // are named so a reviewer can check the pairing without leaving this file.
  const String couldNotReachTheServer =
      'We could not reach the server. Check your connection and try again.'; // couldNotReachTheServer
  const String logIn = 'Log In'; // authLogIn
  const String navHome = 'Home'; // navHome
  const String navBasket = 'Basket'; // navBasket

  // The seeded demo customer on dev. Six digits exactly: `_submitCredentials` rejects any other
  // length with passcodeMustBeSixDigits before a request is ever made, so a typo here would look
  // like a validation bug rather than a wrong constant.
  const String username = 'customer';
  const String passcode = '100001';

  /// Pumps real frames until [ready] holds or [timeout] elapses, and reports which.
  ///
  /// `pumpAndSettle` cannot be used anywhere in this test, at either end. The splash holds a
  /// [CircularProgressIndicator] for its full [SplashScreen.hold]; the Log In button swaps its
  /// label for another one while the request is in flight; and once [CustomerShell] mounts there
  /// are three `Timer.periodic` instances that never stop — the notification poll every 15s
  /// (notification_inbox.dart:41), the search-hint rotator every 2800ms and the banner carousel
  /// every 4s (store_home_screen.dart:127 and :132), the last two driving AnimatedSwitchers. The
  /// tree never reaches a quiet frame, so pumpAndSettle would burn its timeout and throw on a run
  /// that is actually going fine.
  ///
  /// Returning a bool rather than asserting is deliberate: the caller decides what a timeout means,
  /// and gets to fail on the assertion that explains it instead of on a helper.
  Future<bool> pumpUntil(
    WidgetTester tester,
    bool Function() ready, {
    required Duration timeout,
    Duration step = const Duration(milliseconds: 100),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (ready()) {
        return true;
      }
      await tester.pump(step);
    }
    return ready();
  }

  bool isOnScreen(Finder finder) => finder.evaluate().isNotEmpty;

  /// Whatever the sign-in screen is currently complaining about, or null.
  ///
  /// Both failure modes render an [AuthErrorNote]: a rejected credential carries Keycloak's own
  /// words through `AuthException`, and everything else carries couldNotReachTheServer. Lifting the
  /// message into the failure reason is the difference between "CustomerShell was not found" and
  /// knowing the realm answered "Account is disabled".
  String? authErrorOnScreen(WidgetTester tester) {
    final Iterable<AuthErrorNote> notes =
        tester.widgetList<AuthErrorNote>(find.byType(AuthErrorNote));
    return notes.isEmpty ? null : notes.first.message;
  }

  testWidgets(
    'a cold start signs customer/100001 in against the live dev backend',
    (WidgetTester tester) async {
      // The real entrypoint, not a hand-rolled `pumpWidget(DeliveryMobileApp())`. Awaiting it
      // matters more than it looks: main() awaits `Firebase.initializeApp()` before runApp, and
      // skipping that would poison this test in the most confusing way available. `_adoptSession`
      // touches `late final DeviceTokenRegistrar`, whose initialiser evaluates
      // `FirebaseMessaging.instance` outside `register()`'s own try/catch — with Firebase
      // uninitialised that throws, unwinds into `_submit`'s generic catch, and paints
      // couldNotReachTheServer on top of a sign-in that completely succeeded. Booting the app the
      // way the app boots is what keeps the assertion below about the product.
      await app.main();
      await tester.pump();

      // The splash is held a minimum of SplashScreen.hold (1900ms) even when there is no session to
      // restore, so the first real screen cannot be asserted before it clears. The wait is far
      // longer than the hold because `restore()` is inside the same future and will hit the network
      // if a refresh token exists.
      final bool gateReached = await pumpUntil(
        tester,
        () => isOnScreen(find.byType(SignInScreen)),
        timeout: const Duration(seconds: 30),
      );

      // Asserted before the gate itself so a hang has its own failure. If the app is still on the
      // splash after 30s the bootstrap future never completed, which is a different problem from
      // landing on the wrong screen, and the two should not share a message.
      expect(
        find.byType(SplashScreen),
        findsNothing,
        reason: 'The splash never cleared. _restoreAfterSplash is still pending after 30s, so '
            'either the 1900ms hold or AuthService.restore() is stuck — nothing below this line '
            'has been exercised.',
      );
      expect(
        find.byType(SignInScreen),
        findsOneWidget,
        reason: gateReached
            ? 'Something other than SignInScreen is the cold-start landing.'
            : 'The cold-start gate never appeared. main.dart defaults _gate to _Gate.signIn and '
                'returns SignInScreen for a null session, so the likely cause is a session that '
                'survived from an earlier run — uninstall the app and run again.',
      );

      // The locale check, and it comes first on purpose. Every remaining finder is an English
      // string, and LocaleController starts as "follow the device" over [en, ar] with a persisted
      // override. An Arabic device — or a run after somebody tapped the AR pill on this screen —
      // renders every one of them in Arabic. Failing here says "the app is not in English"; failing
      // four lines later says "Log In is missing", which sends the reader hunting for a layout bug
      // that does not exist.
      expect(
        find.widgetWithText(AuthPrimaryButton, logIn),
        findsOneWidget,
        reason: 'authLogIn did not resolve to English. The device locale or the persisted '
            'delivery.locale is Arabic, and every find.text below this line is about to fail for '
            'that reason and no other.',
      );

      // The credentials step draws exactly one AuthField (the address) and one raw obscured
      // TextField (the passcode). This guards the password finder below, which is a predicate over
      // obscureText and quietly stops being unique the day a second obscured field appears here.
      expect(
        find.byType(AuthField),
        findsOneWidget,
        reason: 'The sign-in form is not the credentials step this test was written against.',
      );

      // The form sits in a SliverFillRemaining inside a CustomScrollView, so on a short viewport the
      // fields can start below the fold.
      await tester.ensureVisible(find.byType(AuthField));
      await tester.pump();

      // enterText replaces the field's contents, which matters because _prefillLastLogin puts the
      // previous successful identifier here on any device that has signed in before.
      await tester.enterText(find.byType(AuthField), username);
      await tester.pump();

      // Addressed by what it IS rather than by its position. Both fields are TextFields and
      // `find.byType(TextField).at(1)` would depend on the order the form happens to build them in;
      // only the passcode is obscured, and that is a property of the credential, not of the layout.
      final Finder passcodeField = find.byWidgetPredicate(
        (Widget widget) => widget is TextField && widget.obscureText,
        description: 'the obscured TextField (the six-digit passcode)',
      );
      expect(
        passcodeField,
        findsOneWidget,
        reason: 'The passcode field is identified by obscureText alone, and that is no longer '
            'unique on this screen.',
      );
      await tester.enterText(passcodeField, passcode);
      await tester.pump();

      // The button, not the keypad icon in the field's suffix — that one pushes the PasscodePad
      // step, which needs six separate digit taps and a different set of finders entirely. The
      // ensureVisible is for the same reason as the one above the address field: this column is
      // taller than a small phone's viewport, and a tap that lands outside the viewport is a
      // failure with nothing to do with sign-in.
      final Finder loginButton = find.widgetWithText(AuthPrimaryButton, logIn);
      await tester.ensureVisible(loginButton);
      await tester.pump();
      await tester.tap(loginButton);
      await tester.pump();

      // The live round trip: an OAuth password grant against iam-dev, then a role decode. Bounded
      // at 60s because this crosses the public internet, and broken early on either outcome so a
      // rejection is reported in seconds rather than after the full wait. AuthErrorNote covers both
      // failure branches of _submit, so the loop ends the moment the screen has an answer.
      //
      // A brief second SplashScreen flickers past in here — _adoptSession replaces the bootstrap
      // future, and FutureBuilder spends one turn in ConnectionState.waiting — which is why no
      // assertion about the splash belongs after the tap.
      await pumpUntil(
        tester,
        () =>
            isOnScreen(find.byType(CustomerShell)) ||
            isOnScreen(find.byType(AuthErrorNote)),
        timeout: const Duration(seconds: 60),
      );

      final String? shownError = authErrorOnScreen(tester);

      // THE assertion from the bug report.
      expect(
        find.text(couldNotReachTheServer),
        findsNothing,
        reason: 'The reported sentence is on screen after a passcode that is known to be good. '
            'It comes from the generic catch in _submit, so it is one of: the device genuinely '
            'could not reach iam-dev.youdrop.shop; the build is missing its --dart-define pair '
            'and went to the 192.168.10.24 default, which Android blocks as cleartext; or '
            'something threw out of onSignedIn AFTER a successful token exchange — the '
            'DeviceTokenRegistrar / FirebaseMessaging.instance path being the known candidate.',
      );

      // The half that makes the line above honest. findsNothing passes on the splash, on the
      // untouched form and on a blank screen; this is the one that says a token came back, carried
      // a CUSTOMER role and no APPLICANT/CARRIER/DELIVERY/MERCHANT, and put the customer app on
      // screen. It also catches realm drift: re-seed the demo account with APPLICANT and main.dart
      // diverts to PendingApplicationScreen while the assertion above still passes.
      expect(
        find.byType(CustomerShell),
        findsOneWidget,
        reason: shownError == null
            ? 'Sign-in produced no session and no error note within 60s. The request is still in '
                'flight, or the role branch in main.dart put this account somewhere other than '
                'CustomerShell.'
            : 'Sign-in failed and the screen says: "$shownError". A credential message here means '
                'the demo account has changed; anything else means the round trip did not '
                'complete.',
      );

      // The gate is gone rather than merely covered — the FutureBuilder took the signed-in branch,
      // so there is no login screen sitting behind the app for a back gesture to land on.
      expect(find.byType(SignInScreen), findsNothing);

      // Scoped to the nav bar on purpose. Bare find.text('Home') is ambiguous here on two counts:
      // custLabelHome is also "Home" and the home header renders whatever label the saved address
      // carries, and CustomerShell's IndexedStack builds all five tabs at once — it wraps the
      // unselected ones in _VisibilityScope and ExcludeFocus and lets RenderIndexedStack skip
      // painting them, so there is no Offstage in the tree and the default skipOffstage finders
      // match their text anyway. Reading the labels off CustomerNavBar proves the shell mounted
      // with its own chrome and cannot be satisfied by a coincidence elsewhere in the tree. They
      // are pure l10n, so unlike storefront content they do not depend on the dev catalog having
      // anything in it.
      final Finder navBar = find.byType(CustomerNavBar);
      expect(find.descendant(of: navBar, matching: find.text(navHome)),
          findsOneWidget);
      expect(find.descendant(of: navBar, matching: find.text(navBasket)),
          findsOneWidget);
    },
    // Generous, but not unbounded: the two waits inside can account for 90s, and a test that hangs
    // past this should fail rather than hold the suite open.
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
