import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// The multi-shop basket's contract with Order Manager: the quote a basket screen shows and the
/// checkout that places every shop's order at once.
///
/// Nothing here is drawn, and all of it decides what a customer is charged: a quote read as zeros
/// where the server said "unknown" would show a total without a shop in it, and a retried checkout
/// read as a failure would send the customer back to place it again.
void main() {
  Map<String, dynamic> orderJson(String id, {String? checkoutId, int? size, double total = 14.5}) =>
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
        if (checkoutId != null) 'checkoutId': checkoutId,
        if (size != null) 'checkoutSize': size,
      };

  final Map<String, dynamic> quoteJson = <String, dynamic>{
    'shops': <dynamic>[
      <String, dynamic>{
        'storeId': 's1',
        'storeName': 'Abou Joseph Shawarma',
        'refusal': null,
        'subtotal': 11.5,
        'minimumOrder': 0,
        'shortfall': 0,
        'deliveryFee': 2.25,
        'deliveryFeeCharged': 2.25,
        'deliveryFeeWaived': false,
        'expressSurcharge': 2,
        'discountAmount': 1.94,
        'totalAmount': 13.81,
      },
      <String, dynamic>{
        'storeId': 's2',
        'storeName': 'Byblos Pharmacy',
        'refusal': 'BELOW_MINIMUM',
        'refusalMessage': 'Byblos Pharmacy has a minimum order of 10.00; your items from it come to 5.00',
        'subtotal': 5,
        'minimumOrder': 10,
        'shortfall': 5,
        'deliveryFee': 3,
        'deliveryFeeCharged': 0,
        'deliveryFeeWaived': true,
        'offerTitle': 'Free delivery on medicine',
        'expressSurcharge': 2,
        'discountAmount': 0,
        'totalAmount': 7,
      },
    ],
    'placeable': false,
    'subtotal': 16.5,
    'deliveryFeeCharged': 2.25,
    'expressSurcharge': 4,
    'discountAmount': 1.94,
    'totalAmount': 20.81,
    'promo': <String, dynamic>{
      'valid': true,
      'reason': 'OK',
      'message': 'The code was applied',
      'code': 'SAVE6',
      'kind': 'AMOUNT_OFF',
      'discount': 1.94,
    },
    'maxShops': 3,
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

  void refuse(RequestOptions o, RequestInterceptorHandler h, int status,
          Map<String, dynamic> body) =>
      h.reject(DioException(
        requestOptions: o,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(requestOptions: o, statusCode: status, data: body),
      ));

  OrderSubmission threeShops() => OrderSubmission(
        idempotencyKey: '0f8e3c1a-5b7d-4e2a-9c61-7d2f0b9e4a11',
        items: <OrderLineSubmission>[
          (productId: 'shawarma', qty: 2, optionIds: const <String>[]),
          (productId: 'pepsi', qty: 2, optionIds: const <String>[]),
          (productId: 'panadol', qty: 1, optionIds: const <String>[]),
        ],
        deliveryAddress: '12 Rose Street',
        deliveryZoneId: 'zone-hamra',
      );

  group('a quote', () {
    test('asks with the lines, the area, the tier and the code — nothing a price does not read',
        () async {
      final ({OrderApi api, List<RequestOptions> sent}) s = server((RequestOptions o,
              RequestInterceptorHandler h) =>
          h.resolve(Response<dynamic>(requestOptions: o, statusCode: 200, data: quoteJson)));

      await s.api.quote(BasketQuestion(
        items: <OrderLineSubmission>[
          (productId: 'shawarma', qty: 2, optionIds: const <String>['tarator']),
        ],
        deliveryZoneId: 'zone-hamra',
        deliveryTier: DeliveryTier.express,
        promoCode: ' SAVE6 ',
      ));

      final RequestOptions sent = s.sent.single;
      expect(sent.method, 'POST');
      expect(sent.path, '/api/orders/quote');
      expect(sent.data, <String, dynamic>{
        'items': <dynamic>[
          <String, dynamic>{'productId': 'shawarma', 'qty': 2, 'optionIds': <String>['tarator']},
        ],
        'deliveryZoneId': 'zone-hamra',
        'deliveryTier': 'EXPRESS',
        'promoCode': 'SAVE6',
      });
    });

    test('reads every shop\'s figures, its refusal and the code, as the server said them', () {
      final BasketQuote quote = BasketQuote.fromJson(quoteJson);

      expect(quote.placeable, isFalse);
      expect(quote.totalAmount, 20.81);
      expect(quote.maxShops, 3);
      expect(quote.promo?.valid, isTrue);
      expect(quote.promo?.code, 'SAVE6');
      final ShopQuote pharmacy = quote.shop('s2')!;
      expect(pharmacy.refusal, ShopRefusal.belowMinimum);
      expect(pharmacy.shortfall, 5);
      expect(pharmacy.deliveryFeeWaived, isTrue);
      expect(pharmacy.offerTitle, 'Free delivery on medicine');
      expect(quote.shop('s1')!.refusal, isNull);
    });

    test('a shop that could not be priced is unknown, never zero — and so is the basket', () {
      final BasketQuote quote = BasketQuote.fromJson(<String, dynamic>{
        'shops': <dynamic>[
          <String, dynamic>{
            'storeId': 's3',
            'storeName': 'Dekkane Abou Selim',
            'refusal': 'CLOSED',
            'refusalMessage': 'Dekkane Abou Selim is closed and is not taking orders right now',
            'deliveryFeeWaived': false,
          },
          <String, dynamic>{'storeId': 's4', 'storeName': 'Somewhere new', 'refusal': 'RAINED_OFF'},
        ],
        'placeable': false,
        'maxShops': 3,
      });

      expect(quote.totalAmount, isNull);
      expect(quote.subtotal, isNull);
      expect(quote.shops.first.priced, isFalse);
      expect(quote.shops.first.totalAmount, isNull);
      expect(quote.shops.first.refusal, ShopRefusal.closed);
      // A reason this build does not know is still a refusal.
      expect(quote.shops.last.refusal, ShopRefusal.unknown);
    });

    test('the same basket listed in another order is the same question', () {
      BasketQuestion ask(List<OrderLineSubmission> items, {String? code}) =>
          BasketQuestion(items: items, deliveryZoneId: 'z', promoCode: code);
      const OrderLineSubmission a = (productId: 'a', qty: 1, optionIds: <String>['x', 'y']);
      const OrderLineSubmission b = (productId: 'b', qty: 2, optionIds: <String>[]);
      const OrderLineSubmission aSwapped = (productId: 'a', qty: 1, optionIds: <String>['y', 'x']);

      expect(ask(<OrderLineSubmission>[a, b]).signature,
          ask(<OrderLineSubmission>[b, aSwapped]).signature);
      expect(ask(<OrderLineSubmission>[a, b]).signature,
          isNot(ask(<OrderLineSubmission>[a, b], code: 'SAVE6').signature));
    });
  });

  group('a checkout from several shops', () {
    test('201 is every order, linked, and the request carries the attempt\'s key', () async {
      final ({OrderApi api, List<RequestOptions> sent}) s = server(
          (RequestOptions o, RequestInterceptorHandler h) => h.resolve(Response<dynamic>(
                requestOptions: o,
                statusCode: 201,
                data: <String, dynamic>{
                  'checkoutId': 'checkout-1',
                  'orders': <dynamic>[
                    orderJson('order-1', checkoutId: 'checkout-1', size: 2),
                    orderJson('order-2', checkoutId: 'checkout-1', size: 2, total: 8),
                  ],
                  'totalAmount': 22.5,
                },
              )));

      final PlaceCheckoutResult result = await s.api.placeCheckout(threeShops());

      expect(s.sent.single.path, '/api/orders/checkout');
      expect(s.sent.single.headers[OrderApi.idempotencyKeyHeader],
          '0f8e3c1a-5b7d-4e2a-9c61-7d2f0b9e4a11');
      // One flat list of every shop's lines: the server groups them from its own catalog.
      expect((s.sent.single.data as Map<String, dynamic>)['items'], hasLength(3));
      expect(result, isA<CheckoutPlaced>());
      final CheckoutPlaced placed = result as CheckoutPlaced;
      expect(placed.replayed, isFalse);
      expect(placed.checkoutId, 'checkout-1');
      expect(placed.totalAmount, 22.5);
      expect(placed.orders.map((DeliveryOrder o) => o.isPartOfCheckout), <bool>[true, true]);
    });

    test('200 is a retry answered with the orders the first try placed', () async {
      final ({OrderApi api, List<RequestOptions> sent}) s = server(
          (RequestOptions o, RequestInterceptorHandler h) => h.resolve(Response<dynamic>(
                requestOptions: o,
                statusCode: 200,
                data: <String, dynamic>{
                  'checkoutId': 'checkout-1',
                  'orders': <dynamic>[orderJson('order-1', checkoutId: 'checkout-1', size: 2)],
                  'totalAmount': 14.5,
                },
              )));

      final CheckoutPlaced placed = await s.api.placeCheckout(threeShops()) as CheckoutPlaced;

      expect(placed.replayed, isTrue);
    });

    test('a changed total and an already-used key are outcomes to show, not errors', () async {
      final CheckoutPriceChanged changed = await server(
          (RequestOptions o, RequestInterceptorHandler h) => refuse(o, h, 409, <String, dynamic>{
                'code': 'PRICE_CHANGED',
                'total': 23.5,
                'expectedTotal': 22.5,
              })).api.placeCheckout(threeShops(), expectedTotal: 22.5) as CheckoutPriceChanged;
      expect(changed.total, 23.5);
      expect(changed.expectedTotal, 22.5);

      final CheckoutAlreadyPlaced already = await server(
          (RequestOptions o, RequestInterceptorHandler h) => refuse(o, h, 409, <String, dynamic>{
                'code': 'IDEMPOTENCY_KEY_REUSED',
                'orderId': 'order-9',
              })).api.placeCheckout(threeShops()) as CheckoutAlreadyPlaced;
      expect(already.orderId, 'order-9');
    });

    test('a shop that refuses is thrown as the refusal it is, naming the shop', () async {
      final ({OrderApi api, List<RequestOptions> sent}) s = server(
          (RequestOptions o, RequestInterceptorHandler h) => refuse(o, h, 422, <String, dynamic>{
                'code': 'SHOP_REFUSED',
                'refusal': 'CLOSED',
                'storeId': 's3',
                'detail': 'Dekkane Abou Selim is closed and is not taking orders right now',
              }));

      await expectLater(
        s.api.placeCheckout(threeShops()),
        throwsA(isA<DioException>().having(
            (DioException e) => (e.response?.data as Map<String, dynamic>)['detail'],
            'detail',
            contains('Dekkane Abou Selim'))),
      );
    });
  });

  test('an order says whether it was one of several shops\' orders placed together', () {
    expect(DeliveryOrder.fromJson(orderJson('a', checkoutId: 'c', size: 3)).isPartOfCheckout,
        isTrue);
    expect(DeliveryOrder.fromJson(orderJson('b', checkoutId: 'c', size: 3)).checkoutSize, 3);
    expect(DeliveryOrder.fromJson(orderJson('c')).isPartOfCheckout, isFalse);
    expect(DeliveryOrder.fromJson(orderJson('c')).checkoutId, isNull);
  });
}
