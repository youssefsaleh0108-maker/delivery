import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_core/src/auth/oidc_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// What happens to a request when the token behind it has to be renewed first.
///
/// <p>Every client in this repo — the phone app and both web consoles — shares one Dio built by
/// [ApiClient.create], and its auth interceptor does two things that are easy to get wrong
/// together. It refreshes an expired token BEFORE sending, and it refreshes and retries once
/// AFTER a 401. Both run inside a `QueuedInterceptor`, which serialises interceptor callbacks so
/// that a burst of parallel requests triggers one refresh rather than five.
///
/// <p>That serialisation is the risk. The 401 path re-sends through the SAME Dio while the queue
/// is still held open by the very callback doing the re-sending, which is the classic shape of a
/// self-deadlock: nothing is ever sent again, no error is ever raised, and every screen in the
/// app sits on a spinner with no request in flight to explain it.
///
/// <p>These tests exist because the back-office console was observed doing exactly that — a cold
/// load made one call to the token endpoint and then went permanently silent, while the
/// dashboard's tiles stayed on "Loading…" with no request in flight to explain it. The
/// interceptor was the obvious suspect and these were written to convict it.
///
/// <p><strong>They acquitted it.</strong> All three shapes complete: a request on an
/// already-expired token, a 401 retried once, and a dashboard-sized burst on a stale session
/// that renews exactly once between them. So the console's stall is somewhere else, and the next
/// person to see a hung screen can skip this file rather than re-deriving that from the source.
/// They stay because the retry path is shared by the phone app and both web consoles, it is the
/// kind of code that deadlocks silently when someone changes it, and nothing else covered it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // FlutterSecureStorage is a platform channel, and AuthService reads and writes the refresh
  // token through it. An in-memory stand-in keeps this a pure Dart test.
  final Map<String, String> vault = <String, String>{};
  setUp(() {
    vault.clear();
    vault['delivery.refresh_token'] = 'stored-refresh-token';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async {
        switch (call.method) {
          case 'read':
            return vault[(call.arguments as Map<Object?, Object?>)['key'] as String];
          case 'write':
            final Map<Object?, Object?> a = call.arguments as Map<Object?, Object?>;
            vault[a['key'] as String] = a['value'] as String;
            return null;
          case 'delete':
            vault.remove((call.arguments as Map<Object?, Object?>)['key'] as String);
            return null;
          case 'readAll':
            return vault;
          default:
            return null;
        }
      },
    );
  });

  /// An access token the session parser can read: unsigned, but shaped like the real thing.
  String jwt({required String sub}) {
    String seg(Map<String, Object?> m) =>
        base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    return '${seg(<String, Object?>{'alg': 'none'})}.'
        '${seg(<String, Object?>{
          'sub': sub,
          'preferred_username': 'tester',
          'realm_access': <String, Object?>{'roles': <String>['CUSTOMER']},
        })}.sig';
  }

  test('a request whose token is already expired still goes out', () async {
    final _FakeOidc oidc = _FakeOidc(token: jwt(sub: 'u1'), ttl: const Duration(hours: 1));
    final AuthService auth = AuthService(
      config: const AuthConfig(
        issuer: 'https://iam.test/realms/r',
        clientId: 'mobile-app',
        redirectUrl: 'app://cb',
      ),
      oidcClient: oidc,
    );

    // Restore gives the service a session. It starts ALREADY EXPIRED, which is the state a cold
    // load lands in: the stored refresh token is older than the access token it last minted.
    oidc.ttl = const Duration(seconds: -60);
    await auth.restore();
    expect(auth.session, isNotNull);
    expect(auth.session!.isExpired, isTrue, reason: 'the case under test needs a stale session');

    // From here the refresh mints a good one.
    oidc.ttl = const Duration(hours: 1);

    final Dio dio = ApiClient.create(baseUrl: 'https://api.test', authService: auth);
    final _Adapter adapter = _Adapter();
    dio.httpClientAdapter = adapter;

    final Response<dynamic> res = await dio
        .get<dynamic>('/api/orders')
        .timeout(const Duration(seconds: 5), onTimeout: () {
      throw TimeoutException(
        'The request never reached the adapter. The interceptor renewed the token and then never '
        'released the queue, so nothing is sent and nothing errors — the screen waiting on this '
        'sits on a spinner forever.',
      );
    });

    expect(res.statusCode, 200);
    expect(adapter.sent, hasLength(1));
    expect(adapter.sent.single.headers['Authorization'], 'Bearer ${oidc.lastMinted}',
        reason: 'the renewed token must be the one that goes out, not the stale one');
  });

  test('a 401 is retried once with a fresh token, and the caller gets the retry', () async {
    final _FakeOidc oidc = _FakeOidc(token: jwt(sub: 'u2'), ttl: const Duration(hours: 1));
    final AuthService auth = AuthService(
      config: const AuthConfig(
        issuer: 'https://iam.test/realms/r',
        clientId: 'mobile-app',
        redirectUrl: 'app://cb',
      ),
      oidcClient: oidc,
    );
    await auth.restore();

    final Dio dio = ApiClient.create(baseUrl: 'https://api.test', authService: auth);
    final _Adapter adapter = _Adapter(failFirstWith: 401);
    dio.httpClientAdapter = adapter;

    // THE ONE THAT MATTERS. onError re-sends through the same Dio from inside a QueuedInterceptor
    // callback. If that re-entry cannot obtain the queue, this never returns and never throws.
    final Response<dynamic> res = await dio
        .get<dynamic>('/api/orders')
        .timeout(const Duration(seconds: 5), onTimeout: () {
      throw TimeoutException(
        'The 401 retry deadlocked. onError refreshed the token and re-sent through the same Dio '
        'while still holding the QueuedInterceptor, so the retry can never be dispatched: the '
        'caller waits forever, no error surfaces, and every screen behind this Dio stops.',
      );
    });

    expect(res.statusCode, 200);
    expect(adapter.sent, hasLength(2), reason: 'the original and exactly one retry');
    expect(adapter.sent.last.extra['delivery.retried'], isTrue);
  });

  test('five parallel requests on a stale session all complete', () async {
    final _FakeOidc oidc = _FakeOidc(token: jwt(sub: 'u3'), ttl: const Duration(seconds: -60));
    final AuthService auth = AuthService(
      config: const AuthConfig(
        issuer: 'https://iam.test/realms/r',
        clientId: 'mobile-app',
        redirectUrl: 'app://cb',
      ),
      oidcClient: oidc,
    );
    await auth.restore();
    oidc.ttl = const Duration(hours: 1);

    // restore() renews once by definition — it redeems the stored refresh token — so the
    // interesting number is what the BURST adds on top of that, not the total.
    final int refreshesBeforeBurst = oidc.refreshes;

    final Dio dio = ApiClient.create(baseUrl: 'https://api.test', authService: auth);
    final _Adapter adapter = _Adapter();
    dio.httpClientAdapter = adapter;

    // A dashboard mounting fires several at once. This is the shape that was observed stalling.
    final List<Response<dynamic>> all = await Future.wait(<Future<Response<dynamic>>>[
      for (final String p in <String>[
        '/api/orders/stats',
        '/api/orders',
        '/api/stores',
        '/api/orders/daily',
        '/api/orders/activity',
      ])
        dio.get<dynamic>(p),
    ]).timeout(const Duration(seconds: 8), onTimeout: () {
      throw TimeoutException(
        'A dashboard-shaped burst never completed. One refresh should serve all five; instead '
        'the queue is holding them and no request is in flight.',
      );
    });

    expect(all.map((Response<dynamic> r) => r.statusCode), everyElement(200));
    expect(adapter.sent, hasLength(5));
    expect(oidc.refreshes - refreshesBeforeBurst, 1,
        reason: 'QueuedInterceptor exists so a burst of five triggers ONE renewal, not five — '
            'five competing refreshes would rotate the token out from under each other');
  });
}

