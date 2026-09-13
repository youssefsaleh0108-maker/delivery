import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Service offers on the client: the `service` block and "From" price a product carries, the paused
/// status, and the calls the provider dashboard and the Services tab make.
///
/// Pinned here: every term parses as product-service writes it; a term, status or block this build
/// does not know reads as unknown or absent rather than as a guess, and is never saved back as
/// something else; and each call uses the verb, path and query ProductController or StoreController
/// serves.
class _Recorder implements HttpClientAdapter {
  _Recorder(this.respond);

  final Object? Function(RequestOptions options) respond;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(respond(options)), 200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        });
  }

  @override
  void close({bool force = false}) {}
}

const Map<String, dynamic> _cardTerms = <String, dynamic>{
  'pricingType': 'FIXED',
  'unitLabel': 'cards',
  'unitSize': 500,
  'turnaroundMinHours': 24,
  'turnaroundMaxHours': 48,
  'fulfilmentModes': 'BOTH',
  'attachmentPolicy': 'REQUIRED',
  'instructionsPrompt': 'Which paper colour?',
};

Map<String, dynamic> _offer({
  String status = 'ACTIVE',
  Object? service = _cardTerms,
  Object? fromPrice = 15.75,
}) =>
    <String, dynamic>{
      'id': 'offer-1',
      'merchantId': 'provider-1',
      'storeId': 'press-1',
      'name': 'Business card printing',
      'price': 15.0,
      'status': status,
      'imageRefs': <String>[],
      'imageUrls': <String>[],
      'imageThumbUrls': <String>[],
      'inStock': true,
      'giftFeatured': false,
      if (service != null) 'service': service,
      if (fromPrice != null) 'fromPrice': fromPrice,
    };

Map<String, dynamic> _page(List<Map<String, dynamic>> content, {int total = 0}) => <String, dynamic>{
      'content': content,
      'page': 0,
      'size': 20,
      'totalElements': total,
      'totalPages': 1,
    };

