import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_portal/src/backoffice/dashboard_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The cross-merchant orders ledger — Figma `backoffice-orders` (3:2817).
///
/// The screen is read-only apart from one thing, and that one thing is what most of these tests are
/// about: a support cancellation is a real mutation on somebody's dinner, so it has to be
/// unreachable without a reason typed and a second click, and invisible entirely on an order the
/// server did not offer it on.
const List<Size> _windows = <Size>[
  Size(1440, 900),
  Size(1280, 800),
  Size(1024, 720),
];

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.orders);

  List<Map<String, dynamic>> orders;

  /// Every request the screen made, so the tests can assert on what it asked the server for.
  final List<RequestOptions> calls = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add(options);
    final Map<String, List<String>> headers = <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    };

    if (options.path.endsWith('/cancel')) {
      return ResponseBody.fromString(jsonEncode(orders.first), 200, headers: headers);
    }
    return ResponseBody.fromString(
      jsonEncode(<String, dynamic>{
        'content': orders,
        'page': 0,
        'totalElements': orders.length,
        'totalPages': 1,
      }),
      200,
      headers: headers,
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _order({
  required String id,
  String status = 'PREPARING',
  double total = 24.5,
  String? riderId = 'rider-0001-aaaa',
  String? storeName = 'Rose & Crust',
  List<String> actions = const <String>[],
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
      'availableActions': actions,
      'placedAt': DateTime.now().subtract(const Duration(minutes: 5)).toUtc().toIso8601String(),
      'deliveredAt': null,
      'cancelReason': null,
    };

void main() {
  late _StubAdapter adapter;
  late OrderApi api;

  setUp(() {
    adapter = _StubAdapter(<Map<String, dynamic>>[
      _order(id: 'aaaaaaaa-1111', actions: <String>['CANCEL']),
      _order(
        id: 'bbbbbbbb-2222',
        status: 'DELIVERED',
        total: 1234.5,
        riderId: null,
        storeName: 'Salad & Co.',
      ),
    ]);
    api = OrderApi(Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter);
  });

  Future<void> pump(WidgetTester tester, {Size size = const Size(1440, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      home: Scaffold(body: DashboardScreen(api: api)),
    ));
    await tester.pumpAndSettle();
  }

  /// The screen polls; the tree has to go before the test ends or the timer outlives it.
  Future<void> close(WidgetTester tester) => tester.pumpWidget(const SizedBox());

  for (final Size size in _windows) {
    testWidgets('renders the ledger at ${size.width.toInt()}px', (WidgetTester tester) async {
      await pump(tester, size: size);

      expect(find.text('Orders Ledger'), findsOneWidget);
      expect(find.text('Rider Assigned'), findsOneWidget);
      expect(find.text('#aaaaaaaa'), findsOneWidget);
      // The design's word for an order nobody has picked up.
      expect(find.text('Unassigned'), findsOneWidget);
      // Grouped and to the cent, with no currency asserted.
      expect(find.text('1,234.50'), findsOneWidget);

      await close(tester);
    });
  }

  testWidgets('keeps every lifecycle filter, not only the four drawn',
      (WidgetTester tester) async {
    await pump(tester);

    for (final String label in <String>[
      'All',
      'Preparing',
      'On the way',
      'Delivered',
      'Placed',
      'Accepted',
      'Ready for pickup',
      'Cancelled',
    ]) {
      expect(find.text(label), findsWidgets, reason: '$label pill is missing');
    }

    // `.first` is the pill: the filter row is drawn above the table, and the second "Delivered" on
    // screen is the status badge on a row.
    await tester.tap(find.text('Delivered').first);
    await tester.pumpAndSettle();

    expect(adapter.calls.last.queryParameters['status'], 'DELIVERED');

    await close(tester);
  });

  testWidgets('searches the loaded page rather than pretending to search the ledger',
      (WidgetTester tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField).last, 'Salad');
    await tester.pumpAndSettle();

    expect(find.text('#bbbbbbbb'), findsOneWidget);
    expect(find.text('#aaaaaaaa'), findsNothing);
    // A client-side filter must not have gone back to the server for it.
    expect(adapter.calls.last.queryParameters.containsKey('status'), isFalse);

    await close(tester);
  });

  testWidgets('offers no cancellation on an order the server did not offer it on',
      (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.text('#bbbbbbbb'));
    await tester.pumpAndSettle();

    expect(find.text('Order #bbbbbbbb'), findsOneWidget);
    expect(find.text('Support cancellation'), findsNothing);
    expect(find.text('Cancel order'), findsNothing);

    await close(tester);
  });

  testWidgets('will not cancel without a reason, and asks twice',
      (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.text('#aaaaaaaa'));
    await tester.pumpAndSettle();

    expect(find.text('Support cancellation'), findsOneWidget);

    // Armed but inert: no reason typed yet.
    await tester.tap(find.text('Cancel order'));
    await tester.pumpAndSettle();
    expect(find.text('Yes, cancel it'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Reason for cancelling'),
        'Customer phoned; shop closed early');
    await tester.pumpAndSettle();

    // First click arms, second click sends.
    await tester.tap(find.text('Cancel order'));
    await tester.pumpAndSettle();
    expect(adapter.calls.where((RequestOptions o) => o.path.endsWith('/cancel')), isEmpty);

    await tester.tap(find.text('Yes, cancel it'));
    await tester.pumpAndSettle();

    final RequestOptions sent =
        adapter.calls.lastWhere((RequestOptions o) => o.path.endsWith('/cancel'));
    expect(sent.path, '/api/orders/aaaaaaaa-1111/cancel');
    expect((sent.data as Map<String, dynamic>)['reason'], 'Customer phoned; shop closed early');
    // The dialog closes and the table reloads.
    expect(find.text('Support cancellation'), findsNothing);

    await close(tester);
  });
}
