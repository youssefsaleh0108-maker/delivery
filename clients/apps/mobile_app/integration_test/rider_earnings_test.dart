import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_app/main.dart' as app;

// The rider's earnings screen, driven through the real app against the live dev backend.
//
// WHAT IS BEING GUARDED. `RiderBalance.available` is signed on purpose — a rider who is holding
// the platform's cash is legitimately in the negative, and the arithmetic upstream needs that sign.
// What must never happen is that figure reaching a rider's eyes as their pay. The screen therefore
// renders `RiderBalance.withdrawable` — `available > 0 ? available : 0`, rider_money_models.dart:254
// — in the two places a rider reads "what can I take out": the balance line under the headline
// (rider_earnings_screen.dart:400-401) and the cash-out sheet's own figure (line 1444). Beside the
// clamped zero the sheet explains itself with riderCashOutHeldNote (lines 1456-1459), because a
// clamp without a reason just trades one wrong reading for another — somebody who worked all day
// sees 0.00 and no account of where it went.
//
// WHY THIS CANNOT BE A WIDGET TEST. test/ can and should pin the clamp against a fake adapter, and
// a fake proves the arithmetic. It cannot prove that the screen a rider actually opens is wired to
// `withdrawable` rather than `available`, because a fake feeds whatever the test decided to feed
// it. This file feeds it the real ledger of a real account that is genuinely in the negative, so
// the wiring itself is the thing under test.
//
// WHY IT IS NOT VACUOUS. The dev rider (rider/300003) is carrying cash: GET /api/rider/earnings
// answers `available: -110.39` with `cashFloatHeld: 110.39` for this account. Pre-fix, the balance
// line rendered that raw figure and this account displayed "-110.39" to its owner. Every assertion
// below is written so that reading fails it. That is also why the vacuity guards matter more than
// usual here: if any of the three ledger calls fails, the screen falls back to an empty state with
// no money on it at all, and a bare "no minus signs anywhere" sweep would go green for entirely the
// wrong reason. The guards turn that into a red test instead.
//
// WHAT IT COSTS. This test talks to api-dev.youdrop.shop and iam-dev.youdrop.shop over the public
// internet, so it is only as reliable as they are, and it MUST be given the backend addresses —
// main.dart:82-89 defaults them to a stale LAN IP, and without the defines sign-in hangs on a TCP
// timeout rather than failing usefully:
//
//   flutter test integration_test/rider_earnings_test.dart \
//     --dart-define=API_BASE_URL=https://api-dev.youdrop.shop \
//     --dart-define=KEYCLOAK_ISSUER=https://iam-dev.youdrop.shop/realms/delivery-platform
//
// Two device preconditions, both of which present as confusing finder failures rather than as
// themselves. The device must be in English, because main.dart passes a null locale until a saved
// preference loads and the app therefore follows the system language, and every finder here is
// English. And POST_NOTIFICATIONS should be pre-granted — _adoptSession fires DeviceTokens.register
// immediately after sign-in, which raises the Android 13+ permission dialog over the Flutter view:
//
//   adb shell pm grant com.delivery.mobile_app android.permission.POST_NOTIFICATIONS

/// Pumps a frame at a time until [ready] holds, or the deadline passes.
///
/// Deliberately not [WidgetTester.pumpAndSettle], and on this journey that is not a style
/// preference — pumpAndSettle cannot work here at all. Three separate screens on this path draw an
/// indeterminate [CircularProgressIndicator]: the splash while the stored session is looked for
/// (splash_screen.dart:171), AuthPrimaryButton while the sign-in round trip is out
/// (one_time_code.dart:487-490), and the earnings FutureBuilder while the three ledger calls are in
/// flight (rider_earnings_screen.dart:241-242). A spinner schedules a frame forever, so the quiet
/// frame pumpAndSettle waits for never arrives; the app would be working perfectly and the test
/// would still die on a timeout whose message pointed at nothing. Polling asks the only question
/// worth asking: is the thing I am waiting for there yet.
///
/// [reason] is what the failure message says when it is not. Required rather than optional because
/// a bare "timed out waiting for a Finder" on a network-backed journey is nearly useless — the
/// interesting information is always which of the several plausible causes it was.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  required String what,
  required String reason,
  Duration timeout = const Duration(seconds: 60),
}) async {
  const Duration step = Duration(milliseconds: 100);
  final int budget = timeout.inMilliseconds ~/ step.inMilliseconds;
  for (int i = 0; i < budget; i++) {
    await tester.pump(step);
    if (ready()) {
      // One more frame once the condition holds, so anything read off the tree afterwards comes
      // from a laid-out frame rather than the one that introduced the widget.
      await tester.pump(step);
      return;
    }
  }
  fail('Timed out after ${timeout.inSeconds}s waiting for $what. $reason');
}