void main() {
  group('ProductStatus', () {
    test('PAUSED parses as paused, and a status this build does not know is still a draft', () {
      expect(ProductStatus.fromWire('PAUSED'), ProductStatus.paused);
      expect(ProductStatus.paused.wireValue, 'PAUSED');
      expect(ProductStatus.fromWire('HIDDEN'), ProductStatus.draft);
    });
  });

  group('a service offer', () {
    test('reads every term as the server writes it, and the From price the server worked out', () {
      final Product offer = Product.fromJson(_offer());
      final ServiceTerms terms = offer.service!;

      expect(offer.isServiceOffer, isTrue);
      expect(terms.pricingType, ServicePricingType.fixed);
      expect(terms.unitLabel, 'cards');
      expect(terms.unitSize, 500);
      expect(terms.turnaroundMinHours, 24);
      expect(terms.turnaroundMaxHours, 48);
      expect(terms.fulfilmentModes, ServiceFulfilment.both);
      expect(terms.fulfilmentModes.includesPickup, isTrue);
      expect(terms.fulfilmentModes.includesDelivery, isTrue);
      expect(terms.attachmentPolicy, ServiceAttachmentPolicy.required);
      expect(terms.instructionsPrompt, 'Which paper colour?');
      expect(terms.isEditable, isTrue);
      expect(offer.fromPrice, 15.75);
    });

    test('the pricing types, fulfilments and file policies are exactly the server\'s', () {
      expect(
          ServicePricingType.values.map((ServicePricingType t) => t.wireValue).whereType<String>(),
          <String>['FIXED', 'PER_UNIT', 'FROM']);
      expect(ServiceFulfilment.values.map((ServiceFulfilment f) => f.wireValue).whereType<String>(),
          <String>['PICKUP', 'DELIVERY', 'BOTH']);
      expect(
          ServiceAttachmentPolicy.values
              .map((ServiceAttachmentPolicy p) => p.wireValue)
              .whereType<String>(),
          <String>['NONE', 'OPTIONAL', 'REQUIRED']);
      for (final ServicePricingType type in ServicePricingType.values) {
        if (type.wireValue != null) expect(ServicePricingType.fromWire(type.wireValue), type);
      }
      for (final ServiceFulfilment fulfilment in ServiceFulfilment.values) {
        if (fulfilment.wireValue != null) {
          expect(ServiceFulfilment.fromWire(fulfilment.wireValue), fulfilment);
        }
      }
      for (final ServiceAttachmentPolicy policy in ServiceAttachmentPolicy.values) {
        if (policy.wireValue != null) {
          expect(ServiceAttachmentPolicy.fromWire(policy.wireValue), policy);
        }
      }
      expect(ServiceFulfilment.pickup.includesDelivery, isFalse);
      expect(ServiceFulfilment.delivery.includesPickup, isFalse);
    });

    test('a goods product has no terms and no From price, and saves none', () {
      final Product dish = Product.fromJson(_offer(service: null, fromPrice: null));

      expect(dish.service, isNull);
      expect(dish.isServiceOffer, isFalse);
      expect(dish.fromPrice, isNull);
      expect(dish.toRequestJson().containsKey('service'), isFalse);
    });

    test('a term this build does not know reads as unknown, never as another term', () {
      final ServiceTerms terms = Product.fromJson(_offer(service: <String, dynamic>{
        ..._cardTerms,
        'pricingType': 'QUOTE',
        'fulfilmentModes': 'COURIER',
        'attachmentPolicy': 'TWO_FILES',
      })).service!;

      expect(terms.pricingType, ServicePricingType.unknown);
      expect(terms.fulfilmentModes, ServiceFulfilment.unknown);
      expect(terms.fulfilmentModes.includesPickup, isFalse);
      expect(terms.fulfilmentModes.includesDelivery, isFalse);
      expect(terms.attachmentPolicy, ServiceAttachmentPolicy.unknown);
      expect(terms.isEditable, isFalse);
    });

    test('terms holding a value this build does not know are never saved back as something else', () {
      final Product offer = Product.fromJson(
          _offer(service: <String, dynamic>{..._cardTerms, 'attachmentPolicy': 'TWO_FILES'}));

      expect(offer.toRequestJson, throwsStateError);
    });

    test('a number the server did not send stays absent, and a pack is at least one unit', () {
      final ServiceTerms terms = ServiceTerms.maybeFromJson(<String, dynamic>{
        'pricingType': 'PER_UNIT',
        'unitLabel': 'sqm',
        'unitSize': 'lots',
        'turnaroundMaxHours': '48',
        'fulfilmentModes': 'PICKUP',
        'attachmentPolicy': 'NONE',
      })!;

      expect(terms.unitSize, 1);
      expect(terms.turnaroundMinHours, isNull);
      expect(terms.turnaroundMaxHours, isNull);
      expect(ServiceTerms.maybeFromJson(<String, dynamic>{..._cardTerms, 'unitSize': 0})!.unitSize, 1);
    });

    test('a block that is not a block is no block, and a From price that is not a number is absent',
        () {
      final Product odd = Product.fromJson(_offer(service: 'FIXED', fromPrice: '15.75'));

      expect(odd.service, isNull);
      expect(odd.fromPrice, isNull);
    });

    test('an offer saves its terms with the product, in the server\'s words', () {
      expect(Product.fromJson(_offer()).toRequestJson()['service'], <String, dynamic>{
        'pricingType': 'FIXED',
        'unitLabel': 'cards',
        'unitSize': 500,
        'turnaroundMinHours': 24,
        'turnaroundMaxHours': 48,
        'fulfilmentModes': 'BOTH',
        'attachmentPolicy': 'REQUIRED',
        'instructionsPrompt': 'Which paper colour?',
      });
    });
  });

  group('CatalogApi', () {
    late _Recorder recorder;
    late CatalogApi api;

    void answering(Object? Function(RequestOptions options) respond) {
      recorder = _Recorder(respond);
      api = CatalogApi(Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = recorder);
    }

    test('the dashboard counts active offers from the server total, asking for one row', () async {
      answering((_) => _page(<Map<String, dynamic>>[_offer()], total: 3));

      final Paged<Product> active = await api.myProducts(status: ProductStatus.active, size: 1);

      final RequestOptions sent = recorder.requests.single;
      expect(sent.method, 'GET');
      expect(sent.uri.path, '/api/products/mine');
      expect(sent.uri.queryParameters, <String, String>{'status': 'ACTIVE', 'page': '0', 'size': '1'});
      expect(active.totalElements, 3);
    });

    test('the list without a status asks for every status, as it always did', () async {
      answering((_) => _page(<Map<String, dynamic>>[]));

      await api.myProducts();

      expect(recorder.requests.single.uri.queryParameters, <String, String>{'page': '0', 'size': '20'});
    });

    test('pause and resume post to the offer and read back its status', () async {
      answering((RequestOptions options) =>
          _offer(status: options.path.endsWith('/pause') ? 'PAUSED' : 'ACTIVE'));

      final Product paused = await api.pause('offer-1');
      final Product resumed = await api.resume('offer-1');

      expect(recorder.requests.map((RequestOptions r) => '${r.method} ${r.uri.path}'), <String>[
        'POST /api/products/offer-1/pause',
        'POST /api/products/offer-1/resume',
      ]);
      expect(paused.status, ProductStatus.paused);
      expect(resumed.status, ProductStatus.active);
    });

    test('searching services sends the text and the category in the server\'s words', () async {
      answering((_) => _page(<Map<String, dynamic>>[_offer()], total: 1));

      final Paged<Product> found = await api.searchServices(
          search: 'cards', serviceCategory: ServiceCategory.printing, page: 2);

      final RequestOptions sent = recorder.requests.single;
      expect(sent.method, 'GET');
      expect(sent.uri.path, '/api/products/services');
      expect(sent.uri.queryParameters, <String, String>{
        'search': 'cards',
        'serviceCategory': 'PRINTING',
        'page': '2',
        'size': '20',
      });
      expect(found.content.single.service!.unitSize, 500);
    });

    test('a search with no text and no category sends neither', () async {
      answering((_) => _page(<Map<String, dynamic>>[]));

      await api.searchServices(search: '');

      expect(recorder.requests.single.uri.queryParameters, <String, String>{'page': '0', 'size': '20'});
    });

    test('a two-shop account counts one shop\'s active offers by naming the shop', () async {
      answering((_) => _page(<Map<String, dynamic>>[_offer()], total: 2));

      final Paged<Product> active =
          await api.myProducts(storeId: 'press-1', status: ProductStatus.active, size: 1);

      final RequestOptions sent = recorder.requests.single;
      expect(sent.uri.path, '/api/products/mine');
      expect(sent.uri.queryParameters,
          <String, String>{'storeId': 'press-1', 'status': 'ACTIVE', 'page': '0', 'size': '1'});
      expect(active.totalElements, 2);
    });
  });

  group('StoreApi.popularServices', () {
    late _Recorder recorder;
    late StoreApi api;

    void answering(Object? Function(RequestOptions options) respond) {
      recorder = _Recorder(respond);
      api = StoreApi(Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = recorder);
    }

    Map<String, dynamic> row(String id, String name, int metres) => <String, dynamic>{
          'store': <String, dynamic>{
            'id': id,
            'name': name,
            'vertical': 'SERVICES',
            'serviceCategory': 'PRINTING',
          },
          'latitude': 33.9,
          'longitude': 35.5,
          'distanceMetres': metres,
        };

    test('asks for shops near the point, keeps the server\'s order and drops a row it cannot read',
        () async {
      answering((_) => <Object?>[
            row('press-1', 'Al Fakhry Press', 2950),
            row('tailor-1', 'Hamra Tailor', 420),
            <String, dynamic>{
              'store': <String, dynamic>{'name': 'No id'},
              'latitude': 33.9,
              'longitude': 35.5,
            },
            <String, dynamic>{
              'store': <String, dynamic>{'id': 'unpinned', 'name': 'No pin'},
            },
            'not a row',
          ]);

      final List<NearbyStore> popular = await api.popularServices(33.8977, 35.4829,
          serviceCategory: ServiceCategory.printing, limit: 5);

      final RequestOptions sent = recorder.requests.single;
      expect(sent.method, 'GET');
      expect(sent.uri.path, '/api/stores/services/popular');
      expect(sent.uri.queryParameters, <String, String>{
        'latitude': '33.8977',
        'longitude': '35.4829',
        'serviceCategory': 'PRINTING',
        'limit': '5',
      });
      expect(popular.map((NearbyStore s) => s.store.name), <String>['Al Fakhry Press', 'Hamra Tailor']);
      expect(popular.first.distanceMetres, 2950);
      expect(popular.first.store.serviceCategory, ServiceCategory.printing);
    });

    test('no popular shops nearby yet is an empty list, never a guess', () async {
      answering((_) => <Object?>[]);

      expect(await api.popularServices(33.8977, 35.4829), isEmpty);
      expect(recorder.requests.single.uri.queryParameters,
          <String, String>{'latitude': '33.8977', 'longitude': '35.4829', 'limit': '10'});
    });

    test('an answer that is not a list is no shops', () async {
      answering((_) => <String, dynamic>{'content': <Object?>[]});

      expect(await api.popularServices(33.8977, 35.4829), isEmpty);
    });
  });
}
