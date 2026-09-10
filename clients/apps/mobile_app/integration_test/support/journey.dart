
/// The shared mechanics every business-flow scenario needs: waiting, signing in, and saying where
/// it got to.
///
/// <p>Six integration tests each grew their own copy of `_pumpUntil` and their own thirty lines of
/// sign-in. That was fine when each one signed in once as one role. A scenario that walks an order
/// from a customer's basket to a rider's hand signs in three times, and three copies of a subtle
/// race guard is how one of them quietly loses it.
///
/// <p><strong>Why none of this uses `pumpAndSettle`.</strong> Every shell in this app runs
/// permanent timers — the merchant queue refreshes every 5s, the rider board every 5s and pings
/// every 10s, the customer's orders poll every 5s, the notification inbox every 15s — and several
/// screens draw an indeterminate `CircularProgressIndicator`, which schedules frames forever.
/// `pumpAndSettle` either times out or, worse, returns at a moment unrelated to whether the data
/// arrived. Polling for the widget the step is actually about is the only question worth asking.
library;

import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/customer_nav_bar.dart';
import 'package:mobile_app/src/one_time_code.dart';
import 'package:mobile_app/src/profile_drawer.dart';
import 'package:mobile_app/src/rider_home_screen.dart';
import 'package:mobile_app/src/rider_settings_widgets.dart';
import 'package:mobile_app/src/sign_in_screen.dart';
import 'package:mobile_app/src/store_home_screen.dart';

/// Pumps a frame at a time until [finder] matches, and reports whether it did.
Future<bool> appearsWithin(WidgetTester tester, Finder finder, Duration timeout) async {
  const Duration step = Duration(milliseconds: 100);
  final int budget = timeout.inMilliseconds ~/ step.inMilliseconds;
  for (int i = 0; i < budget; i++) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) {
      // One more frame once it exists, so anything read or tapped afterwards comes off a laid-out
      // tree rather than off the frame that introduced it.
      await tester.pump(step);
      return true;
    }
  }
  return false;
}

/// [appearsWithin], but a timeout is a failure carrying a sentence about what it means.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 45),
  required String reason,
}) async {
  if (await appearsWithin(tester, finder, timeout)) return;
  fail('Timed out after ${timeout.inSeconds}s waiting for $finder. $reason');
}

/// The mirror image, for waiting out a route that is popping.
Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  required String reason,
}) async {
  const Duration step = Duration(milliseconds: 100);
  final int budget = timeout.inMilliseconds ~/ step.inMilliseconds;
  for (int i = 0; i < budget; i++) {
    await tester.pump(step);
    if (finder.evaluate().isEmpty) {
      await tester.pump(step);
      return;
    }
  }
  fail('Timed out after ${timeout.inSeconds}s waiting for $finder to go away. $reason');
}

/// Keeps pumping for a fixed stretch, letting timers and network work run.
Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  const Duration step = Duration(milliseconds: 100);
  for (int i = 0; i < duration.inMilliseconds ~/ step.inMilliseconds; i++) {
    await tester.pump(step);
  }
}

/// Narrates a scenario as it runs, so a red run reads as a story rather than as a stack trace.
void step(String what) => debugPrint('  ·  $what');

/// The English string table, read out of the ARB rather than typed from memory.
DeliveryStrings get en => lookupDeliveryStrings(const Locale('en'));

