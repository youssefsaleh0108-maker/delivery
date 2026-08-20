import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/customer_nav_bar.dart';

/// The basket button is a layout claim — bigger, round, centred, and lifted out of the bar — and
/// every part of that claim is the sort of thing that survives a refactor visually while quietly
/// losing its taps. The overhang is the real risk: a circle painted outside its parent still paints,
/// and then silently ignores the half that hangs over the edge.
void main() {
  Future<int?> pumpBar(WidgetTester tester,
      {int index = 0, int basketCount = 0}) async {
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
          index: index,
          basketCount: basketCount,
          onSelected: (int i) => tapped = i,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return tapped;
  }

  testWidgets('the basket is larger than the destinations beside it',
      (WidgetTester tester) async {
    await pumpBar(tester);

    final Size basket = tester.getSize(find.byIcon(Icons.shopping_bag_rounded));
    final Size shops = tester.getSize(find.byIcon(Icons.storefront));

    expect(basket.width, greaterThan(shops.width));
  });

  testWidgets('the basket is centred and stands above the bar', (WidgetTester tester) async {
    // With a count on it, deliberately: a Badge lays its child out top-start, so an empty basket is
    // the one state in which the bag is centred for the wrong reason.
    await pumpBar(tester, basketCount: 3);

    final Rect basket = tester.getRect(find.byIcon(Icons.shopping_bag_rounded));
    final Rect shops = tester.getRect(find.byIcon(Icons.storefront));
    final double screenCentre = tester.getSize(find.byType(MaterialApp)).width / 2;

    // Centred horizontally on the bar rather than sitting third in a row of five.
    expect(basket.center.dx, closeTo(screenCentre, 1));
    // And lifted: its icon sits higher than the icons of the flat destinations.
    expect(basket.center.dy, lessThan(shops.center.dy));
  });

  testWidgets('the whole circle takes taps, including the half above the bar',
      (WidgetTester tester) async {
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

    // Deliberately the top edge of the button, which is the part that hangs over the bar.
    final Rect circle = tester.getRect(find.byIcon(Icons.shopping_bag_rounded));
    await tester.tapAt(Offset(circle.center.dx, circle.top + 2));
    await tester.pumpAndSettle();

    expect(tapped, CustomerNavBar.basketIndex);
  });

  testWidgets('it still fits on a small phone', (WidgetTester tester) async {
    // 320 logical pixels: four labelled destinations plus a 64pt hole in the middle is exactly the
    // arrangement that overflows first, and an overflow here is a red-striped bar on a real device.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpBar(tester, basketCount: 12);

    expect(tester.takeException(), isNull);
    final Rect basket = tester.getRect(find.byIcon(Icons.shopping_bag_rounded));
    expect(basket.center.dx, closeTo(160, 1));
  });

  testWidgets('the count rides on the basket', (WidgetTester tester) async {
    await pumpBar(tester, basketCount: 3);
    expect(find.text('3'), findsOneWidget);

    await pumpBar(tester);
    // No badge on an empty basket — a zero is noise on the one control that should read as ready.
    expect(find.text('0'), findsNothing);
  });

  testWidgets('the other four destinations still report their own index',
      (WidgetTester tester) async {
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

    // Account is index 4, not 3: the basket keeps its slot in the middle even though it is drawn
    // outside the row, so the two destinations after it must not shift down by one.
    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    expect(tapped, 4);

    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();
    expect(tapped, 3);
  });
}
