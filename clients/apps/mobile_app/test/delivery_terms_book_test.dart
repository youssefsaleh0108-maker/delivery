import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/delivery_terms_book.dart';
import 'package:mobile_app/src/offline_store.dart';

/// The delivery fees a checkout asserts when the phone cannot ask: exactly what the platform last
/// said for that shop and area, kept across a restart, and never invented.
void main() {
  const String owner = 'customer-1';

  /// Product Service's terms endpoint, answered in-process — or not answered at all.
  ({DeliveryZoneApi api, List<RequestOptions> asked}) platform({double fee = 0, bool reachable = true}) {
    final List<RequestOptions> asked = <RequestOptions>[];
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway.test'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) {
        asked.add(o);
        if (!reachable) {
          h.reject(DioException(requestOptions: o, type: DioExceptionType.connectionError));
          return;
        }
        h.resolve(Response<dynamic>(requestOptions: o, statusCode: 200, data: <String, dynamic>{
          'storeId': 's1',
          'served': true,
          'deliveryFee': fee,
          'minOrder': 0,
          'etaMinMinutes': 20,
          'etaMaxMinutes': 35,
        }));
      },
    ));
    return (api: DeliveryZoneApi(dio), asked: asked);
  }

  test('asks for the shop\'s fee to that area exactly as Order Manager does at placement',
      () async {
    final p = platform(fee: 3.5);
    final DeliveryTermsBook book =
        DeliveryTermsBook(api: p.api, store: _MemoryStore(), ownerId: owner);

    final ZoneTerms? terms = await book.learn('s1', 'zone-hamra');

    expect(terms?.deliveryFee, 3.5);
    expect(p.asked.single.path, '/api/delivery-zones/terms/s1');
    expect(p.asked.single.queryParameters['zoneId'], 'zone-hamra');
    expect(book.known('s1', 'zone-hamra')?.deliveryFee, 3.5);
  });

  test('keeps the answer across a restart, for a checkout that finds itself offline — and knows '
      'nothing it was never told', () async {
    final _MemoryStore store = _MemoryStore();
    await DeliveryTermsBook(api: platform(fee: 3.5).api, store: store, ownerId: owner)
        .learn('s1', 'zone-hamra');

    final DeliveryTermsBook afterRestart =
        DeliveryTermsBook(api: platform(reachable: false).api, store: store, ownerId: owner);
    await afterRestart.load();

    expect(afterRestart.known('s1', 'zone-hamra')?.deliveryFee, 3.5);
    // Unreachable: the last answer stands, rather than nothing.
    expect((await afterRestart.learn('s1', 'zone-hamra'))?.deliveryFee, 3.5);
    // Never asked: unknown, rather than a guess.
    expect(await afterRestart.learn('s1', 'zone-verdun'), isNull);
  });

  test('asks once while its answer is fresh, however many screens want it', () async {
    final p = platform(fee: 2);
    final DeliveryTermsBook book =
        DeliveryTermsBook(api: p.api, store: _MemoryStore(), ownerId: owner);

    await Future.wait(<Future<ZoneTerms?>>[
      book.learn('s1', 'zone-hamra'),
      book.learn('s1', 'zone-hamra'),
    ]);
    await book.learn('s1', 'zone-hamra');

    expect(p.asked, hasLength(1));
  });

  test('another account on the same phone does not read it', () async {
    final _MemoryStore store = _MemoryStore();
    await DeliveryTermsBook(api: platform(fee: 3.5).api, store: store, ownerId: owner)
        .learn('s1', 'zone-hamra');

    final DeliveryTermsBook theirs =
        DeliveryTermsBook(api: platform(reachable: false).api, store: store, ownerId: 'customer-2');
    await theirs.load();

    expect(theirs.known('s1', 'zone-hamra'), isNull);
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