/// Signs in on the sign-in screen that is currently showing.
///
/// <p>Everything here is load-bearing and every line of it was learned from a real intermittent
/// failure in one of the six tests that came before:
///
/// <ul>
///   <li><strong>Locale normalisation.</strong> `MaterialApp` is handed a null locale until the
///       saved preference resolves, so an Arabic phone — or an 'ar' left in secure storage by an
///       earlier run — renders every finder below in Arabic and none of them match. The pill names
///       the language you would switch TO, so a literal "English" on screen means the app is
///       currently Arabic.
///   <li><strong>The prefill race.</strong> `SignInScreen.initState` fires `_prefillLastLogin()`,
///       which reads secure storage and then does `setState(() => _username.text = last)`. If that
///       lands after this types, it silently replaces the username and the sign-in fails as bad
///       credentials — intermittently. In a role-switching scenario this is not a rare race but
///       the normal case, because the previous role's username is exactly what is stored.
///   <li><strong>Fields by hint, not by position.</strong> A device with a fingerprint enrolment
///       and a stashed session grows a "Continue as …" card above the fields, and
///       `find.byType(TextField).at(0)` stops meaning the username.
/// </ul>
Future<void> signIn(
  WidgetTester tester,
  String username,
  String passcode, {
  required Type expectedShell,
  Duration shellTimeout = const Duration(seconds: 90),
}) async {
  await pumpUntil(
    tester,
    find.byType(SignInScreen),
    timeout: const Duration(seconds: 60),
    reason: 'The app never reached the sign-in screen. The usual cause is a session left in secure '
        'storage by an earlier run, which makes AuthService.restore() succeed and drops the app '
        'straight onto a signed-in shell. Run `adb shell pm clear com.delivery.mobile_app` first.',
  );

  if (find.text(en.english).evaluate().isNotEmpty) {
    await tester.tap(find.byIcon(Icons.language));
    await pumpUntil(tester, find.text(en.authLogIn),
        reason: 'The app is in Arabic and tapping the language pill did not return it to English.');
  }

  final Finder usernameField = find.byWidgetPredicate(
    (Widget w) => w is TextField && w.decoration?.hintText == en.authEmailOrPhoneHint,
    description: 'the username field',
  );
  final Finder passcodeField = find.byWidgetPredicate(
    (Widget w) => w is TextField && w.decoration?.hintText == en.authPasscodeHint,
    description: 'the passcode field',
  );
  expect(usernameField, findsOneWidget,
      reason: 'The username field is not on the sign-in screen in English.');

  // Let the prefill resolve BEFORE typing, rather than racing it.
  await pumpFor(tester, const Duration(seconds: 2));

  // Clear first. In a role switch the box already holds the PREVIOUS role's username, and
  // enterText replaces the selection rather than the contents on some engines.
  await tester.enterText(usernameField, '');
  await tester.pump();
  await tester.enterText(usernameField, username);
  await tester.enterText(passcodeField, passcode);
  await tester.pump();

  expect(tester.widget<TextField>(usernameField).controller?.text, username,
      reason: 'The username field no longer holds "$username". _prefillLastLogin() resolved after '
          'enterText and overwrote it with the previous role\'s stored login, so the sign-in that '
          'follows would fail as bad credentials for a reason unrelated to this scenario.');

  final Finder logIn = find.widgetWithText(AuthPrimaryButton, en.authLogIn);
  await tester.ensureVisible(logIn);
  await tester.pump();
  await tester.tap(logIn);

  if (!await appearsWithin(tester, find.byType(expectedShell), shellTimeout)) {
    final Finder note = find.byType(AuthErrorNote);
    final String detail = note.evaluate().isEmpty
        ? 'No error note is showing, so the token call has not come back at all — check the '
            '--dart-define values and that the realm is reachable from the device.'
        : 'The sign-in screen is still up, showing: '
            '"${tester.widget<AuthErrorNote>(note).message}"';
    fail('Signing in as $username never reached $expectedShell. $detail');
  }
  step('signed in as $username');
}

// ---------------------------------------------------------------------------------- signing out

/// Waits for the gate, after a sign-out from [leaving].
///
/// The two ways this hangs are worth naming in the failure, because neither looks like a bug in
/// the scenario: `main._signOut()` awaits `AuthService.signOut()`, which POSTs Keycloak's
/// end-session endpoint with no timeout — so a slow realm holds the old shell on screen — and the
/// role branch lives in `MaterialApp.home`, not on the route stack, so any route left pushed sits
/// on TOP of the sign-in screen and every finder below fails while the app is, in fact, signed out.
Future<void> backAtTheGate(WidgetTester tester, String leaving) async {
  await pumpUntil(
    tester,
    find.byType(SignInScreen),
    timeout: const Duration(seconds: 60),
    reason: 'Signing out of $leaving never returned the app to the gate. Either the Keycloak '
        'logout POST is stalling, or a pushed route is still on the navigator stack above it.',
  );
  // Deliberately NOT an assertion about BiometricLockScreen. That screen is structurally
  // unreachable at the gate — main.dart returns the signed-out branch on a null session and only
  // reaches the lock branch when a session exists — so asserting its absence would pass forever
  // and prove nothing. The stash's REAL footprint here is the "Continue as …" card, which appears
  // when sign-out kept the refresh token instead of revoking it, and which breaks a role switch
  // by pre-filling the departing account.
  expect(find.text(en.custNotYou), findsNothing,
      reason: 'The gate is showing a "Continue as …" card, so the sign-out kept the previous '
          'account\'s refresh token for biometrics rather than revoking it. Some account on this '
          'device has the fingerprint toggle on; reinstall before a multi-role scenario.');
  step('signed out of $leaving');
}

/// The customer's only sign-out in the shipped app: the home header avatar, then the drawer.
///
/// Not the Account tab. `main.dart` always passes a non-null `pointsApi`, and with one the Account
/// tab renders [RewardsScreen] — `AccountScreen`, the only customer surface with a sign-out
/// confirmation dialog, is built solely as the no-API fallback. So a scenario that goes looking for
/// a Log Out button on the Account tab is looking for a widget the real app never builds.
Future<void> signOutCustomer(WidgetTester tester) async {
  // The avatar resolves `Scaffold.of(context).openDrawer()` against the SHELL scaffold, so the
  // Home tab has to be the selected one — a tap on an unpainted IndexedStack child is silently
  // swallowed, and `tester.tap` only warns.
  final Finder home = find.descendant(
      of: find.byType(CustomerNavBar), matching: find.text(en.navHome));
  if (home.evaluate().isNotEmpty) {
    await tester.tap(home);
    await pumpFor(tester, const Duration(milliseconds: 600));
  }

  await tester.tap(find.descendant(
    of: find.byType(StoreHomeScreen),
    matching: find.byWidgetPredicate(
      (Widget w) => w is Semantics && w.properties.label == en.custAccountSettings,
      description: 'the home-header avatar that opens the ProfileDrawer',
    ),
  ));
  await pumpUntil(tester, find.byType(ProfileDrawer),
      timeout: const Duration(seconds: 15),
      reason: 'The header avatar did not open the profile drawer.');

  await tester.tap(find.descendant(
      of: find.byType(ProfileDrawer),
      matching: find.widgetWithText(YdPillButton, en.custLogOutAccount)));
  await tester.pump();
  await backAtTheGate(tester, 'the customer');
}

