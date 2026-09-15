import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Signing in with Google and ending up with the role that was asked for.
///
/// <p>The app asks customer / rider / seller before the browser opens, and [BrokerSignIn] turns the
/// answer into a role. Everything that can go wrong on that path has to end somewhere a person can
/// read — never a blank screen, never a shop they have no role to use — and every role change has to
/// be followed by a token refresh, because the role lands in Keycloak and NOT in the token the app is
/// holding. That second rule is the one that fails silently, so most of these watch the refresh.
///
/// <p>Keycloak is stood in for twice: [_Keycloak] is the browser round trip and the refresh grant,
/// minting tokens from whatever roles the account holds at that moment; the probe client answers the
/// "is Google switched on?" question the way Keycloak's login endpoint does. onboarding-service is
/// [_Onboarding], which grants roles into the same [_Keycloak] — so a test can only see a new role
/// after a refresh, exactly as the app can.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // FlutterSecureStorage is a platform channel, and AuthService keeps the refresh token in it.
  final Map<String, String> vault = <String, String>{};
  setUp(() {
    vault.clear();
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

  const AuthConfig config = AuthConfig(
    issuer: 'https://iam.test/realms/delivery-platform',
    clientId: 'mobile-app',
    redirectUrl: 'com.delivery.app://oauth2redirect',
  );

  /// Everything one test needs, wired the way main.dart wires it.
  ({
    AuthService auth,
    BrokerSignIn broker,
    _Keycloak keycloak,
    _Onboarding server,
    List<http.BaseRequest> probes,
  }) world({
    Set<String> roles = const <String>{},
    bool googleEnabled = true,
    bool probeFails = false,
  }) {
    final _Keycloak keycloak = _Keycloak(roles);
    final List<http.BaseRequest> probes = <http.BaseRequest>[];
    final http.Client keycloakLogin =
        MockClient.streaming((http.BaseRequest request, http.ByteStream _) async {
      probes.add(request);
      if (probeFails) throw http.ClientException('offline');
      if (googleEnabled) {
        // What Keycloak's Identity Provider Redirector answers for an enabled provider.
        return http.StreamedResponse(const Stream<List<int>>.empty(), 303, headers: <String, String>{
          'location': 'https://iam.test/realms/delivery-platform/broker/google/login'
              '?client_id=mobile-app&tab_id=t1&session_code=s1',
        });
      }
      // A disabled provider: the hint is ignored and the password form is served.
      return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode('<html>Sign in to YouDrop</html>')), 200);
    });
    final AuthService auth =
        AuthService(config: config, oidcClient: keycloak, httpClient: keycloakLogin);
    final _Onboarding server = _Onboarding(keycloak);
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = server;
    return (
      auth: auth,
      broker: BrokerSignIn(auth: auth, onboarding: OnboardingApi(dio)),
      keycloak: keycloak,
      server: server,
      probes: probes,
    );
  }

  group('what a returning session needs', () {
    test('picking a role the account already holds just signs it in', () {
      expect(BrokerSignIn.decide(AccountIntent.customer, <DeliveryRole>{DeliveryRole.customer}),
          BrokerStep.proceed);
      expect(BrokerSignIn.decide(AccountIntent.rider, <DeliveryRole>{DeliveryRole.delivery}),
          BrokerStep.proceed);
      expect(BrokerSignIn.decide(AccountIntent.seller, <DeliveryRole>{DeliveryRole.merchant}),
          BrokerStep.proceed);
    });

    test('a pending rider is not sent to apply again', () {
      // APPLICANT beside DELIVERY is a rider whose application is being read; their own surface
      // already says so.
      expect(
          BrokerSignIn.decide(AccountIntent.rider,
              <DeliveryRole>{DeliveryRole.applicant, DeliveryRole.delivery}),
          BrokerStep.proceed);
    });

    test('asking for a role the account lacks is treated as asking for it', () {
      expect(BrokerSignIn.decide(AccountIntent.customer, const <DeliveryRole>{}),
          BrokerStep.becomeCustomer);
      expect(BrokerSignIn.decide(AccountIntent.customer, <DeliveryRole>{DeliveryRole.delivery}),
          BrokerStep.becomeCustomer);
      expect(BrokerSignIn.decide(AccountIntent.rider, <DeliveryRole>{DeliveryRole.customer}),
          BrokerStep.apply);
      expect(BrokerSignIn.decide(AccountIntent.seller, const <DeliveryRole>{}), BrokerStep.apply);
    });
  });

  group('before the browser opens', () {
    test('asks Keycloak the way a browser would, with the hint and a PKCE challenge, and follows nothing',
        () async {
      final w = world();

      expect(await w.auth.brokerAvailable(AuthService.googleBroker), isTrue);

      final http.BaseRequest probe = w.probes.single;
      expect(probe.followRedirects, isFalse,
          reason: 'following the redirect would walk straight on to Google');
      expect(probe.url.path, '/realms/delivery-platform/protocol/openid-connect/auth');
      expect(probe.url.queryParameters['kc_idp_hint'], 'google');
      expect(probe.url.queryParameters['client_id'], 'mobile-app');
      expect(probe.url.queryParameters['redirect_uri'], 'com.delivery.app://oauth2redirect');
      // The mobile-app client requires S256; without a challenge Keycloak refuses before it ever
      // reads the hint, and the answer would mean nothing.
      expect(probe.url.queryParameters['code_challenge_method'], 'S256');
      expect(probe.url.queryParameters['code_challenge'], isNotEmpty);
    });

    test('a provider Keycloak will not hand the sign-in to is reported, and no browser opens',
        () async {
      final w = world(googleEnabled: false);

      final BrokerOutcome outcome = await w.broker.start(AccountIntent.customer);

      expect(outcome, isA<BrokerUnavailable>());
      expect(w.keycloak.browserOpens, 0,
          reason: 'a browser now would show Keycloak\'s own password page, not Google');
      expect(w.server.calls, isEmpty);
    });

    test('can be asked on its own, so the app knows before it puts the question to anybody',
        () async {
      // The app asks at launch and keeps Google off the screens while the answer is no. Asked
      // only inside start(), it came after the customer / rider / seller sheet — every person
      // answered, waited on a spinner, and was then told Google was not available.
      final w = world(googleEnabled: false);

      expect(await w.broker.available(), isFalse);
      expect(w.keycloak.browserOpens, 0);
      expect(w.server.calls, isEmpty);
      expect(await world().broker.available(), isTrue);
    });

    test('a question nobody could answer does not stand between somebody and Google', () async {
      final w = world(probeFails: true);

      expect(await w.auth.brokerAvailable(AuthService.googleBroker), isNull);
      await w.broker.start(AccountIntent.customer);

      expect(w.keycloak.browserOpens, 1);
    });

    test('an enabled provider gets the browser, with the hint that skips Keycloak\'s own page',
        () async {
      final w = world(roles: <String>{'CUSTOMER'});

      await w.broker.start(AccountIntent.customer);

      expect(w.keycloak.browserOpens, 1);
      expect(w.keycloak.extraParams, <String, String>{'kc_idp_hint': 'google'});
    });
  });

  group('the round trip itself', () {
    test('backing out is a cancel that changes nothing, not a failure', () async {
      final w = world();
      w.keycloak.cancel = true;

      final BrokerOutcome outcome = await w.broker.start(AccountIntent.rider);

      expect(outcome, isA<BrokerCancelled>());
      expect(w.server.calls, isEmpty);
      expect(w.auth.session, isNull);
    });

    test('a round trip that throws comes back as a failure the app can put in words', () async {
      final w = world();
      w.keycloak.failWith = PlatformException(code: 'authorize_and_exchange_code_failed');

      final BrokerOutcome outcome = await w.broker.start(AccountIntent.customer);

      expect(outcome, isA<BrokerFailed>());
      expect(w.server.calls, isEmpty);
    });

    test('closing the browser comes back from AppAuth as no session rather than an error',
        () async {
      // The real AppAuth client, with its platform channel answering the way Android does when the
      // Custom Tab is closed. Before the fix this threw, and the app said "sign-in did not
      // complete" to somebody who had simply changed their mind.
      const MethodChannel appAuth = MethodChannel('crossingthestreams.io/flutter_appauth');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(appAuth, (MethodCall call) async {
        throw PlatformException(
          code: 'authorize_and_exchange_code_failed',
          message: 'User cancelled flow',
          details: <String, String>{
            'user_did_cancel': 'true',
            'type': '0',
            'code': '1',
            'error': 'user_cancelled',
            'error_description': 'User cancelled flow',
          },
        );
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(appAuth, null));

      final AuthService auth = AuthService(config: config);

      expect(await auth.signInWithBroker(AuthService.googleBroker), isNull);
    });
  });

  group('a customer', () {
    test('without the role is given CUSTOMER, and the session is refreshed so the role is in it',
        () async {
      final w = world();

      final BrokerOutcome outcome = await w.broker.start(AccountIntent.customer);

      expect(w.server.calls, <String>['POST /api/onboarding/me/customer']);
      expect(w.keycloak.refreshes, 1,
          reason: 'the grant lands in Keycloak; only a refresh carries it into the token');
      final BrokerSignedIn signedIn = outcome as BrokerSignedIn;
      expect(signedIn.session.hasRole(DeliveryRole.customer), isTrue);
      expect(signedIn.notice, isNull);
      expect(w.auth.session!.hasRole(DeliveryRole.customer), isTrue);
    });

    test('whose grant is refused is still signed in, and told, with nothing refreshed', () async {
      final w = world();
      w.server.refuseCustomer = true;

      final BrokerOutcome outcome = await w.broker.start(AccountIntent.customer);

      final BrokerSignedIn signedIn = outcome as BrokerSignedIn;
      expect(signedIn.notice, BrokerNotice.roleNotAdded);
      expect(signedIn.session.roles, isEmpty);
      expect(w.keycloak.refreshes, 0);
    });

    test('who already shops is signed in with nothing asked of the server', () async {
      final w = world(roles: <String>{'CUSTOMER'});

      final BrokerOutcome outcome = await w.broker.start(AccountIntent.customer);

      expect(outcome, isA<BrokerSignedIn>());
      expect(w.server.calls, isEmpty);
      expect(w.keycloak.refreshes, 0);
    });
  });

  group('a rider or a seller', () {
    test('with no role and no application is sent to the application for this account', () async {
      final w = world();

      final BrokerOutcome outcome = await w.broker.start(AccountIntent.rider);

      final BrokerNeedsApplication needs = outcome as BrokerNeedsApplication;
      expect(needs.intent, AccountIntent.rider);
      expect(needs.session.roles, isEmpty,
          reason: 'nothing is granted until the application is actually submitted');
      expect(w.server.calls, <String>['GET /api/onboarding/applications/mine']);
    });

    test('who already rides is signed straight in', () async {
      final w = world(roles: <String>{'DELIVERY'});

      final BrokerOutcome outcome = await w.broker.start(AccountIntent.rider);

      expect(outcome, isA<BrokerSignedIn>());
      expect(w.server.calls, isEmpty);
    });

    test('whose account already applied as the other kind is shown that, not started twice',
        () async {
      final w = world();
      w.server.mine = <String, Object?>{
        'reference': 'ref-9',
        'status': 'SUBMITTED',
        'kind': 'RIDER',
        'businessName': 'Sam Salem',
      };

      final BrokerOutcome outcome = await w.broker.start(AccountIntent.seller);

      expect((outcome as BrokerSignedIn).notice, BrokerNotice.existingApplication);
      expect(w.server.calls, isNot(contains('POST /api/onboarding/applications/mine')));
    });

    test('whose same-kind application lost its roles is resumed, then refreshed into them',
        () async {
      // Recorded, but Keycloak failed before the roles were set. Asking again finishes it: the
      // server's idempotent path re-asserts APPLICANT and the live role.
      final w = world();
      w.server.mine = <String, Object?>{
        'reference': 'ref-9',
        'status': 'SUBMITTED',
        'kind': 'RIDER',
        'businessName': 'Sam Salem',
      };

      final BrokerOutcome outcome = await w.broker.start(AccountIntent.rider);

      expect(w.server.calls, <String>[
        'GET /api/onboarding/applications/mine',
        'POST /api/onboarding/applications/mine',
      ]);
      final BrokerSignedIn signedIn = outcome as BrokerSignedIn;
      expect(signedIn.notice, isNull);
      expect(signedIn.session.hasRole(DeliveryRole.delivery), isTrue);
      expect(signedIn.session.hasRole(DeliveryRole.applicant), isTrue,
          reason: 'resuming must not skip the approval gate');
    });

    test('whose same-kind application was decided and the role taken away is told so, not resumed',
        () async {
      // Approved (which revoked APPLICANT), then suspended (which revoked DELIVERY): the account
      // holds nothing. The server grants nothing on a decided application, so a POST could only
      // come back empty — and "we've opened that" over the role question repeated forever.
      final w = world();
      w.server.mine = <String, Object?>{
        'reference': 'ref-9',
        'status': 'APPROVED',
        'kind': 'RIDER',
        'businessName': 'Sam Salem',
      };

      final BrokerOutcome outcome = await w.broker.start(AccountIntent.rider);

      expect((outcome as BrokerSignedIn).notice, BrokerNotice.applicationClosed);
      expect(w.server.calls, <String>['GET /api/onboarding/applications/mine']);
      expect(w.keycloak.refreshes, 0);
    });

    test('who already trades as the other kind is told so, instead of being sent to apply',
        () async {
      // A shop with no application row — a seeded account, or MERCHANT given by hand — asking to
      // ride. The server refuses a second partner role at the END of the form; say it up front.
      final w = world(roles: <String>{'MERCHANT'});

      final BrokerOutcome outcome = await w.broker.start(AccountIntent.rider);

      expect((outcome as BrokerSignedIn).notice, BrokerNotice.alreadyPartner);
      expect(w.server.calls, <String>['GET /api/onboarding/applications/mine']);
    });

    test('whose resumed application still brings no role says setup did not finish', () async {
      // Undecided, resumed, refreshed — and the role is still not there, because the grant failed
      // server-side. That is "could not finish setting up", not "we opened your application".
      final w = world();
      w.server
        ..grantOnApply = false
        ..mine = <String, Object?>{
          'reference': 'ref-9',
          'status': 'SUBMITTED',
          'kind': 'MERCHANT',
          'businessName': "Sam's Shakes",
        };

      final BrokerOutcome outcome = await w.broker.start(AccountIntent.seller);

      expect((outcome as BrokerSignedIn).notice, BrokerNotice.roleNotAdded);
      expect(w.keycloak.refreshes, 1);
    });
  });

  group('applying as the signed-in account', () {
    test('sends the answers and never an address or a proof — the server reads those off the token',
        () async {
      final w = world();
      final OnboardingApi api =
          OnboardingApi(Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = w.server);

      final OnboardingApplication application = await api.applyForMyAccount(
        kind: OnboardingKind.merchant,
        name: 'Sam Salem',
        businessName: "Sam's Shakes",
        details: <String, dynamic>{'businessType': 'RESTAURANT'},
      );

      expect(application.reference, 'ref-1');
      final Map<String, dynamic> body = w.server.bodies.single;
      expect(body['kind'], 'MERCHANT');
      expect(body['businessName'], "Sam's Shakes");
      expect(body['contactName'], 'Sam Salem');
      expect(body.containsKey('contactEmail'), isFalse);
      expect(body.containsKey('emailVerificationToken'), isFalse);
    });

    test('a rider applies in their own name', () async {
      final w = world();
      final OnboardingApi api =
          OnboardingApi(Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = w.server);

      await api.applyForMyAccount(kind: OnboardingKind.rider, name: 'Sam Salem');

      expect(w.server.bodies.single['businessName'], 'Sam Salem');
    });
  });

  test('the session carries the provider\'s own name, and nothing in its place when there is none',
      () {
    expect(_session(<String>{}, name: 'Sam Salem').name, 'Sam Salem');
    expect(_session(<String>{}, name: null).name, isNull);
  });
}

