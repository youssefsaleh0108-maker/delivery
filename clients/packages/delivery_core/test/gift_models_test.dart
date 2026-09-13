import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// A gift's wire contract on the phone side.
///
/// None of it is visible on a screen, and all of it decides what reaches a door: a gift that
/// travelled as notes would lose its recipient, a wrap that carried an amount would let the phone
/// name its own price, a terms list read loosely would offer cash — which bills the person
/// receiving the gift — and a withheld phone rendered as an empty string would look like a number.
void main() {
  Map<String, dynamic> orderJson() => <String, dynamic>{
        'id': 'order-1',
        'customerId': 'customer-1',
        'merchantId': 'm1',
        'riderId': null,
        'status': 'PLACED',
        'totalAmount': 50.5,
        'deliveryAddress': 'Mar Mikhael, Beirut',
        'paymentMethod': 'CARD',
        'paymentStatus': 'AUTHORIZED',
        'items': <dynamic>[],
        'availableActions': <dynamic>[],
      };

  OrderSubmission aGift({GiftDetails? gift, String key = 'key-gift-0001'}) => OrderSubmission(
        idempotencyKey: key,
        items: <OrderLineSubmission>[(productId: 'bundle-1', qty: 1, optionIds: const <String>[])],
        deliveryAddress: 'Mar Mikhael, Beirut',
        deliveryZoneId: 'zone-mar-mikhael',
        paymentMethod: PaymentMethod.card,
        paymentInstrumentToken: 'dev-test-instrument',
        gift: gift,
      );

  const GiftDetails toMom = GiftDetails(
    recipientName: 'Mona (Mom)',
    recipientPhone: '+96171234567',
    message: 'Habibti Mom',
    wrap: true,
  );

  group('a gift in the placement body', () {
    test('rides as its own object, with no amount anywhere in it', () {
      final Map<String, dynamic> body = aGift(gift: toMom).toBody();

      expect(body['gift'], <String, dynamic>{
        'recipientName': 'Mona (Mom)',
        'recipientPhone': '+96171234567',
        'message': 'Habibti Mom',
        'wrap': true,
      });
      expect(body.containsKey('notes'), isFalse);
      expect('$body'.toLowerCase(), isNot(contains('fee')));
    });

    test('an ordinary checkout sends no gift at all, and a blank card is no card', () {
      expect(aGift().toBody().containsKey('gift'), isFalse);

      final Map<String, dynamic> blank = aGift(
        gift: const GiftDetails(recipientName: 'Rami', recipientPhone: '+9613123456', message: ''),
      ).toBody()['gift'] as Map<String, dynamic>;
      expect(blank.containsKey('message'), isFalse);
      expect(blank['wrap'], isFalse);
    });

    test('survives a round trip through storage with the same key', () {
      final OrderSubmission restored = OrderSubmission.fromJson(aGift(gift: toMom).toJson());

      expect(restored.idempotencyKey, 'key-gift-0001');
      expect(restored.gift?.recipientPhone, '+96171234567');
      expect(restored.gift?.wrap, isTrue);
      expect(restored.toBody()['gift'], aGift(gift: toMom).toBody()['gift']);
    });
  });

  group('gift terms', () {
    test('never offer cash, and drop a method this build does not know', () {
      final GiftTerms terms = GiftTerms.fromJson(<String, dynamic>{
        'wrapFee': 3.0,
        'paymentMethods': <String>['CASH', 'CARD', 'APPLE_PAY', 'WALLET'],
      });

      expect(terms.paymentMethods, <PaymentMethod>[PaymentMethod.card, PaymentMethod.wallet]);
      expect(terms.wrapFee, 3.0);
      expect(terms.canPay, isTrue);
    });

    test('no method means no gift can be paid for', () {
      final GiftTerms terms =
          GiftTerms.fromJson(<String, dynamic>{'wrapFee': 3, 'paymentMethods': <String>[]});

      expect(terms.canPay, isFalse);
    });
  });

  group('a placed gift', () {
    test('reads the gift, and a phone the server withheld as nothing', () {
      final DeliveryOrder order = DeliveryOrder.fromJson(<String, dynamic>{
        ...orderJson(),
        'gift': <String, dynamic>{
          'recipientName': 'Mona (Mom)',
          'recipientPhone': null,
          'message': 'Habibti Mom',
          'wrap': true,
          'wrapFee': 3.0,
        },
      });

      expect(order.gift?.recipientName, 'Mona (Mom)');
      expect(order.gift?.recipientPhone, isNull);
      expect(order.gift?.wrapFee, 3.0);
    });

    test('reads a name and card the server withheld as nothing, and keeps the wrap', () {
      // What a rider browsing the job board, or a delivery company's staff, are sent.
      final DeliveryOrder order = DeliveryOrder.fromJson(<String, dynamic>{
        ...orderJson(),
        'gift': <String, dynamic>{
          'recipientName': null,
          'recipientPhone': null,
          'message': null,
          'wrap': true,
          'wrapFee': 3.0,
        },
      });

      expect(order.gift, isNotNull);
      expect(order.gift?.recipientName, isNull);
      expect(order.gift?.message, isNull);
      expect(order.gift?.wrap, isTrue);
    });

    test('an ordinary order has none', () {
      expect(DeliveryOrder.fromJson(orderJson()).gift, isNull);
    });
  });

  test('a featured bundle is an ordinary live product of its shop', () {
    final GiftBundle bundle = GiftBundle.fromJson(<String, dynamic>{
      'productId': 'bundle-1',
      'merchantId': 'merchant-1',
      'storeId': 'store-1',
      'storeSlug': 'dekkane',
      'storeName': 'Dekkane Abou Selim',
      'name': 'Family Essentials',
      'description': 'Oil, rice, lentils',
      'price': 45,
      'imageUrls': <String>['full.jpg'],
      'imageThumbUrls': <String>['thumb.jpg'],
      'availability': 'OPEN',
      'sameDayDeliverable': true,
    });

    expect(bundle.product.id, 'bundle-1');
    expect(bundle.product.storeId, 'store-1');
    expect(bundle.product.status, ProductStatus.active);
    expect(bundle.product.price, 45.0);
    expect(bundle.thumbUrl, 'thumb.jpg');
    expect(bundle.availability, StoreAvailability.open);
    expect(bundle.sameDayDeliverable, isTrue);
  });

  test('the gift endpoints are asked where the services serve them', () async {
    final List<String> asked = <String>[];
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway.test'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) {
        asked.add('${o.method} ${o.path}');
        h.resolve(Response<dynamic>(
          requestOptions: o,
          statusCode: 200,
          data: o.path == '/api/orders/gift-terms'
              ? <String, dynamic>{'wrapFee': 3.0, 'paymentMethods': <String>['CARD']}
              : o.path == '/api/gift-bundles'
                  ? <dynamic>[]
                  : <String, dynamic>{'productId': 'p1', 'giftFeatured': true},
        ));
      },
    ));

    expect((await OrderApi(dio).giftTerms()).paymentMethods, <PaymentMethod>[PaymentMethod.card]);
    expect(await StoreApi(dio).giftBundles(), isEmpty);
    expect(await CatalogApi(dio).setGiftFeatured('p1', featured: true), isTrue);
    expect(asked, <String>[
      'GET /api/orders/gift-terms',
      'GET /api/gift-bundles',
      'PUT /api/products/p1/gift-featured',
    ]);
  });
}
