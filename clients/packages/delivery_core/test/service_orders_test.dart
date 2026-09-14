import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Service orders on the client: what an order carries once it is a service order, what a service
/// placement and quote send, the provider's three steps, the order lists' filters, an order's history
/// and a shop's reviews.
///
/// Pinned against order-manager's feat/service-orders contract: every field parses as OrderResponse
/// writes it, and an order from a server that never heard of services parses as it always did; a
/// kind, fulfilment, decline or refusal this build does not know reads as unknown rather than as a
/// guess; each call uses the verb, path and body OrderController serves; a basket's requests are
/// unchanged; and the service refusals come back as outcomes while everything else is still thrown.
class _Server implements HttpClientAdapter {
  _Server(this.answer);

  /// The status and JSON body each request is answered with.
  final (int, Object?) Function(RequestOptions options) answer;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    final (int status, Object? body) = answer(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

({OrderApi api, _Server server}) _orders((int, Object?) Function(RequestOptions options) answer) {
  final _Server server = _Server(answer);
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway.test'))..httpClientAdapter = server;
  return (api: OrderApi(dio), server: server);
}

/// A 422 as ApiExceptionHandler writes one for a refused service order.
Map<String, dynamic> _refusal(String code) => <String, dynamic>{
      'type': 'about:blank',
      'title': 'Order rule violated',
      'status': 422,
      'detail': 'The server says why, in English',
      'code': code,
    };

/// A pickup print run waiting at the counter, as OrderResponse writes it for its shop.
Map<String, dynamic> _serviceOrder({
  String status = 'READY',
  Object? fulfilment = 'PICKUP',
  List<Object?> actions = const <Object?>['COLLECTED'],
  String? cancelReason,
  String? uncollectedCancellableAt = '2026-09-17T09:00:00Z',
}) =>
    <String, dynamic>{
      'id': '7f3a2c1d-5b6e-4f00-9a1b-2c3d4e5f6a7b',
      'kind': 'SERVICE',
      'customerId': 'customer-1',
      'merchantId': 'provider-1',
      'riderId': null,
      'deliveryProviderId': null,
      'status': status,
      'totalAmount': 31.5,
      'subtotal': 31.5,
      'deliveryFee': 0,
      'deliveryFeeCharged': 0,
      'deliveryTier': 'STANDARD',
      'expressSurcharge': 0,
      'deliveryFeeWaived': false,
      'merchantFeeWaived': false,
      'carrierFeeWaived': false,
      'discountAmount': null,
      'promoCode': null,
      'storeId': 'press-1',
      'storeName': 'Hamra Press',
      'deliveryAddress': null,
      'paymentMethod': 'CASH',
      'paymentStatus': 'DUE',
      'paidAt': null,
      'contactPhone': '+96171234567',
      'notes': null,
      'gift': null,
      'checkoutId': null,
      'checkoutSize': null,
      'items': <dynamic>[
        <String, dynamic>{
          'productId': 'offer-1',
          'productName': 'Business cards',
          'unitPrice': 15.75,
          'baseUnitPrice': 15.0,
          'qty': 2,
          'lineTotal': 31.5,
          'options': <dynamic>[
            <String, dynamic>{'groupName': 'Finish', 'optionName': 'Matte', 'priceDelta': 0.75},
          ],
          'optionsSummary': 'Finish: Matte',
          'service': <String, dynamic>{
            'pricingType': 'FIXED',
            'unitLabel': 'cards',
            'unitSize': 500,
            'turnaroundMinHours': 24,
            'turnaroundMaxHours': 48,
            'attachmentPolicy': 'REQUIRED',
            'instructionsPrompt': 'Which paper colour?',
            'instructions': 'Leave a white border',
          },
        },
      ],
      'availableActions': actions,
      'placedAt': '2026-09-13T08:00:00Z',
      'acceptedAt': '2026-09-13T08:05:00Z',
      'pickedUpAt': null,
      'deliveredAt': null,
      'cancelledAt': null,
      'cancelReason': cancelReason,
      'fulfilment': fulfilment,
      'serviceCategory': 'PRINTING',
      'customerDisplayName': 'Jean-Pierre D.',
      'readyAt': '2026-09-14T09:00:00Z',
      'estimatedReadyAt': '2026-09-15T08:05:00Z',
      'uncollectedCancellableAt': uncollectedCancellableAt,
    };

/// An order as a server from before service orders writes one: none of their fields at all.
Map<String, dynamic> _basketBeforeServices() => <String, dynamic>{
      'id': 'order-1',
      'customerId': 'customer-1',
      'merchantId': 'm1',
      'riderId': null,
      'status': 'PREPARING',
      'totalAmount': 12.4,
      'deliveryAddress': '12 Rose Street',
      'paymentMethod': 'CASH',
      'paymentStatus': 'DUE',
      'items': <dynamic>[
        <String, dynamic>{
          'productId': 'p1',
          'productName': 'Shawarma',
          'unitPrice': 6.2,
          'qty': 2,
          'lineTotal': 12.4,
        },
      ],
      'availableActions': <dynamic>['READY', 'CANCEL'],
    };

Map<String, dynamic> _page(List<Map<String, dynamic>> content) => <String, dynamic>{
      'content': content,
      'page': 0,
      'size': 20,
      'totalElements': content.length,
      'totalPages': 1,
    };

OrderSubmission _pickup({String? key}) => OrderSubmission(
      idempotencyKey: key,
      items: <OrderLineSubmission>[
        (productId: 'offer-1', qty: 2, optionIds: const <String>['matte']),
      ],
      deliveryAddress: '',
      contactPhone: '+96171234567',
      fulfilment: Fulfilment.pickup,
      attachmentFileIds: const <String>['file-1', 'file-2'],
      serviceInstructions: 'Leave a white border',
    );

void main() {
  group('an order from a server that predates service orders', () {
    test('parses exactly as before: a delivered basket with nothing to wait for', () {
      final DeliveryOrder order = DeliveryOrder.fromJson(_basketBeforeServices());

      expect(order.kind, OrderKind.catalog);
      expect(order.fulfilment, Fulfilment.delivery);
      expect(order.isService, isFalse);
      expect(order.isPickup, isFalse);
      expect(order.serviceCategory, isNull);
      expect(order.customerDisplayName, isNull);
      expect(order.readyAt, isNull);
      expect(order.estimatedReadyAt, isNull);
      expect(order.uncollectedCancellableAt, isNull);
      expect(order.serviceLine, isNull);
      expect(order.items.single.service, isNull);
      expect(order.items.single.optionsSummary, isNull);
      expect(order.availableActions, <OrderAction>[OrderAction.ready, OrderAction.cancel]);
      expect(order.declineReason, isNull);
      expect(order.wasCancelledAsNotCollected, isFalse);
      expect(order.canCancelAsNotCollected(DateTime.utc(2030)), isFalse);
    });
  });

  group('a service order', () {
    test('reads every field as order-manager writes it', () {
      final DeliveryOrder order = DeliveryOrder.fromJson(_serviceOrder());

      expect(order.kind, OrderKind.service);
      expect(order.fulfilment, Fulfilment.pickup);
      expect(order.isService, isTrue);
      expect(order.isPickup, isTrue);
      expect(order.serviceCategory, ServiceCategory.printing);
      expect(order.customerDisplayName, 'Jean-Pierre D.');
      expect(order.readyAt!.toUtc(), DateTime.utc(2026, 9, 14, 9));
      expect(order.estimatedReadyAt!.toUtc(), DateTime.utc(2026, 9, 15, 8, 5));
      expect(order.uncollectedCancellableAt!.toUtc(), DateTime.utc(2026, 9, 17, 9));
      expect(order.availableActions, <OrderAction>[OrderAction.collected]);
      // A pickup goes nowhere, and the server says so with no address at all.
      expect(order.deliveryAddress, '');

      final OrderLine line = order.items.single;
      expect(line.optionsSummary, 'Finish: Matte');
      final ServiceOrderLine service = line.service!;
      expect(service.packs, 2);
      expect(service.unitSize, 500);
      expect(service.units, 1000);
      expect(service.unitLabel, 'cards');
      expect(service.pricingType, ServicePricingType.fixed);
      expect(service.turnaroundMinHours, 24);
      expect(service.turnaroundMaxHours, 48);
      expect(service.attachmentPolicy, ServiceAttachmentPolicy.required);
      expect(service.instructionsPrompt, 'Which paper colour?');
      expect(service.instructions, 'Leave a white border');
      expect(order.serviceLine, same(service));
    });

    test('the kinds, fulfilments, decline reasons and refusal codes are exactly the server\'s', () {
      expect(OrderKind.values.map((OrderKind k) => k.wire).whereType<String>(),
          <String>['CATALOG', 'BUTLER_BUY', 'BUTLER_SEND', 'SERVICE']);
      expect(Fulfilment.values.map((Fulfilment f) => f.wire).whereType<String>(),
          <String>['DELIVERY', 'PICKUP']);
      expect(DeclineReason.picklist.map((DeclineReason r) => r.wire),
          <String>['TOO_BUSY', 'CANNOT_DO', 'FILE_PROBLEM', 'OTHER']);
      expect(
          ServiceOrderRefusal.values.map((ServiceOrderRefusal r) => r.wire).whereType<String>(),
          <String>[
            // ServiceOrderRefusedException.Refusal, in its order.
            'ONE_SERVICE_AT_A_TIME', 'PACKS_OUT_OF_RANGE', 'FULFILMENT_NOT_OFFERED',
            'NOT_A_SERVICE_ORDER', 'STANDARD_ONLY', 'NOT_GIFTABLE', 'CASH_ONLY', 'NOT_IN_BASKET',
            'NOT_ON_BEHALF', 'CATEGORY_CLOSED', 'OFFER_NOT_ORDERABLE', 'DECLINE_REASON_REQUIRED',
            'NOT_COLLECTABLE', 'UNCOLLECTED_TOO_SOON', 'RESERVED_CANCEL_REASON',
            // OrderAttachmentGate.Refusal, as placement sends it.
            'ATTACHMENTS_UNAVAILABLE', 'ATTACHMENT_REQUIRED', 'ATTACHMENTS_NOT_ACCEPTED',
            'ATTACHMENT_NOT_USABLE',
          ]);
      expect(OrderAction.fromWire('COLLECTED'), OrderAction.collected);
      expect(OrderAction.collected.path, 'collected');
    });

    test('a kind, fulfilment or category this build does not know is unknown, never a guess', () {
      final DeliveryOrder order = DeliveryOrder.fromJson(_serviceOrder(fulfilment: 'LOCKER')
        ..['kind'] = 'RENTAL'
        ..['serviceCategory'] = 'ASTROLOGY');

      expect(order.kind, OrderKind.unknown);
      expect(order.fulfilment, Fulfilment.unknown);
      expect(order.serviceCategory, isNull);
      expect(order.isService, isFalse);
      // Not a pickup, so nothing a counter does is offered for it.
      expect(order.isPickup, isFalse);
      expect(order.canCancelAsNotCollected(DateTime.utc(2030)), isFalse);
    });

    test('null service fields read as what an order without them was', () {
      final DeliveryOrder order = DeliveryOrder.fromJson(_serviceOrder(
        fulfilment: null,
        uncollectedCancellableAt: null,
      )
        ..['kind'] = null
        ..['serviceCategory'] = null
        ..['customerDisplayName'] = '   '
        ..['readyAt'] = null
        ..['estimatedReadyAt'] = 42);

      expect(order.kind, OrderKind.catalog);
      expect(order.fulfilment, Fulfilment.delivery);
      expect(order.serviceCategory, isNull);
      expect(order.customerDisplayName, isNull);
      expect(order.readyAt, isNull);
      expect(order.estimatedReadyAt, isNull);
      expect(order.uncollectedCancellableAt, isNull);
    });

    test('a service block that is not one is none, and what it does not say stays unsaid', () {
      Map<String, dynamic> withService(Object? service) {
        final Map<String, dynamic> json = _serviceOrder();
        (json['items'] as List<dynamic>).single['service'] = service;
        return json;
      }

      expect(DeliveryOrder.fromJson(withService('oops')).serviceLine, isNull);
      expect(DeliveryOrder.fromJson(withService(null)).serviceLine, isNull);

      final ServiceOrderLine bare = DeliveryOrder.fromJson(withService(<String, dynamic>{}))
          .serviceLine!;
      expect(bare.pricingType, ServicePricingType.unknown);
      expect(bare.attachmentPolicy, ServiceAttachmentPolicy.unknown);
      expect(bare.unitSize, 1);
      expect(bare.units, 2);
      expect(bare.unitLabel, isNull);
      expect(bare.turnaroundMinHours, isNull);
      expect(bare.turnaroundMaxHours, isNull);
      expect(bare.instructions, isNull);

      final ServiceOrderLine odd = DeliveryOrder.fromJson(withService(<String, dynamic>{
        'pricingType': 'BARTER',
        'attachmentPolicy': 'MAYBE',
        'unitSize': 0,
        'turnaroundMaxHours': '48',
        // What a rider reads: the server sends no instructions to them.
        'instructions': null,
      })).serviceLine!;
      expect(odd.pricingType, ServicePricingType.unknown);
      expect(odd.attachmentPolicy, ServiceAttachmentPolicy.unknown);
      expect(odd.unitSize, 1);
      expect(odd.turnaroundMaxHours, isNull);
      expect(odd.instructions, isNull);
    });

    test('an action this build does not know, or an entry that is not one, is left out', () {
      expect(
          DeliveryOrder.fromJson(_serviceOrder(
                  actions: const <Object?>['COLLECTED', 'TELEPORT', null, 7, 'CANCEL']))
              .availableActions,
          <OrderAction>[OrderAction.collected, OrderAction.cancel]);
      expect(
          DeliveryOrder.fromJson(_serviceOrder()..['availableActions'] = 'COLLECTED')
              .availableActions,
          isEmpty);
    });
  });

  group('cancelling a pickup as not collected', () {
    DeliveryOrder waiting({String status = 'READY', Object? fulfilment = 'PICKUP', String? from}) =>
        DeliveryOrder.fromJson(_serviceOrder(
            status: status, fulfilment: fulfilment, uncollectedCancellableAt: from));

    test('unlocks when the customer\'s time is up, not a second sooner', () {
      final DeliveryOrder order = waiting(from: '2026-09-17T09:00:00Z');

      expect(order.canCancelAsNotCollected(DateTime.utc(2026, 9, 17, 8, 59, 59)), isFalse);
      expect(order.canCancelAsNotCollected(DateTime.utc(2026, 9, 17, 9)), isTrue);
      expect(order.canCancelAsNotCollected(DateTime.utc(2026, 9, 20)), isTrue);
    });

    test('never for an order that is not a pickup still waiting at the counter', () {
      final DateTime later = DateTime.utc(2030);

      expect(waiting(status: 'DELIVERED', from: '2026-09-17T09:00:00Z').canCancelAsNotCollected(later),
          isFalse);
      expect(waiting(fulfilment: 'DELIVERY', from: '2026-09-17T09:00:00Z')
          .canCancelAsNotCollected(later), isFalse);
      expect(waiting().canCancelAsNotCollected(later), isFalse);
    });
  });

  group('how an order says its shop gave up on it', () {
    DeliveryOrder cancelled(String? reason) =>
        DeliveryOrder.fromJson(_serviceOrder(status: 'CANCELLED', cancelReason: reason));

    test('a decline reads back as its reason, and one this build does not know is still a decline',
        () {
      expect(cancelled('PROVIDER_DECLINED: TOO_BUSY').declineReason, DeclineReason.tooBusy);
      expect(cancelled('PROVIDER_DECLINED: FILE_PROBLEM').declineReason, DeclineReason.fileProblem);
      expect(cancelled(' provider_declined:cannot_do ').declineReason, DeclineReason.cannotDo);
      expect(cancelled('PROVIDER_DECLINED: HOLIDAY').declineReason, DeclineReason.unknown);
      expect(cancelled('Changed my mind').declineReason, isNull);
      expect(cancelled(null).declineReason, isNull);
      expect(cancelled('PROVIDER_DECLINED: TOO_BUSY').wasCancelledAsNotCollected, isFalse);
    });

    test('a pickup nobody collected says so, with or without the shop\'s own words', () {
      expect(cancelled('NOT_COLLECTED').wasCancelledAsNotCollected, isTrue);
      expect(cancelled('NOT_COLLECTED: waited a week').wasCancelledAsNotCollected, isTrue);
      expect(cancelled('NOT_COLLECTEDNESS').wasCancelledAsNotCollected, isFalse);
      expect(cancelled('Customer not collected').wasCancelledAsNotCollected, isFalse);
      expect(cancelled('NOT_COLLECTED').declineReason, isNull);
    });

    test('a decline is sent in the spelling the server stores, and an unknown one is never sent', () {
      expect(DeclineReason.tooBusy.cancelReason, 'PROVIDER_DECLINED: TOO_BUSY');
      expect(DeclineReason.fromCancelReason(DeclineReason.other.cancelReason), DeclineReason.other);
      expect(() => DeclineReason.unknown.cancelReason, throwsStateError);
    });
  });

  group('a service order placed', () {
    test('sends the fulfilment, the files and the instructions, and no address for a pickup',
        () async {
      final s = _orders((RequestOptions o) => (201, _serviceOrder(status: 'PLACED')));
      final OrderSubmission attempt = _pickup();

      final PlaceOrderResult result = await s.api.place(attempt);

      final RequestOptions sent = s.server.requests.single;
      expect(sent.method, 'POST');
      expect(sent.path, '/api/orders');
      expect(sent.headers[OrderApi.idempotencyKeyHeader], attempt.idempotencyKey);
      expect(sent.data, <String, dynamic>{
        'items': <dynamic>[
          <String, dynamic>{'productId': 'offer-1', 'qty': 2, 'optionIds': <String>['matte']},
        ],
        'contactPhone': '+96171234567',
        'paymentMethod': 'CASH',
        'deliveryTier': 'STANDARD',
        'fulfilment': 'PICKUP',
        'attachmentFileIds': <String>['file-1', 'file-2'],
        'serviceInstructions': 'Leave a white border',
      });
      expect(result, isA<OrderPlaced>());
      expect((result as OrderPlaced).order.isService, isTrue);
    });

    test('a delivery names its door and says it is a delivery', () async {
      final s = _orders((RequestOptions o) => (201, _serviceOrder(status: 'PLACED')));

      await s.api.place(OrderSubmission(
        items: <OrderLineSubmission>[(productId: 'offer-1', qty: 1, optionIds: const <String>[])],
        deliveryAddress: '12 Rose Street',
        deliveryZoneId: 'zone-hamra',
        fulfilment: Fulfilment.delivery,
        serviceInstructions: '   ',
      ));

      expect(s.server.requests.single.data, <String, dynamic>{
        'items': <dynamic>[
          <String, dynamic>{'productId': 'offer-1', 'qty': 1},
        ],
        'deliveryAddress': '12 Rose Street',
        'deliveryZoneId': 'zone-hamra',
        'paymentMethod': 'CASH',
        'deliveryTier': 'STANDARD',
        'fulfilment': 'DELIVERY',
      });
    });

    test('a retry sends the same key and the same body, service fields and all', () async {
      final s = _orders((RequestOptions o) => (201, _serviceOrder(status: 'PLACED')));
      final OrderSubmission attempt = _pickup();

      await s.api.place(attempt);
      await s.api.place(attempt);

      expect(s.server.requests, hasLength(2));
      expect(s.server.requests[1].headers[OrderApi.idempotencyKeyHeader], attempt.idempotencyKey);
      expect(s.server.requests[1].data, s.server.requests[0].data);
    });

    test('a basket sends none of the service fields, so its request is the one it always was', () {
      final OrderSubmission basket = OrderSubmission(
        items: <OrderLineSubmission>[(productId: 'p1', qty: 2, optionIds: const <String>[])],
        deliveryAddress: '12 Rose Street',
      );

      expect(basket.toBody(), <String, dynamic>{
        'items': <dynamic>[
          <String, dynamic>{'productId': 'p1', 'qty': 2},
        ],
        'deliveryAddress': '12 Rose Street',
        'paymentMethod': 'CASH',
        'deliveryTier': 'STANDARD',
      });
    });

    test('survives being written to disk and read back, and an attempt stored before does too', () {
      final OrderSubmission original = _pickup();

      final OrderSubmission restored = OrderSubmission.fromJson(original.toJson());

      expect(restored.idempotencyKey, original.idempotencyKey);
      expect(restored.fulfilment, Fulfilment.pickup);
      expect(restored.attachmentFileIds, <String>['file-1', 'file-2']);
      expect(restored.serviceInstructions, 'Leave a white border');
      expect(restored.toBody(), original.toBody());

      final Map<String, dynamic> storedBeforeServices = OrderSubmission(
        items: <OrderLineSubmission>[(productId: 'p1', qty: 1, optionIds: const <String>[])],
        deliveryAddress: '4 Mill Lane',
      ).toJson()
        ..remove('fulfilment')
        ..remove('attachmentFileIds')
        ..remove('serviceInstructions');
      final OrderSubmission old = OrderSubmission.fromJson(storedBeforeServices);
      expect(old.fulfilment, isNull);
      expect(old.attachmentFileIds, isEmpty);
      expect(old.serviceInstructions, isNull);
      expect(old.toBody().containsKey('fulfilment'), isFalse);
    });

    test('a fulfilment this build does not know is never sent', () {
      expect(
          () => OrderSubmission(
                items: <OrderLineSubmission>[(productId: 'p1', qty: 1, optionIds: const <String>[])],
                deliveryAddress: '',
                fulfilment: Fulfilment.unknown,
              ),
          throwsArgumentError);
    });
  });

  group('what a service placement can be told', () {
    test('every service refusal is an outcome naming its code, not an error', () async {
      for (final ServiceOrderRefusal refusal in ServiceOrderRefusal.values) {
        if (refusal == ServiceOrderRefusal.unknown) continue;
        final s = _orders((RequestOptions o) => (422, _refusal(refusal.wire!)));

        final PlaceOrderResult result = await s.api.place(_pickup());

        expect(
            result,
            isA<ServiceOrderRefused>()
                .having((ServiceOrderRefused r) => r.refusal, 'refusal', refusal)
                .having((ServiceOrderRefused r) => r.code, 'code', refusal.wire)
                .having((ServiceOrderRefused r) => r.detail, 'detail',
                    'The server says why, in English'),
            reason: refusal.name);
      }
    });

    test('an unreadable services directory is an outcome of its own', () async {
      final s = _orders((RequestOptions o) => (503, <String, dynamic>{
            'title': 'Temporarily unavailable',
            'status': 503,
            'code': 'SERVICES_DIRECTORY_UNAVAILABLE',
          }));

      expect(await s.api.place(_pickup()), isA<ServicesDirectoryUnavailable>());
    });

    test('a basket\'s refusals, codes this build does not know and anything unlabelled are thrown',
        () async {
      for (final (int, Map<String, dynamic>) answer in <(int, Map<String, dynamic>)>[
        (422, <String, dynamic>{'code': 'SHOP_REFUSED', 'refusal': 'CLOSED', 'storeId': 's1'}),
        (422, _refusal('SOMETHING_NEW')),
        (422, <String, dynamic>{'detail': 'Item unavailable'}),
        (503, <String, dynamic>{'detail': 'The areas around this shop cannot be read right now'}),
        (503, <String, dynamic>{'code': 'SOMETHING_ELSE'}),
      ]) {
        final s = _orders((RequestOptions o) => answer);

        await expectLater(s.api.place(_pickup()), throwsA(isA<DioException>()),
            reason: '$answer');
      }
    });
  });

  group('a service quote', () {
    final Map<String, dynamic> quoteJson = <String, dynamic>{
      'shops': <dynamic>[
        <String, dynamic>{
          'storeId': 'press-1',
          'storeName': 'Hamra Press',
          'refusal': null,
          'refusalMessage': null,
          'subtotal': 47.25,
          'minimumOrder': 0,
          'shortfall': 0,
          'deliveryFee': 0,
          'deliveryFeeCharged': 0,
          'deliveryFeeWaived': false,
          'offerTitle': null,
          'expressSurcharge': 0,
          'discountAmount': 0,
          'totalAmount': 47.25,
        },
      ],
      'placeable': true,
      'subtotal': 47.25,
      'deliveryFeeCharged': 0,
      'expressSurcharge': 0,
      'discountAmount': 0,
      'totalAmount': 47.25,
      'promo': null,
      'maxShops': 3,
    };

    test('asks for one line of packs, how the work is got, on the standard tier', () async {
      final s = _orders((RequestOptions o) => (200, quoteJson));

      final ServiceQuoteResult result = await s.api.quoteService(BasketQuestion.service(
        productId: 'offer-1',
        packs: 3,
        optionIds: const <String>['matte'],
        fulfilment: Fulfilment.pickup,
        deliveryZoneId: 'zone-hamra',
        promoCode: ' SAVE6 ',
      ));

      final RequestOptions sent = s.server.requests.single;
      expect(sent.method, 'POST');
      expect(sent.path, '/api/orders/quote');
      expect(sent.data, <String, dynamic>{
        'items': <dynamic>[
          <String, dynamic>{'productId': 'offer-1', 'qty': 3, 'optionIds': <String>['matte']},
        ],
        'deliveryZoneId': 'zone-hamra',
        'deliveryTier': 'STANDARD',
        'promoCode': 'SAVE6',
        'fulfilment': 'PICKUP',
      });
      expect(result, isA<ServiceQuoted>());
      final ServiceQuoted quoted = result as ServiceQuoted;
      expect(quoted.quote.placeable, isTrue);
      expect(quoted.shop?.storeId, 'press-1');
      expect(quoted.shop?.deliveryFeeCharged, 0);
      expect(quoted.shop?.totalAmount, 47.25);
    });

    test('a basket\'s question says nothing of fulfilment, and a service\'s signature does', () {
      const OrderLineSubmission line = (productId: 'offer-1', qty: 1, optionIds: <String>[]);
      final BasketQuestion basket =
          BasketQuestion(items: <OrderLineSubmission>[line], deliveryZoneId: 'z');
      BasketQuestion service(Fulfilment fulfilment) => BasketQuestion.service(
          productId: 'offer-1', packs: 1, fulfilment: fulfilment, deliveryZoneId: 'z');

      expect(basket.toBody().containsKey('fulfilment'), isFalse);
      expect(basket.signature,
          BasketQuestion(items: <OrderLineSubmission>[line], deliveryZoneId: 'z').signature);
      expect(service(Fulfilment.pickup).signature, isNot(service(Fulfilment.delivery).signature));
      expect(service(Fulfilment.delivery).signature, isNot(basket.signature));
      expect(
          () => BasketQuestion(items: <OrderLineSubmission>[line], fulfilment: Fulfilment.unknown),
          throwsArgumentError);
    });

    test('what a service can never be is a refusal, a code this build does not know included',
        () async {
      final s = _orders((RequestOptions o) => (422, _refusal('STANDARD_ONLY')));
      final ServiceQuoteResult standardOnly = await s.api.quoteService(
          BasketQuestion.service(productId: 'offer-1', packs: 1, fulfilment: Fulfilment.delivery));
      expect(
          standardOnly,
          isA<ServiceQuoteRefused>()
              .having((ServiceQuoteRefused r) => r.refusal, 'refusal',
                  ServiceOrderRefusal.standardOnly));

      final t = _orders((RequestOptions o) => (422, _refusal('MOON_PHASE')));
      final ServiceQuoteResult unknown = await t.api.quoteService(
          BasketQuestion.service(productId: 'offer-1', packs: 1, fulfilment: Fulfilment.delivery));
      expect(
          unknown,
          isA<ServiceQuoteRefused>()
              .having((ServiceQuoteRefused r) => r.refusal, 'refusal', ServiceOrderRefusal.unknown)
              .having((ServiceQuoteRefused r) => r.code, 'code', 'MOON_PHASE'));
    });

    test('an unreadable directory is its own answer, and a refusal without a code is thrown',
        () async {
      final BasketQuestion question =
          BasketQuestion.service(productId: 'offer-1', packs: 1, fulfilment: Fulfilment.pickup);
      final s = _orders((RequestOptions o) =>
          (503, <String, dynamic>{'code': 'SERVICES_DIRECTORY_UNAVAILABLE'}));
      expect(await s.api.quoteService(question), isA<ServiceQuoteUnavailable>());

      final t = _orders((RequestOptions o) => (422, <String, dynamic>{'detail': 'no'}));
      await expectLater(t.api.quoteService(question), throwsA(isA<DioException>()));
    });
  });

  group('the provider\'s steps', () {
    test('collected posts to the order\'s own endpoint with no body, and reads the order back',
        () async {
      final s = _orders((RequestOptions o) =>
          (200, _serviceOrder(status: 'DELIVERED', actions: const <Object?>[])));

      final ServiceOrderActionResult result = await s.api.collected('o-1');

      final RequestOptions sent = s.server.requests.single;
      expect(sent.method, 'POST');
      expect(sent.path, '/api/orders/o-1/collected');
      expect(sent.data, isNull);
      expect(
          result,
          isA<ServiceOrderUpdated>().having(
              (ServiceOrderUpdated r) => r.order.status, 'status', OrderStatus.delivered));
    });

    test('act() reaches the same endpoint for the COLLECTED action the server offered', () async {
      final s = _orders((RequestOptions o) => (200, _serviceOrder(status: 'DELIVERED')));

      await s.api.act('o-1', OrderAction.collected);

      expect(s.server.requests.single.path, '/api/orders/o-1/collected');
      expect(s.server.requests.single.data, isNull);
    });

    test('a decline is the shop\'s cancel, sent as the picklist\'s code', () async {
      for (final DeclineReason reason in DeclineReason.picklist) {
        final s = _orders((RequestOptions o) => (200,
            _serviceOrder(status: 'CANCELLED', cancelReason: 'PROVIDER_DECLINED: ${reason.wire}')));

        final ServiceOrderActionResult result = await s.api.decline('o-1', reason);

        final RequestOptions sent = s.server.requests.single;
        expect(sent.method, 'POST');
        expect(sent.path, '/api/orders/o-1/cancel');
        expect(sent.data, <String, dynamic>{'reason': 'PROVIDER_DECLINED: ${reason.wire}'});
        expect((result as ServiceOrderUpdated).order.declineReason, reason);
      }
    });

    test('a decline with no reason this build knows is refused before anything is sent', () {
      final s = _orders((RequestOptions o) => (200, _serviceOrder()));

      expect(() => s.api.decline('o-1', DeclineReason.unknown), throwsArgumentError);
      expect(s.server.requests, isEmpty);
    });

    test('an uncollected pickup is cancelled as NOT_COLLECTED, with the shop\'s words after it',
        () async {
      final s = _orders((RequestOptions o) =>
          (200, _serviceOrder(status: 'CANCELLED', cancelReason: 'NOT_COLLECTED')));

      await s.api.cancelNotCollected('o-1');
      await s.api.cancelNotCollected('o-1', note: '  Waited a week ');
      await s.api.cancelNotCollected('o-1', note: '   ');

      expect(s.server.requests.map((RequestOptions o) => o.path).toSet(),
          <String>{'/api/orders/o-1/cancel'});
      expect(s.server.requests.map((RequestOptions o) => o.data), <Object>[
        <String, dynamic>{'reason': 'NOT_COLLECTED'},
        <String, dynamic>{'reason': 'NOT_COLLECTED: Waited a week'},
        <String, dynamic>{'reason': 'NOT_COLLECTED'},
      ]);
    });

    test('the server\'s refusals are outcomes naming their code, one it does not know included',
        () async {
      Future<ServiceOrderActionResult> refusedWith(
          String code, Future<ServiceOrderActionResult> Function(OrderApi api) step) {
        final s = _orders((RequestOptions o) => (422, _refusal(code)));
        return step(s.api);
      }

      expect(
          await refusedWith('NOT_COLLECTABLE', (OrderApi api) => api.collected('o-1')),
          isA<ServiceOrderActionRefused>().having((ServiceOrderActionRefused r) => r.refusal,
              'refusal', ServiceOrderRefusal.notCollectable));
      expect(
          await refusedWith(
              'UNCOLLECTED_TOO_SOON', (OrderApi api) => api.cancelNotCollected('o-1')),
          isA<ServiceOrderActionRefused>().having((ServiceOrderActionRefused r) => r.refusal,
              'refusal', ServiceOrderRefusal.uncollectedTooSoon));
      expect(
          await refusedWith('RESERVED_CANCEL_REASON',
              (OrderApi api) => api.decline('o-1', DeclineReason.tooBusy)),
          isA<ServiceOrderActionRefused>().having((ServiceOrderActionRefused r) => r.refusal,
              'refusal', ServiceOrderRefusal.reservedCancelReason));
      expect(
          await refusedWith('SHOP_ON_FIRE', (OrderApi api) => api.collected('o-1')),
          isA<ServiceOrderActionRefused>()
              .having((ServiceOrderActionRefused r) => r.refusal, 'refusal',
                  ServiceOrderRefusal.unknown)
              .having((ServiceOrderActionRefused r) => r.code, 'code', 'SHOP_ON_FIRE'));
    });

    test('a refusal without a code, and anything that is not a refusal, is thrown', () async {
      final s = _orders((RequestOptions o) => (422, <String, dynamic>{
            'detail': 'This order has already been delivered, so there is nothing to cancel',
          }));
      await expectLater(s.api.cancelNotCollected('o-1'), throwsA(isA<DioException>()));

      final t = _orders((RequestOptions o) => (404, <String, dynamic>{'detail': 'not found'}));
      await expectLater(t.api.collected('o-1'), throwsA(isA<DioException>()));
    });
  });

  group('the order lists', () {
    test('a merchant\'s narrows by kind and fulfilment, and without them is the list it always was',
        () async {
      final s = _orders((RequestOptions o) => (200, _page(<Map<String, dynamic>>[_serviceOrder()])));

      await s.api.forMerchant();
      final Paged<DeliveryOrder> pickups = await s.api
          .forMerchant(kind: OrderKind.service, fulfilment: Fulfilment.pickup, page: 1);

      expect(s.server.requests.map((RequestOptions o) => o.path).toSet(),
          <String>{'/api/orders/merchant'});
      expect(s.server.requests[0].queryParameters, <String, dynamic>{'page': 0, 'size': 20});
      expect(s.server.requests[1].queryParameters, <String, dynamic>{
        'page': 1,
        'size': 20,
        'kind': 'SERVICE',
        'fulfilment': 'PICKUP',
      });
      expect(pickups.content.single.isPickup, isTrue);
    });

    test('the back office narrows by status, kind and fulfilment together', () async {
      final s = _orders((RequestOptions o) => (200, _page(<Map<String, dynamic>>[])));

      await s.api.all();
      await s.api.all(status: OrderStatus.ready);
      await s.api.all(
          status: OrderStatus.ready, kind: OrderKind.service, fulfilment: Fulfilment.pickup);

      expect(s.server.requests.map((RequestOptions o) => o.queryParameters), <Object>[
        <String, dynamic>{'page': 0, 'size': 20},
        <String, dynamic>{'page': 0, 'size': 20, 'status': 'READY'},
        <String, dynamic>{
          'page': 0,
          'size': 20,
          'status': 'READY',
          'kind': 'SERVICE',
          'fulfilment': 'PICKUP',
        },
      ]);
    });

    test('a kind or fulfilment this build does not know is never sent as a filter', () {
      final s = _orders((RequestOptions o) => (200, _page(<Map<String, dynamic>>[])));

      expect(() => s.api.forMerchant(kind: OrderKind.unknown), throwsArgumentError);
      expect(() => s.api.all(fulfilment: Fulfilment.unknown), throwsArgumentError);
      expect(s.server.requests, isEmpty);
    });
  });

  group('an order\'s history', () {
    test('reads each step oldest first, leaving out one this build cannot place', () async {
      final s = _orders((RequestOptions o) => (200, <dynamic>[
            <String, dynamic>{
              'status': 'PLACED',
              'changedBy': 'customer-1',
              'changedAt': '2026-09-13T08:00:00Z',
              'note': null,
            },
            <String, dynamic>{
              'status': 'TELEPORTED',
              'changedBy': 'provider-1',
              'changedAt': '2026-09-13T08:01:00Z',
            },
            'junk',
            <String, dynamic>{
              'status': 'CANCELLED',
              'changedBy': 'provider-1',
              'changedAt': '2026-09-13T08:02:00Z',
              'note': 'PROVIDER_DECLINED: TOO_BUSY',
            },
          ]));

      final List<OrderStatusChange> history = await s.api.statusHistory('o-1');

      expect(s.server.requests.single.method, 'GET');
      expect(s.server.requests.single.path, '/api/orders/o-1/history');
      expect(history.map((OrderStatusChange c) => c.status),
          <OrderStatus>[OrderStatus.placed, OrderStatus.cancelled]);
      expect(history.first.changedBy, 'customer-1');
      expect(history.first.changedAt!.toUtc(), DateTime.utc(2026, 9, 13, 8));
      expect(history.first.note, isNull);
      expect(history.last.note, 'PROVIDER_DECLINED: TOO_BUSY');
    });

    test('an answer that is not a list is no history', () async {
      final s = _orders((RequestOptions o) => (200, <String, dynamic>{}));

      expect(await s.api.statusHistory('o-1'), isEmpty);
    });
  });

  group('StoreApi.reviews', () {
    ({StoreApi api, _Server server}) stores(Object? body) {
      final _Server server = _Server((RequestOptions o) => (200, body));
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway.test'))..httpClientAdapter = server;
      return (api: StoreApi(dio), server: server);
    }

    test('asks for a page of the shop\'s reviews and reads each as product-service writes it',
        () async {
      final s = stores(<String, dynamic>{
        'content': <dynamic>[
          <String, dynamic>{
            'id': 'r1',
            'storeId': 'press-1',
            'orderId': 'o1',
            'rating': 5,
            'comment': 'Crisp cards, on time',
            'createdAt': '2026-09-10T10:00:00Z',
            'mine': true,
          },
          <String, dynamic>{
            'id': 'r2',
            'storeId': 'press-1',
            'orderId': 'o2',
            'rating': 4,
            'comment': null,
            'createdAt': '2026-09-09T10:00:00Z',
            'mine': false,
          },
        ],
        'page': 1,
        'size': 2,
        'totalElements': 7,
        'totalPages': 4,
      });

      final Paged<StoreReview> reviews = await s.api.reviews('press-1', page: 1, size: 2);

      expect(s.server.requests.single.method, 'GET');
      expect(s.server.requests.single.path, '/api/stores/press-1/reviews');
      expect(s.server.requests.single.queryParameters, <String, dynamic>{'page': 1, 'size': 2});
      expect(reviews.page, 1);
      expect(reviews.totalElements, 7);
      expect(reviews.totalPages, 4);
      final StoreReview first = reviews.content.first;
      expect(first.id, 'r1');
      expect(first.storeId, 'press-1');
      expect(first.orderId, 'o1');
      expect(first.rating, 5);
      expect(first.comment, 'Crisp cards, on time');
      expect(first.createdAt!.toUtc(), DateTime.utc(2026, 9, 10, 10));
      expect(first.mine, isTrue);
      expect(reviews.content.last.comment, isNull);
      expect(reviews.content.last.mine, isFalse);
    });

    test('a review this build cannot show is left out, and the counts stay the server\'s', () async {
      final s = stores(<String, dynamic>{
        'content': <dynamic>[
          <String, dynamic>{'id': 'r1', 'rating': 0},
          <String, dynamic>{'rating': 5},
          'junk',
          <String, dynamic>{'id': 'r4', 'rating': 3},
        ],
        'page': 0,
        'size': 20,
        'totalElements': 4,
        'totalPages': 1,
      });

      final Paged<StoreReview> reviews = await s.api.reviews('press-1');

      expect(reviews.content.map((StoreReview r) => r.id), <String>['r4']);
      expect(reviews.totalElements, 4);
    });

    test('an answer that is not a page is no reviews', () async {
      final Paged<StoreReview> reviews = await stores(<dynamic>[]).api.reviews('press-1');

      expect(reviews.content, isEmpty);
      expect(reviews.totalElements, 0);
    });
  });

  group('labels', () {
    test('collected and every decline reason read in English and in Arabic', () {
      final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
      final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

      expect(OrderAction.collected.labelIn(en), en.svcActionCollected);
      expect(OrderAction.collected.labelIn(ar), isNot(OrderAction.collected.labelIn(en)));
      for (final DeclineReason reason in DeclineReason.picklist) {
        expect(reason.labelIn(en), isNotEmpty, reason: reason.name);
        expect(reason.labelIn(ar), isNot(reason.labelIn(en)), reason: reason.name);
      }
      expect(DeclineReason.picklist.map((DeclineReason r) => r.labelIn(en)).toSet(), hasLength(4));
      expect(DeclineReason.unknown.labelIn(ar), DeclineReason.other.labelIn(ar));
    });
  });
}