/// A session whose token carries exactly these claims.
AuthSession _session(Set<String> roles, {String? name}) => AuthSession(
      accessToken: _jwt(roles, name: name),
      refreshToken: null,
      expiresAt: null,
      roles: const <DeliveryRole>{},
      subject: 'google-sam',
    );

/// An access token the session parser can read: unsigned, but shaped like Keycloak's.
String _jwt(Set<String> roles, {String? name = 'Sam Salem'}) {
  String seg(Map<String, Object?> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${seg(<String, Object?>{'alg': 'none'})}.'
      '${seg(<String, Object?>{
        'sub': 'google-sam',
        if (name != null) 'name': name,
        'email': 'sam@gmail.example',
        'email_verified': true,
        'realm_access': <String, Object?>{'roles': roles.toList()},
      })}.sig';
}

/// Keycloak, as far as the app can tell: a browser round trip that mints a token, and a refresh
/// that mints one from whatever roles the account holds NOW.
class _Keycloak implements OidcClient {
  _Keycloak(Set<String> roles) : roles = <String>{...roles};

  /// The account's realm roles on the server. A grant by [_Onboarding] lands here, and only a
  /// refresh carries it into a token — the behaviour under test.
  final Set<String> roles;

  bool cancel = false;
  Object? failWith;
  int browserOpens = 0;
  int refreshes = 0;
  Map<String, String>? extraParams;

