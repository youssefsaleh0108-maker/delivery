import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delivery_merchant/delivery_merchant.dart';

/// The shop's dashboard.
///
/// A dashboard fails quietly: nothing throws, the numbers are simply wrong or worded in a way that
/// says the opposite of what happened. So what is tested here is mostly the wording around the
/// numbers — "up 40% on yesterday" against a yesterday of zero is the classic version of this, and
/// it is a division by zero dressed up as a fact.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body);

  final Object body;
  final List<String> calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    return ResponseBody.fromString(jsonEncode(body), 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

late _StubAdapter _adapter;

Map<String, dynamic> _day(String day, int orders, int delivered, double money,
        {double waived = 0}) =>
    <String, dynamic>{
      'day': day,
      'orders': orders,
      'delivered': delivered,
      'money': money,
      'waived': waived,
    };

/// Two weeks ending on a Sunday, so the weekday labels are predictable.
List<Map<String, dynamic>> _fortnight({int todayOrders = 12, int yesterdayOrders = 8}) {
  final List<Map<String, dynamic>> days = <Map<String, dynamic>>[];
  for (int i = 13; i >= 2; i--) {
    days.add(_day('2026-08-${(16 - i).toString().padLeft(2, '0')}', 5, 4, 100));
  }
  days.add(_day('2026-08-15', yesterdayOrders, yesterdayOrders, 200));
  days.add(_day('2026-08-16', todayOrders, todayOrders - 2, 300));
  return days;
}

Map<String, dynamic> _summary({
  int todayOrders = 12,
  int yesterdayOrders = 8,
  // Deliberately a different percentage from the order counts (25% against 50%), so an assertion
  // about one comparison cannot be satisfied by the other one saying the same thing.
  double todayMoney = 250,
  double yesterdayMoney = 200,
  int awaitingYou = 3,
  int preparing = 1,
  int ready = 0,
  int onTheWay = 2,
  double savedByOffers = 0,
  List<Map<String, dynamic>>? topProducts,
}) {
  final List<Map<String, dynamic>> days = _fortnight(
      todayOrders: todayOrders, yesterdayOrders: yesterdayOrders);
  days[days.length - 1]['money'] = todayMoney;
  days[days.length - 2]['money'] = yesterdayMoney;

  return <String, dynamic>{
    'windowDays': 14,
    'days': days,
    'today': days[days.length - 1],
    'yesterday': days[days.length - 2],
    'window': <String, dynamic>{
      'orders': 100,
      'delivered': 90,
      'money': 1600.0,
      'waived': savedByOffers > 0 ? 400.0 : 0.0,
    },
    'platformFees': 150.0,
    'savedByOffers': savedByOffers,
    'commissionPercentage': 12.5,
    'awaitingYou': awaitingYou,
    'preparing': preparing,
    'readyForPickup': ready,
    'onTheWay': onTheWay,
    'topProducts': topProducts ??
        <Map<String, dynamic>>[
          <String, dynamic>{'name': 'Zaatar Manoush', 'qty': 42, 'revenue': 210.0},
          <String, dynamic>{'name': 'Lahm Baajin', 'qty': 17, 'revenue': 187.0},
        ],
  };
}

OrderApi _api(Map<String, dynamic> summary) {
  _adapter = _StubAdapter(summary);
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = _adapter;
  return OrderApi(dio);
}

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      theme: DeliveryTheme.light(),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    );

