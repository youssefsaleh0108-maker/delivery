import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/application_refusals.dart';
import 'package:mobile_app/src/one_time_code.dart';
import 'package:mobile_app/src/partner_application_screen.dart';

/// The open form's passcode step proves the application is the applicant's with a secret, never with
/// the reference alone.
///
/// The reference is a display id — back office sees it, and so does the delivery company a rider
/// applies to, whose portal prints it — so the server stopped taking it as proof. The submission now
/// answers with an account-setup ticket, and the passcode step sends that, in the body. When the
/// server will not take it — its half hour ran out while a retry waited, say — or never gave one, the
/// app proves the address again with a new code and sends that proof instead.
const AuthConfig _config = AuthConfig(
  issuer: 'https://iam.test/realms/delivery-platform',
  clientId: 'mobile-app',
  redirectUrl: 'com.delivery.app://oauth2redirect',
);

const String _account = 'POST /api/onboarding/applications/ref-open/account';

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

Future<void> _pumpABit(WidgetTester tester) async {
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  final Finder button = find.widgetWithText(AuthPrimaryButton, label);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Finder _fieldOf(String label) => find.descendant(
    of: find.byWidgetPredicate((Widget w) => w is AuthField && w.label == label),
    matching: find.byType(TextField));

Future<void> _enterCode(WidgetTester tester, String code) async {
  await tester.enterText(
      find.descendant(of: find.byType(OneTimeCodeField), matching: find.byType(TextField)), code);
  await _pumpABit(tester);
}

/// A rider on the open form, filled in and submitted, with the first email code answered: what
/// happens next is the passcode step.
Future<DeliveryStrings> _applyAndProveTheAddress(WidgetTester tester, _Server server,
    {required void Function(AuthSession) onSignedIn}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final DeliveryStrings t = await DeliveryStrings.delegate.load(const Locale('en'));
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = server;

  await tester.pumpWidget(_app(PartnerApplicationScreen(
    api: OnboardingApi(dio),
    documentsApi: DocumentsApi(dio),
    kind: PartnerKind.rider,
    authService: _PasswordGrant(),
    onSignedIn: onSignedIn,
    onClose: () {},
  )));
  await tester.pumpAndSettle();
  await _tapButton(tester, t.authGetStarted);
  await tester.enterText(_fieldOf(t.authFullName), 'Sam Salem');
  await tester.enterText(_fieldOf(t.authEmailAddress), 'Sam@Example.test');
  await tester.enterText(_fieldOf(t.password), '246810');
  await tester.pump();
  await _tapButton(tester, t.authNext); // -> vehicle
  await _tapButton(tester, t.authNext); // -> documents
  await _tapButton(tester, t.authNext); // -> who they ride for
  final Finder company = find.text('Swift Couriers');
  await tester.ensureVisible(company);
  await tester.pumpAndSettle();
  await tester.tap(company);
  await tester.pumpAndSettle();
  final Finder submit = find.widgetWithText(AuthPrimaryButton, t.authSubmitApplication);
  await tester.ensureVisible(submit);
  await tester.pumpAndSettle();
  await tester.tap(submit);
  await _pumpABit(tester);
  expect(find.text(t.authVerifyYourEmail), findsOneWidget);
  await _enterCode(tester, '123456');
  return t;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // AuthService keeps the refresh token in secure storage, a platform channel.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async => null,
    );
  });

  testWidgets('the ticket from the submission goes straight to the passcode step, in the body',
      (WidgetTester tester) async {
    AuthSession? signedIn;
    final _Server server = _Server();

    await _applyAndProveTheAddress(tester, server, onSignedIn: (AuthSession s) => signedIn = s);
    await _pumpABit(tester);

    expect(server.bodies[_account], <String, dynamic>{
      'password': '246810',
      'accountTicket': 'ticket-open',
    });
    // Never in the path, which access logs keep.
    expect(server.calls.where((String c) => c.contains('ticket-open')), isEmpty);
    // One code, for the application; nothing asked a second time.
    expect(server.codesSent, <String>['sam@example.test']);
    expect(signedIn, isNotNull);
  });

  testWidgets(
      'a ticket the server no longer takes is replaced by a new code on the address, and its proof',
      (WidgetTester tester) async {
    AuthSession? signedIn;
    // The ticket's half hour ran out before the passcode step reached the server.
    final _Server server = _Server()..ticketRefused = true;

    final DeliveryStrings t = await _applyAndProveTheAddress(tester, server,
        onSignedIn: (AuthSession s) => signedIn = s);
    await _pumpABit(tester);

    // Refused once, with the ticket — then a second code, to the application's own address, and
    // the code screen saying why it asks again.
    expect(server.accountBodies, hasLength(1));
    expect(server.accountBodies.single['accountTicket'], 'ticket-open');
    expect(server.codesSent, <String>['sam@example.test', 'sam@example.test']);
    expect(find.text(t.authVerifyYourEmail), findsOneWidget);
    expect(find.text(t.wizAccountConfirmAgain), findsOneWidget);
    expect(signedIn, isNull);

    await _enterCode(tester, '654321');
    await _pumpABit(tester);

    // The proof of that code goes where the ticket went, and the ticket does not go again.
    expect(server.accountBodies, hasLength(2));
    expect(server.accountBodies.last, <String, dynamic>{
      'password': '246810',
      'emailVerificationToken': 'proof-EMAIL-2',
    });
    expect(server.confirmedFor.last, 'sam@example.test');
    expect(signedIn, isNotNull);
  });

  testWidgets('no ticket at all proves the address before the passcode step — never the reference alone',
      (WidgetTester tester) async {
    AuthSession? signedIn;
    // An answer without a ticket: a server older than tickets.
    final _Server server = _Server()..issuesTicket = false;

    final DeliveryStrings t = await _applyAndProveTheAddress(tester, server,
        onSignedIn: (AuthSession s) => signedIn = s);
    await _pumpABit(tester);

    expect(server.accountBodies, isEmpty);
    expect(find.text(t.wizAccountConfirmAgain), findsOneWidget);

    await _enterCode(tester, '654321');
    await _pumpABit(tester);

    expect(server.accountBodies.single, <String, dynamic>{
      'password': '246810',
      'emailVerificationToken': 'proof-EMAIL-2',
    });
    expect(signedIn, isNotNull);
  });

  testWidgets('back from that second code returns to where the sign-in waits, not to the wizard',
      (WidgetTester tester) async {
    final _Server server = _Server()..ticketRefused = true;

    final DeliveryStrings t =
        await _applyAndProveTheAddress(tester, server, onSignedIn: (_) {});
    await _pumpABit(tester);
    expect(find.text(t.wizAccountConfirmAgain), findsOneWidget);

    await tester.tap(find.byType(AuthBackButton));
    await _pumpABit(tester);

    expect(find.text(t.wizAccountProofRejected), findsOneWidget);
    expect(find.widgetWithText(AuthPrimaryButton, t.tryAgain), findsOneWidget);
    expect(find.widgetWithText(AuthPrimaryButton, t.authSubmitApplication), findsNothing);
    // Try again asks for a code once more, rather than sending the reference alone.
    await tester.tap(find.widgetWithText(AuthPrimaryButton, t.tryAgain));
    await _pumpABit(tester);
    expect(server.codesSent, hasLength(3));
    expect(server.accountBodies, hasLength(1));
  });

  test('the refusals are said in either language, and only they send the applicant back for a code',
      () async {
    final DeliveryStrings en = await DeliveryStrings.delegate.load(const Locale('en'));
    final DeliveryStrings ar = await DeliveryStrings.delegate.load(const Locale('ar'));
    DioException answered(String code) {
      final RequestOptions request = RequestOptions(path: '/api/onboarding/applications/r/account');
      return DioException(
        requestOptions: request,
        response: Response<dynamic>(
            requestOptions: request,
            statusCode: 422,
            data: <String, Object?>{'code': code, 'message': 'the server English'}),
      );
    }

    final DioException missing = answered('sign-in-proof-missing');
    final DioException rejected = answered('sign-in-proof-rejected');
    expect(isSignInProofRefused(missing), isTrue);
    expect(isSignInProofRefused(rejected), isTrue);
    expect(isSignInProofRefused(answered('sign-in-exists')), isFalse);
    expect(isSignInProofRefused(answered('account-exists')), isFalse);
    expect(isSignInProofRefused(StateError('offline')), isFalse);

    expect(applicationServerMessage(en, missing), en.wizAccountProofMissing);
    expect(applicationServerMessage(ar, missing), ar.wizAccountProofMissing);
    expect(applicationServerMessage(en, rejected), en.wizAccountProofRejected);
    expect(applicationServerMessage(ar, rejected), ar.wizAccountProofRejected);
    expect(en.wizAccountProofMissing, contains('update the app'));
    for (final String Function(DeliveryStrings) s in <String Function(DeliveryStrings)>[
      (DeliveryStrings t) => t.wizAccountProofMissing,
      (DeliveryStrings t) => t.wizAccountProofRejected,
      (DeliveryStrings t) => t.wizAccountConfirmAgain,
    ]) {
      expect(s(ar), isNot(s(en)));
    }
  });
}