/// The merchant's sign-out: Settings tab, scroll to the bottom of the list, then confirm.
///
/// The merchant is the one role that asks. `find.text(signOut)` matches TWICE in that dialog — the
/// title and the confirm button — so the tap has to be scoped to the button or it fails as an
/// ambiguous finder rather than as anything meaningful.
Future<void> signOutMerchant(WidgetTester tester) async {
  await tester.tap(find.descendant(
      of: find.byType(YdBottomNav), matching: find.text(en.navSettings)));
  await pumpUntil(tester, find.byType(MerchantSettingsScreen),
      timeout: const Duration(seconds: 20),
      reason: 'The Settings tab did not build. MerchantShell renders SizedBox.shrink() until the '
          'tab is in its visited set, so this needs a frame or two rather than an instant read.');

  final Finder logOut = find.descendant(
      of: find.byType(MerchantSettingsScreen), matching: find.text(en.merchbLogOutAccount));
  final Finder list = find.descendant(
      of: find.byType(MerchantSettingsScreen), matching: find.byType(ListView));
  for (int i = 0; i < 40 && logOut.evaluate().isEmpty; i++) {
    await tester.drag(list, const Offset(0, -250));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(logOut, findsOneWidget,
      reason: 'The Log Out row never came into the list. It is the last child of the settings '
          'ListView, so it is below the fold on a phone until the list is dragged up.');
  // The loop stops as soon as the finder MATCHES, and a ListView builds a cache extent beyond the
  // viewport — so the row can exist without being on screen. Hence ensureVisible before the tap.
  await tester.ensureVisible(logOut);
  await tester.pump();
  await tester.tap(logOut);
  await tester.pump();

  await pumpUntil(tester, find.byType(AlertDialog),
      timeout: const Duration(seconds: 10),
      reason: 'Pressing Log Out did not raise the confirmation dialog.');
  await tester.tap(find.widgetWithText(ElevatedButton, en.signOut));
  await tester.pump();
  await backAtTheGate(tester, 'the merchant');
}

/// The rider's sign-out: Settings tab, scroll, press. No dialog on this path.
Future<void> signOutRider(WidgetTester tester) async {
  await tester.tap(find.descendant(
      of: find.byType(YdBottomNav), matching: find.text(en.settings)));
  await pumpFor(tester, const Duration(milliseconds: 800));

  final Finder logOut = find.byType(RiderLogOutButton);
  final Finder list = find.descendant(
      of: find.byType(RiderHomeScreen), matching: find.byType(ListView));
  for (int i = 0; i < 40 && logOut.evaluate().isEmpty; i++) {
    if (list.evaluate().isEmpty) break;
    await tester.drag(list.first, const Offset(0, -250));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(logOut, findsOneWidget, reason: 'The rider Log Out button is not on the Settings tab.');
  await tester.ensureVisible(logOut);
  await tester.pump();
  await tester.tap(logOut);
  await tester.pump();
  await backAtTheGate(tester, 'the rider');
}

/// Every string currently rendered, for a failure that needs to say what WAS there rather than
/// only what was not.
///
/// A finder that matches nothing is the least informative failure a widget test can produce: the
/// screen it was looking at could be the wrong one, an error state, a spinner, or the right screen
/// with one word changed. Printing the actual text turns all four into different sentences.
String describeScreen(WidgetTester tester) {
  final List<String> seen = <String>[];
  for (final Element e in find.byType(Text).evaluate()) {
    final Text t = e.widget as Text;
    final String? s = t.data ?? t.textSpan?.toPlainText();
    if (s != null && s.trim().isNotEmpty) seen.add(s.trim());
  }
  return seen.isEmpty ? '(no text on screen)' : seen.join(' | ');
}

/// [Finder.first] that answers "nothing matched" instead of throwing.
///
/// `find.ancestor(…).first` is the natural way to name one card among many, and it is a trap in a
/// polling helper: `.first` calls `Iterable.first` while evaluating, so on a frame where nothing
/// matches yet it throws `Bad state: No element` rather than returning an empty result. The poll
/// then dies on its first tick with a message about iterables, several screens away from the
/// step that was actually waiting for something to arrive.
///
/// Wait on the unfiltered finder, and use this only where exactly one is needed.
extension SafeFirst on Finder {
  Finder get firstOrNothing => evaluate().isEmpty ? this : first;
}
