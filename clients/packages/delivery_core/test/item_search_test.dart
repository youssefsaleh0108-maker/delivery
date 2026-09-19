import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// The customer item search, against a recording adapter.
///
/// Pinned against product-service's `ItemSearchController`: `POST /api/products/search/items` with a
/// JSON body (`ItemSearchRequest`), and the page it answers (`ItemSearchPageResponse`). The first
/// thing held here is where the customer's pin travels: in the body, never in the URL, where
/// gateways, proxies and access logs keep it.
class _Server implements HttpClientAdapter {
  _Server(this.answer);

  final Object? Function(RequestOptions options) answer;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(answer(options)), 200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        });
  }

  @override
  void close({bool force = false}) {}
}

({StoreApi api, _Server server}) _stores(Object? Function(RequestOptions options) answer) {
  final _Server server = _Server(answer);
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway.test'))..httpClientAdapter = server;
  return (api: StoreApi(dio), server: server);
}

Map<String, dynamic> _card(String id, String name) => <String, dynamic>{
      'id': id,
      'slug': id,
      'name': name,
      'vertical': 'GROCERY',
      'availability': 'BUSY',
      'deliveryFee': 1.5,
      'etaMinMinutes': 20,
      'etaMaxMinutes': 30,
    };

Map<String, dynamic> _product(String id, String name, double price) => <String, dynamic>{
      'id': id,
      'merchantId': 'merchant-1',
      'storeId': 'shop-1',
      'name': name,
      'price': price,
      'status': 'ACTIVE',
      'inStock': true,
    };

/// A page as `ItemSearchController` writes it: one shop near the pin, Pepsi and two more there.
Map<String, dynamic> _page({bool nearby = true, bool truncated = false}) => <String, dynamic>{
      'content': <Object?>[
        <String, dynamic>{
          'store': _card('shop-1', 'Corner Grocer'),
          'latitude': 33.9008,
          'longitude': 35.4829,
          'distanceMetres': nearby ? 345 : null,
          'items': <Object?>[_product('p1', 'Pepsi 1L', 1.25)],
          'matchedInStore': 3,
        },
      ],
      'page': 0,
      'size': 10,
      'totalElements': 1,
      'totalPages': 1,
      'truncated': truncated,
      'candidateLimit': 300,
      'nearby': nearby,
    };

void main() {
  group('StoreApi.searchItems', () {
    test('posts the words and the pin in the body, and never puts the pin in the URL', () async {
      final s = _stores((RequestOptions o) => _page());

      await s.api.searchItems(const ItemSearchQuery.text('pepsi'),
          latitude: 33.8977, longitude: 35.4829, size: 3);

      final RequestOptions sent = s.server.requests.single;
      expect(sent.method, 'POST');
      expect(sent.path, '/api/products/search/items');
      expect(sent.queryParameters, isEmpty);
      expect(sent.uri.toString(), 'http://gateway.test/api/products/search/items');
      expect(sent.uri.toString(), isNot(contains('33.8977')));
      expect(sent.uri.toString(), isNot(contains('35.4829')));
      expect(sent.data, <String, dynamic>{
        'q': 'pepsi',
        'latitude': 33.8977,
        'longitude': 35.4829,
        'page': 0,
        'size': 3,
      });
    });

    test('without a pin, sends no point at all, and half a pin is no pin', () async {
      final s = _stores((RequestOptions o) => _page(nearby: false));

      await s.api.searchItems(const ItemSearchQuery.text('pepsi'));
      await s.api.searchItems(const ItemSearchQuery.text('pepsi'), latitude: 33.8977);

      for (final RequestOptions sent in s.server.requests) {
        expect((sent.data as Map<String, dynamic>).keys, isNot(contains('latitude')));
        expect((sent.data as Map<String, dynamic>).keys, isNot(contains('longitude')));
      }
    });

    test('a query of terms and a barcode sends them, and only what is set', () async {
      final s = _stores((RequestOptions o) => _page());

      await s.api.searchItems(
          const ItemSearchQuery(terms: <String>['Pepsi 1L', 'بيبسي'], barcode: '5449000000996'),
          page: 2);

      expect(s.server.requests.single.data, <String, dynamic>{
        'terms': <String>['Pepsi 1L', 'بيبسي'],
        'barcode': '5449000000996',
        'page': 2,
        'size': 10,
      });
    });

    test('reads each shop, its best items, how many more it has, and what the page can claim',
        () async {
      final s = _stores((RequestOptions o) => _page(truncated: true));

      final ItemSearchPage page = await s.api.searchItems(const ItemSearchQuery.text('pepsi'),
          latitude: 33.8977, longitude: 35.4829);

      final ItemSearchGroup group = page.content.single;
      expect(group.store.name, 'Corner Grocer');
      expect(group.store.availability, StoreAvailability.busy);
      expect(group.distanceMetres, 345);
      expect(group.items.single.name, 'Pepsi 1L');
      expect(group.items.single.price, 1.25);
      expect(group.matchedInStore, 3);
      expect(group.moreInStore, 2);
      expect(page.nearby, isTrue);
      expect(page.truncated, isTrue);
      expect(page.candidateLimit, 300);
      expect(page.totalElements, 1);
    });

    test('without a point no shop has a distance', () async {
      final s = _stores((RequestOptions o) => _page(nearby: false));

      final ItemSearchPage page = await s.api.searchItems(const ItemSearchQuery.text('pepsi'));

      expect(page.nearby, isFalse);
      expect(page.content.single.distanceMetres, isNull);
    });
  });

  group('an item search page', () {
    test('drops a row it cannot draw rather than failing the page', () {
      final ItemSearchPage page = ItemSearchPage.fromJson(<String, dynamic>{
        'content': <Object?>[
          'not a row',
          <String, dynamic>{'store': <String, dynamic>{'name': 'No id'}, 'items': <Object?>[]},
          <String, dynamic>{
            'store': _card('shop-2', 'No readable item'),
            'items': <Object?>[<String, dynamic>{'id': 'p9'}],
            'matchedInStore': 1,
          },
          _page()['content'][0],
        ],
        'page': 0,
        'totalElements': 4,
        'totalPages': 1,
      });

      expect(page.content.map((ItemSearchGroup g) => g.store.name), <String>['Corner Grocer']);
      expect(page.truncated, isFalse);
      expect(page.nearby, isFalse);
      expect(page.candidateLimit, isNull);
    });

    test('never counts fewer matches than it carries', () {
      final ItemSearchGroup? group = ItemSearchGroup.maybeFromJson(<String, dynamic>{
        'store': _card('shop-1', 'Corner Grocer'),
        'items': <Object?>[_product('p1', 'Pepsi 1L', 1.25), _product('p2', 'Pepsi Can', 0.75)],
        'matchedInStore': 1,
      });

      expect(group!.moreInStore, 0);
    });

    test('a query labels itself by what the customer typed, else its first term, else its barcode', () {
      expect(const ItemSearchQuery.text('pepsi').label, 'pepsi');
      expect(const ItemSearchQuery(terms: <String>['Pepsi 1L']).label, 'Pepsi 1L');
      expect(const ItemSearchQuery(barcode: '5449000000996').label, '5449000000996');
      expect(const ItemSearchQuery.text('pepsi'), const ItemSearchQuery.text('pepsi'));
      expect(const ItemSearchQuery.text('pepsi') == const ItemSearchQuery.text('cola'), isFalse);
    });
  });
}
