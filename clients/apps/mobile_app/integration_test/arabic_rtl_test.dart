import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_app/main.dart' as app;

// Arabic, driven through the app's own control rather than through a test-owned MaterialApp.
//
// test/arabic_rtl_test.dart already proves the string table translates and that individual screens
// render Arabic — but it proves it by CONSTRUCTING a MaterialApp with `locale: Locale('ar')` and
// pumping a widget into it. That is a statement about the widgets. It is not a statement about the
// app: nothing in it touches main.dart, the LocaleController, the AR/EN pill, or the wiring between
// them, so every one of those could be broken and that file would stay green.
//
// This one boots the real app, finds the one control a signed-out user has for changing language,
// taps it, and asserts on what a reader would actually see afterwards. The interesting failures it
// catches are the wiring ones: a pill whose onTap was dropped, a MaterialApp that stopped listening
// to the controller, a locale that flips the strings but not the layout.
//
// It needs no network. On a device with no stored refresh token AuthService.restore() reads secure
// storage, finds nothing and returns null without an HTTP call, so the --dart-define backend URLs
// and the demo logins are both irrelevant here.

/// Pumps a frame at a time until [finder] matches, or the deadline passes.
///
/// Deliberately not [WidgetTester.pumpAndSettle], and that is not a style preference. The first
/// screen this test meets is SplashScreen, which draws an unconditional CircularProgressIndicator
/// while the stored session is looked for. A spinner schedules a frame forever, so pumpAndSettle
/// never reaches the quiet frame it is waiting for and dies on its own timeout — the app would be
/// working perfectly and the test would still fail, with a message pointing at nothing. Polling
/// asks the only question that actually matters: is the thing I am waiting for on screen yet.
///
/// The budget is deliberately far longer than anything here should need. The splash alone holds for
/// [SplashScreen.hold] — 1.9 seconds — before the gate is even built, and on a cold app the frames
/// either side of that are competing with Firebase init and two platform-channel reads.
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
      // One more frame once it exists, so the geometry read off it afterwards is from a laid-out
      // tree rather than the frame that introduced it.
      await tester.pump(step);
      return;
    }
  }
  fail('Timed out after ${timeout.inSeconds}s waiting for $finder. $reason');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'the language pill turns the sign-in screen Arabic and flips it right-to-left',
      (WidgetTester tester) async {
    // Looked up rather than hand-typed, exactly as test/arabic_rtl_test.dart does it. Hand-typing
    // is genuinely dangerous in this file: the Arabic ARB embeds invisible bidi control characters
    // in places, and a literal that differs from the table by one U+200E silently finds nothing and
    // reads like a translation bug.
    final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
    final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

    // Every string this screen draws that has a different Arabic value, as (name, English, Arabic).
    // Each one is asserted three times over the journey — present in English, present in Arabic,
    // and the English gone — which is what stops the negative half being vacuous. A `findsNothing`
    // on a string the screen never renders in ANY language passes for the wrong reason and proves
    // nothing; asserting the same string present in English first is the proof that it does render.
    final List<(String, String, String)> translated = <(String, String, String)>[
      ('authLogIn', en.authLogIn, ar.authLogIn),
      ('authEmailOrPhone', en.authEmailOrPhone, ar.authEmailOrPhone),
      ('password', en.password, ar.password),
      ('authForgotShort', en.authForgotShort, ar.authForgotShort),
      ('authPasscodeHint', en.authPasscodeHint, ar.authPasscodeHint),
      ('authDontHaveAnAccount', en.authDontHaveAnAccount, ar.authDontHaveAnAccount),
      ('authSignUp', en.authSignUp, ar.authSignUp),
      // The single best argument for looking these up instead of typing them. The Arabic value
      // carries a U+200E LEFT-TO-RIGHT MARK before '+961' — it has to, or the '+' renders on the
      // wrong end of the number in an RTL run — and it is invisible in every editor. A hand-typed
      // copy of this string differs from the table by one codepoint nobody can see, matches
      // nothing, and reads exactly like the app having failed to translate it.
      //
      // Both hints in this list are safe to assert whatever is typed in the field, which is not
      // obvious: InputDecorator builds the hint Text unconditionally and fades it to opacity 0
      // when the field is non-empty (maintainHintSize defaults to true), so find.text still
      // matches it. That matters because this field IS prefilled, from `delivery.last_username`,
      // on any device somebody has signed in on before.
      ('authEmailOrPhoneHint', en.authEmailOrPhoneHint, ar.authEmailOrPhoneHint),
    ];

    // A guard on the list itself, not on the app. If somebody adds a key here whose Arabic value
    // equals its English one, the "present in Arabic" and "English absent" assertions below would
    // contradict each other and the failure would look like an app bug. This names the real cause.
    for (final (String key, String e, String a) in translated) {
      expect(a, isNot(e),
          reason: '$key is in the asserted list but its Arabic value is identical to '
              'its English one, so it cannot be used as evidence of translation');
    }

    // The real cold start: WidgetsFlutterBinding.ensureInitialized() returns the integration
    // binding already created above, Firebase init runs inside its own try/catch, then runApp.
    await app.main();

    // The pill is both the control this test drives and the proof of where we are. Icons.language
    // is drawn on exactly two mobile screens — here and SettingsScreen — and the other one is
    // behind a login, so finding it means SignInScreen and nothing else.
    await _pumpUntil(
      tester,
      find.byIcon(Icons.language),
      reason: 'Never reached the sign-in screen. The usual cause is a session left in secure '
          'storage by an earlier run or by manual use, which sends the app to a signed-in shell '
          'instead. Clear the app data and run this test first.',
    );
    expect(find.byIcon(Icons.language), findsOneWidget);

    // NORMALISATION, and it is load-bearing rather than defensive.
    //
    // Two independent things can make a cold start Arabic before this test has touched anything:
    // a previous run of this test that failed before its teardown and left 'ar' in secure storage
    // under `delivery.locale`, or a device whose own language is Arabic (MaterialApp is handed a
    // null locale until LocaleController.load() resolves, and null means "follow the device").
    // A version of this test that simply assumed English would be flaky on both.
    //
    // The pill names the language you would switch TO, so the literal 'English' on screen means the
    // app is currently Arabic. Note this reads the control's STATE, not a translation: 'English' is
    // byte-identical in app_en.arb and app_ar.arb, because a language is named in its own language.
    if (find.text(en.english).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.language));
      await _pumpUntil(tester, find.text(en.authLogIn),
          reason: 'The app booted in Arabic and tapping the pill did not return it to English.');
    }

    // ------------------------------------------------------------------ the English baseline

    for (final (String key, String e, _) in translated) {
      expect(find.text(e), findsOneWidget,
          reason: '$key is not on the English sign-in screen, so the Arabic assertions on it '
              'later would prove nothing');
    }

    // The pill offering the way across. Its presence here and its absence after the tap is what
    // makes the switch observable rather than assumed.
    expect(find.text(en.arabic), findsOneWidget);
    expect(find.text(en.english), findsNothing);

    // The social divider, which cannot go in the list above because the screen renders it through
    // .toLowerCase() and the list asserts ARB values verbatim. Pinned here in English so that the
    // matching findsNothing under Arabic has something to be the absence OF.
    expect(find.text(en.authOrContinueWith.toLowerCase()), findsOneWidget);

    // The screen carries exactly two TextFields on this step — the username field inside AuthField
    // and the passcode field — and both inherit the ambient direction. Reading it off a real
    // rendered element rather than off the locale is the point: the locale is the input, the
    // direction is the behaviour under test.
    expect(Directionality.of(tester.element(find.byType(TextField).first)),
        TextDirection.ltr);

    // Captured before the tap so the flip can be MEASURED rather than inferred from the locale.
    final double width = tester.getSize(find.byType(MaterialApp)).width;
    final double pillLtrX = tester.getCenter(find.byIcon(Icons.language)).dx;
    expect(pillLtrX, greaterThan(width / 2),
        reason: 'The pill sits in an Align(AlignmentDirectional.centerEnd) inside a stretched '
            'Column, so in a left-to-right layout it belongs in the right half of the screen');

    // ------------------------------------------------------------------ the one interaction

    await tester.tap(find.byIcon(Icons.language));

    // Waiting on the Arabic label rather than pumping a fixed number of frames, because the delay
    // here is real and variable: DeliveryStrings.delegate.load returns a SynchronousFuture, but
    // GlobalMaterialLocalizations.delegate.load('ar') genuinely goes away to load intl date
    // symbols, and Localizations keeps serving the old locale until it comes back.
    await _pumpUntil(
      tester,
      find.text(ar.authLogIn),
      reason: 'Tapping the pill did not put the screen into Arabic. Either the pill lost its '
          'onTap, LocaleController stopped notifying, or the MaterialApp is no longer rebuilt '
          'from that controller.',
    );

    // ------------------------------------------------------------------ the layout, flipped

    // THE assertion of this file. Arabic gives RTL for free through GlobalWidgetsLocalizations —
    // but only while nothing overrides it, and a hardcoded `Directionality(` wrapped around a
    // screen is invisible to anyone reading the app in English. There is no such constructor
    // anywhere in the client tree today; this is what starts failing on the day somebody adds one.
    expect(Directionality.of(tester.element(find.byType(TextField).first)),
        TextDirection.rtl);

    // Strings flipping is not the same as the layout flipping, and the second is the one that gets
    // broken. The pill's directional alignment must physically carry it across the midline; swap
    // AlignmentDirectional.centerEnd for a plain Alignment.centerRight — the substitution that
    // looks harmless and reads identically in English — and this is the assertion that catches it.
    final double pillRtlX = tester.getCenter(find.byIcon(Icons.language)).dx;
    expect(pillRtlX, lessThan(width / 2),
        reason: 'The pill stayed in the right half under Arabic, so its alignment is not '
            'direction-aware');
    expect(pillRtlX, lessThan(pillLtrX));

    // Reading order inside a single row, which is a different failure from the page-level flip.
    // AuthFooterLink is a Wrap holding the question and the action as two separate Texts — its own
    // doc comment says Arabic reflow is why it is two rather than one rich string — and a Wrap
    // takes its child order from the ambient Directionality. In Arabic the question has to sit to
    // the RIGHT of the link it introduces.
    final Offset question = tester.getCenter(find.text(ar.authDontHaveAnAccount));
    final Offset action = tester.getCenter(find.text(ar.authSignUp));
    expect(question.dy, closeTo(action.dy, 1.0),
        reason: 'The footer pair wrapped onto two lines, which makes comparing their horizontal '
            'positions meaningless — the reading-order check below cannot be trusted');
    expect(question.dx, greaterThan(action.dx),
        reason: 'In Arabic the question must read before the action, which means to its right');

    // ------------------------------------------------------------------ the words themselves

    for (final (String key, String e, String a) in translated) {
      expect(find.text(a), findsOneWidget, reason: '$key is not showing its Arabic value');
      // The regression the original widget test was written for, now against the live screen: a
      // screen that is Arabic apart from the one sentence somebody hardcoded last week.
      expect(find.text(e), findsNothing, reason: '$key is still in English');
    }

    // Deliberately absent from that list, and worth saying why so nobody adds them back.
    // `appTitle` is 'YouDrop' in both files and `arabic`/`english` are each a language's own name,
    // so an assertion on any of them passes in every locale. And `authOrContinueWith` is rendered
    // through .toLowerCase(), so searching for the ARB's 'Or continue with' finds nothing even on
    // the English screen — a findsNothing on it would be the vacuous pass this file exists to
    // avoid. Asserted here in the only form that means anything:
    expect(find.text(en.authOrContinueWith.toLowerCase()), findsNothing);
    expect(find.text(ar.authOrContinueWith.toLowerCase()), findsOneWidget);

    // The pill now offers the way back, which is how we know it re-read its own state rather than
    // being rebuilt from a stale flag.
    expect(find.text(ar.english), findsOneWidget);
    expect(find.text(ar.arabic), findsNothing);

    // ------------------------------------------------------------------ put the device back

    // Not tidiness. LocaleController.setLanguage persists to secure storage under
    // `delivery.locale`, which survives both an app restart and an install over the top, so
    // leaving it set would silently make the next cold start on this device Arabic — for this test
    // and for every other test after it. Flipping back is asserted, not just performed, because a
    // teardown that quietly failed would leave exactly that landmine.
    await tester.tap(find.byIcon(Icons.language));
    await _pumpUntil(tester, find.text(en.authLogIn),
        reason: 'Could not return the app to English; the device is left with Arabic persisted '
            'in secure storage under `delivery.locale`.');
    expect(Directionality.of(tester.element(find.byType(TextField).first)),
        TextDirection.ltr);
    expect(find.text(en.arabic), findsOneWidget);
  });
}
