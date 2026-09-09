import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_app/main.dart' as app;
import 'package:mobile_app/src/biometric_lock_screen.dart';
import 'package:mobile_app/src/merchant_shell.dart';
import 'package:mobile_app/src/one_time_code.dart';
import 'package:mobile_app/src/sign_in_screen.dart';

// That a shop can sign in on a phone and reach all five of its own screens.
//
// test/merchant_shell_wiring_test.dart already proves the shell HANDS the right clients to the
// right screens, and it proves it by constructing MerchantShell directly with a stub Dio and a
// hand-built AuthSession. That is a statement about the shell. It is not a statement about the app:
// nothing in it touches main.dart's role branch, AuthService, or the token a real Keycloak issues,
// so a merchant account could be routed to the customer storefront — which is exactly what the app
// used to do, and what the branch comment at main.dart:750 exists to remember — and that file would
// stay green.
//
// This one boots main() itself, types a real credential into the app's own form, and walks the nav
// the way a merchant's thumb does. The failures it is here to catch are the joins: a role claim
// that stops reaching the merchant branch, a tab that stops being built, a nav item that stops
// switching the IndexedStack.
//
// WHAT IT NEEDS FROM THE MACHINE RUNNING IT, all three of which are silent when missing:
//
//   1. The backend addresses. main.dart:82-93 defaults to a LAN IP that answers nowhere on CI, and
//      `flutter test integration_test/` does NOT inherit the run configuration's defines, so they
//      have to be repeated on the command line:
//
//        flutter test integration_test/merchant_shell_test.dart -d <device-id> \
//          --dart-define=API_BASE_URL=https://api-dev.youdrop.shop \
//          --dart-define=KEYCLOAK_ISSUER=https://iam-dev.youdrop.shop/realms/delivery-platform
//
//      Without them the token call sits on a TCP timeout for ~30s and the screen says
//      t.couldNotReachTheServer, which reads exactly like a wrong passcode.
//
//   2. A clean install. A session left in secure storage by an earlier run sends the app straight
//      past the sign-in screen, and a `delivery.locale` of 'ar' renders every string below in
//      Arabic. Both are detected and named below rather than left to surface as a missing widget.
//
//   3. On Android 13+, the notification permission already granted:
//        adb shell pm grant com.delivery.mobile_app android.permission.POST_NOTIFICATIONS
//      DeviceTokenRegistrar.register() fires the instant sign-in succeeds and puts an OS dialog
//      over the app. It is outside the Flutter tree, so the widget assertions keep passing while
//      the first tap on the bottom nav is swallowed by it.

/// The demo shop on the dev realm. Six digits because the realm's credential is a passcode, and the
/// field refuses anything else — see the LengthLimitingTextInputFormatter at sign_in_screen.dart:528.
const String _username = 'merchant';
const String _passcode = '200002';

/// Pumps a frame at a time until [finder] matches, or the deadline passes.
///
/// Deliberately not [WidgetTester.pumpAndSettle], and not as a style preference. Every screen on
/// this journey mounts an indeterminate CircularProgressIndicator at some point — SplashScreen
/// while the stored session is looked for, AuthPrimaryButton during the token call, and the
/// dashboard, orders, inventory and POS tabs while their first request is in flight. A spinner
/// schedules a frame forever, so pumpAndSettle never reaches the quiet frame it waits for: it runs
/// to its own timeout and throws while the app is working perfectly. The shell also polls its order
/// badge every 30 seconds, so this tree is never quiescent by design. Polling asks the only
/// question that matters — is the thing I am waiting for on screen yet.
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 40),
  required String reason,
}) async {
  const Duration step = Duration(milliseconds: 100);
  final int budget = timeout.inMilliseconds ~/ step.inMilliseconds;
  for (int i = 0; i < budget; i++) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) {
      // One more frame once it exists, so anything read off it afterwards comes from a laid-out
      // tree rather than from the frame that introduced it.
      await tester.pump(step);
      return;
    }
  }
  fail('Timed out after ${timeout.inSeconds}s waiting for $finder. $reason');
}

