import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/google_sign_in.dart';
import 'package:mobile_app/src/home_route.dart';
import 'package:mobile_app/src/one_time_code.dart';
import 'package:mobile_app/src/welcome_screen.dart';

/// "When pressing Google, ask if he is a rider, a customer or a seller."
///
/// The rule these pin is that no Google button can start a sign-in without that answer: both
/// buttons go through the same sheet, the sheet will not continue until a role is picked, and
/// dismissing it starts nothing. The rest pins where the answer — and an account that ends up with
/// no role at all — lands.
Widget _app(Widget home) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    );

/// A phone-shaped surface, so the lower half of the Create Account screen is on screen.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// A session whose token carries this address, as a Google-brokered one would.
AuthSession _session(Set<DeliveryRole> roles, {String email = 'sam@gmail.example'}) {
  String seg(Map<String, Object?> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return AuthSession(
    accessToken: '${seg(<String, Object?>{'alg': 'none'})}.'
        '${seg(<String, Object?>{'sub': 'google-sam', 'email': email})}.sig',
    refreshToken: null,
    expiresAt: null,
    roles: roles,
    subject: 'google-sam',
  );
}

/// Opens the sheet from a button and hands on whatever it answered.
class _SheetHost extends StatelessWidget {
  const _SheetHost({required this.onAnswer, this.initial});

  final ValueChanged<AccountIntent?> onAnswer;
  final AccountIntent? initial;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () async =>
                  onAnswer(await showAccountIntentSheet(context, initial: initial)),
              child: const Text('open'),
            ),
          ),
        ),
      );
}

AuthPrimaryButton _sheetContinue(WidgetTester tester) => tester.widget<AuthPrimaryButton>(
    find.widgetWithText(AuthPrimaryButton, 'Continue with Google'));

