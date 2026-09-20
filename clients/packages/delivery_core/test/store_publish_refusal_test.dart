import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Listing a shop, and the two ways the server says it is not ready.
///
/// `POST /api/stores/{id}/publish` answers 422 with a `code` when a shop has no opening hours or no
/// map pin. The code is the point: both Publish controls used to scrape the RFC-7807 `detail` out
/// of the stringified exception with a regular expression and show the server's English, which told
/// an Arabic-reading merchant nothing and gave neither screen a way to tell the two rules apart —
/// so neither could offer the right fix, and a shop went live with no coordinates instead.
///
/// Pinned here: a refusal becomes [StoreNotListable] carrying the code, the detail survives as a
/// fallback for a code this app does not know, and anything that is NOT a listing rule stays the
/// Dio error it is. That last one matters: a timeout is something to try again, and turning it into
/// "your shop is not ready" would be a lie about the merchant's shop.
void main() {
  late List<RequestOptions> requests;

  StoreApi serve({required int status, Object? body}) {
    requests = <RequestOptions>[];
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        requests.add(options);
        final Response<dynamic> response =
            Response<dynamic>(requestOptions: options, statusCode: status, data: body);
        if (status >= 400) {
          handler.reject(DioException.badResponse(
              statusCode: status, requestOptions: options, response: response));
          return;
        }
        handler.resolve(response);
      },
    ));
    return StoreApi(dio);
  }

  Map<String, dynamic> refusal(String code, String detail) => <String, dynamic>{
        'title': 'Shop not ready to be listed',
        'status': 422,
        'detail': detail,
        'code': code,
      };

  test('a shop with no pin is refused with the pin named', () async {
    final StoreApi api = serve(
      status: 422,
      body: refusal(StoreNotListable.pinRequired, 'This shop has no location on the map yet.'),
    );

    await expectLater(
      api.publish('store-1'),
      throwsA(isA<StoreNotListable>()
          .having((StoreNotListable e) => e.code, 'code', StoreNotListable.pinRequired)
          .having((StoreNotListable e) => e.detail, 'detail', contains('map'))),
    );

    final RequestOptions sent = requests.single;
    expect(sent.method, 'POST');
    expect(sent.path, '/api/stores/store-1/publish');
  });

  test('a shop with no opening hours is refused with the hours named', () async {
    final StoreApi api = serve(
      status: 422,
      body: refusal(StoreNotListable.hoursRequired, 'This shop has no opening hours yet.'),
    );

    await expectLater(
      api.publish('store-1'),
      throwsA(isA<StoreNotListable>()
          .having((StoreNotListable e) => e.code, 'code', StoreNotListable.hoursRequired)),
    );
  });

  /// A newer server's rule. The code is carried through unchanged so a screen can fall back to a
  /// general sentence of its own rather than to the server's English.
  test('a code this app does not know still arrives as a refusal', () async {
    final StoreApi api = serve(
      status: 422,
      body: refusal('STORE_PAYOUT_ACCOUNT_REQUIRED', 'This shop has no payout account yet.'),
    );

    await expectLater(
      api.publish('store-1'),
      throwsA(isA<StoreNotListable>().having(
          (StoreNotListable e) => e.code, 'code', 'STORE_PAYOUT_ACCOUNT_REQUIRED')),
    );
  });

  test('a 422 that is not a listing rule is left as the Dio error it is', () async {
    final StoreApi api = serve(
      status: 422,
      body: <String, dynamic>{'title': 'Catalog rule violated', 'detail': 'Something else'},
    );

    await expectLater(api.publish('store-1'), throwsA(isA<DioException>()));
  });

  test('a timeout is not a shop that is not ready', () async {
    final StoreApi api = serve(status: 503, body: <String, dynamic>{'code': 'STORE_PIN_REQUIRED'});

    // 503 with a store-ish code is still not a refusal: only the 422 is the rule.
    await expectLater(api.publish('store-1'), throwsA(isA<DioException>()));
  });

  test('a shop that lists comes back as the server now holds it', () async {
    final StoreApi api = serve(status: 200, body: <String, dynamic>{
      'id': 'store-1',
      'slug': 'falafel-king',
      'name': 'Falafel King',
      'vertical': 'RESTAURANT',
      'status': 'ACTIVE',
      'availability': 'OPEN',
      'latitude': 33.8938,
      'longitude': 35.5018,
    });

    final Store store = await api.publish('store-1');

    expect(store.status, StoreListingStatus.active);
    expect(store.latitude, 33.8938);
    expect(store.longitude, 35.5018);
  });
}
