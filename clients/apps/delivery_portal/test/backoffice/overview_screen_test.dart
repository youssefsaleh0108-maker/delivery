import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_portal/src/backoffice/overview_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Backoffice overview — Figma `backoffice-dashboard` (3:2487).
///
/// The screen has two modes and both are tested here.
///
/// With `/api/orders/daily` and `/api/orders/activity` answering, the movements, the bars and the
/// activity log are the platform's own figures, and the tests below check the arithmetic — the
/// percentage against both halves of the series, and the fact that a previous week of nothing
/// produces no percentage at all rather than an infinity dressed up as growth.
///
/// Without them, the screen falls back to what it can count from the loaded page of orders and says
/// so; the older tests in this file are that path, and they still assert that no movement is
/// invented where there is no series to derive one from.
///
/// The order fixtures are all a few minutes old on purpose: "today" in the fallback is the real
/// clock, so a fixture dated in hours would move across midnight and take the revenue assertions
/// with it. The series fixtures use fixed dates instead, because the server resolves the day.
///
/// Rendered at three widths because Flutter fails a test on a layout overflow, which is the
/// cheapest browser check available here.
const List<Size> _windows = <Size>[
  Size(1440, 900),
  Size(1280, 800),
  Size(1024, 720),
];

class _RouteAdapter implements HttpClientAdapter {
  _RouteAdapter(this.routes);