/// A password sign-in without Keycloak: the account the open form just made, signed in.
class _PasswordGrant extends AuthService {
  _PasswordGrant() : super(config: _config, oidcClient: _NoBrowser());

  @override
  Future<AuthSession> signInWithPassword(String username, String password) async => AuthSession(
        accessToken: 'applicant-token',
        refreshToken: null,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        roles: const <DeliveryRole>{DeliveryRole.delivery, DeliveryRole.applicant},
        subject: 'sam-open',
      );
}

/// The open form never opens a browser.
class _NoBrowser implements OidcClient {
  @override
  Future<TokenSet?> signIn(AuthConfig config, {Map<String, String>? extraParams}) async => null;

  @override
  Future<TokenSet?> completeRedirect(AuthConfig config) async => null;

  @override
  Future<TokenSet?> resumeSession(AuthConfig config) async => null;

  @override
  Future<TokenSet> refresh(AuthConfig config, String refreshToken) =>
      throw UnimplementedError('the open form does not refresh');

  @override
  Future<void> signOut(AuthConfig config, String? refreshToken) async {}
}

/// onboarding-service for the open form: who is hiring, the verification pair, the submission —
/// answered with a ticket unless told otherwise — and the passcode step, which takes the ticket
/// unless told it has expired, and takes a proof of the address. Anything else is refused.
class _Server implements HttpClientAdapter {
  final List<String> calls = <String>[];
  final Map<String, Map<String, dynamic>> bodies = <String, Map<String, dynamic>>{};

