import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Back office's Verified Local switch, on the client: `PUT /api/stores/{id}/verified-local`.
///
/// Pinned: the request is exactly the server's (a PUT with `{verified}` and nothing else — who acts
/// is the token's to say), the store comes back as the server now holds it, a service shop in draft
/// reads back as itself rather than as a listed restaurant, and a refusal is not swallowed.
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

  Map<String, dynamic> shop({required bool verified}) => <String, dynamic>{
        'id': 'store-1',
        'slug': 'print-point',
        'name': 'Print Point',
        'vertical': 'SERVICES',
        'serviceCategory': 'PRINTING',
        'status': 'DRAFT',
        'verifiedLocal': verified,
      };

  test('grants the badge with a PUT carrying only the switch, and reads back the stored store',
      () async {
    final Store store = await serve(status: 200, body: shop(verified: true))
        .setVerifiedLocal('store-1', verified: true);

    final RequestOptions sent = requests.single;
    expect(sent.method, 'PUT');
    expect(sent.path, '/api/stores/store-1/verified-local');
    expect(sent.data, <String, dynamic>{'verified': true});

    expect(store.verifiedLocal, isTrue);
    // A service shop in draft is badged like any shop, and reads back as the shop it is.
    expect(store.vertical, StoreVertical.services);
    expect(store.serviceCategory, ServiceCategory.printing);
    expect(store.status, StoreListingStatus.draft);
  });

  test('withdraws the badge with verified false', () async {
    final Store store = await serve(status: 200, body: shop(verified: false))
        .setVerifiedLocal('store-1', verified: false);

    expect(requests.single.data, <String, dynamic>{'verified': false});
    expect(store.verifiedLocal, isFalse);
  });

  test('a refusal reaches the caller as the 403 it is', () async {
    final StoreApi api =
        serve(status: 403, body: <String, dynamic>{'title': 'Forbidden', 'status': 403});

    await expectLater(
      api.setVerifiedLocal('store-1', verified: true),
      throwsA(isA<DioException>()
          .having((DioException e) => e.response?.statusCode, 'status', 403)),
    );
  });
}
