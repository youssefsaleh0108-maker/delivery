import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shop's dashboard, on a phone.
///
/// What the numbers say is covered by the portal's own dashboard test. This is about the room they
/// are said in: the same widget renders in a navigation rail on a 1400px window and in 360dp of an
/// Android phone, and a page of figures is exactly the kind of screen that fits a browser and
/// silently truncates a handset. An overflow in Flutter paints a stripe and logs an exception
/// rather than failing, so most of these assert on the exception being absent.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body);

  final Object body;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    return ResponseBody.fromString(jsonEncode(body), 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _day(String day, int orders, int delivered, double money) => <String, dynamic>{
      'day': day,
      'orders': orders,
      'delivered': delivered,
      'money': money,
      'waived': 0.0,
    };

/// A full fortnight, which is the case that decides whether the chart fits or scrolls.
List<Map<String, dynamic>> _fortnight() => <Map<String, dynamic>>[
      for (int i = 13; i >= 0; i--)
        _day('2026-08-${(16 - i).toString().padLeft(2, '0')}', 5 + i, 4 + i, 100.0 + i),
    ];

/// Deliberately unkind figures and names: four-digit takings and a product nobody would name in a
/// mockup. A dashboard of single digits and "Pizza" proves nothing about 360dp.
Map<String, dynamic> _summary() {
  final List<Map<String, dynamic>> days = _fortnight();
  return <String, dynamic>{
    'windowDays': 14,
    'days': days,
    'today': days[days.length - 1],
    'yesterday': days[days.length - 2],
    'window': <String, dynamic>{
      'orders': 1284,
      'delivered': 1190,
      'money': 148620.75,
      'waived': 400.0,
    },
    'platformFees': 18577.59,
    'savedByOffers': 1240.50,
    'commissionPercentage': 12.5,
    'awaitingYou': 3,
    'preparing': 1,
    'readyForPickup': 0,
    'onTheWay': 2,
    'topProducts': <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'Zaatar manoush with extra cheese, family size',
        'qty': 428,
        'revenue': 21400.00,
      },
      <String, dynamic>{'name': 'Lahm baajin', 'qty': 17, 'revenue': 187.0},
    ],
  };
}

Widget _host({Locale locale = const Locale('en')}) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))
    ..httpClientAdapter = _StubAdapter(_summary());

  return MaterialApp(
    theme: DeliveryTheme.light(),
    locale: locale,
    localizationsDelegates: DeliveryStrings.localizationsDelegates,
    supportedLocales: DeliveryStrings.supportedLocales,
    home: MerchantDashboardScreen(api: OrderApi(dio)),
  );
}

