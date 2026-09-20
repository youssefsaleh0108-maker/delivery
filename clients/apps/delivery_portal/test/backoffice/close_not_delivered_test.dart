import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/backoffice/dashboard_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Closing an order a rider already has, from the orders ledger (RECON-10).
///
/// The order cannot be cancelled — the server refuses that for everybody once a rider has it — and
/// what support has instead decides whether the shop and the delivery are still paid out of the
/// platform's pocket. So the form asks for a reason and both decisions, sends exactly what the
/// switches say, and asks twice before it does: the same care the support cancellation already
/// takes, on a screen that also moves money.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.orders);

  List<Map<String, dynamic>> orders;

  final List<RequestOptions> calls = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add(options);
    final Map<String, List<String>> headers = <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    };

    if (options.path.endsWith('/close-not-delivered') || options.path.endsWith('/cancel')) {
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
  String status = 'PICKED_UP',
  List<String> actions = const <String>['CLOSE_NOT_DELIVERED'],
  String? cancelStage,
  String? cancelReason,
  bool compensateMerchant = false,
  bool compensateCarrier = false,
}) =>
    <String, dynamic>{
      'id': id,
      'customerId': 'cust-0001-bbbb',
      'merchantId': 'merch-0001-cccc',
      'riderId': 'rider-0001-aaaa',
      'storeName': 'Rose & Crust',
      'status': status,
      'totalAmount': 19.5,
      'deliveryAddress': '12 Example Street',
      'items': <dynamic>[],
      'availableActions': actions,
      'placedAt': DateTime.now().subtract(const Duration(minutes: 40)).toUtc().toIso8601String(),
      'deliveredAt': null,
      'cancelReason': cancelReason,
      'cancelStage': cancelStage,
      'compensateMerchant': compensateMerchant,
      'compensateCarrier': compensateCarrier,
    };

void main() {
  late _StubAdapter adapter;
  late OrderApi api;

  void serve(List<Map<String, dynamic>> orders) {
    adapter = _StubAdapter(orders);
    api = OrderApi(Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter);
  }

  setUp(() => serve(<Map<String, dynamic>>[_order(id: 'aaaaaaaa-1111')]));

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: Scaffold(body: DashboardScreen(api: api)),
    ));
    await tester.pumpAndSettle();
  }

  /// The screen polls; the tree has to go before the test ends or the timer outlives it.
  Future<void> close(WidgetTester tester) => tester.pumpWidget(const SizedBox());

  Future<void> openTheOrder(WidgetTester tester) async {
    await tester.tap(find.text('#aaaaaaaa'));
    await tester.pumpAndSettle();
  }

  RequestOptions lastClose() =>
      adapter.calls.lastWhere((RequestOptions o) => o.path.endsWith('/close-not-delivered'));

  testWidgets('an order on the road offers closing it, not cancelling it, with both shares on',
      (WidgetTester tester) async {
    await pump(tester);
    await openTheOrder(tester);

    // The section heading, and the button under it.
    expect(find.text('Close as not delivered'), findsNWidgets(2));
    expect(find.text('Support cancellation'), findsNothing);
    expect(find.text('Cancel order'), findsNothing);

    // The owner's default: the shop made the goods and the rider carried them.
    expect(find.text('Pay the shop its share'), findsOneWidget);
    expect(find.text('Pay the delivery fee'), findsOneWidget);
    for (final String id in <String>['merchant', 'carrier']) {
      expect(
        tester
            .widget<Switch>(find.byKey(ValueKey<String>('close-not-delivered-pay-$id')))
            .value,
        isTrue,
        reason: 'the $id share starts switched on',
      );
    }

    await close(tester);
  });

  testWidgets('will not close without a reason, asks twice, and sends both decisions',
      (WidgetTester tester) async {
    await pump(tester);
    await openTheOrder(tester);

    // Armed but inert: no reason typed yet.
    await tester.tap(find.text('Close as not delivered').last);
    await tester.pumpAndSettle();
    expect(find.text('Yes, close it'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Why it was not delivered'),
        'Customer refused it at the door');
    await tester.pumpAndSettle();

    // First click arms, second sends.
    await tester.tap(find.text('Close as not delivered').last);
    await tester.pumpAndSettle();
    expect(adapter.calls.where((RequestOptions o) => o.path.endsWith('/close-not-delivered')),
        isEmpty);

    await tester.tap(find.text('Yes, close it'));
    await tester.pumpAndSettle();

    final RequestOptions sent = lastClose();
    expect(sent.path, '/api/orders/aaaaaaaa-1111/close-not-delivered');
    final Map<String, dynamic> body = sent.data as Map<String, dynamic>;
    expect(body['reason'], 'Customer refused it at the door');
    expect(body['compensateMerchant'], isTrue);
    expect(body['compensateCarrier'], isTrue);
    // The dialog closes and the table reloads.
    expect(find.text('Close as not delivered'), findsNothing);

    await close(tester);
  });

  testWidgets('a share switched off is sent switched off', (WidgetTester tester) async {
    await pump(tester);
    await openTheOrder(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Why it was not delivered'),
        'Shop sent the wrong order');
    await tester.tap(find.byKey(const ValueKey<String>('close-not-delivered-pay-merchant')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Close as not delivered').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, close it'));
    await tester.pumpAndSettle();

    final Map<String, dynamic> body = lastClose().data as Map<String, dynamic>;
    expect(body['compensateMerchant'], isFalse);
    expect(body['compensateCarrier'], isTrue);

    await close(tester);
  });

  testWidgets('an order already closed after pickup says so, and what was paid',
      (WidgetTester tester) async {
    serve(<Map<String, dynamic>>[
      _order(
        id: 'aaaaaaaa-1111',
        status: 'CANCELLED',
        actions: const <String>[],
        cancelStage: 'AFTER_PICKUP',
        cancelReason: 'Customer refused it at the door',
        compensateMerchant: true,
      )
    ]);
    await pump(tester);
    await openTheOrder(tester);

    expect(find.text('Closed after pickup'), findsOneWidget);
    expect(find.text('Nothing was collected; the platform paid the shop its share'),
        findsOneWidget);
    expect(find.text('Closed because'), findsOneWidget);
    // Nothing left to do to it.
    expect(find.text('Yes, close it'), findsNothing);
    expect(find.text('Support cancellation'), findsNothing);

    await close(tester);
  });

  testWidgets('an order still at the shop is cancelled exactly as it always was',
      (WidgetTester tester) async {
    serve(<Map<String, dynamic>>[
      _order(id: 'aaaaaaaa-1111', status: 'PREPARING', actions: const <String>['CANCEL'])
    ]);
    await pump(tester);
    await openTheOrder(tester);

    expect(find.text('Support cancellation'), findsOneWidget);
    expect(find.text('Close as not delivered'), findsNothing);
    expect(find.byKey(const ValueKey<String>('close-not-delivered-pay-merchant')), findsNothing);

    await tester.enterText(
        find.widgetWithText(TextField, 'Reason for cancelling'), 'Shop closed early');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, cancel it'));
    await tester.pumpAndSettle();

    final RequestOptions sent =
        adapter.calls.lastWhere((RequestOptions o) => o.path.endsWith('/cancel'));
    expect((sent.data as Map<String, dynamic>)['reason'], 'Shop closed early');

    await close(tester);
  });
}
