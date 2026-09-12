import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/offline_catalog.dart';
import 'package:mobile_app/src/offline_store.dart';

/// The offline shelf (Figma 121:279's "Your Last Cached Purchases"): what it saves while the phone
/// can reach YouDrop, and what it keeps when it cannot.
///
/// Wrong in one direction, the shelf offers something the shop no longer sells or a Quick Add that
/// bounces when the connection returns; wrong in the other, a failed refresh wipes the one thing an
/// offline customer could still read.
void main() {
  const String owner = 'customer-1';
  final DateTime noon = DateTime.utc(2026, 9, 12, 12);

  Map<String, dynamic> line(String productId, String name, double price) => <String, dynamic>{
        'productId': productId,
        'productName': name,
        'unitPrice': price,
        'qty': 1,
        'lineTotal': price,
      };

  Map<String, dynamic> order(String id, String storeId, List<Map<String, dynamic>> items) =>
      <String, dynamic>{
        'id': id,
        'customerId': owner,
        'merchantId': 'm-$storeId',
        'riderId': null,
        'status': 'DELIVERED',
        'totalAmount': 10,
        'deliveryAddress': '12 Rose Street',
        'paymentMethod': 'CASH',
        'paymentStatus': 'PAID',
        'storeId': storeId,
        'storeName': 'Shop $storeId',
        'items': items,
        'availableActions': <dynamic>[],
      };

  Map<String, dynamic> product(String id, String name, double price) => <String, dynamic>{
        'id': id,
        'merchantId': 'm-s1',
        'storeId': 's1',
        'name': name,
        'price': price,
        'status': 'ACTIVE',
      };

  Map<String, dynamic> page(List<Map<String, dynamic>> content) => <String, dynamic>{
        'content': content,
        'page': 0,
        'totalElements': content.length,
        'totalPages': 1,
      };

  /// The platform as the shelf reads it. The customer's latest order is from s1 (man'oushe and a
  /// knefe that comes in sizes); an older one is from another shop and must not mix in.
  Map<String, Object> platform() => <String, Object>{
        '/api/orders/mine': page(<Map<String, dynamic>>[
          order('o2', 's1', <Map<String, dynamic>>[
            line('p1', "Fresh Man'oushe", 1.20),
            line('p2', 'Knefe Kaak', 3.50),
          ]),
          order('o1', 's9', <Map<String, dynamic>>[line('p9', 'Elsewhere', 9)]),
        ]),
        '/api/stores/s1/products': page(<Map<String, dynamic>>[
          product('p1', "Fresh Man'oushe", 1.20),
          product('p2', 'Knefe Kaak', 3.50),
        ]),
        '/api/stores/s1': <String, dynamic>{
          'id': 's1',
          'slug': 'dekkane-abou-selim',
          'name': 'Dekkane Abou Selim',
          'availability': 'OPEN',
          'deliveryFee': 2,
          'minOrder': 0,
        },
        '/api/products/p1/options': const <dynamic>[],
        '/api/products/p2/options': <dynamic>[
          <String, dynamic>{
            'id': 'size',
            'name': 'Size',
            'options': <dynamic>[
              <String, dynamic>{'id': 'large', 'name': 'Large', 'priceDelta': 1},
            ],
          },
        ],
      };

  /// Answers GETs from [answers]; anything missing is a 404. [down] makes every request fail the
  /// way a dropped connection does. Records every path asked for.
  ({OrderApi orders, StoreApi stores, List<String> asked, void Function(bool) setDown}) serve(
      Map<String, Object> answers) {
    final List<String> asked = <String>[];
    bool down = false;
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway.test'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) {
        asked.add(o.path);
        if (down) {
          h.reject(DioException(requestOptions: o, type: DioExceptionType.connectionError));
          return;
        }
        final Object? body = answers[o.path];
        if (body == null) {
          h.reject(DioException(
            requestOptions: o,
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(requestOptions: o, statusCode: 404),
          ));
          return;
        }
        h.resolve(Response<dynamic>(requestOptions: o, statusCode: 200, data: body));
      },
    ));
    return (
      orders: OrderApi(dio),
      stores: StoreApi(dio),
      asked: asked,
      setDown: (bool value) => down = value,
    );
  }

  test('saves what was last bought at the last shop, with its prices, whether each needs a '
      'choice, and when — and a restart reads it back', () async {
    final _MemoryStore store = _MemoryStore();
    final server = serve(platform());
    final OfflineCatalog catalog = OfflineCatalog(store: store, ownerId: owner, now: () => noon);

    await catalog.refresh(orders: server.orders, stores: server.stores);

    expect(catalog.store?.name, 'Dekkane Abou Selim');
    expect(catalog.savedAt, noon);
    expect(catalog.products.map((CachedProduct p) => p.product.name),
        <String>["Fresh Man'oushe", 'Knefe Kaak']);
    expect(catalog.products[0].product.price, 1.20);
    expect(catalog.products[0].canQuickAdd, isTrue);
    // Sizes are priced by the live catalog, so the knefe cannot be added without a connection.
    expect(catalog.products[1].canQuickAdd, isFalse);
    expect(catalog.products.any((CachedProduct p) => p.product.id == 'p9'), isFalse);

    final OfflineCatalog afterRestart = OfflineCatalog(store: store, ownerId: owner);
    await afterRestart.load();

    expect(afterRestart.store?.id, 's1');
    expect(afterRestart.store?.deliveryFee, 2);
    expect(afterRestart.savedAt, noon);
    expect(afterRestart.products.map((CachedProduct p) => (p.product.id, p.canQuickAdd)),
        <(String, bool)>[('p1', true), ('p2', false)]);
  });

  test('something the shop has stopped selling is not offered', () async {
    final Map<String, Object> answers = platform()
      ..['/api/stores/s1/products'] =
          page(<Map<String, dynamic>>[product('p1', "Fresh Man'oushe", 1.20)]);
    final server = serve(answers);
    final OfflineCatalog catalog = OfflineCatalog(store: _MemoryStore(), ownerId: owner);

    await catalog.refresh(orders: server.orders, stores: server.stores);

    expect(catalog.products.map((CachedProduct p) => p.product.id), <String>['p1']);
  });

  test('a product whose options could not be read counts as needing a choice', () async {
    final Map<String, Object> answers = platform()..remove('/api/products/p1/options');
    final server = serve(answers);
    final OfflineCatalog catalog = OfflineCatalog(store: _MemoryStore(), ownerId: owner);

    await catalog.refresh(orders: server.orders, stores: server.stores);

    expect(catalog.products.first.hasOptions, isNull);
    expect(catalog.products.first.canQuickAdd, isFalse);
  });

  test('a refresh that fails keeps the shelf it had', () async {
    DateTime clock = noon;
    final _MemoryStore store = _MemoryStore();
    final server = serve(platform());
    final OfflineCatalog catalog = OfflineCatalog(store: store, ownerId: owner, now: () => clock);
    await catalog.refresh(orders: server.orders, stores: server.stores);
    final String saved = store.values.values.single;

    clock = noon.add(const Duration(hours: 1));
    server.setDown(true);
    await catalog.refresh(orders: server.orders, stores: server.stores, force: true);

    expect(catalog.products, hasLength(2));
    expect(catalog.savedAt, noon);
    expect(store.values.values.single, saved);
  });

  test('a shelf saved moments ago is not re-read on every start, unless asked', () async {
    final _MemoryStore store = _MemoryStore();
    final server = serve(platform());
    await OfflineCatalog(store: store, ownerId: owner, now: () => noon)
        .refresh(orders: server.orders, stores: server.stores);
    server.asked.clear();

    final OfflineCatalog nextStart = OfflineCatalog(
        store: store, ownerId: owner, now: () => noon.add(const Duration(minutes: 1)));
    await nextStart.load();
    await nextStart.refresh(orders: server.orders, stores: server.stores);
    expect(server.asked, isEmpty);

    await nextStart.refresh(orders: server.orders, stores: server.stores, force: true);
    expect(server.asked, contains('/api/orders/mine'));
  });

  test('another account on the same phone does not see it', () async {
    final _MemoryStore store = _MemoryStore();
    final server = serve(platform());
    await OfflineCatalog(store: store, ownerId: owner)
        .refresh(orders: server.orders, stores: server.stores);

    final OfflineCatalog theirs = OfflineCatalog(store: store, ownerId: 'customer-2');
    await theirs.load();

    expect(theirs.isEmpty, isTrue);
    expect(theirs.store, isNull);
  });
}

class _MemoryStore implements OfflineStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
