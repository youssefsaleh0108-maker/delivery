import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Search by photo, against a recording adapter.
///
/// Pinned against product-service's `PhotoSearchController`: `POST /api/products/search/photo` as a
/// multipart form (the photo as the part `photo`, the pin as the form fields `latitude` and
/// `longitude`), the page it answers (`PhotoSearchResponse`), its refusals (`ApiExceptionHandler`'s
/// `code`, `limit`, `scope`, `retryAfterSeconds`) and `GET /api/products/search/capabilities`.
class _Server implements HttpClientAdapter {
  _Server(this.answer, {this.status = 200});

  final Object? Function(RequestOptions options) answer;
  final int status;
  final List<RequestOptions> requests = <RequestOptions>[];

  /// Every request body, as sent.
  final List<String> bodies = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    final List<int> sent = <int>[];
    if (requestStream != null) {
      await for (final Uint8List chunk in requestStream) {
        sent.addAll(chunk);
      }
    }
    bodies.add(latin1.decode(sent));
    return ResponseBody.fromString(jsonEncode(answer(options)), status,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        });
  }

  @override
  void close({bool force = false}) {}
}

({StoreApi api, _Server server}) _stores(Object? Function(RequestOptions options) answer,
    {int status = 200}) {
  final _Server server = _Server(answer, status: status);
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway.test'))..httpClientAdapter = server;
  return (api: StoreApi(dio), server: server);
}

/// A page as `PhotoSearchController` writes it: one shop, and what the photo was read as.
Map<String, dynamic> _photoPage({bool similar = false}) => <String, dynamic>{
      'content': <Object?>[
        <String, dynamic>{
          'store': <String, dynamic>{
            'id': 'shop-1',
            'slug': 'shop-1',
            'name': 'Corner Grocer',
            'vertical': 'GROCERY',
            'availability': 'OPEN',
            'deliveryFee': 1.5,
            'etaMinMinutes': 20,
            'etaMaxMinutes': 30,
          },
          'latitude': 33.9008,
          'longitude': 35.4829,
          'distanceMetres': 345,
          'items': <Object?>[
            <String, dynamic>{
              'id': 'p1',
              'merchantId': 'merchant-1',
              'storeId': 'shop-1',
              'name': 'Pepsi 1L',
              'price': 1.25,
              'status': 'ACTIVE',
              'inStock': true,
            },
          ],
          'matchedInStore': 2,
        },
      ],
      'page': 0,
      'size': 10,
      'totalElements': 1,
      'totalPages': 1,
      'truncated': false,
      'candidateLimit': 300,
      'nearby': true,
      'understood': <String, dynamic>{
        'name': 'Pepsi 1L',
        'nameAr': 'بيبسي',
        'brand': 'Pepsi',
        'size': '1 L',
        'barcode': null,
        'isProduct': true,
      },
      'similar': similar,
      'nextQuery': <String, dynamic>{
        'terms': <String>['pepsi 1l', 'بيبسي', 'pepsi'],
        'barcode': null,
      },
      'photosLeftToday': 7,
    };

/// A small JPEG, as a phone's already-shrunk photo would be.
Uint8List _smallJpeg() => Uint8List.fromList(img.encodeJpg(img.Image(width: 64, height: 48)));

