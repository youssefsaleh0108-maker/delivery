import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/one_time_code.dart';
import 'package:mobile_app/src/partner_application_screen.dart';

/// Somebody who signed in with Google and said "I want to sell" goes through the SAME application,
/// for the account they are already holding.
///
/// Three things the open form needs must fall away — the email code, the passcode, and creating an
/// account at the end — and the rest must not: the same steps, and an application sent to the
/// server's signed-in endpoint, followed by a token refresh so the roles it granted are in the
/// session that gets routed. The second test pins that a stranger still gets the open form.
const AuthConfig _config = AuthConfig(
  issuer: 'https://iam.test/realms/delivery-platform',
  clientId: 'mobile-app',
  redirectUrl: 'com.delivery.app://oauth2redirect',
);

Widget _app(Widget home) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    );

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  final Finder button = find.widgetWithText(AuthPrimaryButton, label);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // AuthService keeps the refresh token in secure storage, a platform channel.
  final Map<String, String> vault = <String, String>{};
  setUp(() {
    vault.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async {
        final Map<Object?, Object?> a = (call.arguments as Map<Object?, Object?>?) ??
            const <Object?, Object?>{};
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

  testWidgets(
      'a Google account applying to sell is prefilled, asked for no code or passcode, and applies as itself',
      (WidgetTester tester) async {
    _phone(tester);
    final _Keycloak keycloak = _Keycloak();
    final AuthService auth = AuthService(config: _config, oidcClient: keycloak);
    final AuthSession account = (await auth.signInWithBroker(AuthService.googleBroker))!;
    final _Server server = _Server(keycloak);
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = server;
    AuthSession? handedOn;

    await tester.pumpWidget(_app(PartnerApplicationScreen(
      api: OnboardingApi(dio),
      documentsApi: DocumentsApi(dio),
      kind: PartnerKind.merchant,
      authService: auth,
      account: account,
      onSignedIn: (AuthSession session) => handedOn = session,
      onClose: () {},
    )));
    await tester.pumpAndSettle();
    await _tapButton(tester, 'Get started');

    // The account's own name and address; the address ticked and not editable; no passcode.
    expect(find.text('Sam Salem'), findsOneWidget);
    final TextField email = tester.widget<TextField>(find.ancestor(
        of: find.text('sam@gmail.example'), matching: find.byType(TextField)));
    expect(email.readOnly, isTrue);
    expect(find.byWidgetPredicate((Widget w) => w is AuthField && w.obscure), findsNothing,
        reason: 'they sign in with Google; a passcode would be a second credential');
    expect(find.text("We'll use the email on the account you signed in with."), findsOneWidget);

    // The shop's name is the one thing step one still needs.
    expect(tester.widget<AuthPrimaryButton>(find.widgetWithText(AuthPrimaryButton, 'Next'))
        .onPressed, isNull);
    await tester.enterText(find.byType(TextField).first, "Sam's Shakes");
    await tester.pump();

    await _tapButton(tester, 'Next'); // -> documents
    await _tapButton(tester, 'Next'); // -> bank details, left blank on purpose
    await _tapButton(tester, 'Next'); // -> review
    final Finder submit = find.widgetWithText(AuthPrimaryButton, 'Submit application');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    // The finishing phase draws a spinner, so pump rather than settle.
    for (int i = 0; i < 20 && handedOn == null; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // One call, to the signed-in endpoint: no email code, no passcode account, no second sign-in.
    expect(server.calls, <String>['POST /api/onboarding/applications/mine']);
    final Map<String, dynamic> body = server.bodies.single;
    expect(body['kind'], 'MERCHANT');
    expect(body['businessName'], "Sam's Shakes");
    expect(body['contactName'], 'Sam Salem');
    expect(body.containsKey('contactEmail'), isFalse,
        reason: 'the server takes the address from the token, never from the form');

    // And the session handed on was refreshed AFTER the grant, so it carries the roles.
    expect(keycloak.refreshes, 1);
    expect(handedOn, isNotNull);
    expect(handedOn!.hasRole(DeliveryRole.applicant), isTrue);
    expect(handedOn!.hasRole(DeliveryRole.merchant), isTrue);
  });

  /// The account path for a seller, filled in and submitted against [server]: what the screen
  /// handed on, and how many times it asked to be closed.
  Future<({List<AuthSession> handedOn, List<bool> closed})> submitAsSeller(
      WidgetTester tester, _Server server) async {
    final AuthService auth = AuthService(config: _config, oidcClient: server.keycloak);
    final AuthSession account = (await auth.signInWithBroker(AuthService.googleBroker))!;
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = server;
    final List<AuthSession> handedOn = <AuthSession>[];
    final List<bool> closed = <bool>[];

    await tester.pumpWidget(_app(PartnerApplicationScreen(
      api: OnboardingApi(dio),
      documentsApi: DocumentsApi(dio),
      kind: PartnerKind.merchant,
      authService: auth,
      account: account,
      onSignedIn: handedOn.add,
      onClose: () => closed.add(true),
    )));
    await tester.pumpAndSettle();
    await _tapButton(tester, 'Get started');
    await tester.enterText(find.byType(TextField).first, "Sam's Shakes");
    await tester.pump();
    await _tapButton(tester, 'Next');
    await _tapButton(tester, 'Next');
    await _tapButton(tester, 'Next');
    final Finder submit = find.widgetWithText(AuthPrimaryButton, 'Submit application');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return (handedOn: handedOn, closed: closed);
  }

  testWidgets(
      'an account whose application was already decided is told so, not handed on without the role',
      (WidgetTester tester) async {
    // A partner approved the old way — their record on the provisioned column, which GET
    // /applications/mine cannot see — and suspended since. The server hands back the decided
    // application with 200 and grants nothing. Before the fix the role-less session was handed on,
    // and they landed on the role question with no reason given.
    _phone(tester);
    final _Server server = _Server(_Keycloak())..decided = true;

    final ({List<AuthSession> handedOn, List<bool> closed}) result =
        await submitAsSeller(tester, server);

    expect(result.handedOn, isEmpty);
    expect(
        find.text('The partner application on this account has already been decided, so it '
            "can't be reopened here. Please contact support."),
        findsOneWidget);
    // Nothing after the refusal: no documents sent to an application that is not theirs to add to.
    expect(server.calls, <String>['POST /api/onboarding/applications/mine']);

    // "Try again" could only repeat the same answer; Close hands the decision back to the app.
    expect(find.widgetWithText(AuthPrimaryButton, 'Try again'), findsNothing);
    await _tapButton(tester, 'Close');
    expect(result.closed, hasLength(1));
  });

  testWidgets("a refusal the server names is said in the app's words, not the server's English",
      (WidgetTester tester) async {
    _phone(tester);
    final _Server server = _Server(_Keycloak())
      ..refusal = (
        status: 422,
        body: <String, Object?>{
          'message': 'This account already rides with YouDrop',
          'code': 'already-partner',
        },
      );

    final ({List<AuthSession> handedOn, List<bool> closed}) result =
        await submitAsSeller(tester, server);

    expect(result.handedOn, isEmpty);
    expect(
        find.text('This account is already a YouDrop partner, and an account can hold only one '
            'partner role.'),
        findsOneWidget);
    expect(find.text('This account already rides with YouDrop'), findsNothing);
  });

  testWidgets('a 502 says the application is in and a retry finishes it, in the app\'s words',
      (WidgetTester tester) async {
    _phone(tester);
    final _Server server = _Server(_Keycloak())
      ..refusal = (
        status: 502,
        body: <String, Object?>{'message': 'Keycloak said no'},
      );

    await submitAsSeller(tester, server);

    expect(
        find.text("Your application is in, but we couldn't finish setting up your account. "
            'Please try again.'),
        findsOneWidget);
    expect(find.text('Keycloak said no'), findsNothing);
    expect(find.widgetWithText(AuthPrimaryButton, 'Try again'), findsOneWidget);
  });

  testWidgets('a stranger still gets the open form: an editable address and a passcode',
      (WidgetTester tester) async {
    _phone(tester);
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = _Server(_Keycloak());

    await tester.pumpWidget(_app(PartnerApplicationScreen(
      api: OnboardingApi(dio),
      documentsApi: DocumentsApi(dio),
      kind: PartnerKind.merchant,
      authService: AuthService(config: _config, oidcClient: _Keycloak()),
      onSignedIn: (_) {},
      onClose: () {},
    )));
    await tester.pumpAndSettle();
    await _tapButton(tester, 'Get started');

    expect(find.byWidgetPredicate((Widget w) => w is AuthField && w.obscure), findsOneWidget);
    expect(find.byWidgetPredicate((Widget w) => w is AuthField && w.readOnly), findsNothing);
    expect(find.text("We'll use the email on the account you signed in with."), findsNothing);
  });
}

/// Keycloak as the app sees it: a browser round trip and a refresh, each minting a token from the
/// roles the account holds at that moment.
class _Keycloak implements OidcClient {
  final Set<String> roles = <String>{};
  int refreshes = 0;

  TokenSet _mint() {
    String seg(Map<String, Object?> m) =>
        base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    return TokenSet(
      accessToken: '${seg(<String, Object?>{'alg': 'none'})}.'
          '${seg(<String, Object?>{
            'sub': 'google-sam',
            'name': 'Sam Salem',
            'email': 'sam@gmail.example',
            'email_verified': true,
            'realm_access': <String, Object?>{'roles': roles.toList()},
          })}.sig',
      refreshToken: 'refresh-$refreshes',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
  }

  @override
  Future<TokenSet?> signIn(AuthConfig config, {Map<String, String>? extraParams}) async => _mint();

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

/// onboarding-service's signed-in application endpoint, granting into [keycloak] as the real one
/// does. Anything else the screen calls is recorded and refused, so a stray call shows up.
class _Server implements HttpClientAdapter {
  _Server(this.keycloak);

  final _Keycloak keycloak;
  final List<String> calls = <String>[];
  final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];

  /// Answers the application with this status and body instead of taking it.
  ({int status, Map<String, Object?> body})? refusal;

  /// Answers as the server does for an account whose application was already decided: 200, the
  /// receipt as it stands, and no role touched.
  bool decided = false;

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    final String route = '${options.method} ${options.path}';
    calls.add(route);
    final Object? data = options.data;
    if (data is Map<String, dynamic>) bodies.add(data);

    if (route == 'POST /api/onboarding/applications/mine') {
      final String kind = (data! as Map<String, dynamic>)['kind'] as String;
      final ({int status, Map<String, Object?> body})? refused = refusal;
      if (refused != null) return _json(refused.status, refused.body);
      if (decided) {
        return _json(200, <String, Object?>{
          'reference': 'ref-0',
          'status': 'APPROVED',
          'kind': kind,
          'businessName': (data as Map<String, dynamic>)['businessName'],
        });
      }
      keycloak.roles
        ..add('APPLICANT')
        ..add(kind == 'RIDER' ? 'DELIVERY' : 'MERCHANT');
      return _json(201, <String, Object?>{
        'reference': 'ref-1',
        'status': 'SUBMITTED',
        'kind': kind,
        'businessName': (data as Map<String, dynamic>)['businessName'],
      });
    }
    return _json(404, <String, Object?>{'message': 'not expected in this test'});
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
