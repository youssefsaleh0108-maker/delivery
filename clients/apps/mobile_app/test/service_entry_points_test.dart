import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/google_sign_in.dart';
import 'package:mobile_app/src/partner_application_screen.dart';
import 'package:mobile_app/src/partner_choice_screen.dart';

/// The ways into the services signup (Figma 126:11) for somebody who is not signed in, or who is
/// signing in with Google.
///
/// Each door is absent rather than dead when its host does not wire it, and each leads to the
/// services signup rather than the shop wizard — which would ask a tailor what kind of food they sell.
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

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  group('the partner choice', () {
    testWidgets('offers services beside selling and delivering, and opens the services signup',
        (WidgetTester tester) async {
      int services = 0;
      final List<PartnerKind> wizards = <PartnerKind>[];
      await tester.pumpWidget(_app(PartnerChoiceScreen(
        onChoose: wizards.add,
        onClose: () {},
        onChooseServices: () => services++,
      )));
      await tester.pumpAndSettle();

      expect(find.text(en.svcChoiceCard), findsOneWidget);
      expect(find.text(en.svcChoiceCardBlurb), findsOneWidget);
      await tester.tap(find.text(en.svcChoiceCard));
      await tester.pumpAndSettle();

      expect(services, 1);
      expect(wizards, isEmpty, reason: 'a tailor is not sent into the shop wizard');
    });

    testWidgets('leaves the card off when the host does not wire it', (WidgetTester tester) async {
      await tester.pumpWidget(_app(PartnerChoiceScreen(onChoose: (PartnerKind _) {}, onClose: () {})));
      await tester.pumpAndSettle();

      expect(find.text(en.svcChoiceCard), findsNothing);
      expect(find.text(en.applyAsMerchant), findsOneWidget);
    });
  });

  testWidgets('the Google role question offers Services, and answers with it',
      (WidgetTester tester) async {
    AccountIntent? answered;
    await tester.pumpWidget(_app(Scaffold(
      body: SingleChildScrollView(
        child: AccountIntentOptions(
          selected: null,
          onSelected: (AccountIntent intent) => answered = intent,
        ),
      ),
    )));
    await tester.pumpAndSettle();

    expect(find.text(en.svcIntentBlurb), findsOneWidget);
    await tester.tap(find.text(en.svcIntent));
    await tester.pumpAndSettle();

    expect(answered, AccountIntent.services);
    // Still the seller it is to the platform: the same role and the same kind of application.
    expect(answered!.role, DeliveryRole.merchant);
    expect(answered!.applicationKind, OnboardingKind.merchant);
  });
}
