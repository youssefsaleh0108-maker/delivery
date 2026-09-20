import 'dart:async';
import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the realm's refresh-token rotation demands of the client, and what the web build does
/// with a token it is no longer allowed to store.
///
/// <p>The realm now sets `revokeRefreshToken` with `refreshTokenMaxReuse: 0` (PT-3). Every refresh
/// returns a new token and destroys the one it was bought with, and presenting a destroyed token
/// is how Keycloak detects a stolen one — so its answer is to kill the whole session, not to
/// refuse the one request. That turns a client-side race from a wasted round trip into a user
/// being signed out of a session that was perfectly healthy, usually while doing something else.
///
/// <p>[_RotatingKeycloak] below enforces exactly that rule, so these tests fail the way dev would:
/// a second grant on a spent token throws instead of quietly working.
///
/// <p>The second group covers the other half. `flutter_secure_storage` on the web is
/// `window.localStorage` — same origin, readable by any script that gets onto the page, and it
/// kept its own encryption key in the next entry along. The web build therefore holds its refresh
/// token in memory only and recovers a reload through Keycloak's SSO session instead. On a phone,
/// where the keystore is real and closing the app must not sign anybody out, nothing changes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // FlutterSecureStorage is a platform channel; an in-memory stand-in keeps this pure Dart and
  // lets a test assert on exactly what was and was not written.
  final Map<String, String> vault = <String, String>{};
  setUp(() {
    vault.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async {
        final Map<Object?, Object?> a =
            (call.arguments as Map<Object?, Object?>?) ?? const <Object?, Object?>{};
        switch (call.method) {
          case 'read':
            return vault[a['key'] as String];
          case 'write':
            vault[a['key'] as String] = a['value'] as String;
            return null;
          case 'delete':
            vault.remove(a['key'] as String);
            return null;
          case 'readAll':
            return vault;
          default:
            return null;
        }
      },
    );
  });

  const AuthConfig config = AuthConfig(
    issuer: 'https://iam.test/realms/delivery-platform',
    clientId: 'delivery-portal',
    redirectUrl: 'https://portal.test/',
  );

  AuthService web(_RotatingKeycloak oidc) =>
      AuthService(config: config, oidcClient: oidc, persistRefreshToken: false);

  AuthService phone(_RotatingKeycloak oidc) =>
      AuthService(config: config, oidcClient: oidc, persistRefreshToken: true);

  group('rotation: one refresh grant at a time', () {
    test('a screen, a socket and a retry racing on one token spend it once', () async {
      final _RotatingKeycloak oidc = _RotatingKeycloak();
      final AuthService auth = web(oidc);
      await auth.refresh('seed');

      // Three callers that do not know about each other. In the app these are the Dio
      // interceptor, UserQueueSocket reconnecting, and a screen calling refresh() directly —
      // three paths to the same token, and only the first of them runs inside Dio's queue.
      oidc.gate = Completer<void>();
      final List<Future<AuthSession>> racers = <Future<AuthSession>>[
        auth.refresh(),
        auth.refresh(),
        auth.refresh(),
      ];
      await pumpEventQueue();
      oidc.gate!.complete();
      final List<AuthSession> settled = await Future.wait(racers);

      expect(oidc.presented, <String>['seed', 'r1'],
          reason: 'the second and third callers must join the grant in flight, not start one. '
              'Without that the realm sees a spent token and ends the session.');
      expect(oidc.grants, 2);
      for (final AuthSession session in settled) {
        expect(session.accessToken, settled.first.accessToken,
            reason: 'all three callers share one result');
      }
      expect(auth.session!.refreshToken, 'r2');
    });

    test('a caller that names its own token waits for the grant already in flight', () async {
      final _RotatingKeycloak oidc = _RotatingKeycloak();
      final AuthService auth = web(oidc);
      await auth.refresh('seed');

      oidc.gate = Completer<void>();
      final Future<AuthSession> inFlight = auth.refresh();
      await pumpEventQueue();
      // The biometric stash and a stored token both arrive this way. They cannot simply join the
      // flight — they carry a different token — so they have to queue behind it.
      final Future<AuthSession> named = auth.refresh('stashed');
      await pumpEventQueue();
      expect(oidc.presented, isNot(contains('stashed')),
          reason: 'two grants in the air at once is the thing rotation punishes');

      oidc.gate!.complete();
      await inFlight;
      await named;
      expect(oidc.presented, <String>['seed', 'r1', 'stashed']);
    });

    test('the token a rotation returned is the one the next refresh presents', () async {
      final _RotatingKeycloak oidc = _RotatingKeycloak();
      final AuthService auth = web(oidc);
      await auth.refresh('seed');
      await auth.refresh();
      await auth.refresh();
      expect(oidc.presented, <String>['seed', 'r1', 'r2']);
      expect(auth.session!.refreshToken, 'r3');
    });

    test('a failed grant does not wedge the next one', () async {
      final _RotatingKeycloak oidc = _RotatingKeycloak();
      final AuthService auth = web(oidc);
      await auth.refresh('seed');

      oidc.failNext = true;
      await expectLater(auth.refresh(), throwsA(isA<StateError>()));
      // The slot has to be clear again, or one flaky network call would leave every later refresh
      // waiting on a future that already failed.
      final AuthSession recovered = await auth.refresh('handed-back');
      expect(recovered.refreshToken, 'r2');
    });
  });

  group('the web build keeps the refresh token in memory only', () {
    test('a token stays in the session and never reaches storage', () async {
      final _RotatingKeycloak oidc = _RotatingKeycloak();
      final AuthService auth = web(oidc);
      final AuthSession session = await auth.refresh('seed');
      expect(session.refreshToken, 'r1');
      expect(vault.containsKey('delivery.refresh_token'), isFalse,
          reason: 'localStorage is not secure storage, whatever the package is called');
    });

    test('a reload clears what an older build left behind and resumes the SSO session', () async {
      // The build that shipped before this change wrote here. Somebody upgrading has a month-old
      // back-office refresh token in localStorage until something removes it.
      vault['delivery.refresh_token'] = 'left-by-the-previous-build';
      final _RotatingKeycloak oidc = _RotatingKeycloak()..resumeResult = _mint(1);
      final AuthService auth = web(oidc);

      final AuthSession? restored = await auth.restore();
      expect(vault.containsKey('delivery.refresh_token'), isFalse);
      expect(oidc.resumeCalls, 1);
      expect(restored, isNotNull);
      expect(restored!.refreshToken, 'r1');
      expect(oidc.presented, isEmpty,
          reason: 'the stale token must be dropped, not spent');
    });

    test('no SSO session leaves the caller signed out rather than looping', () async {
      final _RotatingKeycloak oidc = _RotatingKeycloak();
      final AuthService auth = web(oidc);
      expect(await auth.restore(), isNull);
      expect(oidc.resumeCalls, 1);
    });

    test('a phone still persists its token and restores from it', () async {
      final _RotatingKeycloak oidc = _RotatingKeycloak();
      final AuthService auth = phone(oidc);
      vault['delivery.refresh_token'] = 'seed';

      final AuthSession? restored = await auth.restore();
      expect(restored, isNotNull);
      expect(oidc.resumeCalls, 0, reason: 'there is no browser session to resume');
      expect(oidc.presented, <String>['seed']);
      expect(vault['delivery.refresh_token'], 'r1',
          reason: 'the rotated token replaces the one it was bought with');
    });
  });
}