/// Mints tokens on demand and counts how often it was asked.
class _FakeOidc implements OidcClient {
  _FakeOidc({required this.token, required this.ttl});

  final String token;
  Duration ttl;
  int refreshes = 0;
  String lastMinted = '';

  @override
  Future<TokenSet> refresh(AuthConfig config, String refreshToken) async {
    refreshes++;
    lastMinted = '$token.$refreshes';
    return TokenSet(
      accessToken: lastMinted,
      refreshToken: 'rotated-$refreshes',
      expiresAt: DateTime.now().add(ttl),
    );
  }

  @override
  Future<TokenSet?> completeRedirect(AuthConfig config) async => null;

  @override
  Future<TokenSet?> signIn(AuthConfig config, {Map<String, String>? extraParams}) async => null;

  @override
  Future<void> signOut(AuthConfig config, String? refreshToken) async {}
}

/// Records what actually reached the wire, which is the whole question here.
class _Adapter implements HttpClientAdapter {
  _Adapter({this.failFirstWith});

  final int? failFirstWith;
  final List<RequestOptions> sent = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    sent.add(options);
    final bool firstAndFailing = failFirstWith != null && sent.length == 1;
    return ResponseBody.fromString(
      firstAndFailing ? '{"error":"expired"}' : '{"content":[],"totalElements":0}',
      firstAndFailing ? failFirstWith! : 200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