/// Switches tabs through the shell's own bottom bar, which is the only way a merchant can.
///
/// The scope to [YdBottomNav] is not tidiness. t.navInventory and t.invTitle are both exactly
/// "Inventory", so an unscoped find.text('Inventory') matches two widgets once that tab is up and
/// the tap would fail on an ambiguous finder; t.navDashboard is likewise the dashboard header's
/// fallback shop name when storeApi.mine() comes back empty (dashboard_screen.dart:372). The nav
/// bar sits outside the IndexedStack and is on screen for all five tabs, so scoping to it also
/// means this helper can never accidentally be satisfied by body text.
Future<void> _openTab(WidgetTester tester, String label) async {
  final Finder item = find.descendant(
    of: find.byType(YdBottomNav),
    matching: find.text(label),
  );
  expect(item, findsOneWidget,
      reason: 'The shell did not draw a "$label" destination. _visibleTabs() gives all five to an '
          'owner (merchant_shell.dart:195-202), so a missing one means the staff lookup demoted a '
          'MERCHANT account below owner.');
  await tester.tap(item);
  // One frame for _open()'s setState, then slack for the tab's first build — it is being
  // constructed for the very first time here, because _tabAt returns SizedBox.shrink() for
  // anything not yet in _visited (merchant_shell.dart:215).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a merchant signs in and reaches all five shop tabs',
      (WidgetTester tester) async {
    // The real cold start. WidgetsFlutterBinding.ensureInitialized() inside main() returns the
    // integration binding created above, Firebase init runs in its own try/catch, then runApp.
    await app.main();

    // ------------------------------------------------------------------ the sign-in screen
    //
    // Anchored on the widget type rather than on a string, because a device left in Arabic would
    // otherwise fail here with "found 0 widgets with text 'Log In'" and send whoever reads it
    // looking for a bug in the sign-in screen. The locale is checked separately, below.
    await _reachSignIn(tester);

    // The copy this test is written against, read out of packages/delivery_l10n/lib/l10n/app_en.arb
    // and checked once here against the table the running app actually resolved.
    //
    // This is a guard on the test, not on the app, and it earns its place twice. An Arabic device —
    // or a `delivery.locale` of 'ar' left in secure storage by an earlier session — renders every
    // string below in Arabic, and without this the first symptom is a missing widget three
    // assertions later. And if somebody rewords a key, this says which one instead of leaving a
    // find.text() to come up empty.
    final DeliveryStrings t =
        DeliveryStrings.of(tester.element(find.byType(SignInScreen)));
    expect(
      <String, String>{
        'authLogIn': t.authLogIn,
        'navDashboard': t.navDashboard,
        'navPos': t.navPos,
        'navInventory': t.navInventory,
        'navOrders': t.navOrders,
        'navSettings': t.navSettings,
        'posTitle': t.posTitle,
        'invTitle': t.invTitle,
        'merchOrderFlow': t.merchOrderFlow,
        'merchManagerView': t.merchManagerView,
        'merchbAccountSettings': t.merchbAccountSettings,
        'merchbAppLanguage': t.merchbAppLanguage,
        'merchbShopProfile': t.merchbShopProfile,
      },
      <String, String>{
        'authLogIn': 'Log In',
        'navDashboard': 'Dashboard',
        'navPos': 'POS',
        'navInventory': 'Inventory',
        'navOrders': 'Orders',
        'navSettings': 'Settings',
        'posTitle': 'Point of sale',
        'invTitle': 'Inventory',
        'merchOrderFlow': 'Order Flow',
        'merchManagerView': 'Manager View',
        'merchbAccountSettings': 'Account Settings',
        'merchbAppLanguage': 'App Language',
        'merchbShopProfile': 'Shop Profile',
      },
      reason: 'The app did not resolve the English string table, or a key was reworded. Every '
          'find.text() below is the literal English value from app_en.arb; if this app is running '
          'in Arabic, uninstall it and run again on a clean install.',
    );

    // Sign-in is the app's own form, not a browser: AuthService.signInWithPassword posts the OAuth
    // password grant straight to Keycloak (auth_service.dart:153), so there is no Custom Tab to
    // escape and the whole thing is drivable from here.
    expect(find.widgetWithText(AuthPrimaryButton, 'Log In'), findsOneWidget);

    // The guard that keeps the index-based finder below honest. The credentials step draws exactly
    // one AuthField, which wraps one TextField (one_time_code.dart:210), plus the one raw TextField
    // the passcode uses (sign_in_screen.dart:517). If a third field is ever added, this fails loudly
    // rather than silently typing a passcode into the wrong box.
    expect(find.byType(TextField), findsNWidgets(2),
        reason: 'The credentials step no longer draws exactly two text fields, so "the last one is '
            'the passcode" is no longer true.');

    await tester.enterText(
      find.descendant(of: find.byType(AuthField), matching: find.byType(TextField)),
      _username,
    );

    // enterText replaces the whole value, so _prefillLastLogin() (sign_in_screen.dart:92) having
    // already put a previous username in the field is harmless.
    final Finder passcodeField = find.byType(TextField).last;
    expect(tester.widget<TextField>(passcodeField).obscureText, isTrue,
        reason: 'The last text field on the credentials step is not the obscured passcode one, so '
            'the credential is about to be typed into the username box.');
    await tester.enterText(passcodeField, _passcode);

    // Both fields call setState from onChanged; this is the frame that lands before the tap.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(AuthPrimaryButton, 'Log In'));

    // ------------------------------------------------------------------ the role branch
    //
    // A real token round trip over the public internet, then main.dart's branch: carrier (717)
    // wins first, delivery (727) second, and only an account that is neither lands on the shell
    // below. If merchant/200002 ever picks up one of those claims on the dev realm this is where
    // it shows, and the message says so — the client cannot see the realm and nothing here pins it.
    await _pumpUntil(
      tester,
      find.byType(MerchantShell),
      timeout: const Duration(seconds: 60),
      reason: 'Signed in but never reached the shop. Either the credential was refused (the screen '
          'will be showing the reason), the backend addresses were not passed as --dart-define, or '
          'this account carries CARRIER or DELIVERY, which main.dart branches on before MERCHANT.',
    );

    // TAB 1 of 5 — the dashboard, which _MerchantShellState opens on: _tab starts at
    // MerchantTab.dashboard and _visited starts as {dashboard} (merchant_shell.dart:104-107).
    //
    // Only the widget type is asserted for this tab, and that is deliberate. The dashboard renders
    // its body — and therefore t.welcomeBack — only once orderApi.merchantSummary() has answered,
    // and shows t.couldNotLoadOrdersShort if it fails (dashboard_screen.dart:287-291). Asserting on
    // the greeting would make this test a monitor for order-manager's uptime rather than a test of
    // the shell. The byType assertion is network-independent and still real: non-selected
    // IndexedStack children are skipped by default finders, so it fails the moment the shell stops
    // opening on this tab.
    expect(find.byType(MerchantDashboardScreen), findsOneWidget);
    expect(find.descendant(of: find.byType(YdBottomNav), matching: find.text('Dashboard')),
        findsOneWidget);

    // TAB 2 of 5 — the register.
    await _openTab(tester, 'POS');
    expect(find.byType(PosTerminalScreen), findsOneWidget);
    // "Point of sale" is drawn by YdScreenHeader at pos_terminal_screen.dart:417-418, outside every
    // FutureBuilder, so this holds whether or not pos-service and catalog-service answer. Nothing
    // here touches the unavailable band above it: main.dart:141-142 says pos-service is not
    // deployed yet, so asserting it present would pin a temporary outage and asserting it absent
    // would fail today.
    expect(find.descendant(of: find.byType(PosTerminalScreen), matching: find.text('Point of sale')),
        findsOneWidget);
    // The teeth of the tab walk. Every findsOneWidget above would still pass if the IndexedStack
    // index had not moved and both screens were mounted at once; this is what proves the tap
    // actually changed tabs rather than just building a second screen behind the first.
    expect(find.byType(MerchantDashboardScreen), findsNothing);

    // TAB 3 of 5 — the shelves.
    await _openTab(tester, 'Inventory');
    expect(find.byType(InventoryScreen), findsOneWidget);
    // MerchantScreenHeader(title: t.invTitle) at inventory_screen.dart:368-369 sits above every
    // loading branch. The descendant scope is what makes findsOneWidget correct here rather than
    // findsNWidgets(2): the nav label one tap below says the same word.
    expect(find.descendant(of: find.byType(InventoryScreen), matching: find.text('Inventory')),
        findsOneWidget);
    expect(find.byType(PosTerminalScreen), findsNothing);

    // TAB 4 of 5 — the queue.
    await _openTab(tester, 'Orders');
    expect(find.byType(OrdersScreen), findsOneWidget);
    // orders_screen.dart:163-174 builds one MerchantScreenHeader and inserts it into both the
    // pinned wide branch and the sliver narrow one, so neither string depends on the viewport or on
    // order-manager answering.
    expect(find.descendant(of: find.byType(OrdersScreen), matching: find.text('Order Flow')),
        findsOneWidget);
    expect(find.descendant(of: find.byType(OrdersScreen), matching: find.text('Manager View')),
        findsOneWidget);
    expect(find.byType(InventoryScreen), findsNothing);

    // TAB 5 of 5 — settings, and the strongest tab in the journey: MerchantSettingsScreen is a
    // StatelessWidget whose build makes no network call at all (merchant_settings_screen.dart:
    // 111-141), so all three of these strings are unconditional.
    await _openTab(tester, 'Settings');
    expect(find.byType(MerchantSettingsScreen), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(MerchantSettingsScreen), matching: find.text('Account Settings')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(MerchantSettingsScreen), matching: find.text('App Language')),
        findsOneWidget);
    // Drawn unconditionally at line 254, but its onTap is non-null only because a MERCHANT-role
    // session is seeded as MerchantAccess.owner() — so this row is also the shell's ownership
    // decision, visible on screen.
    expect(
        find.descendant(of: find.byType(MerchantSettingsScreen), matching: find.text('Shop Profile')),
        findsOneWidget);
    expect(find.byType(OrdersScreen), findsNothing);

    // Closing the journey on the shell's own contract: an owner sees all five destinations, in nav
    // order, and the bar is still the same bar after four tab switches.
    //
    // Asserted as five named labels rather than as a count of Text widgets inside YdBottomNav,
    // because the Orders badge is also a Text in there (yd_bottom_nav.dart:113-129) and a count
    // would be five or six depending on whether the dev shop happens to have an unaccepted order
    // at the moment the test runs.
    for (final String label in const <String>[
      'Dashboard',
      'POS',
      'Inventory',
      'Orders',
      'Settings',
    ]) {
      expect(find.descendant(of: find.byType(YdBottomNav), matching: find.text(label)),
          findsOneWidget,
          reason: 'The shop lost its "$label" tab.');
    }
  });
}

