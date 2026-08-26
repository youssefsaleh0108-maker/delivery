import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/carrier/dashboard_screen.dart';
import 'package:delivery_portal/src/shell/shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Carrier Control Tower — Figma `carrier-dashboard` (3:3429).
///
/// The design asks for four KPI cards, an hourly chart and a live feed, and the platform can
/// honestly answer some of that and not the rest. These tests are about that line: every figure on
/// screen has to come from something the app loaded, and every figure the design draws that nothing
/// can answer has to say so rather than showing a plausible number.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.responses, {this.failing = const <String>{}});

  /// Path suffix to body. Longest suffix wins, so `/carrier/summary` beats `/carrier`.
  final Map<String, Object> responses;

  /// Path suffixes that answer 404, for the "this endpoint is unhappy" cases.
  final Set<String> failing;

  final List<String> calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');

    for (final String path in failing) {
      if (options.path.contains(path)) {
        return ResponseBody.fromString('{"message":"no"}', 404);
      }
    }

    final List<String> matches = responses.keys
        .where((String key) => options.path.contains(key))
        .toList()
      ..sort((String a, String b) => b.length.compareTo(a.length));

    if (matches.isEmpty) return ResponseBody.fromString('{}', 404);
    return ResponseBody.fromString(jsonEncode(responses[matches.first]), 200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _day(String day, int orders, int delivered, double money) =>
    <String, dynamic>{
      'day': day,
      'orders': orders,
      'delivered': delivered,
      'money': money,
      'waived': 0,
    };

Map<String, dynamic> _summary({
  int todayDelivered = 8,
  int yesterdayDelivered = 6,
  double todayMoney = 45,
  double yesterdayMoney = 36,
}) {
  final Map<String, dynamic> yesterday =
      _day('2026-08-15', yesterdayDelivered, yesterdayDelivered, yesterdayMoney);
  final Map<String, dynamic> today =
      _day('2026-08-16', todayDelivered + 1, todayDelivered, todayMoney);

  return <String, dynamic>{
    'windowDays': 14,
    'days': <Map<String, dynamic>>[yesterday, today],
    'today': today,
    'yesterday': yesterday,
    'window': <String, dynamic>{
      'orders': 100,
      'delivered': 95,
      'money': 500.0,
      'waived': 0.0,
    },
    'earned': 460.0,
    'savedByOffers': 0.0,
    'cutPercentage': 10.0,
  };
}

/// One carrier job. [hoursAgo] places it on today's clock, which is what the hourly chart buckets.
Map<String, dynamic> _job({
  required String id,
  String status = 'DELIVERED',
  String? riderId = 'rider-aaaaaaaa',
  int hoursAgo = 1,
}) {
  final DateTime at = DateTime.now().subtract(Duration(hours: hoursAgo));
  return <String, dynamic>{
    'id': id,
    'customerId': 'c1',
    'merchantId': 'm1',
    'riderId': riderId,
    'status': status,
    'totalAmount': 50.0,
    'deliveryAddress': '12 Bliss Street',
    'deliveryFee': 5.0,
    'storeName': 'Corner Shop',
    'contactPhone': '+100',
    'notes': null,
    'items': <dynamic>[],
    'availableActions': <dynamic>[],
    'placedAt': at.toIso8601String(),
    'deliveredAt': status == 'DELIVERED' ? at.toIso8601String() : null,
    'cancelReason': null,
  };
}

Map<String, dynamic> _page(List<Map<String, dynamic>> jobs) => <String, dynamic>{
      'content': jobs,
      'page': 0,
      'size': 100,
      'totalElements': jobs.length,
      'totalPages': 1,
    };

Map<String, dynamic> _company() => <String, dynamic>{
      'id': 'p1',
      'slug': 'swift',
      'name': 'Swift Couriers',
      'kind': 'EXTERNAL',
      'status': 'ACTIVE',
      'canTakeWork': true,
      'accountRef': null,
      'contactName': 'Cara',
      'contactPhone': '+100',
      'payoutState': 'VERIFIED',
    };

late _StubAdapter _adapter;

({OrderApi order, DeliveryProviderApi provider}) _apis({
  Map<String, dynamic>? summary,
  List<String> riders = const <String>['rider-aaaaaaaa', 'rider-bbbbbbbb'],
  List<Map<String, dynamic>>? jobs,
  Set<String> failing = const <String>{},
}) {
  _adapter = _StubAdapter(
    <String, Object>{
      '/orders/carrier/summary': summary ?? _summary(),
      '/orders/carrier': _page(jobs ?? <Map<String, dynamic>>[_job(id: 'aaaaaaaa11')]),
      '/my-company/riders': <String, dynamic>{'providerId': 'p1', 'riders': riders},
      '/my-company': _company(),
    },
    failing: failing,
  );
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = _adapter;
  return (order: OrderApi(dio), provider: DeliveryProviderApi(dio));
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
      home: Scaffold(body: child),
    );

Future<void> pump(
  WidgetTester tester,
  ({OrderApi order, DeliveryProviderApi provider}) apis, {
  Locale locale = const Locale('en'),
  VoidCallback? onShowJobs,
  /// The content column's width — the viewport minus the 260px rail when this screen is mounted
  /// in the console. 1180 is what the design's 1440 leaves it.
  double width = 1180,
}) async {
  // The console is drawn at 1440. Tall, because the page scrolls and a short viewport makes every
  // findsNothing below the fold pass for the wrong reason.
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_wrap(
    CarrierDashboardScreen(
      api: apis.order,
      providerApi: apis.provider,
      onShowJobs: onShowJobs,
    ),
    locale: locale,
  ));
  await tester.pumpAndSettle();
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  testWidgets('draws the design four KPI cards, headed by the company', (WidgetTester tester) async {
    await pump(tester, _apis());

    expect(find.text('Carrier Control Tower'), findsOneWidget);
    expect(find.text('Operational health dashboard for Swift Couriers'), findsOneWidget);

    expect(find.text('Total Assigned Riders'), findsOneWidget);
    expect(find.text('Active Right Now'), findsOneWidget);
    expect(find.text('Deliveries Today'), findsOneWidget);
    expect(find.text("Today's Revenue"), findsOneWidget);
    expect(find.byType(ConsoleKpiCard), findsNWidgets(4));
  });

  testWidgets('every number on the page came from something it loaded',
      (WidgetTester tester) async {
    await pump(tester, _apis());

    // Two riders on the fleet endpoint, eight delivered today, 45.00 taken today.
    expect(find.text('2 Riders'), findsOneWidget);
    expect(find.text('8 Completed'), findsOneWidget);
    expect(find.text('45.00'), findsOneWidget);
    // One job, held by one rider, and it is finished — so nobody is out.
    expect(find.text('0 Active'), findsOneWidget);
  });

  testWidgets('the fleet card admits it cannot compare with yesterday',
      (WidgetTester tester) async {
    // The design's "+4 new vs yesterday". Nothing records how large a fleet was yesterday, so the
    // card must not print a movement — it prints the chip instead.
    await pump(tester, _apis());

    expect(find.text('Day-over-day soon'), findsOneWidget);
    expect(find.textContaining('+4'), findsNothing);
  });

  testWidgets('the two figures that can be compared show a real movement',
      (WidgetTester tester) async {
    // 8 delivered against 6 is +33.3%; 45.00 against 36.00 is +25.0%. Two different numbers, so an
    // assertion about one cannot be satisfied by the other.
    await pump(tester, _apis());

    expect(find.text('+33.3%'), findsOneWidget);
    expect(find.text('+25.0%'), findsOneWidget);
    expect(find.text('vs yesterday'), findsNWidgets(2));
  });

  testWidgets('never divides by a yesterday of nothing', (WidgetTester tester) async {
    await pump(tester, _apis(summary: _summary(yesterdayDelivered: 0, yesterdayMoney: 0)));

    expect(find.textContaining('Infinity'), findsNothing);
    expect(find.textContaining('NaN'), findsNothing);
    expect(find.text('Nothing delivered yesterday to compare with'), findsOneWidget);
  });

  testWidgets('the chart is one series and says the tier split is not real',
      (WidgetTester tester) async {
    // The design splits every column into Express and Standard. There are no service tiers on this
    // platform; a second series would be an invented number beside a real one.
    await pump(tester, _apis());

    expect(find.text('Hourly Dispatch Volume'), findsOneWidget);
    expect(find.text('Jobs'), findsOneWidget);
    expect(find.text('Tier split soon'), findsOneWidget);
    expect(find.text('Express'), findsNothing);
    expect(find.text('Standard'), findsNothing);
  });

  testWidgets('the feed is built from real jobs with real timestamps',
      (WidgetTester tester) async {
    await pump(tester, _apis(jobs: <Map<String, dynamic>>[
      _job(id: 'aaaaaaaa11'),
      _job(id: 'bbbbbbbb22', status: 'CANCELLED', hoursAgo: 2),
    ]));

    expect(find.text('Live Active Feed'), findsOneWidget);
    expect(find.textContaining('Job #aaaaaaaa delivered'), findsOneWidget);
    expect(find.textContaining('Job #bbbbbbbb was cancelled.'), findsOneWidget);
  });

  testWidgets('a KPI whose data did not arrive shows a dash, not a zero',
      (WidgetTester tester) async {
    // A fleet of "0 Riders" is a claim. A fleet the app could not read is not, and the two must not
    // look the same to somebody deciding whether to go hiring.
    await pump(tester, _apis(failing: const <String>{'/my-company/riders'}));

    expect(find.text('—'), findsWidgets);
    expect(find.text('0 Riders'), findsNothing);
  });

  testWidgets('the deliveries card leads to the job board', (WidgetTester tester) async {
    bool went = false;
    await pump(tester, _apis(), onShowJobs: () => went = true);

    await tester.tap(find.text('Deliveries Today'));
    await tester.pumpAndSettle();
    expect(went, isTrue);
  });

  testWidgets('belonging to no company reads as a gap, not a crash',
      (WidgetTester tester) async {
    // A freshly provisioned carrier account before anybody attaches it. Showing a stack trace on
    // one screen and a sentence on the other would read as two different problems.
    await pump(tester, _apis(failing: const <String>{'/orders/carrier/summary'}));

    expect(find.text(en.noCompanyYet), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
  });

  // 1180, 1020 and 764 are what a 1440 / 1280 / 1024 window leaves the content column once the
  // design's 260px rail has taken its share. The split row and the KPI grid both reflow across
  // that range, and this project's convention is that an overflow fails the test.
  for (final double width in <double>[1180, 1020, 764]) {
    testWidgets('lays out at a ${width.toInt()}px content column', (WidgetTester tester) async {
      await pump(tester, _apis(), width: width);
      expect(tester.takeException(), isNull);
    });
  }
}
