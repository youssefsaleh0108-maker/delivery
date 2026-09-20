import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// PT-6: Reject cancels a customer's order, so it asks first — from both places it is offered.
///
/// The portal's pinned test covers the queue. These cover the order's own page, which offers the
/// same button and was the second unguarded tap; what the merchant's words do to the reason
/// Backoffice reads; and the dialog itself on a 320dp phone and in Arabic, since it is new layout
/// in a package two hosts of very different widths mount.
class _Script implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];

  List<RequestOptions> get posts =>
      requests.where((RequestOptions r) => r.method == 'POST').toList();

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    // A decision is answered with the order as it now stands; every read with the order as it was.
    final (int status, Object body) = options.method == 'POST'
        ? (200, _order(status: 'CANCELLED', actions: const <String>[]))
        : options.path == '/api/orders/merchant'
            ? (200, _page(<Map<String, dynamic>>[_order()]))
            : (200, _order());
    return ResponseBody.fromString(jsonEncode(body), status,
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

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      theme: DeliveryTheme.light(),
      supportedLocales: DeliveryStrings.supportedLocales,
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      home: child is Scaffold ? child : Scaffold(body: child),
    );

Finder _button(String label) => find.widgetWithText(MerchantActionButton, label);

/// The dialog's two answers, in the order it lays them out: keep, then reject.
Finder _dialogButtons() =>
    find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextButton));

/// The order's own page, opened on an order the merchant may still reject.
Future<_Script> _pumpDetail(WidgetTester tester,
    {Size size = const Size(1280, 900), Locale locale = const Locale('en')}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final _Script script = _Script();
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = script;
  await tester.pumpWidget(_wrap(
    MerchantOrderDetailScreen(
      api: OrderApi(dio),
      order: DeliveryOrder.fromJson(_order()),
    ),
    locale: locale,
  ));
  await tester.pumpAndSettle();
  return script;
}

/// The queue, with one order waiting.
Future<_Script> _pumpQueue(WidgetTester tester,
    {Size size = const Size(1280, 900), Locale locale = const Locale('en')}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final _Script script = _Script();
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = script;
  await tester.pumpWidget(_wrap(OrdersScreen(api: OrderApi(dio)), locale: locale));
  await tester.pumpAndSettle();
  return script;
}

void main() {
  testWidgets('the order page asks before it rejects, and keeps the order when told to',
      (WidgetTester tester) async {
    final _Script script = await _pumpDetail(tester);
    final DeliveryStrings t = lookupDeliveryStrings(const Locale('en'));

    await tester.tap(_button(t.merchReject));
    await tester.pumpAndSettle();

    expect(script.posts, isEmpty, reason: 'the order was cancelled on a single tap');
    expect(find.text(t.merchRejectConfirmTitle), findsOneWidget);

    await tester.tap(_dialogButtons().first); // Keep order
    await tester.pumpAndSettle();

    expect(script.posts, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
    // The screen is left as it was found: the button works again, not stuck busy.
    expect(tester.widget<MerchantActionButton>(_button(t.merchReject)).onPressed, isNotNull);
  });

  testWidgets('confirming on the order page sends the cancel with the marker Backoffice reads',
      (WidgetTester tester) async {
    final _Script script = await _pumpDetail(tester);
    final DeliveryStrings t = lookupDeliveryStrings(const Locale('en'));

    await tester.tap(_button(t.merchReject));
    await tester.pumpAndSettle();
    await tester.tap(_dialogButtons().last);
    await tester.pumpAndSettle();

    expect(script.posts, hasLength(1));
    expect(script.posts.single.path, '/api/orders/$_id/cancel');
    expect(script.posts.single.data, <String, dynamic>{'reason': merchantCancelReason});
  });

  testWidgets('the merchant\'s own words go after the marker, never instead of it',
      (WidgetTester tester) async {
    final _Script script = await _pumpQueue(tester);
    final DeliveryStrings t = lookupDeliveryStrings(const Locale('en'));

    await tester.tap(_button(t.merchReject));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Out of dough  ');
    await tester.tap(_dialogButtons().last);
    await tester.pumpAndSettle();

    expect(script.posts.single.data,
        <String, dynamic>{'reason': '$merchantCancelReason: Out of dough'});
  });

  testWidgets('a reason longer than the server takes is cut, not refused',
      (WidgetTester tester) async {
    final _Script script = await _pumpQueue(tester);
    final DeliveryStrings t = lookupDeliveryStrings(const Locale('en'));

    await tester.tap(_button(t.merchReject));
    await tester.pumpAndSettle();
    // Past what the field's own limit allows, as a paste or an emoji-heavy note can be.
    await tester.enterText(find.byType(TextField), '😀' * 400);
    await tester.tap(_dialogButtons().last);
    await tester.pumpAndSettle();

    final String sent = (script.posts.single.data as Map<String, dynamic>)['reason'] as String;
    expect(sent, startsWith('$merchantCancelReason: '));
    expect(sent.length, lessThanOrEqualTo(OrderApi.cancelReasonMaxLength));
    // Never cut between the two code units of one emoji: every high surrogate still has its low
    // one after it, and no low surrogate stands alone.
    for (int i = 0; i < sent.length; i++) {
      final int unit = sent.codeUnitAt(i);
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        expect(i + 1, lessThan(sent.length), reason: 'a high surrogate at the very end');
        expect(sent.codeUnitAt(i + 1), inInclusiveRange(0xDC00, 0xDFFF));
        i++;
      } else {
        expect(unit, isNot(inInclusiveRange(0xDC00, 0xDFFF)), reason: 'a low surrogate alone');
      }
    }
  });

  testWidgets('the dialog fits a 320dp phone', (WidgetTester tester) async {
    await _pumpQueue(tester, size: const Size(320, 640));
    final DeliveryStrings t = lookupDeliveryStrings(const Locale('en'));

    await tester.tap(_button(t.merchReject));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    final Size dialog = tester.getSize(find.byType(AlertDialog));
    expect(dialog.width, lessThanOrEqualTo(320));
  });

  testWidgets('the dialog is Arabic in Arabic, and lays out right to left',
      (WidgetTester tester) async {
    await _pumpQueue(tester, locale: const Locale('ar'));
    final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

    await tester.tap(_button(ar.merchReject));
    await tester.pumpAndSettle();

    expect(find.text(ar.merchRejectConfirmTitle), findsOneWidget);
    expect(find.text(ar.merchRejectConfirmBody), findsOneWidget);
    expect(find.text(ar.merchRejectReason), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(AlertDialog))), TextDirection.rtl);
    // Keep comes first in reading order, which right to left puts on the right.
    expect(tester.getCenter(_dialogButtons().first).dx,
        greaterThan(tester.getCenter(_dialogButtons().last).dx));
    expect(tester.takeException(), isNull);
  });
}