/// [_pumpUntil] for the common case of waiting for something to appear.
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  required String reason,
  Duration timeout = const Duration(seconds: 60),
}) =>
    _pumpUntil(
      tester,
      () => finder.evaluate().isNotEmpty,
      what: '$finder',
      reason: reason,
      timeout: timeout,
    );

/// Money the app formats with `toStringAsFixed(2)`, carrying a minus sign.
///
/// The two-decimal fraction is what makes this safe to sweep the whole tree with. Every money
/// figure on this screen goes through `toStringAsFixed(2)`, and nothing else rendered here has that
/// shape behind a hyphen-minus: the short order reference is the first eight characters of a UUID,
/// which are hex and carry no decimal point; the delivered-at line is a formatted time; the rating
/// uses one decimal place; and every place the screen draws a dash for a missing figure — the four
/// unavailable stat values (rider_earnings_screen.dart:850, 884, 888 and 901) and
/// riderCashOutHeldNote's own separator — are U+2014 EM DASH, not the hyphen-minus this matches.
final RegExp _negativeMoney = RegExp(r'-\d+\.\d{2}');

/// Asserts that no text currently on screen shows negative money.
///
/// Walks [RichText] rather than [Text] because RichText is what Text, Text.rich and an input's hint
/// all render down to, so one pass covers the three without caring which the screen happened to
/// use. [EditableText] is swept separately and explicitly: a text field's *content* is drawn by
/// RenderEditable, not by a RichText, so it is invisible to the first loop. That matters here
/// because the cash-out sheet seeds its amount field from the balance
/// (rider_earnings_screen.dart:1365-1368).
///
/// Semantics labels are excluded from the plain text so this reads what a rider reads. The chart's
/// bar amounts are consequently NOT covered — they exist only as `Semantics(value:)`
/// (rider_earnings_screen.dart:963) and are never drawn as text — so the claim this makes is "no
/// rendered text figure on this screen is negative", which is the claim that matters.
void _expectNoNegativeMoney(WidgetTester tester, String where) {
  for (final RichText text in tester.widgetList<RichText>(find.byType(RichText))) {
    final String plain = text.text.toPlainText(includeSemanticsLabels: false);
    expect(
      _negativeMoney.hasMatch(plain),
      isFalse,
      reason: 'negative money rendered in $where: "$plain"',
    );
  }
  for (final EditableText field in tester.widgetList<EditableText>(find.byType(EditableText))) {
    expect(
      _negativeMoney.hasMatch(field.controller.text),
      isFalse,
      reason: 'negative money seeded into a text field in $where: "${field.controller.text}"',
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Literals rather than lookupDeliveryStrings, and each is annotated with the ARB key it was read
  // out of so the next reader can re-derive it. Two of these carry characters that do not survive
  // being retyped from memory and are the reason nothing here is hand-guessed: the sign-in hint
  // ends in U+2026 HORIZONTAL ELLIPSIS rather than three periods, and riderBalanceLine's separator
  // is U+00B7 MIDDLE DOT rather than a full stop. A finder that differs by either matches nothing
  // and reads like a missing screen.
  const String logIn = 'Log In'; // authLogIn
  const String emailOrPhoneHint = 'e.g. name@domain.com or +961…'; // authEmailOrPhoneHint
  const String passcodeHint = 'Your six-digit passcode'; // authPasscodeHint
  const String riderAvailableTab = 'Available'; // riderTabAvailable
  const String riderActiveTab = 'Active'; // riderTabActive
  const String riderEarningsTab = 'Earnings'; // riderTabEarnings
  const String myEarnings = 'My earnings'; // riderMyEarnings
  const String couldNotLoad = 'Could not load your earnings'; // riderCouldNotLoadEarnings
  const String cashOut = 'Cash out'; // riderCashOutTitle
  const String cashOutAvailable = 'Available to cash out'; // riderCashOutAvailable
  const String weekly = 'Weekly'; // riderPeriodWeekly
  const String weeksDeliveries = "This week's deliveries"; // riderThisWeeksDeliveries

  // The clamped half of riderBalanceLine, "Balance {balance} · available for cash-out {available}",
  // generated as riderBalanceLine(Object balance, Object available) and called with
  // (balance.balance, balance.withdrawable).
  //
  // Only the SECOND figure is required to be unsigned, and that is the whole point of the shape.
  // `withdrawable` is what the fix clamps; `balance.balance` is not clamped by it and is not this
  // regression's business, so pinning it here would mean a red test the day the backend reports a
  // negative gross balance — a failure with no bug behind it. The sweep still covers that first
  // figure, as the broader "nothing on this screen shows negative money" claim; keeping the two
  // separate is what makes a failure legible. If the sweep fires and this does not, the gross
  // balance went negative. If this fires, the clamp is gone.
  final RegExp balanceLine =
      RegExp(r'^Balance -?\d+\.\d{2} · available for cash-out \d+\.\d{2}$');

  // Matched as a substring on purpose. riderCashOutHeldNote is
  // "{amount} of it is cash you are still carrying — hand it in to free it up", so an exact finder
  // would have to hardcode today's float and would break on the next delivery. This slice sits
  // between the interpolated amount and the U+2014 em dash and contains nothing that drifts.
  const String heldNoteFragment = 'of it is cash you are still carrying';

  testWidgets(
      'a rider carrying cash sees a clamped, explained zero rather than negative pay',
      (WidgetTester tester) async {
    // Not awaited. main() is async and awaits Firebase.initializeApp() before runApp, so awaiting
    // it here would block the test on a platform channel instead of pumping frames; the polling
    // below covers both that await and the splash hold behind it. An empty tree simply matches
    // nothing while the app is still coming up.
    unawaited(app.main());
    await tester.pump();

    // ---------------------------------------------------------------- sign in
    //
    // The landing screen on a device with no stored session. AuthService.restore() finds nothing,
    // _bootstrap completes with null and the gate falls to its _Gate.signIn default (main.dart:313)
    // once SplashScreen's 1.9s hold is up. SignInScreen opens on _Step.credentials
    // (sign_in_screen.dart:208), so this is the two-field form and not the passcode pad.
    await _pumpUntilFound(
      tester,
      find.text(logIn),
      reason: 'Expected the sign-in form after the splash. A device with a session already stored '
          'lands on the biometric lock instead — sign out first. This step needs no network.',
    );

    // There is not a single widget Key in this codebase, and both of these are plain TextFields, so
    // byType(TextField) is ambiguous between them. The hint is the only thing that tells them
    // apart. The username field is an AuthField, whose internal TextField takes its
    // decoration.hintText from the `hint` argument (one_time_code.dart:230); the passcode field is
    // the raw TextField at sign_in_screen.dart:517.
    final Finder usernameField = find.byWidgetPredicate(
      (Widget w) => w is TextField && w.decoration?.hintText == emailOrPhoneHint,
    );
    final Finder passcodeField = find.byWidgetPredicate(
      (Widget w) => w is TextField && w.decoration?.hintText == passcodeHint,
    );

    // Asserted before being typed into, so that a hint reworded upstream fails as "the field I
    // meant is gone" rather than as an opaque "tap on a null finder" three lines later.
    expect(usernameField, findsOneWidget,
        reason: 'the AuthField hinted authEmailOrPhoneHint is how this test identifies the '
            'username field; there are no keys to fall back on');
    expect(passcodeField, findsOneWidget,
        reason: 'the TextField hinted authPasscodeHint is how this test identifies the passcode '
            'field; there are no keys to fall back on');

    await tester.enterText(usernameField, 'rider');
    await tester.pump();
    // Six digits deliberately: the field carries FilteringTextInputFormatter.digitsOnly and a
    // six-character limit, and _submitCredentials refuses anything of a different length before it
    // makes a network call at all.
    await tester.enterText(passcodeField, '300003');
    await tester.pump();

    // ensureVisible because the form lives in a CustomScrollView (sign_in_screen.dart:324) and the
    // button sits below the password group — on a short screen a bare tap would throw for being
    // off-screen, which reads like a missing button.
    await tester.ensureVisible(find.text(logIn));
    await tester.pump();
    await tester.tap(find.text(logIn));
    await tester.pump();

    // ------------------------------------------------------- landing as a rider
    //
    // AuthPrimaryButton swaps its label for a spinner while busy, so the OAuth password grant
    // against Keycloak is in flight for as long as this takes. Given the widest budget on the
    // journey: it is two hops over the public internet before a single pixel of the app changes.
    await _pumpUntilFound(
      tester,
      find.text(riderAvailableTab),
      timeout: const Duration(seconds: 90),
      reason: 'Expected RiderHomeScreen after sign-in. Either the credentials were refused, or '
          'KEYCLOAK_ISSUER was not passed and the request timed out against main.dart:82-89\'s '
          'stale LAN default, or the token no longer carries the DELIVERY role.',
    );

    // The role branch actually taken, not just "some shell mounted". This trio is the rider bottom
    // nav; carrier and merchant surfaces have an "Available" of their own, and carrier is tested
    // FIRST in main.dart:717, so an account that picked up a carrier role would land somewhere else
    // entirely and still satisfy a bare "Available". Naming all three localises that failure.
    expect(find.text(riderActiveTab), findsWidgets,
        reason: 'riderTabActive is missing, so this is not the rider bottom nav');
    expect(find.text(riderEarningsTab), findsOneWidget,
        reason: 'riderTabEarnings should be the only "Earnings" in the mobile app tree — the other '
            'ARB keys with that value belong to the portal, and carrEarningsTab belongs to the '
            'carrier shell, which a DELIVERY-only account never mounts');

    // ------------------------------------------------------- the earnings tab
    //
    // _tab starts at 0 (rider_home_screen.dart:131), so this tap is what builds
    // RiderEarningsScreen at all. YdBottomNav draws each label as a Text inside an InkWell, so
    // tapping the label hits the button.
    await tester.tap(find.text(riderEarningsTab));
    await tester.pump();

    // The header renders immediately, above the FutureBuilder, so "My earnings" being on screen
    // says nothing about whether the ledger arrived. The balance line is the thing worth waiting
    // for — it is the widget the fix touches. Three parallel GETs stand between the tap and it.
    await _pumpUntilFound(
      tester,
      find.textContaining('available for cash-out'),
      timeout: const Duration(seconds: 90),
      reason: 'Expected riderBalanceLine. The screen fetches /api/rider/earnings, '
          '/api/rider/earnings/jobs and /api/rider/cash-outs in parallel and shows a spinner until '
          'all three answer.',
    );

    // VACUITY GUARD. Everything below is a statement about money that is on screen, and a failed
    // load puts no money on screen at all — the FutureBuilder's error branch replaces the body with
    // an empty state (rider_earnings_screen.dart:235-237). Without this, a dev backend having a bad
    // afternoon would produce a confidently green run that had inspected nothing.
    expect(find.text(couldNotLoad), findsNothing,
        reason: 'the ledger failed to load, so there are no figures here to make any claim about');
    expect(find.text(myEarnings), findsOneWidget,
        reason: 'riderMyEarnings is referenced exactly once in the app '
            '(rider_earnings_screen.dart:728), so this is the proof that the screen under test is '
            'the one on screen');

    // THE CORE ASSERTION. On this account `available` is -110.39 and `withdrawable` clamps it to
    // 0.00, so pre-fix this line read "... available for cash-out -110.39" and the shape below
    // rejects it. The amounts are matched by shape rather than pinned, so a rider finishing a job
    // mid-run does not turn this red.
    expect(
      find.byWidgetPredicate((Widget w) =>
          w is Text && w.data != null && balanceLine.hasMatch(w.data!)),
      findsOneWidget,
      reason: 'riderBalanceLine must render balance.withdrawable, which is clamped at zero, and '
          'never the signed balance.available',
    );

    _expectNoNegativeMoney(tester, 'the earnings screen body');

    // ------------------------------------------------------- the cash-out sheet
    //
    // The other half of the fix only exists in here. riderCashOutHeldNote is rendered at
    // rider_earnings_screen.dart:1459 and nowhere else in the app, so the explanation standing
    // beside the clamped zero cannot be asserted from the main screen at all — the sheet has to be
    // opened.
    //
    // The header's trailing slot is this "Cash out" text only while there is no request in flight;
    // an open one replaces it with the "Requested" tag (line 690-695). The rider account is shared
    // demo data, so somebody else requesting a cash-out is a real way for this to change under the
    // test — hence the reason string, which turns that into one line of diagnosis.
    expect(find.text(cashOut), findsOneWidget,
        reason: 'expected the header cash-out action. If a cash-out is already open on this shared '
            'demo account the slot renders the "Requested" tag instead and this test cannot reach '
            'the sheet — settle it in backoffice and re-run');
    await tester.tap(find.text(cashOut));
    await tester.pump();

    // The sheet's own label rather than its title: after the sheet opens "Cash out" matches twice,
    // the header action and the sheet heading (line 1422), so it is no longer usable as a finder.
    // This also waits out the bottom-sheet animation without pumpAndSettle.
    await _pumpUntilFound(
      tester,
      find.text(cashOutAvailable),
      timeout: const Duration(seconds: 20),
      reason: 'Expected the cash-out sheet. It is built from the already-loaded ledger, so this is '
          'the modal route animating in and not a network wait.',
    );

    // THE SECOND HALF OF THE FIX: the clamped zero has to say why it is zero. Knowingly coupled to
    // live data — the note is behind `balance.cashFloatHeld > 0` (line 1456) and today this rider
    // carries 110.39. That coupling is accepted rather than engineered around, because the
    // alternative is a conditional that passes silently on the day the float is settled, which is
    // precisely the shape of the vacuous assertion this file exists to avoid. If it fires, check
    // the float before suspecting the screen.
    expect(find.textContaining(heldNoteFragment), findsOneWidget,
        reason: 'riderCashOutHeldNote must accompany the clamped figure. If backoffice has settled '
            'this rider\'s cash float then cashFloatHeld is 0 and the note is correctly absent — '
            'that is a data change, not a regression');

    // Re-swept with the sheet mounted, which is the only way to reach the sheet's own copy of the
    // clamped figure (line 1444), the minimum (line 1471) and the seeded amount field.
    _expectNoNegativeMoney(tester, 'the cash-out sheet');

    // ------------------------------------------------- the week's actual money
    //
    // Everything above is true and still leaves the sweep thin, because the default Today period
    // has no completed jobs on this account and every figure it inspected except the balance line
    // was literally "0.00". Weekly is where the real amounts are. From here down the test is
    // strengthening the same claim rather than making a new one.
    await tester.tapAt(const Offset(20, 20)); // the scrim above the sheet
    await _pumpUntil(
      tester,
      () => find.text(cashOutAvailable).evaluate().isEmpty,
      what: 'the cash-out sheet to dismiss',
      reason: 'Tapped the modal barrier near the top of the screen; a sheet tall enough to reach '
          'that point would swallow the tap.',
      timeout: const Duration(seconds: 20),
    );

    // Exact-match, so it cannot collide with riderPeriodToday. The switch is local state
    // (rider_earnings_screen.dart:802 sets _period and nothing refetches), so the heading changing
    // is the whole proof that the tap landed.
    await tester.tap(find.text(weekly));
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.text(weeksDeliveries),
      timeout: const Duration(seconds: 20),
      reason: 'Expected the period selector to switch to Weekly; the deliveries heading is driven '
          'straight off _period.',
    );

    // The body is a ListView with a `children:` list, so its SliverList still only builds what is
    // in the viewport plus cache extent, and tester.widgetList only sees attached elements. A
    // single sweep therefore never looks at an off-screen job row — at job.earned, riderTipLine or
    // riderReimbursedLine (lines 611-631). Scrolling is what makes "no money figure on this screen
    // is negative" a statement about the screen rather than about its first viewport.
    final Finder ledgerList = find.byType(ListView);
    expect(ledgerList, findsOneWidget,
        reason: 'the ledger body is the only ListView mounted on this path — the fallback list at '
            'line 1043 belongs to the no-moneyApi branch, which the real app never takes');
    final Finder ledgerScrollable =
        find.descendant(of: ledgerList, matching: find.byType(Scrollable));

    double previous = -1;
    for (int i = 0; i < 25; i++) {
      _expectNoNegativeMoney(tester, 'the weekly ledger, viewport $i');

      final ScrollPosition position = tester.state<ScrollableState>(ledgerScrollable).position;
      // Bottom reached, or the list refused to move — either way there is nothing new to inspect
      // and looping further would only re-sweep the same widgets.
      if (position.pixels >= position.maxScrollExtent - 0.5 || position.pixels == previous) {
        break;
      }
      previous = position.pixels;

      // Upwards. A downward drag on this body would trip the RefreshIndicator and refetch the
      // ledger instead of scrolling it.
      await tester.drag(ledgerList, const Offset(0, -400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }
  });
}