/// Waits for the sign-in screen, and fails fast — by name — on the two device states that quietly
/// skip it.
///
/// A plain [_pumpUntil] would spend its whole budget and then report a missing SignInScreen, which
/// is true and useless. Both of the states below are leftovers from an earlier run rather than
/// anything the app did wrong, and both are fixed the same way: uninstall.
Future<void> _reachSignIn(WidgetTester tester) async {
  const Duration step = Duration(milliseconds: 100);
  // Generous on purpose. SplashScreen holds for SplashScreen.hold — 1.9 seconds — before the gate
  // is built at all, and the frames either side of it compete with Firebase init and two
  // platform-channel reads on a cold app.
  const int budget = 40000 ~/ 100;

  for (int i = 0; i < budget; i++) {
    await tester.pump(step);
    if (find.byType(SignInScreen).evaluate().isNotEmpty) {
      await tester.pump(step);
      return;
    }
    if (find.byType(MerchantShell).evaluate().isNotEmpty) {
      fail('The app restored a session and went straight to the shop, so the sign-in half of this '
          'journey never ran. Uninstall the app and run again — this test is a cold start.');
    }
    if (find.byType(BiometricLockScreen).evaluate().isNotEmpty) {
      fail('A stored session is sitting behind the fingerprint lock, which no test can answer: it '
          'is an OS prompt outside the Flutter tree. Uninstall the app and run again.');
    }
  }
  fail('Timed out after 40s without reaching the sign-in screen, the shop, or the lock screen. '
      'The app never got past the splash.');
}
