import 'dart:convert';
import 'dart:typed_data';

import 'package:carrier_portal/src/dashboard_screen.dart';
import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The delivery company's dashboard.
///
/// The company already has an earnings page and a score page. What this one owes them is the thing
/// neither has: whether today is better or worse than yesterday, and what the fortnight looks like.
/// So the tests are about the comparison being honest — and about the one state that is not a
/// failure, a carrier who has been given the role but not yet attached to a company.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body, {this.status = 200});

  final Object body;
  final int status;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    return ResponseBody.fromString(jsonEncode(body), status, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _day(String day, int orders, int delivered, double money,
        {double waived = 0}) =>
    <String, dynamic>{
      'day': day,
      'orders': orders,
      'delivered': delivered,
      'money': money,
      'waived': waived,
    };

Map<String, dynamic> _summary({
  int todayJobs = 9,
  int yesterdayJobs = 6,
  double todayMoney = 45,
  double yesterdayMoney = 36,
  double savedByOffers = 0,
}) {
  final List<Map<String, dynamic>> days = <Map<String, dynamic>>[
    for (int i = 13; i >= 2; i--)
      _day('2026-08-${(16 - i).toString().padLeft(2, '0')}', 4, 4, 20),
    _day('2026-08-15', yesterdayJobs, yesterdayJobs, yesterdayMoney),
    _day('2026-08-16', todayJobs, todayJobs - 1, todayMoney),
  ];

  return <String, dynamic>{
    'windowDays': 14,
    'days': days,
    'today': days[days.length - 1],
    'yesterday': days[days.length - 2],
    'window': <String, dynamic>{
      'orders': 100,
      'delivered': 95,
      'money': 500.0,
      'waived': savedByOffers > 0 ? 100.0 : 0.0,
    },
    'earned': 460.0,
    'savedByOffers': savedByOffers,
    'cutPercentage': 10.0,
  };
}

OrderApi _api(Object body, {int status = 200}) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))
    ..httpClientAdapter = _StubAdapter(body, status: status);
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

Future<void> pump(WidgetTester tester, OrderApi api,
    {Locale locale = const Locale('en'), VoidCallback? onShowJobs}) async {
  // Tall enough for the whole page: a ListView only builds what fits, and a short viewport makes
  // every findsNothing below the fold pass for the wrong reason.
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_wrap(
    CarrierDashboardScreen(api: api, onShowJobs: onShowJobs),
    locale: locale,
  ));
  await tester.pumpAndSettle();
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  testWidgets('opens with the day, not another running total', (WidgetTester tester) async {
    await pump(tester, _api(_summary()));

    expect(find.text(en.jobsToday.toUpperCase()), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text(en.earnedToday.toUpperCase()), findsOneWidget);
    expect(find.text('45.00'), findsOneWidget);
  });

  testWidgets('compares today with yesterday in words', (WidgetTester tester) async {
    // 9 against 6 is 50% up; 45 against 36 is 25%. Two different figures, so an assertion about
    // one cannot be satisfied by the other.
    await pump(tester, _api(_summary()));

    expect(find.text(en.upOnYesterday(50)), findsOneWidget);
    expect(find.text(en.upOnYesterday(25)), findsOneWidget);
  });

  testWidgets('never divides by a yesterday of nothing', (WidgetTester tester) async {
    await pump(tester, _api(_summary(yesterdayJobs: 0, yesterdayMoney: 0)));

    expect(find.text(en.noneYesterday), findsWidgets);
    expect(find.textContaining('Infinity'), findsNothing);
    expect(find.textContaining('NaN'), findsNothing);
  });

  testWidgets('shows what the company keeps and at what rate', (WidgetTester tester) async {
    await pump(tester, _api(_summary()));

    expect(find.text('460.00'), findsOneWidget);
    expect(find.text(en.earned.toUpperCase()), findsOneWidget);
    expect(find.text(en.feesInWindowNote('10')), findsOneWidget);
  });

  testWidgets('the window count leads to the job board', (WidgetTester tester) async {
    bool went = false;
    await pump(tester, _api(_summary()), onShowJobs: () => went = true);

    await tester.tap(find.text(en.ordersInWindow.toUpperCase()));
    await tester.pumpAndSettle();
    expect(went, isTrue);
  });

  testWidgets('says nothing about offers when none was given', (WidgetTester tester) async {
    await pump(tester, _api(_summary()));

    expect(find.text(en.savedByOffers.toUpperCase()), findsNothing);
  });

  testWidgets('tells the company when an offer left them the whole fee',
      (WidgetTester tester) async {
    await pump(tester, _api(_summary(savedByOffers: 10)));

    expect(find.text(en.savedByOffers.toUpperCase()), findsOneWidget);
    expect(find.text('10.00'), findsOneWidget);
  });

  testWidgets('belonging to no company reads as a gap, not a crash',
      (WidgetTester tester) async {
    // A freshly provisioned carrier account before anybody attaches it. The earnings screen already
    // words this state; showing a stack trace on one screen and a sentence on the other would read
    // as two different problems.
    await pump(tester, _api(<String, dynamic>{'message': 'no company'}, status: 404));

    expect(find.text(en.noCompanyYet), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
  });

  testWidgets('the whole screen is translated', (WidgetTester tester) async {
    await pump(tester, _api(_summary()), locale: const Locale('ar'));

    expect(find.text(ar.jobsToday.toUpperCase()), findsOneWidget);
    expect(find.text(ar.earnedToday.toUpperCase()), findsOneWidget);
    expect(find.text(ar.upOnYesterday(50)), findsOneWidget);
    // Twice: the heading over the chart and the footnote on the tile beneath it. Arabic has no
    // upper case, so toUpperCase leaves the string alone and both render identically.
    expect(find.text(ar.lastDaysHeading(14)), findsNWidgets(2));
  });
}