  /// Where each code was sent, in order, and the address each confirmation named.
  final List<String> codesSent = <String>[];
  final List<String> confirmedFor = <String>[];

  /// Every body the passcode step was sent, in order.
  final List<Map<String, dynamic>> accountBodies = <Map<String, dynamic>>[];

  /// Whether the submission answers with an account-setup ticket.
  bool issuesTicket = true;

  /// Whether the passcode step refuses the ticket, as it does once its half hour is up.
  bool ticketRefused = false;

  int _confirmed = 0;

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    final String route = '${options.method} ${options.path}';
    calls.add(route);
    final Object? data = options.data;
    if (data is Map<String, dynamic>) bodies[route] = data;

    switch (route) {
      case 'GET /api/onboarding/hiring-companies':
        return _json(200, <Map<String, Object?>>[
          <String, Object?>{'id': 'swift-id', 'name': 'Swift Couriers', 'regions': <String>['Hamra']},
        ]);
      case 'POST /api/onboarding/verifications':
        codesSent.add(((data! as Map<String, dynamic>)['destination'] as String).toLowerCase());
        return _json(202, <String, Object?>{'expiresAt': '2026-09-19T10:10:00Z'});
      case 'POST /api/onboarding/verifications/confirm':
        final String destination =
            ((data! as Map<String, dynamic>)['destination'] as String).toLowerCase();
        confirmedFor.add(destination);
        _confirmed++;
        return _json(200, <String, Object?>{
          'token': 'proof-EMAIL-$_confirmed',
          'destination': destination,
        });
      case 'POST /api/onboarding/applications':
        return _json(201, <String, Object?>{
          'reference': 'ref-open',
          'status': 'SUBMITTED',
          'kind': 'RIDER',
          'businessName': 'Sam Salem',
          if (issuesTicket) 'accountTicket': 'ticket-open',
        });
      case _account:
        final Map<String, dynamic> body = Map<String, dynamic>.of(data! as Map<String, dynamic>);
        accountBodies.add(body);
        if (body['accountTicket'] != null && ticketRefused) {
          return _json(422, <String, Object?>{
            'code': 'sign-in-proof-rejected',
            'message': 'That confirmation has expired or was already used.',
          });
        }
        if (body['accountTicket'] == null && body['emailVerificationToken'] == null) {
          return _json(422, <String, Object?>{
            'code': 'sign-in-proof-missing',
            'message': 'This version of the app can no longer finish setting up a sign-in.',
          });
        }
        return _json(201, <String, Object?>{});
    }
    return _json(404, <String, Object?>{'message': 'not expected in this test: $route'});
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
