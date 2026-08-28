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
/// The design asks for four KPI cards with movements, a two-series hourly chart and a live feed.
/// Most of that is answerable now: the carrier-scoped daily series carries the tier split and two
/// whole weeks, and orders carry the tier they were placed at. These tests are about the line that
/// has not moved — every figure on screen comes from something the app loaded, and a comparison
/// nothing measured is not drawn at all.
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

/// Fourteen days of the carrier's own money: a quiet week, then one worth twice as much. Two equal
/// windows, which is the only shape a week-on-week line may be drawn from.
List<Map<String, dynamic>> _fortnight() => <Map<String, dynamic>>[
      for (int i = 1; i <= 7; i++)
        _day('2026-08-0${i.toString()}', 2, 1, 10),
      for (int i = 10; i <= 16; i++) _day('2026-08-$i', 4, 2, 20),
    ];

Map<String, dynamic> _summary({
  int todayDelivered = 8,
  int yesterdayDelivered = 6,
  double todayMoney = 45,
  double yesterdayMoney = 36,
  List<Map<String, dynamic>>? days,
}) {
  final Map<String, dynamic> yesterday =
      _day('2026-08-15', yesterdayDelivered, yesterdayDelivered, yesterdayMoney);
  final Map<String, dynamic> today =
      _day('2026-08-16', todayDelivered + 1, todayDelivered, todayMoney);

  return <String, dynamic>{
    'windowDays': 14,
    'days': days ?? _fortnight(),
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

/// The carrier-scoped tier series: seven quiet days, then seven with twice the deliveries, both
/// tiers always present because the server zero-fills.
Map<String, dynamic> _series() => <String, dynamic>{
      'windowDays': 14,
      'days': <Map<String, dynamic>>[
        for (int i = 1; i <= 7; i++)
          <String, dynamic>{
            'day': '2026-08-0$i',
            'standard': <String, dynamic>{'orders': 2, 'delivered': 1, 'gross': 30.0},
            'express': <String, dynamic>{'orders': 0, 'delivered': 0, 'gross': 0.0},
          },
        for (int i = 10; i <= 16; i++)
          <String, dynamic>{
            'day': '2026-08-$i',
            'standard': <String, dynamic>{'orders': 3, 'delivered': 1, 'gross': 40.0},
            'express': <String, dynamic>{'orders': 1, 'delivered': 1, 'gross': 25.0},
          },
      ],
    };

/// One carrier job. [hoursAgo] places it on today's clock, which is what the hourly chart buckets.
Map<String, dynamic> _job({
  required String id,
  String status = 'DELIVERED',
  String? riderId = 'rider-aaaaaaaa',
  int hoursAgo = 1,
  String tier = 'STANDARD',
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
    'deliveryTier': tier,
    'expressSurcharge': tier == 'EXPRESS' ? 2.0 : 0.0,
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

typedef CarrierApis = ({
  OrderApi order,
  DeliveryProviderApi provider,
  AggregatesApi aggregates,
  RiderPerformanceApi performance,
});

CarrierApis _apis({
  Map<String, dynamic>? summary,
  List<String> riders = const <String>['rider-aaaaaaaa', 'rider-bbbbbbbb'],
  List<Map<String, dynamic>>? jobs,
  List<Map<String, dynamic>>? deliveredToday,
  Set<String> failing = const <String>{},
}) {
  _adapter = _StubAdapter(
    <String, Object>{
      '/orders/carrier/summary': summary ?? _summary(),
      '/orders/carrier/daily': _series(),
      '/orders/carrier': _page(jobs ?? <Map<String, dynamic>>[_job(id: 'aaaaaaaa11')]),
      '/orders/riders/delivered-today': deliveredToday ??
          <Map<String, dynamic>>[
            <String, dynamic>{
              'riderId': 'rider-aaaaaaaa',
              'delivered': 4,
              'day': '2026-08-16',
            },
          ],
      '/my-company/riders': <String, dynamic>{'providerId': 'p1', 'riders': riders},
      '/my-company': _company(),
    },
    failing: failing,
  );
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = _adapter;
  return (
    order: OrderApi(dio),
    provider: DeliveryProviderApi(dio),
    aggregates: AggregatesApi(dio),
    performance: RiderPerformanceApi(dio),
  );
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
  CarrierApis apis, {
  Locale locale = const Locale('en'),
  VoidCallback? onShowJobs,
  /// The content column's width — the viewport minus the 260px rail when this screen is mounted
  /// in the console. 1180 is what the design's 1440 leaves it.
  double width = 1180,
  /// The shell has not been rewired to pass the new clients yet, so the screen has to work with
  /// and without them. False mounts it the way the portal mounts it today.
  bool wired = true,
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
      aggregatesApi: wired ? apis.aggregates : null,
      performanceApi: wired ? apis.performance : null,
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

  testWidgets('the fleet card says what it knows about today, not an invented movement',
      (WidgetTester tester) async {
    // The design's "+4 new vs yesterday" has no source — nothing records a fleet's size yesterday.
    // What the platform does know about the same riders today is drawn instead.
    await pump(tester, _apis());

    expect(find.text('1 of 2 delivered something today'), findsOneWidget);
    expect(find.text('Day-over-day soon'), findsNothing);
    expect(find.textContaining('+4'), findsNothing);
  });

  testWidgets('a rider absent from delivered-today counts as zero, not as missing',
      (WidgetTester tester) async {
    // The endpoint omits riders who delivered nothing. Treating that absence as an error would
    // blank a card on the commonest morning of all.
    await pump(tester, _apis(deliveredToday: const <Map<String, dynamic>>[]));

    expect(find.text('0 of 2 delivered something today'), findsOneWidget);
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

  testWidgets('the week-over-week line is computed from two equal windows',
      (WidgetTester tester) async {
    // Deliveries from the carrier-scoped series: 7 last fortnight, 14 this week. Money from the
    // summary's own day list: 70.00 then 140.00 — never from the series, whose gross carries the
    // express surcharge, which is platform revenue and not a carrier's.
    await pump(tester, _apis());

    expect(find.textContaining('This week: 14 delivered'), findsOneWidget);
    expect(find.textContaining('This week: 140.00 earned on delivery fees'), findsOneWidget);
    expect(find.textContaining('+100.0% on the week before'), findsNWidgets(2));
  });

  testWidgets('a series that did not arrive leaves the week line off, not at zero',
      (WidgetTester tester) async {
    await pump(tester, _apis(failing: const <String>{'/orders/carrier/daily'}));

    expect(find.textContaining('This week: 14 delivered'), findsNothing);
    // The money half comes from the summary and is unaffected.
    expect(find.textContaining('This week: 140.00 earned on delivery fees'), findsOneWidget);
  });

  testWidgets('never divides by a yesterday of nothing', (WidgetTester tester) async {
    await pump(tester, _apis(summary: _summary(yesterdayDelivered: 0, yesterdayMoney: 0)));

    expect(find.textContaining('Infinity'), findsNothing);
    expect(find.textContaining('NaN'), findsNothing);
    expect(find.text('Nothing delivered yesterday to compare with'), findsOneWidget);
  });

  testWidgets('the chart draws the design two series, off the tier each job was placed at',
      (WidgetTester tester) async {
    await pump(tester, _apis(jobs: <Map<String, dynamic>>[
      _job(id: 'aaaaaaaa11'),
      _job(id: 'bbbbbbbb22', tier: 'EXPRESS', hoursAgo: 2),
    ]));

    expect(find.text('Hourly Dispatch Volume'), findsOneWidget);
    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('Express'), findsOneWidget);
    expect(find.text('Tier split soon'), findsNothing);
    expect(find.textContaining('split by the tier each was placed at'), findsOneWidget);
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
    expect(find.text('2 of 2 recent'), findsOneWidget);
  });

  testWidgets('the header search narrows the feed to matching jobs', (WidgetTester tester) async {
    await pump(tester, _apis(jobs: <Map<String, dynamic>>[
      _job(id: 'aaaaaaaa11'),
      _job(id: 'bbbbbbbb22', status: 'CANCELLED', hoursAgo: 2),
    ]));

    await tester.enterText(find.byType(TextField).first, 'bbbbbbbb');
    await tester.pumpAndSettle();

    expect(find.textContaining('Job #bbbbbbbb was cancelled.'), findsOneWidget);
    expect(find.textContaining('Job #aaaaaaaa delivered'), findsNothing);
    expect(find.text('1 of 1 matching'), findsOneWidget);
  });

  testWidgets('a KPI whose data did not arrive shows a dash, not a zero',
      (WidgetTester tester) async {
    // A fleet of "0 Riders" is a claim. A fleet the app could not read is not, and the two must not
    // look the same to somebody deciding whether to go hiring.
    await pump(tester, _apis(failing: const <String>{'/my-company/riders'}));

    expect(find.text('—'), findsWidgets);
    expect(find.text('0 Riders'), findsNothing);
  });

  testWidgets('works, and says less, when the new clients are not passed',
      (WidgetTester tester) async {
    // The portal shell still builds this screen with two APIs. Until it passes the rest, the page
    // has to draw what it can rather than break or invent.
    await pump(tester, _apis(), wired: false);

    expect(find.text('8 Completed'), findsOneWidget);
    expect(find.text('Fleet size is not recorded day by day'), findsOneWidget);
    expect(find.textContaining('This week: 14 delivered'), findsNothing);
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
