import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/customer_nav_bar.dart';

/// The bar is five equal destinations now, and the thing worth pinning down is no longer the
/// geometry of a raised button — it is the **order**. Every jump between tabs is an integer, the
/// stack behind the bar is built from the same integers, and the two agreeing is what stops the
/// basket button from opening Butler. A test that reads the labels off the rendered bar is the
/// only thing that catches that pair drifting, because both halves keep compiling either way.
void main() {
  Future<int?> pumpBar(
    WidgetTester tester, {
    int index = 0,
    int basketCount = 0,
    Locale? locale,
  }) async {
    int? tapped;
    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      locale: locale,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocaleController.supported,
      home: Scaffold(
        bottomNavigationBar: CustomerNavBar(
          index: index,
          basketCount: basketCount,
          onSelected: (int i) => tapped = i,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return tapped;
  }

  testWidgets('the five destinations are in the design\'s order',
      (WidgetTester tester) async {
    await pumpBar(tester);

    final DeliveryStrings t = await DeliveryStrings.delegate.load(const Locale('en'));
    final List<String> expected = <String>[
      t.navHome,
      t.navButler,
      t.navBasket,
      t.navOrders,
      t.navAccount,
    ];

    // Read left to right off the rendered bar rather than out of the list that built it.
    final List<String> onScreen = tester
        .widgetList<Text>(find.byType(Text))
        .map((Text text) => text.data ?? '')
        .where(expected.contains)
        .toList();

    expect(onScreen, expected);
  });

  testWidgets('each destination reports its own index', (WidgetTester tester) async {
    final DeliveryStrings t = await DeliveryStrings.delegate.load(const Locale('en'));

    for (final MapEntry<String, int> destination in <String, int>{
      t.navHome: CustomerNavBar.homeIndex,
      t.navOrders: CustomerNavBar.ordersIndex,
      t.navButler: CustomerNavBar.butlerIndex,
      t.navBasket: CustomerNavBar.basketIndex,
      t.navAccount: CustomerNavBar.accountIndex,
    }.entries) {
      int? tapped;
      await tester.pumpWidget(MaterialApp(
        theme: DeliveryTheme.light(),
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          DeliveryStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: LocaleController.supported,
        home: Scaffold(
          bottomNavigationBar: CustomerNavBar(
            index: 0,
            basketCount: 0,
            onSelected: (int i) => tapped = i,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text(destination.key));
      await tester.pumpAndSettle();

      expect(tapped, destination.value, reason: destination.key);
    }
  });

  testWidgets('the count rides on the basket', (WidgetTester tester) async {
    await pumpBar(tester, basketCount: 3);
    final DeliveryStrings t = await DeliveryStrings.delegate.load(const Locale('en'));

    expect(find.text('3'), findsOneWidget);

    // On the basket and nowhere else: the badge is drawn inside the tab, so its centre has to sit
    // within that tab's own box.
    final Rect badge = tester.getRect(find.text('3'));
    final Rect basket = tester.getRect(find.text(t.navBasket));
    expect(badge.center.dx, closeTo(basket.center.dx, 24));

    await pumpBar(tester);
    // No badge on an empty basket — a zero is noise on the one control that should read as ready.
    expect(find.text('0'), findsNothing);
  });

  testWidgets('a three-figure basket does not stretch the bar',
      (WidgetTester tester) async {
    await pumpBar(tester, basketCount: 240);

    expect(tester.takeException(), isNull);
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('it still fits on a small phone', (WidgetTester tester) async {
    // 320 logical pixels: five labelled destinations with 20px of side padding is the arrangement
    // that overflows first, and an overflow here is a red-striped bar on a real device.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpBar(tester, basketCount: 12);

    expect(tester.takeException(), isNull);
  });

  testWidgets('it mirrors in Arabic', (WidgetTester tester) async {
    await pumpBar(tester, locale: const Locale('ar'));
    final DeliveryStrings ar = await DeliveryStrings.delegate.load(const Locale('ar'));

    // Home is the first destination, which in RTL means the rightmost one. The bar is a plain Row,
    // so this is really a check that nothing in it reaches for `left`/`right`.
    final double home = tester.getCenter(find.text(ar.navHome)).dx;
    final double account = tester.getCenter(find.text(ar.navAccount)).dx;
    expect(home, greaterThan(account));
  });
}
