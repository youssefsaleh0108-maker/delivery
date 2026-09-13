import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// The placement contract the offline outbox and every future checkout lean on.
///
/// Nothing here is visible on a screen, and all of it is visible in a customer's bank balance or
/// their kitchen: a retry that minted a new key would place a second order; a price change read as
/// a failure would drop the order silently, or read as success would charge a total nobody saw.
void main() {
  Map<String, dynamic> orderJson({String id = 'order-1', double total = 12.40}) =>
      <String, dynamic>{
        'id': id,
        'customerId': 'customer-1',
        'merchantId': 'm1',
        'riderId': null,
        'status': 'PLACED',
        'totalAmount': total,
        'deliveryAddress': '12 Rose Street',
        'paymentMethod': 'CASH',
        'paymentStatus': 'DUE',
        'items': <dynamic>[],
        'availableActions': <dynamic>[],
      };

  /// Records each request and answers it with [answer], without opening a socket.
  ({OrderApi api, List<RequestOptions> sent}) server(
      void Function(RequestOptions o, RequestInterceptorHandler h) answer) {
    final List<RequestOptions> sent = <RequestOptions>[];
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway.test'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) {
        sent.add(o);
        answer(o, h);
      },
    ));
    return (api: OrderApi(dio), sent: sent);
  }

  void conflict(RequestOptions o, RequestInterceptorHandler h, Map<String, dynamic> body) =>
      h.reject(DioException(
        requestOptions: o,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(requestOptions: o, statusCode: 409, data: body),
      ));

  OrderSubmission aCheckout({String? key}) => OrderSubmission(
        idempotencyKey: key,
        items: <OrderLineSubmission>[
          (productId: 'p1', qty: 2, optionIds: const <String>[]),
          (productId: 'p2', qty: 1, optionIds: const <String>['large']),
        ],
        deliveryAddress: '12 Rose Street',
        deliveryZoneId: 'zone-hamra',
        contactPhone: '+961 3 000000',
        notes: 'Ring twice',
        deliveryLatitude: 33.8938,
        deliveryLongitude: 35.5018,
      );

  group('the idempotency key', () {
    test('is sent on every placement, and a retry of the same attempt sends the same one',
        () async {
      final s = server((RequestOptions o, RequestInterceptorHandler h) => h.resolve(
          Response<dynamic>(requestOptions: o, statusCode: 201, data: orderJson())));
      final OrderSubmission attempt = aCheckout();

      await s.api.place(attempt);
      await s.api.place(attempt);

      expect(s.sent, hasLength(2));
      expect(s.sent[0].headers[OrderApi.idempotencyKeyHeader], attempt.idempotencyKey);
      expect(s.sent[1].headers[OrderApi.idempotencyKeyHeader], attempt.idempotencyKey);
      // And the body is the same request both times, which is what the server checks a repeat by.
      expect(s.sent[1].data, s.sent[0].data);
    });

    test('is a fresh random UUID v4 for each new attempt', () {
      final RegExp v4 =
          RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      final Set<String> keys = <String>{for (int i = 0; i < 200; i++) aCheckout().idempotencyKey};

      expect(keys, hasLength(200));
      expect(keys.every(v4.hasMatch), isTrue);
    });

    test('survives being written to disk and read back, and the token does not', () {
      final OrderSubmission original = OrderSubmission(
        items: <OrderLineSubmission>[(productId: 'p1', qty: 1, optionIds: const <String>['a'])],
        deliveryAddress: '4 Mill Lane',
        paymentMethod: PaymentMethod.card,
        paymentInstrumentToken: 'tok_secret',
        deliveryTier: DeliveryTier.express,
        promoCode: 'SAVE2',
      );

      final Map<String, dynamic> stored = original.toJson();
      final OrderSubmission restored = OrderSubmission.fromJson(stored);

      expect(stored.values, isNot(contains('tok_secret')));
      expect(restored.idempotencyKey, original.idempotencyKey);
      expect(restored.paymentInstrumentToken, isNull);
      expect(restored.deliveryTier, DeliveryTier.express);
      // Everything but the token is the same request.
      final Map<String, dynamic> expectedBody = original.toBody()
        ..remove('paymentInstrumentToken');
      expect(restored.toBody(), expectedBody);
    });
  });

  group('the expected total', () {
    test('is absent unless asked for, so the live checkout places exactly as before', () async {
      final s = server((RequestOptions o, RequestInterceptorHandler h) => h.resolve(
          Response<dynamic>(requestOptions: o, statusCode: 201, data: orderJson())));

      await s.api.place(aCheckout());

      expect((s.sent.single.data as Map<String, dynamic>).containsKey('expectedTotal'), isFalse);
    });

    test('is rounded to cents, so a total added up in doubles still matches', () async {
      final s = server((RequestOptions o, RequestInterceptorHandler h) => h.resolve(
          Response<dynamic>(requestOptions: o, statusCode: 201, data: orderJson())));

      // 10.40 + 2.00 is 12.399999999999999 in a double; the server takes two decimals at most.
      await s.api.place(aCheckout(), expectedTotal: 10.40 + 2.00);

      expect((s.sent.single.data as Map<String, dynamic>)['expectedTotal'], 12.4);
    });
  });

  group('what comes back', () {
    test('201 is a new order', () async {
      final s = server((RequestOptions o, RequestInterceptorHandler h) => h.resolve(
          Response<dynamic>(requestOptions: o, statusCode: 201, data: orderJson())));

      final PlaceOrderResult result = await s.api.place(aCheckout());

      expect(result, isA<OrderPlaced>().having((OrderPlaced r) => r.replayed, 'replayed', false));
      expect((result as OrderPlaced).order.id, 'order-1');
    });

    test('200 is the order this attempt already placed', () async {
      final s = server((RequestOptions o, RequestInterceptorHandler h) => h.resolve(
          Response<dynamic>(requestOptions: o, statusCode: 200, data: orderJson())));

      final PlaceOrderResult result = await s.api.place(aCheckout());

      expect(result, isA<OrderPlaced>().having((OrderPlaced r) => r.replayed, 'replayed', true));
    });

    test('409 PRICE_CHANGED is a typed answer carrying both totals, not an error', () async {
      final s = server((RequestOptions o, RequestInterceptorHandler h) => conflict(o, h,
          <String, dynamic>{'code': 'PRICE_CHANGED', 'total': 13.9, 'expectedTotal': 12.4}));

      final PlaceOrderResult result = await s.api.place(aCheckout(), expectedTotal: 12.40);

      expect(
          result,
          isA<OrderPriceChanged>()
              .having((OrderPriceChanged r) => r.total, 'total', 13.9)
              .having((OrderPriceChanged r) => r.expectedTotal, 'expectedTotal', 12.4));
    });

    test('409 IDEMPOTENCY_KEY_REUSED names the order the attempt already placed', () async {
      final s = server((RequestOptions o, RequestInterceptorHandler h) => conflict(o, h,
          <String, dynamic>{'code': 'IDEMPOTENCY_KEY_REUSED', 'orderId': 'order-earlier'}));

      final PlaceOrderResult result = await s.api.place(aCheckout());

      expect(result,
          isA<OrderAlreadyPlaced>().having((OrderAlreadyPlaced r) => r.orderId, 'id', 'order-earlier'));
    });

    test('anything else is thrown exactly as before — a refused basket is not a result',
        () async {
      final s = server((RequestOptions o, RequestInterceptorHandler h) => h.reject(DioException(
            requestOptions: o,
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
                requestOptions: o, statusCode: 422, data: <String, dynamic>{'detail': 'closed'}),
          )));

      await expectLater(s.api.place(aCheckout()), throwsA(isA<DioException>()));
    });

    test('an unlabelled 409 is not guessed at', () async {
      final s = server((RequestOptions o, RequestInterceptorHandler h) =>
          conflict(o, h, <String, dynamic>{'detail': 'something else'}));

      await expectLater(s.api.place(aCheckout()), throwsA(isA<DioException>()));
    });
  });

  group('whether a placement that threw may have placed the order anyway', () {
    DioException failure(DioExceptionType type, {int? status}) {
      final RequestOptions request = RequestOptions(path: '/api/orders');
      return DioException(
        requestOptions: request,
        type: type,
        response:
            status == null ? null : Response<dynamic>(requestOptions: request, statusCode: status),
      );
    }

    test('it may, whenever the request can have arrived and the answer did not come back', () {
      // A receive timeout follows a request that left; Dio's "connection error" covers a
      // connection closed while the answer was awaited; the rest cannot rule arrival out.
      for (final DioExceptionType type in <DioExceptionType>[
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
        DioExceptionType.sendTimeout,
        DioExceptionType.unknown,
        DioExceptionType.cancel,
      ]) {
        expect(OrderApi.mayHavePlaced(failure(type)), isTrue, reason: type.name);
      }
      // A gateway that gave up, or a server that failed, may have done so after the commit.
      for (final int status in <int>[500, 502, 503, 504]) {
        expect(OrderApi.mayHavePlaced(failure(DioExceptionType.badResponse, status: status)),
            isTrue,
            reason: '$status');
      }
    });

    test('it may not, when no connection was ever made or the platform refused the request', () {
      expect(OrderApi.mayHavePlaced(failure(DioExceptionType.connectionTimeout)), isFalse);
      for (final int status in <int>[400, 401, 402, 403, 409, 422, 429]) {
        expect(OrderApi.mayHavePlaced(failure(DioExceptionType.badResponse, status: status)),
            isFalse,
            reason: '$status');
      }
    });
  });
}