void main() {
  group('the question asked before Google', () {
    testWidgets('offers customer, rider and seller, and will not continue until one is picked',
        (WidgetTester tester) async {
      final List<AccountIntent?> answers = <AccountIntent?>[];
      await tester.pumpWidget(_app(_SheetHost(onAnswer: answers.add)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('How will you use YouDrop?'), findsOneWidget);
      for (final String line in <String>[
        'Customer',
        'I want to order',
        'Rider',
        'I want to deliver',
        'Seller',
        'I want to sell',
      ]) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
      // Nothing is chosen for them: this answer decides whether the account is reviewed.
      expect(_sheetContinue(tester).onPressed, isNull);

      await tester.tap(find.text('Rider'));
      await tester.pump();
      expect(_sheetContinue(tester).onPressed, isNotNull);

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(answers, <AccountIntent?>[AccountIntent.rider]);
    });

    testWidgets('dismissing it answers nothing, so nothing starts', (WidgetTester tester) async {
      final List<AccountIntent?> answers = <AccountIntent?>[];
      await tester.pumpWidget(_app(_SheetHost(onAnswer: answers.add)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(12, 12));
      await tester.pumpAndSettle();

      expect(find.text('How will you use YouDrop?'), findsNothing);
      expect(answers, <AccountIntent?>[null]);
    });

    testWidgets('starts on the role it is given, and still waits for the confirmation',
        (WidgetTester tester) async {
      final List<AccountIntent?> answers = <AccountIntent?>[];
      await tester.pumpWidget(
          _app(_SheetHost(onAnswer: answers.add, initial: AccountIntent.seller)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(answers, isEmpty);
      expect(_sheetContinue(tester).onPressed, isNotNull);

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(answers, <AccountIntent?>[AccountIntent.seller]);
    });
  });

  group("the sign-in screen's Google button", () {
    testWidgets('asks first, and starts Google only with the answer', (WidgetTester tester) async {
      final List<AccountIntent> started = <AccountIntent>[];
      await tester.pumpWidget(_app(Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SocialSignInRow(enabled: true, onGoogle: started.add),
        ),
      )));

      await tester.tap(find.text('Google'));
      await tester.pumpAndSettle();

      // The sheet is up and nothing has started yet. Before this change the same tap showed a
      // "coming soon" snackbar and nothing else.
      expect(find.text('How will you use YouDrop?'), findsOneWidget);
      expect(find.text('Google sign-in is coming soon.'), findsNothing);
      expect(started, isEmpty);

      await tester.tap(find.text('Seller'));
      await tester.pump();
      await tester.tap(find.widgetWithText(AuthPrimaryButton, 'Continue with Google'));
      await tester.pumpAndSettle();

      expect(started, <AccountIntent>[AccountIntent.seller]);
    });

    testWidgets('says "coming soon" rather than opening anything when Google is not wired',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app(const Scaffold(
        body: SocialSignInRow(enabled: true),
      )));

      await tester.tap(find.text('Google'));
      await tester.pump();

      expect(find.text('Google sign-in is coming soon.'), findsOneWidget);
      expect(find.text('How will you use YouDrop?'), findsNothing);
    });

    testWidgets('holds still while a Google round trip is already in flight',
        (WidgetTester tester) async {
      final List<AccountIntent> started = <AccountIntent>[];
      await tester.pumpWidget(_app(Scaffold(
        body: SocialSignInRow(enabled: false, onGoogle: started.add, googleBusy: true),
      )));

      expect(
          find.descendant(
              of: find.widgetWithText(SocialAuthButton, 'Google'),
              matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);

      await tester.tap(find.text('Google'));
      await tester.pump();

      expect(find.text('How will you use YouDrop?'), findsNothing);
      expect(started, isEmpty);
    });
  });

  group('the Create Account screen', () {
    testWidgets('offers Continue with Google, starting the question on the role card chosen there',
        (WidgetTester tester) async {
      _phone(tester);
      final List<AccountIntent> started = <AccountIntent>[];
      await tester.pumpWidget(_app(WelcomeScreen(
        onSignIn: () {},
        onSignUp: () {},
        onJoinAsPartner: () {},
        onGoogle: started.add,
      )));

      await tester.tap(find.text('I want to Deliver'));
      await tester.pump();
      await tester.ensureVisible(find.text('Continue with Google'));
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      // Still asked — the sheet is up — but already on Rider, so confirming is one tap.
      expect(find.text('How will you use YouDrop?'), findsOneWidget);
      expect(started, isEmpty);
      await tester.tap(find.widgetWithText(AuthPrimaryButton, 'Continue with Google'));
      await tester.pumpAndSettle();

      expect(started, <AccountIntent>[AccountIntent.rider]);
    });

    testWidgets('draws no Google button when there is no Google handler',
        (WidgetTester tester) async {
      _phone(tester);
      await tester.pumpWidget(_app(WelcomeScreen(
        onSignIn: () {},
        onSignUp: () {},
        onJoinAsPartner: () {},
      )));

      expect(find.text('Continue with Google'), findsNothing);
    });
  });

  group('an account that holds no role', () {
    test('is asked what it is, rather than falling through into the customer shell', () {
      // The old last line of main.dart's role branch was "anything else shops". With the realm no
      // longer making every Google account a customer, a role-less account reached it — and landed
      // in a shop that refuses every order for want of the role.
      expect(homeFor(const <DeliveryRole>{}), HomeSurface.chooseRole);
      expect(homeFor(const <DeliveryRole>{}, preferred: DeliveryRole.customer),
          HomeSurface.chooseRole);
    });

    testWidgets('gets the same three answers, and nothing happens until one is picked',
        (WidgetTester tester) async {
      _phone(tester);
      final List<AccountIntent> chosen = <AccountIntent>[];
      bool signedOut = false;
      await tester.pumpWidget(_app(AccountSetupScreen(
        session: _session(const <DeliveryRole>{}),
        onChoose: chosen.add,
        onSignOut: () => signedOut = true,
      )));

      expect(find.text('One more step'), findsOneWidget);
      // Whose account it is, so a shared phone does not set up the wrong person.
      expect(find.text('sam@gmail.example'), findsOneWidget);
      expect(tester.widget<AuthPrimaryButton>(find.widgetWithText(AuthPrimaryButton, 'Continue'))
          .onPressed, isNull);

      await tester.tap(find.text('Customer'));
      await tester.pump();
      await tester.tap(find.widgetWithText(AuthPrimaryButton, 'Continue'));
      await tester.pump();
      expect(chosen, <AccountIntent>[AccountIntent.customer]);

      await tester.tap(find.text('Sign out'));
      await tester.pump();
      expect(signedOut, isTrue);
    });
  });

  group('where a signed-in session lands', () {
    test('a pending applicant with nothing to explore gets the status screen', () {
      expect(homeFor(<DeliveryRole>{DeliveryRole.applicant}), HomeSurface.pendingApplication);
      expect(homeFor(<DeliveryRole>{DeliveryRole.applicant, DeliveryRole.carrier}),
          HomeSurface.pendingApplication);
    });

    test('a pending rider or seller gets their own surface', () {
      expect(homeFor(<DeliveryRole>{DeliveryRole.applicant, DeliveryRole.delivery}),
          HomeSurface.rider);
      expect(homeFor(<DeliveryRole>{DeliveryRole.applicant, DeliveryRole.merchant}),
          HomeSurface.merchant);
    });

    test('without a preference the old priority holds: company, then rider, then shop', () {
      expect(homeFor(<DeliveryRole>{DeliveryRole.carrier, DeliveryRole.delivery}),
          HomeSurface.carrier);
      expect(homeFor(<DeliveryRole>{DeliveryRole.merchant, DeliveryRole.delivery}),
          HomeSurface.rider);
      expect(homeFor(<DeliveryRole>{DeliveryRole.customer}), HomeSurface.customer);
    });

    test('the role just asked for wins when the account holds it', () {
      // "Seller" picked on the Google question by an account that also rides.
      expect(
          homeFor(<DeliveryRole>{DeliveryRole.merchant, DeliveryRole.delivery},
              preferred: DeliveryRole.merchant),
          HomeSurface.merchant);
      expect(
          homeFor(<DeliveryRole>{DeliveryRole.customer, DeliveryRole.delivery},
              preferred: DeliveryRole.customer),
          HomeSurface.customer);
    });

    test('a preference the account does not hold changes nothing', () {
      expect(homeFor(<DeliveryRole>{DeliveryRole.customer}, preferred: DeliveryRole.delivery),
          HomeSurface.customer);
    });

    test('roles with no surface of their own still shop, exactly as before', () {
      expect(homeFor(<DeliveryRole>{DeliveryRole.backoffice}), HomeSurface.customer);
      expect(homeFor(<DeliveryRole>{DeliveryRole.merchantStaff}), HomeSurface.customer);
    });
  });
}