  TokenSet _mint() => TokenSet(
        accessToken: _jwt(roles),
        refreshToken: 'refresh-$refreshes',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );

  @override
  Future<TokenSet?> signIn(AuthConfig config, {Map<String, String>? extraParams}) async {
    browserOpens++;
    this.extraParams = extraParams;
    final Object? failure = failWith;
    if (failure != null) throw failure;
    return cancel ? null : _mint();
  }

  @override
  Future<TokenSet?> completeRedirect(AuthConfig config) async => null;

  @override
  Future<TokenSet> refresh(AuthConfig config, String refreshToken) async {
    refreshes++;
    return _mint();
  }

  @override
  Future<void> signOut(AuthConfig config, String? refreshToken) async {}
}

/// onboarding-service's two signed-in writes and the applicant lookup, granting into [keycloak].
class _Onboarding implements HttpClientAdapter {
  _Onboarding(this.keycloak);

  final _Keycloak keycloak;
  final List<String> calls = <String>[];
  final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];

  bool refuseCustomer = false;

  /// False makes the application answer as if Keycloak had lost the grant: recorded, no roles.
  bool grantOnApply = true;

  /// What `GET /applications/mine` answers. Null is the 404 of somebody who never applied.
  Map<String, Object?>? mine;

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    final String route = '${options.method} ${options.path}';
    calls.add(route);
    final Object? data = options.data;
    if (data is Map<String, dynamic>) bodies.add(data);

    switch (route) {
      case 'POST /api/onboarding/me/customer':
        if (refuseCustomer) {
          return _json(502, <String, Object?>{'message': 'Keycloak would not set the role'});
        }
        keycloak.roles.add('CUSTOMER');
        return ResponseBody.fromString('', 204);
      case 'GET /api/onboarding/applications/mine':
        final Map<String, Object?>? current = mine;
        return current == null
            ? _json(404, <String, Object?>{'message': 'You have no application in progress'})
            : _json(200, current);
      case 'POST /api/onboarding/applications/mine':
        final Map<String, dynamic> answers = data! as Map<String, dynamic>;
        final String kind = answers['kind'] as String;
        // What the server does: APPLICANT first, then the live role.
        if (grantOnApply) {
          keycloak.roles
            ..add('APPLICANT')
            ..add(kind == 'RIDER' ? 'DELIVERY' : 'MERCHANT');
        }
        return _json(201, <String, Object?>{
          'reference': 'ref-1',
          'status': 'SUBMITTED',
          'kind': kind,
          'businessName': answers['businessName'],
        });
      default:
        return _json(404, <String, Object?>{'message': 'no such route'});
    }
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Map<String, Object?> body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