String _jwt(int n) {
  String seg(Map<String, Object?> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${seg(<String, Object?>{'alg': 'none'})}.'
      '${seg(<String, Object?>{
        'sub': 'u1',
        'preferred_username': 'backoffice',
        'realm_access': <String, Object?>{'roles': <String>['BACKOFFICE']},
      })}.sig$n';
}

TokenSet _mint(int n) => TokenSet(
      accessToken: _jwt(n),
      refreshToken: 'r$n',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );

/// Keycloak with `revokeRefreshToken` on and `refreshTokenMaxReuse: 0`: a token is good once.
class _RotatingKeycloak implements OidcClient {
  /// Every token presented at the token endpoint, in order.
  final List<String> presented = <String>[];

  /// Tokens this realm has already destroyed by rotating them away.
  final Set<String> _spent = <String>{};

  int grants = 0;
  int resumeCalls = 0;

  /// Held open to keep a grant in flight while a test starts another.
  Completer<void>? gate;

  /// What the browser's SSO session yields on the next [resumeSession], or null for "nobody is
  /// signed in here".
  TokenSet? resumeResult;

  bool failNext = false;

  @override
  Future<TokenSet> refresh(AuthConfig config, String refreshToken) async {
    presented.add(refreshToken);
    final Completer<void>? held = gate;
    if (held != null) await held.future;
    if (failNext) {
      failNext = false;
      throw StateError('the token endpoint was unreachable');
    }
    if (!_spent.add(refreshToken)) {
      throw StateError(
          'refresh token reuse: the realm would end this session, not just refuse the grant');
    }
    grants++;
    return _mint(grants);
  }

  @override
  Future<TokenSet?> resumeSession(AuthConfig config) async {
    resumeCalls++;
    return resumeResult;
  }

  @override
  Future<TokenSet?> completeRedirect(AuthConfig config) async => null;

  @override
  Future<TokenSet?> signIn(AuthConfig config, {Map<String, String>? extraParams}) async => null;

  @override
  Future<void> signOut(AuthConfig config, String? refreshToken) async {}
}