/// Phone width. Height is a knob rather than a constant: a ListView builds only what fits, so a
/// 640dp viewport would let anything below the fold pass a findsNothing for the wrong reason.
Future<void> _pumpPhone(WidgetTester tester,
    {double height = 640, double textScale = 1.0, Locale locale = const Locale('en')}) async {
  tester.view.physicalSize = Size(360, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: _host(locale: locale),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  testWidgets('lays out on a 360dp phone without overflowing', (WidgetTester tester) async {
    await _pumpPhone(tester, height: 2400);

    expect(tester.takeException(), isNull);
    expect(find.text(en.ordersToday), findsOneWidget);
    expect(find.text('148620.75'), findsOneWidget);
  });

  testWidgets('still fits at the largest font size Android offers', (WidgetTester tester) async {
    await _pumpPhone(tester, height: 2400, textScale: 2.0);

    expect(tester.takeException(), isNull);
  });

  testWidgets('the page itself never scrolls sideways', (WidgetTester tester) async {
    await _pumpPhone(tester, height: 2400);

    // The page's own list, which is the one a thumb lands on nine times out of ten.
    final ListView page = tester.widget<ListView>(find.byType(ListView).first);
    expect(page.scrollDirection, Axis.vertical);

    // A fortnight is wider than 360dp, so the chart does scroll — inside its own card, never by
    // taking the page with it. The card is a [YdCard] since the redesign; it was a [SoftCard].
    final Finder sideways = find.descendant(
      of: find.byType(YdCard),
      matching: find.byWidgetPredicate((Widget w) =>
          w is SingleChildScrollView && w.scrollDirection == Axis.horizontal),
    );
    expect(sideways, findsOneWidget);
    expect(tester.getSize(sideways).width, lessThanOrEqualTo(360));
  });

  testWidgets("today's two figures sit side by side and neither is truncated",
      (WidgetTester tester) async {
    // This used to assert the opposite — two stacked headlines on a phone, side by side only on a
    // desktop. The 2026-08 design draws `summary-grid` (3:1763) as a 2-up row of metric cards at
    // every width, so the claim worth holding changed with it: they are level, they are equal, and
    // a four-digit day's takings still fit in half of 360dp.
    await _pumpPhone(tester, height: 2400);

    // Located by their labels rather than by position: the same card type carries the queue
    // counts further down the page, and `.at(1)` would silently start measuring one of those.
    Finder card(String label) => find.ancestor(
          of: find.text(label),
          matching: find.byType(MerchantMetricCard),
        );
    expect(card(en.ordersToday), findsOneWidget);
    expect(card(en.salesToday), findsOneWidget);

    final Rect orders = tester.getRect(card(en.ordersToday));
    final Rect money = tester.getRect(card(en.salesToday));
    expect(money.top, orders.top);
    expect(money.left, greaterThan(orders.left));
    expect(money.width, closeTo(orders.width, 0.5));

    // The figures themselves, not just the boxes around them.
    expect(find.text('148620.75'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the chart keeps its numbers somewhere a thumb can reach',
      (WidgetTester tester) async {
    await _pumpPhone(tester, height: 2400);

    // The bars' own tooltips need a hover or a long press on a bar that may be five pixels tall.
    await tester.tap(find.text(en.dayByDay));
    await tester.pumpAndSettle();

    // The most recent day is the row somebody opened this to see, so it is first. The date is
    // whatever MaterialLocalizations calls a medium date — asserting the month and day rather than
    // a full format string keeps this about the sheet rather than about Flutter's date wording.
    expect(find.textContaining('Aug 16'), findsOneWidget);
    expect(find.text('113.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the controls a thumb has to hit are big enough for one',
      (WidgetTester tester) async {
    await _pumpPhone(tester, height: 2400);

    // KNOWN DEVIATION, recorded rather than silently dropped. This used to require 48dp of every
    // tappable on the screen. The redesign draws its section actions as inline text links ("View
    // All", "Day by day") sitting on the baseline of a heading, and those measure about 25dp tall;
    // padding them to 48 would open a gap the frames do not have. So the rule is applied to the
    // controls that are *boxes* — the ones a thumb aims at rather than reads — and the text links
    // are exempted here on the record.
    final Finder links = find.descendant(
      of: find.byType(YdSectionHeader),
      matching: find.byType(InkWell),
    );
    final Set<Element> exempt = links.evaluate().toSet();

    for (final Element element in find.byType(InkWell).evaluate()) {
      if (exempt.contains(element)) continue;
      final Size size = element.size!;
      expect(size.height, greaterThanOrEqualTo(48),
          reason: 'a tappable ${size.width}x${size.height} is too short for a thumb');
    }

    // And the refresh control in the header, which Material would otherwise size at 40.
    expect(tester.getSize(find.byType(IconButton)).height, greaterThanOrEqualTo(48));
  });

  testWidgets('a wide window does not stretch the page across a monitor',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    // The gutter moved. The redesign's sections are full-bleed white bands that carry their own
    // 24px padding, so the list itself has none — and what keeps a row of figures from spanning a
    // 1400px window is the content constraint rather than a list inset.
    final ListView page = tester.widget<ListView>(find.byType(ListView).first);
    expect((page.padding! as EdgeInsets).left, 0);
    expect(tester.getSize(find.byType(ListView).first).width,
        lessThanOrEqualTo(merchantMaxContentWidth));

    // The chart has room for a fortnight on a desktop, so nothing is hidden behind a drag.
    expect(
      find.byWidgetPredicate((Widget w) =>
          w is SingleChildScrollView && w.scrollDirection == Axis.horizontal),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arabic fits the same phone', (WidgetTester tester) async {
    await _pumpPhone(tester, height: 2400, locale: const Locale('ar'));

    expect(tester.takeException(), isNull);
    expect(Directionality.of(tester.element(find.byType(ListView).first)), TextDirection.rtl);
  });
}