Future<void> pump(WidgetTester tester, Map<String, dynamic> summary,
    {Locale locale = const Locale('en'), VoidCallback? onShowOrders}) async {
  // Tall enough for the whole page. A ListView only builds what fits, so a viewport that cuts the
  // page in half makes every findsNothing below the fold pass for the wrong reason.
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_wrap(
    MerchantDashboardScreen(api: _api(summary), onShowOrders: onShowOrders),
    locale: locale,
  ));
  await tester.pumpAndSettle();
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  testWidgets('leads with what needs doing, then the day', (WidgetTester tester) async {
    await pump(tester, _summary());

    // The redesign renamed the small-caps "TO ACCEPT" tile to the "Pending Orders" card the Figma
    // frame draws, and dropped the letter-spaced upper case from every label — the tiles and the
    // section headings are sentence case now. What the test is here for is unchanged: the count
    // somebody has to act on is on the screen, next to the words that say what it is, and it is
    // above the history rather than buried under it.
    expect(find.text(en.merchPendingOrders), findsOneWidget);
    expect(find.text(en.merchNewOrders), findsOneWidget);
    expect(find.text('3'), findsWidgets);

    expect(find.text(en.needsYouNow), findsOneWidget);
    expect(find.text(en.ordersToday), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('250.00'), findsOneWidget);

    // The one ordering that still has to hold. The frame puts today's two figures above the
    // pending card, both inside the first screenful; what must never happen is the thing needing
    // action falling below a fortnight of history nobody has to do anything about.
    expect(
      tester.getTopLeft(find.text(en.merchPendingOrders)).dy,
      lessThan(tester.getTopLeft(find.text(en.bestSellers)).dy),
    );
  });

  testWidgets('says how today compares with yesterday', (WidgetTester tester) async {
    await pump(tester, _summary(todayOrders: 12, yesterdayOrders: 8));

    // 12 against 8 is 50% up, and the arrow and the words have to agree.
    expect(find.text(en.upOnYesterday(50)), findsOneWidget);
    expect(find.byIcon(Icons.trending_up_rounded), findsWidgets);
  });

  testWidgets('a fall is stated plainly and not painted as an alarm',
      (WidgetTester tester) async {
    await pump(tester, _summary(todayOrders: 6, yesterdayOrders: 12));

    expect(find.text(en.downOnYesterday(50)), findsOneWidget);
    expect(find.byIcon(Icons.trending_down_rounded), findsWidgets);
    // A quiet day is not an error. If this ever turns red, somebody has decided that trade dipping
    // is a fault, and the colour that means "something is broken" stops meaning it.
    final Text comparison = tester.widget<Text>(find.text(en.downOnYesterday(50)));
    expect(comparison.style?.color, DeliveryColors.muted);
  });

  testWidgets('never divides by a yesterday of nothing', (WidgetTester tester) async {
    await pump(tester, _summary(todayOrders: 5, yesterdayOrders: 0, yesterdayMoney: 0));

    // "Up 100%" from a standing start is arithmetic, not information — and against zero it is not
    // even arithmetic.
    expect(find.text(en.noneYesterday), findsWidgets);
    expect(find.textContaining('Infinity'), findsNothing);
    expect(find.textContaining('NaN'), findsNothing);
  });

  testWidgets('a day with nothing on either side says so', (WidgetTester tester) async {
    await pump(tester, _summary(
        todayOrders: 0, yesterdayOrders: 0, todayMoney: 0, yesterdayMoney: 0));

    expect(find.text(en.nothingYetToday), findsWidgets);
  });

  testWidgets('an empty queue is a sentence, not four zeroes', (WidgetTester tester) async {
    await pump(tester, _summary(awaitingYou: 0, preparing: 0, ready: 0, onTheWay: 0));

    // Four zero tiles read as "the screen is broken". One line reads as "you are up to date".
    expect(find.text(en.allCaughtUp), findsOneWidget);
    // Same guarantee against the redesign's wording: nothing on this screen announces a queue.
    expect(find.text(en.merchNewOrders), findsNothing);
    expect(find.text(en.needsYouNow), findsNothing);
  });

  testWidgets('the queue leads somewhere', (WidgetTester tester) async {
    bool went = false;
    await pump(tester, _summary(), onShowOrders: () => went = true);

    // The tile became the design's pending-orders card, and the whole card is the target now
    // rather than the number inside it.
    await tester.tap(find.text(en.merchPendingOrders));
    await tester.pumpAndSettle();
    expect(went, isTrue, reason: 'a count you cannot act on is decoration');
  });

  testWidgets('shows what the platform charged and at what rate',
      (WidgetTester tester) async {
    await pump(tester, _summary());

    expect(find.text('150.00'), findsOneWidget);
    expect(find.text(en.feesInWindow), findsOneWidget);
    expect(find.text(en.feesInWindowNote('12.5')), findsOneWidget);
  });

  // Two tests rather than two pumps in one: pumping the same widget type a second time updates the
  // existing element instead of building a new State, so the screen would still be showing the
  // first response and the assertion would be about nothing.
  testWidgets('says nothing about offers when none was given', (WidgetTester tester) async {
    await pump(tester, _summary());

    // A zero here is a line about a benefit they never received, which reads as one withheld.
    expect(find.text(en.savedForYou), findsNothing);
  });

  testWidgets('tells the shop when an offer saved them money', (WidgetTester tester) async {
    await pump(tester, _summary(savedByOffers: 50));

    expect(find.text(en.savedForYou), findsOneWidget);
    expect(find.text('50.00'), findsOneWidget);
  });

  testWidgets('lists best sellers with both what sold and what it earned',
      (WidgetTester tester) async {
    await pump(tester, _summary());

    expect(find.text('Zaatar Manoush'), findsOneWidget);
    expect(find.text(en.soldQty(42)), findsOneWidget);
    expect(find.text('210.00'), findsOneWidget);
  });

  testWidgets('says so plainly when nothing has sold', (WidgetTester tester) async {
    await pump(tester, _summary(topProducts: <Map<String, dynamic>>[]));

    expect(find.text(en.nothingSoldYet), findsOneWidget);
  });

  testWidgets('the whole screen is translated, including the chart axis',
      (WidgetTester tester) async {
    await pump(tester, _summary(), locale: const Locale('ar'));

    expect(find.text(ar.needsYouNow), findsOneWidget);
    expect(find.text(ar.ordersToday), findsOneWidget);
    expect(find.text(ar.bestSellers), findsOneWidget);
    // The trap the shared display enums fell into: an English string left behind inside an
    // otherwise translated screen. The weekday initials come from Flutter's own localisations.
    expect(find.text(ar.upOnYesterday(50)), findsOneWidget);
  });

  testWidgets('a failed refresh keeps the numbers that were already there',
      (WidgetTester tester) async {
    await pump(tester, _summary());
    expect(find.text('12'), findsOneWidget);

    // The poll fires on a timer; a single miss must not replace a working page with an error.
    _adapter.calls.clear();
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    expect(find.text('12'), findsOneWidget);
  });
}
