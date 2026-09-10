import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The preconditions a business-flow scenario needs, arranged over HTTP before the app is driven.
///
/// <p><strong>Why a scenario arranges its own world.</strong> A test that drives a real purchase
/// needs something to buy, a shop the merchant is actually allowed to accept orders for, and a
/// rider who can see the job when it is ready. None of that is guaranteed on a shared environment:
/// the demo merchant's own shop starts with zero products, and the demo rider's fleet membership
/// is left behind by whichever suite ran last. Arranging it here — rather than assuming it — is
/// the difference between a red run that means "the app is broken" and one that means "somebody
/// else's test ran before mine".
///
/// <p><strong>What is deliberately NOT done here.</strong> Nothing in the flow under test. The
/// purchase, the merchant's accept/prepare/ready, the rider's claim/pick-up/deliver — every step a
/// human performs — happens through the UI, in the test, or it is not tested at all. This file
/// only puts the world in a known state and reads it back afterwards to corroborate what the
/// screens claimed.
///
/// <p>The base URLs are read from the SAME `--dart-define`s the app reads, so a scenario can never
/// arrange fixtures on one backend while the app under test talks to another.
class Backend {
  Backend._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.10.24:8100',
  );
  static const String issuer = String.fromEnvironment(
    'KEYCLOAK_ISSUER',
    defaultValue: 'http://192.168.10.24:8180/realms/delivery-platform',
  );

  /// The demo accounts, and the client each one signs in through.
  ///
  /// Backoffice is the odd one out: it authenticates against `delivery-portal` rather than
  /// `mobile-app`, which is how the portal is separated from the phone app.
  static const Map<String, String> _passwords = <String, String>{
    'customer': '100001',
    'merchant': '200002',
    'rider': '300003',
    'backoffice': '400004',
    'carrier': '500005',
  };

  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);

  // ---------------------------------------------------------------- plumbing

  static Future<_Res> _send(
    String method,
    String url, {
    String? token,
    Object? json,
    String? form,
  }) async {
    final HttpClientRequest req = await _http.openUrl(method, Uri.parse(url));
    if (token != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (json != null) {
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(json)));
    } else if (form != null) {
      req.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      req.add(utf8.encode(form));
    }
    final HttpClientResponse res = await req.close();
    final String body = await res.transform(utf8.decoder).join();
    return _Res(res.statusCode, body);
  }

  static Future<_Res> _api(String method, String path, String token, {Object? json}) =>
      _send(method, '$apiBaseUrl$path', token: token, json: json);

  static Never _fail(String what, _Res res) =>
      throw StateError('$what failed: HTTP ${res.code} ${res.body}');

  // ---------------------------------------------------------------- identity

  /// A bearer token for one demo account, from the same realm the app signs in against.
  static Future<String> signIn(String user) async {
    final String client = user == 'backoffice' ? 'delivery-portal' : 'mobile-app';
    final _Res res = await _send(
      'POST',
      '$issuer/protocol/openid-connect/token',
      form: 'client_id=$client&username=$user&password=${_passwords[user]}&grant_type=password',
    );
    if (res.code != 200) _fail('signing in as $user', res);
    return (jsonDecode(res.body) as Map<String, dynamic>)['access_token'] as String;
  }

  /// The `sub` claim, which is the id every service knows this person by.
  static String subjectOf(String token) {
    final String payload = token.split('.')[1];
    final String padded = payload.padRight((payload.length + 3) ~/ 4 * 4, '=');
    return (jsonDecode(utf8.decode(base64Url.decode(padded))) as Map<String, dynamic>)['sub']
        as String;
  }

  // ---------------------------------------------------------------- the shop and its goods

  /// The shop the demo merchant actually owns.
  ///
  /// This matters more than it looks. The seeded storefront shops belong to a synthetic
  /// `demo-merchant`, so an order placed against one of those can never be accepted by the
  /// merchant who signs in on the phone — the lifecycle would stall on step one for a reason that
  /// has nothing to do with the app.
  static Future<Map<String, dynamic>> merchantStore(String merchantToken) async {
    final _Res res = await _api('GET', '/api/stores/mine', merchantToken);
    if (res.code != 200) _fail('reading the merchant shops', res);
    final List<dynamic> shops =
        (jsonDecode(res.body) as Map<String, dynamic>)['content'] as List<dynamic>;
    if (shops.isEmpty) throw StateError('The demo merchant owns no shop, so nothing can be sold.');
    return (shops.firstWhere(
      (dynamic s) => (s as Map<String, dynamic>)['availability'] != 'CLOSED',
      orElse: () => shops.first,
    )) as Map<String, dynamic>;
  }

  /// A product a customer can actually find and buy, created if the shop has none.
  ///
  /// <p>Getting an item onto the storefront is a three-step business rule, not one call: a new
  /// product is DRAFT, publishing it is refused with "A product needs at least one image before it
  /// can be published", and the image itself goes up through presign → PUT → confirm. All three
  /// are exercised here, so a break anywhere in that chain surfaces as a clear fixture error
  /// rather than as an empty shop three screens into a UI test.
  ///
  /// Returns the product as the customer will see it, including the [name] the test must tap.
  static Future<Map<String, dynamic>> ensureSellableProduct(
    String merchantToken,
    String customerToken,
    Map<String, dynamic> store, {
    required String name,
    double price = 9.75,
  }) async {
    final String storeId = store['id'] as String;

    Future<List<dynamic>> visible() async {
      final _Res res = await _api('GET', '/api/stores/$storeId/products?size=100', customerToken);
      if (res.code != 200) _fail('browsing the shop', res);
      return (jsonDecode(res.body) as Map<String, dynamic>)['content'] as List<dynamic>;
    }

    final List<dynamic> already = await visible();
    for (final dynamic p in already) {
      if ((p as Map<String, dynamic>)['name'] == name) return p;
    }

    final _Res created = await _api('POST', '/api/products', merchantToken, json: <String, Object>{
      'name': name,
      'description': 'Fixture for a business-flow scenario.',
      'price': price,
      'storeId': storeId,
    });
    if (created.code != 200 && created.code != 201) _fail('creating a product', created);
    final Map<String, dynamic> product = jsonDecode(created.body) as Map<String, dynamic>;
    final String id = product['id'] as String;

    await _attachAnImage(merchantToken, id);

    final _Res published = await _api('POST', '/api/products/$id/publish', merchantToken);
    if (published.code != 200) _fail('publishing the product', published);

    for (final dynamic p in await visible()) {
      if ((p as Map<String, dynamic>)['id'] == id) return p;
    }
    throw StateError('Published "$name" is still invisible to a customer browsing the shop.');
  }

  /// presign → PUT the bytes → confirm, which is what the merchant app does behind its image picker.
  static Future<void> _attachAnImage(String merchantToken, String productId) async {
    final _Res pre = await _api(
      'POST',
      '/api/products/$productId/images/presign',
      merchantToken,
      json: <String, String>{'contentType': 'image/png'},
    );
    if (pre.code != 201) _fail('asking for an upload URL', pre);
    final Map<String, dynamic> slot = jsonDecode(pre.body) as Map<String, dynamic>;

    final HttpClientRequest put =
        await _http.openUrl('PUT', Uri.parse(slot['uploadUrl'] as String));
    put.headers.contentType = ContentType('image', 'png');
    // MinIO refuses a presigned PUT with no Content-Length (411). HttpClient does not infer one
    // from the body the way package:http or fetch would, so it is set explicitly.
    put.contentLength = _onePixelPng.length;
    put.add(_onePixelPng);
    final HttpClientResponse res = await put.close();
    await res.drain<void>();
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw StateError('Uploading the image returned HTTP ${res.statusCode}.');
    }

    final _Res confirmed = await _api(
      'POST',
      '/api/products/$productId/images/${slot['fileId']}/confirm',
      merchantToken,
    );
    if (confirmed.code != 204) _fail('confirming the upload', confirmed);
  }

  /// The smallest thing that is genuinely a PNG. The rule is "at least one image", not a good one.
  static final Uint8List _onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  // ---------------------------------------------------------------- who gets the job

  /// Put the demo rider back in the fleet that dispatch actually routes to.
  ///
  /// <p><strong>This is the single most likely reason a lifecycle test hangs at "Ready".</strong>
  /// The job board is scoped to the rider's fleet: `findAvailableFor` returns orders whose
  /// `deliveryProviderId` is the rider's own provider or null. A rider with no membership falls
  /// back to the in-house fleet, which is where dispatch sends everything by default — so out of
  /// the box it works. But three of the suites under `infra/` add the demo rider to the external
  /// "Demo Couriers" company and never take them out again, and from then on every in-house order
  /// on that environment is invisible to the only rider who can sign in. The order reaches READY
  /// and sits there forever, and the app is not wrong about any of it.
  ///
  /// Returns true if a stale membership was actually removed.
  static Future<bool> putRiderBackInHouse(String backofficeToken, String riderSub) async {
    final _Res res =
        await _api('DELETE', '/api/delivery-providers/riders/$riderSub', backofficeToken);
    // 204 removed, 404 there was nothing to remove — both leave the rider in-house.
    if (res.code != 204 && res.code != 404) _fail('clearing the fleet membership', res);
    return res.code == 204;
  }

  /// Let the platform choose the fleet, rather than a pin left behind by another suite.
  static Future<void> clearMerchantCarrierPin(String merchantToken) async {
    await _api('PUT', '/api/delivery-providers/policy', merchantToken,
        json: <String, Object?>{'preferredProviderId': null});
  }

  // ---------------------------------------------------------------- reading the world back

  /// One order as the server sees it — the corroboration for what a screen claimed.
  static Future<Map<String, dynamic>> order(String token, String orderId) async {
    final _Res res = await _api('GET', '/api/orders/$orderId', token);
    if (res.code != 200) _fail('reading order $orderId', res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// The customer's orders, newest first.
  static Future<List<dynamic>> myOrders(String customerToken) async {
    final _Res res = await _api('GET', '/api/orders/mine?page=0&size=20', customerToken);
    if (res.code != 200) _fail('reading the customer orders', res);
    return (jsonDecode(res.body) as Map<String, dynamic>)['content'] as List<dynamic>;
  }

  /// Every state the order passed through, in order, as recorded server-side.
  static Future<List<String>> historyOf(String token, String orderId) async {
    final _Res res = await _api('GET', '/api/orders/$orderId/history', token);
    if (res.code != 200) _fail('reading the history of $orderId', res);
    return (jsonDecode(res.body) as List<dynamic>)
        .map<String>((dynamic h) => (h as Map<String, dynamic>)['status'] as String)
        .toList();
  }

  /// The accounting legs posted for one order. Empty until settlement has run.
  static Future<List<dynamic>> ledgerOf(String backofficeToken, String orderId) async {
    final _Res res = await _api('GET', '/api/accounting/orders/$orderId', backofficeToken);
    if (res.code != 200) return const <dynamic>[];
    final dynamic body = jsonDecode(res.body);
    if (body is List) return body;
    final Map<String, dynamic> map = body as Map<String, dynamic>;
    return (map['transactions'] ?? map['legs'] ?? const <dynamic>[]) as List<dynamic>;
  }

  /// Poll until [ready] is happy, or give up. Settlement and dispatch are asynchronous, so a
  /// scenario that asserts immediately after an action is asserting against a race.
  static Future<T?> waitFor<T>(
    Future<T?> Function() attempt, {
    Duration timeout = const Duration(seconds: 30),
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

class _Res {
  const _Res(this.code, this.body);
  final int code;
  final String body;
}

/// Driving an order from outside the app.
///
/// <p>Used by scenarios that are about ONE role's screens rather than about the whole relay — the
/// customer watching their order advance, for instance, where the merchant and the rider are not
/// the subject and putting them through the UI would only add ways for the test to fail for
/// reasons it is not about. A scenario that IS about the relay drives every hop through the app.
extension BusinessFlow on Backend {
  static Future<Map<String, dynamic>> placeOrder(
    String customerToken, {
    required String productId,
    required String deliveryAddress,
    int qty = 1,
  }) async {
    final _Res res = await Backend._api('POST', '/api/orders', customerToken, json: <String, Object>{
      'items': <Map<String, Object>>[
        <String, Object>{'productId': productId, 'qty': qty},
      ],
      'deliveryAddress': deliveryAddress,
      'contactPhone': '+96170123456',
      'paymentMethod': 'CASH',
    });
    if (res.code != 200 && res.code != 201) Backend._fail('placing an order', res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// One transition, by the role that owns it. Throws with the server's own words if refused.
  static Future<String> advance(String token, String orderId, String action) async {
    final _Res res = await Backend._api('POST', '/api/orders/$orderId/$action', token);
    if (res.code != 200) Backend._fail('$action on order $orderId', res);
    return (jsonDecode(res.body) as Map<String, dynamic>)['status'] as String;
  }

  /// The merchant's half of the relay: accepted, preparing, ready.
  static Future<void> merchantWorksIt(String merchantToken, String orderId) async {
    for (final String action in <String>['accept', 'prepare', 'ready']) {
      await advance(merchantToken, orderId, action);
    }
  }

  /// The rider's half: claimed, collected, delivered.
  static Future<void> riderDeliversIt(String riderToken, String orderId) async {
    for (final String action in <String>['claim', 'pick-up', 'deliver']) {
      await advance(riderToken, orderId, action);
    }
  }
}
