import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:mobile_app/src/butler_screen.dart';
import 'package:mobile_app/src/cart.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/address_sheet.dart';
import 'package:mobile_app/src/delivery_address.dart';

// Arabic is not a translation file — it is whether the app works for the people it is for.
//
// Nothing asserted that before: the string table and its Arabic translation existed while the
// screens went on hardcoding English, and every test passed the whole time. These pump real screens
// under Locale('ar') and assert on what a reader would actually see.

/// A store that never touches secure storage.
///
/// The sheet only reads what is already in memory, and `load()` is deliberately not called — a
/// platform channel in a widget test would fail for reasons that have nothing to do with language.
DeliveryAddressStore _emptyStore() => DeliveryAddressStore(ownerId: 'test-user');

Widget _wrap(Widget child, Locale locale) => MaterialApp(
      locale: locale,
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    );

void main() {
  group('the string table', () {
    test('carries an Arabic translation for every English key', () {
      // The failure this prevents is a screen that is Arabic apart from the one sentence somebody
      // added last week.
      final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
      final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));
      // Two concrete spot-checks rather than reflection, which Dart does not offer here: a plain
      // string and a plural, both of which are generated differently.
      expect(ar.checkout, isNot(en.checkout));
      expect(ar.deliverTo, isNot(en.deliverTo));
      expect(ar.addedToBasket(3), isNot(en.addedToBasket(3)));
    });

    test('Arabic plurals use the categories Arabic actually has', () {
      final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));
      // Arabic distinguishes two and few, which English does not. If the ARB had been written with
      // only one/other these would collapse into the same sentence.
      final Set<String> forms = <String>{
        ar.addedToBasket(1),
        ar.addedToBasket(2),
        ar.addedToBasket(3),
        ar.addedToBasket(11),
      };
      expect(forms, hasLength(4));
    });
  });

  group('the display enums', () {
    // These carry an English `label` baked into the enum constant, which is invisible while the app
    // is English and decisive the moment it is not: a status badge or a filter chip stays English
    // however thoroughly the screen around it is translated.
    final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));
    final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

    test('every order status has an Arabic label', () {
      for (final OrderStatus s in OrderStatus.values) {
        expect(s.labelIn(ar), isNotEmpty, reason: '${s.name} has no Arabic label');
        expect(s.labelIn(ar), isNot(s.labelIn(en)), reason: '${s.name} is still English');
      }
    });

    test('every rider action has an Arabic label', () {
      for (final OrderAction a in OrderAction.values) {
        expect(a.labelIn(ar), isNot(a.labelIn(en)), reason: '${a.name} is still English');
      }
    });

    test('every shop vertical has an Arabic label', () {
      for (final StoreVertical v in StoreVertical.values) {
        expect(v.labelIn(ar), isNot(v.labelIn(en)), reason: '${v.name} is still English');
      }
    });

    test('the English labels still match what the enum itself declares', () {
      // The `label` field stays as the fallback and is what the Backoffice renders, so the two must
      // not drift apart into two different English wordings for the same state.
      expect(OrderStatus.delivered.labelIn(en), OrderStatus.delivered.label);
      expect(OrderAction.claim.labelIn(en), OrderAction.claim.label);
      expect(StoreVertical.grocery.labelIn(en), StoreVertical.grocery.label);
    });
  });

  group('the address sheet in Arabic', () {
    testWidgets('lays out right-to-left', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showAddressSheet(context, _emptyStore()),
            child: const Text('open'),
          ),
        ),
        const Locale('ar'),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // RTL is free from the locale, but only if nothing hardcodes a direction — which is the kind
      // of thing that gets hardcoded and never noticed by anyone reading English.
      expect(Directionality.of(tester.element(find.byType(TextFormField).first)),
          TextDirection.rtl);
    });

    testWidgets('shows Arabic, with no English left behind',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showAddressSheet(context, _emptyStore()),
            child: const Text('open'),
          ),
        ),
        const Locale('ar'),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));
      // The redesigned sheet drops its "Deliver to" title — the question under it says the same
      // thing at more length — so what is asserted here is what the sheet still draws.
      expect(find.text(ar.whereShouldWeBring), findsOneWidget);
      expect(find.text(ar.address), findsOneWidget);
      expect(find.text(ar.deliverHere), findsOneWidget);

      // The actual regression: these were hardcoded English until this work, and the screen looked
      // perfectly fine to anyone testing in English.
      final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
      expect(find.text(en.address), findsNothing);
      expect(find.text(en.deliverHere), findsNothing);
      expect(find.text(en.whereShouldWeBring), findsNothing);
    });

    testWidgets('Butler asks its questions in Arabic', (WidgetTester tester) async {
      // The headline feature, and the screen with the most prose in the app: two modes, each with
      // its own labels, hints and validators.
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
      await tester.pumpWidget(_wrap(
        ButlerScreen(
          addresses: _emptyStore(),
          api: ButlerApi(dio),
          orderApi: OrderApi(dio),
          storeApi: StoreApi(dio),
          // Points at nothing, like the others: the area list simply fails to load and the picker
          // does not appear, which is the same as a deployment with no areas configured.
          zoneApi: DeliveryZoneApi(dio),
          cart: Cart(),
        ),
        const Locale('ar'),
      ));
      // Lets the terms request fail and settle before anything is asserted.
      await tester.pump(const Duration(milliseconds: 50));

      final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));
      final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

      expect(find.text(ar.whatDoYouNeed), findsOneWidget);
      expect(find.text(ar.budgetCapOptional), findsOneWidget);
      expect(find.text(en.whatDoYouNeed), findsNothing);

      // And the other mode's questions, which are a different set of strings entirely. The mode is
      // picked from a pair of cards now rather than a segmented control, so the label moved too.
      await tester.tap(find.text(ar.custSendAnything));
      await tester.pumpAndSettle();

      expect(find.text(ar.whatAreWeMoving), findsOneWidget);
      expect(find.text(ar.pickUpFrom), findsOneWidget);
      expect(find.text(en.pickUpFrom), findsNothing);
    });

    testWidgets('still shows English under an English locale',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showAddressSheet(context, _emptyStore()),
            child: const Text('open'),
          ),
        ),
        const Locale('en'),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
      expect(find.text(en.whereShouldWeBring), findsOneWidget);
      expect(Directionality.of(tester.element(find.byType(TextFormField).first)),
          TextDirection.ltr);
    });
  });
}
