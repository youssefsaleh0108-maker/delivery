import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// A merchant's decisions on an incoming order, from the portal's Orders page: accept it, or reject
/// it (the CANCEL transition, labelled "Reject" here).
///
/// Only the layout of this queue was tested before. These pin what each button sends, what the
/// merchant is told when the server refuses, and that a decision cannot be sent twice while the
/// first is in flight. The last test pins PT-6 and fails today.

/// Answers each request through [handle], and keeps every request for the assertions.
class _Script implements HttpClientAdapter {
  _Script(this.handle);

  final Future<(int, Object?)> Function(RequestOptions) handle;
  final List<RequestOptions> requests = <RequestOptions>[];

  List<RequestOptions> get posts =>
      requests.where((RequestOptions r) => r.method == 'POST').toList();

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    final (int status, Object? body) = await handle(options);
    return ResponseBody.fromString(body == null ? '' : jsonEncode(body), status,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        });
  }

  @override
  void close({bool force = false}) {}
}

const String _id = 'aaaaaaaa-0000-4000-8000-000000000001';

Map<String, dynamic> _order({String status = 'PLACED', List<String>? actions}) =>
    <String, dynamic>{
      'id': _id,
      'customerId': 'customer-1',
      'merchantId': 'merchant-1',
      'riderId': null,
      'status': status,
      'totalAmount': 24.5,
      'deliveryFee': 2.0,
      'deliveryAddress': 'Hamra, Beirut',
      'contactPhone': '+96170000000',
      'items': <dynamic>[
        <String, dynamic>{
          'productId': 'p1',
          'productName': 'Manoushe',
          'unitPrice': 12.25,
          'qty': 2,
          'lineTotal': 24.5,
        },
      ],
      'availableActions': actions ?? const <String>['ACCEPT', 'CANCEL'],
      'placedAt': '2026-09-19T20:55:00Z',
      'deliveredAt': null,
      'cancelReason': null,
    };

Map<String, dynamic> _page(List<Map<String, dynamic>> orders) => <String, dynamic>{
      'content': orders,
      'page': 0,
      'size': 50,
      'totalElements': orders.length,
      'totalPages': 1,
    };

Widget _wrap(Widget child) => MaterialApp(
      locale: const Locale('en'),
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

Future<_Script> _pump(WidgetTester tester,
    Future<(int, Object?)> Function(RequestOptions) onPost) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final _Script script = _Script((RequestOptions r) async {
    if (r.method == 'GET' && r.path == '/api/orders/merchant') {
      return (200, _page(<Map<String, dynamic>>[_order()]));
    }
    if (r.method == 'POST') return onPost(r);
    return (404, null);
  });
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = script;
  await tester.pumpWidget(_wrap(OrdersScreen(api: OrderApi(dio))));
  await tester.pumpAndSettle();
  return script;
}

Finder _button(String label) => find.widgetWithText(MerchantActionButton, label);

void main() {
  testWidgets('Accept sends accept for that order, and nothing else', (WidgetTester tester) async {
    final _Script script = await _pump(tester, (RequestOptions r) async =>
        (200, _order(status: 'ACCEPTED', actions: const <String>['PREPARE', 'CANCEL'])));

    await tester.tap(_button('Accept'));
    await tester.pumpAndSettle();

    expect(script.posts.map((RequestOptions r) => r.path), <String>['/api/orders/$_id/accept']);
  });

  testWidgets('Reject sends the cancel transition with the reason back office reads',
      (WidgetTester tester) async {
    final _Script script = await _pump(tester, (RequestOptions r) async =>
        (200, _order(status: 'CANCELLED', actions: const <String>[])));

    await tester.tap(_button('Reject'));
    await tester.pumpAndSettle();
    // The confirmation PT-6 asks for, if a build has one: confirm it, so this test pins the request.
    final Finder confirm = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextButton));
    if (confirm.evaluate().isNotEmpty) {
      await tester.tap(confirm.last);
      await tester.pumpAndSettle();
    }

    expect(script.posts, hasLength(1));
    expect(script.posts.single.path, '/api/orders/$_id/cancel');
    expect(script.posts.single.data, <String, dynamic>{'reason': 'Cancelled by merchant'});
  });

  testWidgets('an order somebody else moved first says so, and the queue reloads',
      (WidgetTester tester) async {
    final _Script script = await _pump(
        tester, (RequestOptions r) async => (422, <String, dynamic>{'message': 'moved'}));
    final int readsBefore =
        script.requests.where((RequestOptions r) => r.method == 'GET').length;

    await tester.tap(_button('Accept'));
    await tester.pumpAndSettle();

    expect(find.text('That order has already moved on. Refreshing.'), findsOneWidget);
    expect(script.requests.where((RequestOptions r) => r.method == 'GET').length,
        greaterThan(readsBefore));
    // Nothing left in a busy state: the merchant can act again.
    expect(tester.widget<MerchantActionButton>(_button('Accept')).onPressed, isNotNull);
  });

  testWidgets('any other refusal says the action failed, in words', (WidgetTester tester) async {
    await _pump(tester, (RequestOptions r) async => (500, <String, dynamic>{'message': 'boom'}));

    await tester.tap(_button('Accept'));
    await tester.pumpAndSettle();

    expect(find.text('Could not accept.'), findsOneWidget);
  });

  testWidgets('a decision in flight cannot be sent a second time', (WidgetTester tester) async {
    final Completer<(int, Object?)> answer = Completer<(int, Object?)>();
    final _Script script = await _pump(tester, (RequestOptions r) => answer.future);

    final Finder buttons = find.byType(MerchantActionButton);
    final Offset accept = tester.getCenter(_button('Accept'));
    final Offset reject = tester.getCenter(_button('Reject'));

    await tester.tap(_button('Accept'));
    await tester.pump();
    // Both of the order's buttons are dead while the server has the first decision (they draw a
    // spinner instead of their label, so they are found by type and by where they were).
    expect(buttons, findsNWidgets(2));
    for (final MerchantActionButton b in tester.widgetList<MerchantActionButton>(buttons)) {
      expect(b.onPressed, isNull);
    }
    await tester.tapAt(accept);
    await tester.tapAt(reject);
    await tester.pump();

    answer.complete((200, _order(status: 'ACCEPTED', actions: const <String>['PREPARE', 'CANCEL'])));
    await tester.pumpAndSettle();
    expect(script.posts, hasLength(1));
  });

  // PT-6: rejecting an order is irreversible and customer-facing (it cancels the order), yet the
  // button sits beside Accept and sends on one tap, from the queue and from the order's own page.
  // Back office's decline of an application asks for a reason first; this asks nothing.
  testWidgets('PT-6: Reject asks before it cancels a customer\'s order', (WidgetTester tester) async {
    final _Script script = await _pump(tester, (RequestOptions r) async =>
        (200, _order(status: 'CANCELLED', actions: const <String>[])));

    await tester.tap(_button('Reject'));
    await tester.pumpAndSettle();

    expect(script.posts, isEmpty, reason: 'the order was cancelled on a single tap');
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
