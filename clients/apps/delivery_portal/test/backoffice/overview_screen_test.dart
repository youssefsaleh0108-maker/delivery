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
/// Every number on this screen is computed on the client from a page of orders, so the tests are
/// about the two ways that can go wrong: a figure that is not what the data says, and a figure the
/// design draws that the platform cannot answer being filled in anyway. The design's
/// "+14.3% vs last week" is the second kind, and its absence is asserted here rather than left to
/// somebody's good intentions.
///
/// The fixtures are all a few minutes old on purpose: "today" is the real clock, so a fixture dated
/// in hours would move across midnight and take the revenue assertions with it.
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

void main() {
  late _RouteAdapter adapter;
  late OrderApi orderApi;
  late StoreApi storeApi;

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
  });

  Future<void> pump(WidgetTester tester, {Size size = const Size(1440, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      home: Scaffold(body: OverviewScreen(api: orderApi, storeApi: storeApi)),
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

  testWidgets('never invents a week-over-week movement', (WidgetTester tester) async {
    await pump(tester);

    // The design's caption. Nothing on the platform can produce the number in front of it, so the
    // slot carries what the figure was actually measured over instead — and the affordances that
    // would need a backend say so out loud.
    expect(find.textContaining('vs last week'), findsNothing);
    expect(find.textContaining('from the 3 most recent orders'), findsWidgets);
    expect(find.text('Live feed coming soon'), findsOneWidget);

    await close(tester);
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
