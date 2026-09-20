import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// PT-10: the page every partner meets before anything else.
///
/// It was half translated — three of the card's strings and the whole brand panel were English
/// literals, so in Arabic the page read as a mix, and an English sentence set in an Arabic
/// paragraph puts its full stop at the wrong end. Its one translated line was the customer app's
/// "Sign in to see what you ordered before", which is a shopper's prompt on a store page and says
/// nothing true about a console.
///
/// The Arabic sweep is the load-bearing test: it fails on the next literal anybody adds here.

/// Everything that is a name rather than a sentence, and stays itself in both languages.
const List<String> _namesNotSentences = <String>[
  'YouDrop',
  '© 2026 YouDrop Technologies Inc.',
  // The toggle names both languages at once, in their own scripts, in either locale.
  'AR / EN',
];

Future<void> _pump(WidgetTester tester,
    {required Locale locale, Size size = const Size(1440, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    theme: DeliveryTheme.light(),
    supportedLocales: DeliveryStrings.supportedLocales,
    localizationsDelegates: DeliveryStrings.localizationsDelegates,
    home: PortalSignInScreen(
      onSignIn: () async {},
      busy: false,
      locale: LocaleController(read: () async => null, write: (String _) async {}),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Every string the page actually paints.
List<String> _painted(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text w) => w.data ?? w.textSpan?.toPlainText() ?? '')
    .where((String s) => s.trim().isNotEmpty)
    .toList();

void main() {
  testWidgets('the card speaks to a partner, not to a shopper', (WidgetTester tester) async {
    await _pump(tester, locale: const Locale('en'));
    final DeliveryStrings t = lookupDeliveryStrings(const Locale('en'));

    expect(find.text(t.portalSignInWelcome), findsOneWidget);
    expect(find.text(t.portalSignInPrompt), findsOneWidget);
    expect(find.text(t.portalSignInRedirect), findsOneWidget);
    expect(find.text(t.portalSignInApply), findsOneWidget);
    expect(find.text(t.signInPrompt), findsNothing,
        reason: "the customer app's store-page prompt has no business on a console");
  });

  testWidgets('in Arabic nothing on the page is left in English', (WidgetTester tester) async {
    await _pump(tester, locale: const Locale('ar'));

    final Iterable<String> strayed = _painted(tester)
        .where((String s) => !_namesNotSentences.contains(s))
        // The brand name may sit inside an Arabic sentence; the rest of it must be Arabic.
        .map((String s) => s.replaceAll('YouDrop', ''))
        .where((String s) => RegExp(r'[A-Za-z]{2,}').hasMatch(s));

    expect(strayed, isEmpty, reason: 'still English on an Arabic page: ${strayed.toList()}');
  });

  testWidgets('the brand panel is translated too, not only the card',
      (WidgetTester tester) async {
    await _pump(tester, locale: const Locale('ar'));
    final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

    expect(find.text(ar.portalBrandEyebrow), findsOneWidget);
    expect(find.text(ar.portalBrandHeadline), findsOneWidget);
    expect(find.text(ar.portalBrandBlurb), findsOneWidget);
    expect(find.text(ar.portalBrandAudiences), findsOneWidget);
  });

  testWidgets('Arabic gets no letter spacing, which would pull a cursive word apart',
      (WidgetTester tester) async {
    await _pump(tester, locale: const Locale('ar'));
    final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));
    expect(tester.widget<Text>(find.text(ar.portalBrandEyebrow)).style?.letterSpacing, isNull);

    await _pump(tester, locale: const Locale('en'));
    final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
    expect(tester.widget<Text>(find.text(en.portalBrandEyebrow)).style?.letterSpacing, 1);
  });

  testWidgets('the language toggle follows the reading direction', (WidgetTester tester) async {
    await _pump(tester, locale: const Locale('en'));
    final double centre = tester.getSize(find.byType(PortalSignInScreen)).width / 2;
    expect(tester.getCenter(find.byType(PopupMenuButton<String>)).dx, greaterThan(centre),
        reason: 'English reads left to right, so the toggle ends the line on the right');

    await _pump(tester, locale: const Locale('ar'));
    expect(tester.getCenter(find.byType(PopupMenuButton<String>)).dx, lessThan(centre),
        reason: 'Arabic ends its line on the left, and the toggle goes with it');
  });

  testWidgets('a window too narrow for the brand panel still lays out, in both languages',
      (WidgetTester tester) async {
    for (final Locale locale in <Locale>[const Locale('en'), const Locale('ar')]) {
      await _pump(tester, locale: locale, size: const Size(700, 640));
      expect(find.text(lookupDeliveryStrings(locale).portalSignInWelcome), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