void main() {
  group('searching by photo', () {
    test('sends the photo as a multipart part and the pin as form fields, never in the URL', () async {
      final ({StoreApi api, _Server server}) stores = _stores((_) => _photoPage());

      await stores.api.searchByPhoto(
          bytes: _smallJpeg(), contentType: 'image/jpeg', latitude: 33.8977, longitude: 35.4829);

      final RequestOptions sent = stores.server.requests.single;
      expect(sent.method, 'POST');
      expect(sent.path, '/api/products/search/photo');
      expect(sent.uri.query, isEmpty);
      expect(sent.uri.toString(), isNot(contains('33.8977')));
      expect(sent.contentType, startsWith('multipart/form-data'));
      final String body = stores.server.bodies.single;
      expect(body, contains('name="photo"'));
      expect(body.toLowerCase(), contains('content-type: image/jpeg'));
      expect(body, contains('name="latitude"'));
      expect(body, contains('33.8977'));
      expect(body, contains('name="longitude"'));
      expect(body, contains('35.4829'));
    });

    test('without a pin, no point is sent at all', () async {
      final ({StoreApi api, _Server server}) stores = _stores((_) => _photoPage());

      await stores.api.searchByPhoto(bytes: _smallJpeg(), contentType: 'image/jpeg');

      expect(stores.server.bodies.single, isNot(contains('name="latitude"')));
    });

    test('waits 45 seconds to send and to hear back, not the usual 20', () async {
      final ({StoreApi api, _Server server}) stores = _stores((_) => _photoPage());

      await stores.api.searchByPhoto(bytes: _smallJpeg(), contentType: 'image/jpeg');

      expect(stores.server.requests.single.sendTimeout, const Duration(seconds: 45));
      expect(stores.server.requests.single.receiveTimeout, const Duration(seconds: 45));
    });

    test('a photo over 800 KB is shrunk to a 1568 px JPEG before it is sent', () async {
      final ({StoreApi api, _Server server}) stores = _stores((_) => _photoPage());
      final Random noise = Random(7);
      final img.Image large = img.Image(width: 2400, height: 1800);
      for (final img.Pixel pixel in large) {
        pixel
          ..r = noise.nextInt(256)
          ..g = noise.nextInt(256)
          ..b = noise.nextInt(256);
      }
      final Uint8List png = Uint8List.fromList(img.encodePng(large));
      expect(png.length, greaterThan(StoreApi.photoSearchMaxBytes));

      await stores.api.searchByPhoto(bytes: png, contentType: 'image/png');

      final String body = stores.server.bodies.single;
      expect(body.toLowerCase(), contains('content-type: image/jpeg'));
      // The part's own bytes, between its headers and the closing boundary.
      final int partStart = body.indexOf('\r\n\r\n', body.indexOf('name="photo"')) + 4;
      final int partEnd = body.indexOf('\r\n--', partStart);
      final img.Image? sent =
          img.decodeJpg(Uint8List.fromList(latin1.encode(body.substring(partStart, partEnd))));
      expect(sent, isNotNull);
      expect(sent!.width, StoreApi.photoSearchMaxEdge);
      expect(sent.height, lessThan(StoreApi.photoSearchMaxEdge));
    });

    /// The server says how large a photo it takes ({@code maxPhotoBytes} on the capabilities). The
    /// app's own 800 KB is the kinder number on mobile data, but it is not the one that decides, and a
    /// build that ignored a smaller server cap would spend one of the day's photos on a 413.
    test('the smaller of the app\'s cap and the server\'s is what the photo is brought under',
        () async {
      // A gradient with a little grain: big enough as a PNG to need shrinking, and compressible
      // enough that the quality steps really do reach the caps below — unlike pure noise, which
      // bottoms out at the quality floor and lands on the same bytes whatever the cap.
      final Random grain = Random(11);
      final img.Image large = img.Image(width: 2400, height: 1800);
      for (final img.Pixel pixel in large) {
        pixel
          ..r = (pixel.x * 255) ~/ large.width
          ..g = (pixel.y * 255) ~/ large.height
          ..b = (pixel.x + pixel.y + grain.nextInt(24)) % 256;
      }
      final Uint8List png = Uint8List.fromList(img.encodePng(large));
      expect(png.length, greaterThan(StoreApi.photoSearchMaxBytes));

      Future<int> sentBytesWith(int? maxBytes) async {
        final ({StoreApi api, _Server server}) stores = _stores((_) => _photoPage());
        await stores.api
            .searchByPhoto(bytes: png, contentType: 'image/png', maxBytes: maxBytes);
        final String body = stores.server.bodies.single;
        final int partStart = body.indexOf('\r\n\r\n', body.indexOf('name="photo"')) + 4;
        return body.indexOf('\r\n--', partStart) - partStart;
      }

      final int withAppsOwn = await sentBytesWith(null);
      expect(withAppsOwn, lessThanOrEqualTo(StoreApi.photoSearchMaxBytes));

      // A server that takes less gets less.
      expect(await sentBytesWith(200 * 1024), lessThan(withAppsOwn));

      // A server that takes more does not make this build send more: 800 KB is still enough of a
      // photo to read a pack, and the rest is the customer's data.
      expect(await sentBytesWith(5 * 1024 * 1024), withAppsOwn);
      // Nor does a nonsense cap, which would otherwise send a photo nothing could read.
      expect(await sentBytesWith(0), withAppsOwn);
    });

    test('reads the page, what the photo was read as, and the query for the next page', () async {
      final ({StoreApi api, _Server server}) stores = _stores((_) => _photoPage(similar: true));

      final PhotoSearchPage page =
          await stores.api.searchByPhoto(bytes: _smallJpeg(), contentType: 'image/jpeg');

      expect(page.content.single.store.name, 'Corner Grocer');
      expect(page.content.single.items.single.name, 'Pepsi 1L');
      expect(page.nearby, isTrue);
      expect(page.understood.isProduct, isTrue);
      expect(page.understood.label, 'Pepsi 1L');
      expect(page.understood.nameAr, 'بيبسي');
      expect(page.similar, isTrue);
      expect(page.nextQuery, const ItemSearchQuery(terms: <String>['pepsi 1l', 'بيبسي', 'pepsi']));
      expect(page.photosLeftToday, 7);
    });

    test('a photo of no product is an empty page with nothing to page through', () async {
      final ({StoreApi api, _Server server}) stores = _stores((_) => <String, dynamic>{
            'content': <Object?>[],
            'page': 0,
            'totalElements': 0,
            'totalPages': 0,
            'understood': <String, dynamic>{'isProduct': false},
            'similar': false,
            'nextQuery': null,
            'photosLeftToday': 6,
          });

      final PhotoSearchPage page =
          await stores.api.searchByPhoto(bytes: _smallJpeg(), contentType: 'image/jpeg');

      expect(page.content, isEmpty);
      expect(page.understood.isProduct, isFalse);
      expect(page.understood.label, isNull);
      expect(page.nextQuery, isNull);
    });

    test('a limit arrives with its count, which one, and the wait', () async {
      final ({StoreApi api, _Server server}) stores = _stores(
          (_) => <String, dynamic>{
                'title': 'Photo limit reached',
                'code': 'PHOTO_SEARCH_LIMIT',
                'limit': 10,
                'scope': 'DAY',
                'retryAfterSeconds': 3600,
              },
          status: 429);

      await expectLater(
        stores.api.searchByPhoto(bytes: _smallJpeg(), contentType: 'image/jpeg'),
        throwsA(isA<PhotoSearchFailure>()
            .having((PhotoSearchFailure f) => f.code, 'code', PhotoSearchFailure.searchLimit)
            .having((PhotoSearchFailure f) => f.isLimit, 'isLimit', isTrue)
            .having((PhotoSearchFailure f) => f.limit, 'limit', 10)
            .having((PhotoSearchFailure f) => f.scope, 'scope', PhotoSearchFailure.scopeDay)
            .having((PhotoSearchFailure f) => f.retryAfterSeconds, 'wait', 3600)),
      );
    });

    test('an unavailable reader is its own failure; a server error stays a Dio error', () async {
      final ({StoreApi api, _Server server}) off = _stores(
          (_) => <String, dynamic>{'code': 'PHOTO_SEARCH_UNAVAILABLE'},
          status: 503);
      await expectLater(
        off.api.searchByPhoto(bytes: _smallJpeg(), contentType: 'image/jpeg'),
        throwsA(isA<PhotoSearchFailure>()
            .having((PhotoSearchFailure f) => f.code, 'code', PhotoSearchFailure.unavailable)),
      );

      final ({StoreApi api, _Server server}) broken = _stores(
          (_) => <String, dynamic>{'title': 'Internal error'},
          status: 500);
      await expectLater(
        broken.api.searchByPhoto(bytes: _smallJpeg(), contentType: 'image/jpeg'),
        throwsA(isA<DioException>()),
      );
    });
  });

  group("a merchant's find by photo", () {
    ({CatalogApi api, _Server server}) catalogue(Object? Function(RequestOptions options) answer,
        {int status = 200}) {
      final _Server server = _Server(answer, status: status);
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway.test'))..httpClientAdapter = server;
      return (api: CatalogApi(dio), server: server);
    }

    /// An answer as `PhotoFindController` writes it: one match the merchant already has.
    Map<String, dynamic> findAnswer({bool sample = false, bool isProduct = true}) =>
        <String, dynamic>{
          'provider': sample ? 'FAKE' : 'CLAUDE',
          'sample': sample,
          'understood': isProduct
              ? <String, dynamic>{'name': 'Pepsi 1L', 'nameAr': 'بيبسي', 'isProduct': true}
              : <String, dynamic>{'isProduct': false},
          'matches': <Object?>[
            <String, dynamic>{
              'product': <String, dynamic>{
                'id': 'p1',
                'merchantId': 'merchant-1',
                'storeId': 'shop-1',
                'name': 'Pepsi 1 litre',
                'price': 1.25,
                'status': 'ARCHIVED',
                'barcode': '5449000000996',
                'inStock': true,
              },
              'matchedBy': 'BARCODE',
            },
          ],
          'suggestion': <String, dynamic>{
            'name': 'Pepsi 1L',
            'barcode': null,
            'categoryId': 'cat-drinks',
          },
          'findsLeftToday': 29,
        };

    test('sends the photo and the shop as a multipart form', () async {
      final ({CatalogApi api, _Server server}) shop = catalogue((_) => findAnswer());

      await shop.api
          .findByPhoto(bytes: _smallJpeg(), contentType: 'image/jpeg', storeId: 'shop-1');

      final RequestOptions sent = shop.server.requests.single;
      expect(sent.method, 'POST');
      expect(sent.path, '/api/products/mine/find-by-photo');
      expect(sent.contentType, startsWith('multipart/form-data'));
      expect(sent.sendTimeout, const Duration(seconds: 45));
      final String body = shop.server.bodies.single;
      expect(body, contains('name="photo"'));
      expect(body.toLowerCase(), contains('content-type: image/jpeg'));
      expect(body, contains('name="storeId"'));
      expect(body, contains('shop-1'));
    });

    test('reads the matches, how each matched, and what a new product would start from', () async {
      final ({CatalogApi api, _Server server}) shop = catalogue((_) => findAnswer());

      final PhotoFindResult result =
          await shop.api.findByPhoto(bytes: _smallJpeg(), contentType: 'image/jpeg');

      expect(result.provider, 'CLAUDE');
      expect(result.sample, isFalse);
      expect(result.understood.label, 'Pepsi 1L');
      expect(result.matches.single.product.name, 'Pepsi 1 litre');
      expect(result.matches.single.product.status, ProductStatus.archived);
      expect(result.matches.single.isBarcodeMatch, isTrue);
      expect(result.suggestion!.name, 'Pepsi 1L');
      expect(result.suggestion!.barcode, isNull);
      expect(result.suggestion!.categoryId, 'cat-drinks');
      expect(result.findsLeftToday, 29);
    });

    test('a sample answer says which reader gave it', () async {
      final ({CatalogApi api, _Server server}) shop = catalogue((_) => findAnswer(sample: true));

      final PhotoFindResult result =
          await shop.api.findByPhoto(bytes: _smallJpeg(), contentType: 'image/jpeg');

      expect(result.sample, isTrue);
      expect(result.provider, 'FAKE');
    });

    test("the merchant's own limit arrives as a failure of its own", () async {
      final ({CatalogApi api, _Server server}) shop = catalogue(
          (_) => <String, dynamic>{
                'code': 'PHOTO_FIND_LIMIT',
                'limit': 30,
                'scope': 'DAY',
                'retryAfterSeconds': 900,
              },
          status: 429);

      await expectLater(
        shop.api.findByPhoto(bytes: _smallJpeg(), contentType: 'image/jpeg'),
        throwsA(isA<PhotoSearchFailure>()
            .having((PhotoSearchFailure f) => f.code, 'code', PhotoSearchFailure.findLimit)
            .having((PhotoSearchFailure f) => f.isLimit, 'isLimit', isTrue)
            .having((PhotoSearchFailure f) => f.limit, 'limit', 30)),
      );
    });
  });

  group('what photo search the app may offer', () {
    test('reads photoSearch, what is left today and the largest photo', () async {
      final ({StoreApi api, _Server server}) stores = _stores((_) => <String, dynamic>{
            'photoSearch': true,
            'photosLeftToday': 8,
            'maxPhotoBytes': 2097152,
          });

      final PhotoSearchCapabilities capabilities = await stores.api.photoCapabilities();

      expect(stores.server.requests.single.path, '/api/products/search/capabilities');
      expect(capabilities.photoSearch, isTrue);
      expect(capabilities.photosLeftToday, 8);
      expect(capabilities.maxPhotoBytes, 2097152);
    });

    test('an answer it cannot read offers nothing', () async {
      final ({StoreApi api, _Server server}) stores = _stores((_) => <String, dynamic>{});

      expect((await stores.api.photoCapabilities()).photoSearch, isFalse);
    });
  });
}
