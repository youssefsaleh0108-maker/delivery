import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real connection to a deployed environment, for the portal tests that are about business flow
/// rather than about pixels.
///
/// <p><strong>Why this exists alongside the stubbed tests.</strong> Every existing portal test
/// drives its screen through a replaced `HttpClientAdapter` and a hand-written JSON blob. That is
/// the right shape for asking "does this screen lie about what the server said" — and it is
/// structurally incapable of answering "does the server actually say it". A portal that renders a
/// beautiful, correct, empty orders ledger passes all of them.
///
/// <p>These tests place a real order on a real environment and then ask the real screen whether it
/// can see it. Opt in explicitly, because they need the network and they write data:
///
/// ```
/// flutter test test/live --dart-define=LIVE_BACKEND=true \
///   --dart-define=API_BASE_URL=https://api-dev.youdrop.shop \
///   --dart-define=KEYCLOAK_ISSUER=https://iam-dev.youdrop.shop/realms/delivery-platform
/// ```
class Live {
  Live._();

  /// The switch. Without it every live test skips, so `flutter test` stays offline and fast.
  static const bool enabled = bool.fromEnvironment('LIVE_BACKEND');

  static const String apiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'https://api-dev.youdrop.shop');
  static const String issuer = String.fromEnvironment(
    'KEYCLOAK_ISSUER',
    defaultValue: 'https://iam-dev.youdrop.shop/realms/delivery-platform',
  );

  static const Map<String, String> _passwords = <String, String>{
    'customer': '100001',
    'merchant': '200002',
    'rider': '300003',
    'backoffice': '400004',
  };

  /// `flutter test` installs an [HttpOverrides] that answers every request with a 400, so that a
  /// unit test cannot silently depend on the network. These tests depend on it on purpose, and
  /// this is the documented way to say so. Call it once, in `setUpAll`.
  static void allowRealNetwork() => HttpOverrides.global = null;

  static Future<String> signIn(String user) async {
    final String client = user == 'backoffice' ? 'delivery-portal' : 'mobile-app';
    final Response<dynamic> res = await Dio().postUri<dynamic>(
      Uri.parse('$issuer/protocol/openid-connect/token'),
      data: 'client_id=$client&username=$user&password=${_passwords[user]}&grant_type=password',
      options: Options(
        contentType: 'application/x-www-form-urlencoded',
        validateStatus: (int? c) => true,
      ),
    );
    if (res.statusCode != 200) {
      fail('Signing in as $user against $issuer failed: HTTP ${res.statusCode} ${res.data}');
    }
    return (res.data as Map<String, dynamic>)['access_token'] as String;
  }

  /// A Dio the real API clients can be built on, carrying one account's bearer token.
  ///
  /// Deliberately not `ApiClient.create`: that wires an `AuthService`, which on a test host means
  /// secure storage and an OIDC client the password grant does not need. The interceptor's job —
  /// putting the token on every request — is one line here.
  static Dio dioFor(String token) => Dio(BaseOptions(
        baseUrl: apiBaseUrl,
        headers: <String, String>{'Authorization': 'Bearer $token'},
        validateStatus: (int? c) => c != null && c < 500,
      ));

  static Future<dynamic> call(
    Dio dio,
    String method,
    String path, {
    Object? body,
  }) async {
    final Response<dynamic> res = await dio.requestUri<dynamic>(
      Uri.parse('$apiBaseUrl$path'),
      data: body,
      options: Options(method: method, contentType: body == null ? null : 'application/json'),
    );
    if (res.statusCode! >= 400) {
      fail('$method $path failed: HTTP ${res.statusCode} ${jsonEncode(res.data)}');
    }
    return res.data;
  }

  /// Poll until [attempt] returns non-null. Settlement and dispatch are asynchronous; a screen
  /// asserted immediately after an action is asserted into a race.
  static Future<T?> waitFor<T>(
    Future<T?> Function() attempt, {
    Duration timeout = const Duration(seconds: 60),
    Duration every = const Duration(seconds: 2),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final T? value = await attempt();
      if (value != null) return value;
      await Future<void>.delayed(every);
    }
    return null;
  }
}

/// Putting one real order on a real environment, so a portal screen has something true to show.
///
/// The shop has to be the demo merchant's OWN — `order.merchantId` is copied from the product's
/// creator and the merchant queue is a bare equality on it, so an order placed against a seeded
/// storefront shop can never be accepted and never reaches DELIVERED.
extension LiveOrders on Live {
  /// A 1x1 PNG: publishing refuses a product with no image, and the rule is "at least one".
  static final List<int> _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  static Future<Map<String, dynamic>> merchantStore(Dio merchant) async {
    final dynamic body = await Live.call(merchant, 'GET', '/api/stores/mine');
    final List<dynamic> shops = (body as Map<String, dynamic>)['content'] as List<dynamic>;
    if (shops.isEmpty) fail('The demo merchant owns no shop, so nothing can be sold.');
    return shops.first as Map<String, dynamic>;
  }

  /// Create → attach an image → publish, which is the whole business rule for getting an item in
  /// front of a customer.
  static Future<Map<String, dynamic>> sellableProduct(
    Dio merchant,
    Dio customer,
    String storeId,
    String name,
  ) async {
    final Map<String, dynamic> created = (await Live.call(
      merchant,
      'POST',
      '/api/products',
      body: <String, Object>{'name': name, 'price': 8.25, 'storeId': storeId},
    )) as Map<String, dynamic>;
    final String id = created['id'] as String;

    final Map<String, dynamic> slot = (await Live.call(
      merchant,
      'POST',
      '/api/products/$id/images/presign',
      body: <String, String>{'contentType': 'image/png'},
    )) as Map<String, dynamic>;

    // Straight to object storage on a presigned URL, with an explicit Content-Length — MinIO
    // answers 411 without one.
    await Dio().putUri<dynamic>(
      Uri.parse(slot['uploadUrl'] as String),
      data: Stream<List<int>>.value(_png),
      options: Options(
        headers: <String, Object>{
          Headers.contentLengthHeader: _png.length,
          Headers.contentTypeHeader: 'image/png',
        },
        validateStatus: (int? c) => true,
      ),
    );
    await Live.call(merchant, 'POST', '/api/products/$id/images/${slot['fileId']}/confirm');
    await Live.call(merchant, 'POST', '/api/products/$id/publish');

    final dynamic seen = await Live.call(customer, 'GET', '/api/stores/$storeId/products?size=100');
    final List<dynamic> visible = (seen as Map<String, dynamic>)['content'] as List<dynamic>;
    if (!visible.any((dynamic p) => (p as Map<String, dynamic>)['id'] == id)) {
      fail('"$name" was published but a customer browsing the shop cannot see it.');
    }
    return created;
  }

  static Future<Map<String, dynamic>> place(
    Dio customer,
    String productId,
    String address,
  ) async =>
      (await Live.call(customer, 'POST', '/api/orders', body: <String, Object>{
        'items': <Map<String, Object>>[
          <String, Object>{'productId': productId, 'qty': 1},
        ],
        'deliveryAddress': address,
        'contactPhone': '+96170123456',
        'paymentMethod': 'CASH',
      })) as Map<String, dynamic>;

  static Future<void> advance(Dio who, String orderId, List<String> actions) async {
    for (final String action in actions) {
      await Live.call(who, 'POST', '/api/orders/$orderId/$action');
    }
  }
}
