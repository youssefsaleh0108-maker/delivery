import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// A shop thread opened from an order, from either side, and the order the thread then carries.
void main() {
  /// A server that answers every request with [status] and [body], recording what it was asked.
  Dio answering(int status, Object? body, {List<RequestOptions>? asked}) {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        asked?.add(options);
        final Response<dynamic> response =
            Response<dynamic>(requestOptions: options, statusCode: status, data: body);
        if (status >= 400) {
          handler.reject(DioException(
              requestOptions: options, type: DioExceptionType.badResponse, response: response));
        } else {
          handler.resolve(response);
        }
      },
    ));
    return dio;
  }

  const Map<String, dynamic> labelled = <String, dynamic>{
    'id': 't1',
    'storeId': 's1',
    'storeName': 'Abu Hassan Print',
    'customerName': 'Tania K.',
    'yourSide': 'SHOP',
    'open': true,
    'lastSequence': 0,
    'unread': 0,
    'orderId': '5f0c2a9e-1111-4222-8333-444455556666',
    'orderShortId': '5f0c2a9e',
    'orderKind': 'SERVICE',
  };

  group('a shop thread carrying an order', () {
    test('reads the order it was opened from, and keeps it through copyWith', () {
      final ShopThread thread = ShopThread.fromJson(labelled);

      expect(thread.orderId, '5f0c2a9e-1111-4222-8333-444455556666');
      expect(thread.orderShortId, '5f0c2a9e');
      expect(thread.orderKind, OrderKind.service);

      final ShopThread read = thread.copyWith(unread: 0, open: false);
      expect(read.orderId, thread.orderId);
      expect(read.orderShortId, '5f0c2a9e');
      expect(read.orderKind, OrderKind.service);
    });

    test('a thread opened only from the shop page has no order, rather than a basket', () {
      final ShopThread thread = ShopThread.fromJson(<String, dynamic>{
        ...labelled,
        'orderId': null,
        'orderShortId': null,
        'orderKind': null,
      });

      expect(thread.orderId, isNull);
      expect(thread.orderShortId, isNull);
      expect(thread.orderKind, isNull);
    });

    test('an order kind this build does not know stays unknown', () {
      final ShopThread thread = ShopThread.fromJson(<String, dynamic>{...labelled, 'orderKind': 'BOOKING'});

      expect(thread.orderKind, OrderKind.unknown);
    });
  });

  group('the shop thread client', () {
    test('a customer opens from the shop page without an order, and from an order with it', () async {
      final List<RequestOptions> asked = <RequestOptions>[];
      final ShopChatApi api = ShopChatApi(
          answering(200, <String, dynamic>{...labelled, 'yourSide': 'CUSTOMER'}, asked: asked));

      await api.openWithStore('s1');
      final ShopThread fromOrder = await api.openWithStore('s1', orderId: 'o1');

      expect(asked[0].method, 'POST');
      expect(asked[0].path, '/api/chat/stores/s1/thread');
      expect(asked[0].queryParameters, isEmpty);
      expect(asked[1].method, 'POST');
      expect(asked[1].path, '/api/chat/stores/s1/thread');
      expect(asked[1].queryParameters, <String, dynamic>{'orderId': 'o1'});
      expect(fromOrder.yourSide, ShopThreadSide.customer);
      expect(fromOrder.orderKind, OrderKind.service);
    });

    test('a merchant opens the thread for an order, and reads it as the shop', () async {
      final List<RequestOptions> asked = <RequestOptions>[];
      final ShopChatApi api = ShopChatApi(answering(200, labelled, asked: asked));

      final ShopThread thread = await api.openForOrder('o1');

      expect(asked.single.method, 'POST');
      expect(asked.single.path, '/api/chat/orders/o1/shop-thread');
      expect(asked.single.queryParameters, isEmpty);
      expect(thread.yourSide, ShopThreadSide.shop);
      expect(thread.customerName, 'Tania K.');
      expect(thread.orderShortId, '5f0c2a9e');
    });

    test('an order past its window arrives as a closed order chat, with when it closed', () async {
      final ShopChatApi api = ShopChatApi(answering(409,
          <String, dynamic>{'title': 'Order chat closed', 'closedAt': '2026-09-01T10:00:00Z'}));

      await expectLater(
        api.openForOrder('o1'),
        throwsA(isA<ShopOrderChatClosedException>().having(
            (ShopOrderChatClosedException e) => e.closedAt?.toUtc(),
            'closedAt',
            DateTime.utc(2026, 9, 1, 10))),
      );
    });

    test('an order that is not the caller\'s, or orders that cannot be checked, stay the original error',
        () async {
      await expectLater(
        ShopChatApi(answering(404, <String, dynamic>{'title': 'Not found'})).openForOrder('o1'),
        throwsA(isA<DioException>()),
      );
      await expectLater(
        ShopChatApi(answering(404, <String, dynamic>{'title': 'Not found'}))
            .openWithStore('s1', orderId: 'o1'),
        throwsA(isA<DioException>()),
      );
      await expectLater(
        ShopChatApi(answering(503, <String, dynamic>{'title': 'Temporarily unavailable'}))
            .openWithStore('s1', orderId: 'o1'),
        throwsA(isA<DioException>()),
      );
    });
  });
}
