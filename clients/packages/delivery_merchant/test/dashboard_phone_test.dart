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
    // taking the page with it.
    final Finder sideways = find.descendant(
      of: find.byType(SoftCard),
      matching: find.byWidgetPredicate((Widget w) =>
          w is SingleChildScrollView && w.scrollDirection == Axis.horizontal),
    );
    expect(sideways, findsOneWidget);
    expect(tester.getSize(sideways).width, lessThanOrEqualTo(360));
  });

  testWidgets("today's two figures stack on a phone and sit side by side on a desktop",
      (WidgetTester tester) async {
    await _pumpPhone(tester, height: 2400);

    final Offset orders = tester.getTopLeft(find.byType(TrendHeadline).at(0));
    final Offset money = tester.getTopLeft(find.byType(TrendHeadline).at(1));
    expect(money.dy, greaterThan(orders.dy),
        reason: 'two headlines beside each other on a phone lose the comparison line');
    expect(money.dx, orders.dx);

    tester.view.physicalSize = const Size(1400, 2400);
    await tester.pumpAndSettle();

    final Offset wideOrders = tester.getTopLeft(find.byType(TrendHeadline).at(0));
    final Offset wideMoney = tester.getTopLeft(find.byType(TrendHeadline).at(1));
    expect(wideMoney.dy, wideOrders.dy);
    expect(wideMoney.dx, greaterThan(wideOrders.dx));
  });

  testWidgets('the chart keeps its numbers somewhere a thumb can reach',
      (WidgetTester tester) async {
    await _pumpPhone(tester, height: 2400);

    // The bars' own tooltips need a hover or a long press on a bar that may be five pixels tall.
    await tester.tap(find.text(en.dayByDay));
    await tester.pumpAndSettle();

    expect(find.text('Aug 16, 2026'), findsOneWidget);
    expect(find.text('113.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every control a thumb has to hit is at least 48dp tall',
      (WidgetTester tester) async {
    await _pumpPhone(tester, height: 2400);

    for (final Element element in find.byType(InkWell).evaluate()) {
      final Size size = element.size!;
      expect(size.height, greaterThanOrEqualTo(48),
          reason: 'a tappable ${size.width}x${size.height} is too short for a thumb');
    }
    expect(tester.getSize(find.byType(TextButton)).height, greaterThanOrEqualTo(48));
  });

  testWidgets('a wide window keeps the desktop gutter', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final ListView page = tester.widget<ListView>(find.byType(ListView).first);
    expect((page.padding! as EdgeInsets).left, DeliverySpacing.lg);
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