  /// Path → body. Exact paths, so `/api/orders` and `/api/orders/stats` cannot be confused.
  final Map<String, Object> routes;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    final Object? body = routes[options.path];
    final Map<String, List<String>> headers = <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    };
    if (body == null) {
      return ResponseBody.fromString('{}', 404, headers: headers);
    }
    return ResponseBody.fromString(jsonEncode(body), 200, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _order({
  required String id,
  String status = 'DELIVERED',
  double total = 10,
  String? riderId = 'rider-0001-aaaa',
  String? storeName = 'Rose & Crust',
  DateTime? placedAt,
  DateTime? deliveredAt,
}) =>
    <String, dynamic>{
      'id': id,
      'customerId': 'cust-0001-bbbb',
      'merchantId': 'merch-0001-cccc',
      'riderId': riderId,
      'storeName': storeName,
      'status': status,
      'totalAmount': total,
      'deliveryAddress': '12 Example Street',
      'items': <dynamic>[],
      'availableActions': <String>[],
      'placedAt': placedAt?.toUtc().toIso8601String(),
      'deliveredAt': deliveredAt?.toUtc().toIso8601String(),
      'cancelReason': null,
    };

Map<String, dynamic> _page(List<Map<String, dynamic>> content, {int? totalElements}) =>
    <String, dynamic>{
      'content': content,
      'page': 0,
      'totalElements': totalElements ?? content.length,
      'totalPages': 1,
    };

/// One day of the tier-split series. The server zero-fills both tiers on every day, so these
/// fixtures do too — a client that checked for a missing key would be coding against a shape the
/// platform never sends.
Map<String, dynamic> _day(String date, {required int orders, required int delivered, required double gross}) =>
    <String, dynamic>{
      'day': date,
      'standard': <String, dynamic>{
        'orders': orders,
        'delivered': delivered,
        'gross': gross,
      },
      'express': <String, dynamic>{'orders': 0, 'delivered': 0, 'gross': 0},
    };

/// Fourteen days: a flat older week, then a flat recent one. Flat on purpose — the figures under
/// test are the two seven-day sums, and a shaped series only makes the expected numbers harder to
/// read than the code that produces them.
Map<String, dynamic> _series({
  required int olderOrders,
  required double olderGross,
  required int recentOrders,
  required double recentGross,
}) =>
    <String, dynamic>{
      'windowDays': 14,
      'days': <Map<String, dynamic>>[
        for (int i = 0; i < 7; i++)
          _day('2026-08-${(15 + i).toString().padLeft(2, '0')}',
              orders: olderOrders, delivered: olderOrders, gross: olderGross),
        for (int i = 0; i < 7; i++)
          _day('2026-08-${(22 + i).toString().padLeft(2, '0')}',
              orders: recentOrders, delivered: recentOrders - 2, gross: recentGross),
      ],
    };

void main() {
  late _RouteAdapter adapter;
  late OrderApi orderApi;
  late StoreApi storeApi;
  late AggregatesApi aggregatesApi;
  late ActivityApi activityApi;

  DateTime minutesAgo(int m) => DateTime.now().subtract(Duration(minutes: m));

  setUp(() {
    adapter = _RouteAdapter(<String, Object>{
      '/api/orders/stats': <String, dynamic>{
        'countByStatus': <String, dynamic>{'DELIVERED': 900, 'PLACED': 300},
        'total': 12847,
        'active': 42,
      },
      '/api/orders': _page(<Map<String, dynamic>>[
        _order(
          id: 'aaaaaaaa-1111',
          total: 24.5,
          placedAt: minutesAgo(5),
          deliveredAt: minutesAgo(4),
        ),
        _order(
          id: 'bbbbbbbb-2222',
          status: 'PREPARING',
          total: 18.9,
          riderId: null,
          placedAt: minutesAgo(3),
        ),
        // Same rider as the first row: "Active Riders" is distinct riders, not rows.
        _order(
          id: 'cccccccc-3333',
          status: 'CANCELLED',
          total: 999,
          placedAt: minutesAgo(2),
        ),
      ]),
      // 482 storefronts, one page of none of them — the screen only reads the count.
      '/api/stores': _page(<Map<String, dynamic>>[], totalElements: 482),
    });

    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))
      ..httpClientAdapter = adapter;
    orderApi = OrderApi(dio);
    storeApi = StoreApi(dio);
    aggregatesApi = AggregatesApi(dio);
    activityApi = ActivityApi(dio);
  });

  Future<void> pump(WidgetTester tester, {Size size = const Size(1440, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      home: Scaffold(
        body: OverviewScreen(
          api: orderApi,
          storeApi: storeApi,
          aggregatesApi: aggregatesApi,
          activityApi: activityApi,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// The screen polls; the tree has to go before the test ends or the timer outlives it.
  Future<void> close(WidgetTester tester) => tester.pumpWidget(const SizedBox());

  for (final Size size in _windows) {
    testWidgets('renders the four KPIs at ${size.width.toInt()}px',
        (WidgetTester tester) async {
      await pump(tester, size: size);

      expect(find.text('Operations Dashboard'), findsOneWidget);
      expect(find.text('Total Orders'), findsOneWidget);
      // Grouped exactly as the design draws it.
      expect(find.text('12,847'), findsOneWidget);
      expect(find.text('Active Merchants'), findsOneWidget);
      expect(find.text('482'), findsOneWidget);

      await close(tester);
    });
  }

  testWidgets('counts distinct riders, not rows', (WidgetTester tester) async {
    await pump(tester);

    expect(find.text('Active Riders'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    await close(tester);
  });

  testWidgets('leaves a cancelled order out of the revenue', (WidgetTester tester) async {
    await pump(tester);

    // 24.50 + 18.90, with the 999.00 cancelled order excluded.
    expect(find.text('43.40'), findsOneWidget);
    expect(find.textContaining('999'), findsNothing);

    await close(tester);
  });

  testWidgets('invents no movement when the series does not answer',
      (WidgetTester tester) async {
    await pump(tester);

    // The design's caption. With no series behind it there is nothing to derive a movement from,
    // so the slot carries what the figure was actually measured over instead.
    expect(find.textContaining('vs last week'), findsNothing);
    expect(find.textContaining('from the 3 most recent orders'), findsWidgets);
    expect(find.textContaining('Counted from the 3 most recent orders'), findsOneWidget);

    await close(tester);
  });

  testWidgets('says the activity rows are derived when the feed does not answer',
      (WidgetTester tester) async {
    await pump(tester);

    // Not "coming soon" — the feed exists. It did not answer, and a card showing two of the four
    // kinds of event it normally carries has to say which two.
    expect(find.textContaining('The activity feed did not answer'), findsOneWidget);

    await close(tester);
  });

  group('with the platform series and feed answering', () {
    /// Older week: 70 orders worth 700.00. Recent week: 77 orders worth 840.00.
    /// So orders move +10.0% and delivered value +20.0%, and today's gross is 120.00.
    void wireSeries({
      int olderOrders = 10,
      double olderGross = 100,
      int recentOrders = 11,
      double recentGross = 120,
    }) {
      adapter.routes['/api/orders/daily'] = _series(
        olderOrders: olderOrders,
        olderGross: olderGross,
        recentOrders: recentOrders,
        recentGross: recentGross,
      );
    }

    void wireFeed() {
      adapter.routes['/api/orders/activity'] = _page(<Map<String, dynamic>>[
        <String, dynamic>{
          'occurredAt': minutesAgo(4).toUtc().toIso8601String(),
          'event': 'delivered',
          'status': 'DELIVERED',
          'orderId': 'dddddddd-4444',
          'storeName': 'Falafel King',
          'amount': 24.0,
        },
        <String, dynamic>{
          'occurredAt': minutesAgo(9).toUtc().toIso8601String(),
          'event': 'placed',
          'status': 'PLACED',
          // Null on a Butler errand — there is no shop, and the row must say so rather than
          // leaving a blank where a name should be.
          'orderId': 'eeeeeeee-5555',
          'storeName': null,
          'amount': 12.5,
        },
        <String, dynamic>{
          'occurredAt': minutesAgo(20).toUtc().toIso8601String(),
          'event': 'status-changed',
          'status': 'PICKED_UP',
          'orderId': 'ffffffff-6666',
          'storeName': 'Rose & Crust',
          'amount': 30.0,
        },
      ]);
    }

    testWidgets('draws the week-over-week movements the series supports',
        (WidgetTester tester) async {
      wireSeries();
      await pump(tester);

      // 77 against 70, and 840.00 against 700.00 — arithmetic on the series, not a guess.
      expect(find.text('+10.0%'), findsOneWidget);
      expect(find.text('orders vs last week'), findsOneWidget);
      expect(find.text('+20.0%'), findsOneWidget);
      expect(find.text('delivered value vs last week'), findsOneWidget);

      await close(tester);
    });

    testWidgets("takes today's revenue from the server's own day", (WidgetTester tester) async {
      wireSeries();
      await pump(tester);

      // The last entry of the series is today in the platform's zone — not the viewer's clock,
      // and not a sum over the loaded page.
      expect(find.text('120.00'), findsOneWidget);
      expect(find.text('43.40'), findsNothing);

      await close(tester);
    });

    testWidgets('shows a falling movement as a fall, not as growth',
        (WidgetTester tester) async {
      // Recent week is 7 × 5 = 35 orders against 70; value 7 × 50 = 350 against 700.
      wireSeries(recentOrders: 5, recentGross: 50);
      await pump(tester);

      expect(find.text('−50.0%'), findsNWidgets(2));

      await close(tester);
    });

    testWidgets('refuses to compute a percentage of nothing', (WidgetTester tester) async {
      // A previous week with no orders at all. There is no percentage of zero, and printing one
      // would be the single most quotable invented number on this page.
      wireSeries(olderOrders: 0, olderGross: 0);
      await pump(tester);

      expect(find.textContaining('%'), findsNothing);
      expect(find.text('77 orders in the last 7 days'), findsOneWidget);

      await close(tester);
    });

    testWidgets('plots the platform bars rather than the loaded sample',
        (WidgetTester tester) async {
      wireSeries();
      await pump(tester);

      expect(find.text('Every order the platform took, day by day.'), findsOneWidget);
      expect(find.textContaining('Counted from the'), findsNothing);

      await close(tester);
    });

    testWidgets('renders the real feed in the card row language',
        (WidgetTester tester) async {
      wireFeed();
      await pump(tester);

      expect(find.text('Order #dddddddd was delivered.'), findsOneWidget);
      expect(find.text('Order #eeeeeeee placed at a Butler errand.'), findsOneWidget);
      // Every other transition folds into one row that names the status behind it.
      expect(find.text('Order #ffffffff is now on the way.'), findsOneWidget);
      expect(find.text('4 mins ago'), findsOneWidget);
      // The derivation note is gone: these rows are the platform's own events.
      expect(find.textContaining('The activity feed did not answer'), findsNothing);

      await close(tester);
    });
  });

  testWidgets('builds the activity log out of real order events',
      (WidgetTester tester) async {
    await pump(tester);

    expect(find.text('Live Activity Log'), findsOneWidget);
    expect(find.text('Order #aaaaaaaa was delivered.'), findsOneWidget);
    expect(find.text('Order #bbbbbbbb placed at Rose & Crust.'), findsOneWidget);
    expect(find.text('4 mins ago'), findsOneWidget);

    await close(tester);
  });

  testWidgets('survives a storefront count it cannot read', (WidgetTester tester) async {
    adapter.routes.remove('/api/stores');
    await pump(tester);

    // The card blanks itself; the rest of the page still has its numbers.
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('12,847'), findsOneWidget);

    await close(tester);
  });
}
