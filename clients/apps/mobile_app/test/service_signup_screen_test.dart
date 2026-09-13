import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/one_time_code.dart';
import 'package:mobile_app/src/service_signup_screen.dart';

/// Applying to offer services from the one-page signup (Figma 126:11).
///
/// Pinned: nothing is sent until the business, the service and the area are chosen, and the pickers
/// offer only what the server has open. What is sent is a MERCHANT application whose details say
/// SERVICES with the category and the area, and the session handed on was refreshed after the grant.
/// The last screen says plainly that nothing sells until somebody decides — or that auto-approval
/// did. A refused answer comes back to the form in the reader's words. Somebody with no account goes
/// through the email code, the application and their own account. And the frame's promises the
/// platform cannot keep are not on the screen.
const AuthConfig _config = AuthConfig(
  issuer: 'https://iam.test/realms/delivery-platform',
  clientId: 'mobile-app',
  redirectUrl: 'com.delivery.app://oauth2redirect',
);

final DeliveryStrings _en = lookupDeliveryStrings(const Locale('en'));

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

Finder _field(String label) => find.descendant(
    of: find.widgetWithText(AuthField, label.toUpperCase()), matching: find.byType(TextField));

Finder get _apply => find.widgetWithText(AuthPrimaryButton, _en.svcApplyCta);

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<AuthPrimaryButton>(button).onPressed != null;

Future<void> _pick(WidgetTester tester, String hint, String option) async {
  await tester.ensureVisible(find.text(hint));
  await tester.tap(find.text(hint));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester, {int times = 30}) async {
  for (int i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
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

  /// The screen for an account signed in with Google, against [server].
  Future<({List<AuthSession> handedOn, _Keycloak keycloak})> pumpForAccount(
      WidgetTester tester, _Server server) async {
    _phone(tester);
    final AuthService auth = AuthService(config: _config, oidcClient: server.keycloak);
    final AuthSession account = (await auth.signInWithBroker(AuthService.googleBroker))!;
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = server;
    final List<AuthSession> handedOn = <AuthSession>[];

    await tester.pumpWidget(_app(ServiceProviderSignupScreen(
      api: OnboardingApi(dio),
      authService: auth,
      account: account,
      onFinished: handedOn.add,
      onClose: () {},
    )));
    await tester.pumpAndSettle();
    return (handedOn: handedOn, keycloak: server.keycloak);
  }

  Future<void> fillPrintShop(WidgetTester tester) async {
    await tester.enterText(_field(_en.svcBusinessName), 'Al Fakhry Press');
    await tester.pump();
    await _pick(tester, _en.svcServiceCategoryHint, _en.svcCategoryPrinting);
    await _pick(tester, _en.svcAreaHint, 'Mar Mikhael');
  }

  Future<void> tapApply(WidgetTester tester) async {
    await tester.ensureVisible(_apply);
    await tester.pumpAndSettle();
    await tester.tap(_apply);
    await _pump(tester);
  }

  testWidgets('offers only the open categories, and cannot be sent until the answers are there',
      (WidgetTester tester) async {
    final _Server server = _Server(_Keycloak())
      ..openCategories = <String>['PRINTING', 'REPAIRS'];
    await pumpForAccount(tester, server);

    expect(_enabled(tester, _apply), isFalse);
    await tester.enterText(_field(_en.svcBusinessName), 'Al Fakhry Press');
    await tester.pump();
    expect(_enabled(tester, _apply), isFalse, reason: 'no service chosen yet');

    await tester.tap(find.text(_en.svcServiceCategoryHint));
    await tester.pumpAndSettle();
    expect(find.text(_en.svcCategoryPrinting), findsOneWidget);
    expect(find.text(_en.svcCategoryRepairs), findsOneWidget);
    // Closed on the server, so never offered — whatever this build's taxonomy knows.
    expect(find.text(_en.svcCategoryTailoring), findsNothing);
    expect(find.text(_en.svcCategoryCleaning), findsNothing);
    await tester.tap(find.text(_en.svcCategoryPrinting));
    await tester.pumpAndSettle();
    expect(_enabled(tester, _apply), isFalse, reason: 'no area chosen yet');

    await _pick(tester, _en.svcAreaHint, 'Mar Mikhael');
    expect(_enabled(tester, _apply), isTrue);

    // A number that is not Lebanese is said, and holds the form back until it is fixed or cleared.
    await tester.enterText(_field(_en.authPhoneNumber), '12');
    await tester.pump();
    expect(find.text(_en.svcPhoneInvalid), findsOneWidget);
    expect(_enabled(tester, _apply), isFalse);
    await tester.enterText(_field(_en.authPhoneNumber), '');
    await tester.pump();
    expect(_enabled(tester, _apply), isTrue);
  });

  testWidgets(
      'applies as a MERCHANT whose details say SERVICES, and says honestly that it is waiting',
      (WidgetTester tester) async {
    final _Server server = _Server(_Keycloak());
    final ({List<AuthSession> handedOn, _Keycloak keycloak}) screen =
        await pumpForAccount(tester, server);

    await fillPrintShop(tester);
    await tapApply(tester);

    // One application, to the signed-in endpoint; no email code for an account that has an address.
    expect(server.calls.where((String c) => c.startsWith('POST')),
        <String>['POST /api/onboarding/applications/mine']);
    final Map<String, dynamic> body = server.bodies['POST /api/onboarding/applications/mine']!;
    expect(body['kind'], 'MERCHANT');
    expect(body['businessName'], 'Al Fakhry Press');
    expect(body['contactName'], 'Sam Salem');
    expect(body['details'], <String, dynamic>{
      'businessType': 'SERVICES',
      'serviceCategory': 'PRINTING',
      'area': <String, String>{'zoneId': 'zone-mar-mikhael', 'label': 'Mar Mikhael'},
    });
    expect(body.containsKey('contactEmail'), isFalse);
    expect(screen.keycloak.refreshes, 1, reason: 'the roles changed on the server, not in the token');

    // Waiting, said as waiting: nothing here suggests they can sell yet.
    expect(find.text(_en.svcPendingTitle), findsOneWidget);
    expect(find.text(_en.svcPendingBody('sam@gmail.example')), findsOneWidget);
    expect(find.text(_en.statusSubmitted), findsOneWidget);
    expect(find.text(_en.svcReference('ref-1')), findsOneWidget);
    expect(find.text(_en.svcPendingDocuments), findsOneWidget);
    expect(find.text(_en.svcApprovedTitle), findsNothing);

    await tester.tap(find.widgetWithText(AuthPrimaryButton, _en.continueLabel));
    await tester.pumpAndSettle();
    expect(screen.handedOn.single.hasRole(DeliveryRole.merchant), isTrue);
    expect(screen.handedOn.single.hasRole(DeliveryRole.applicant), isTrue);
  });

  testWidgets('says so when auto-approval has already said yes', (WidgetTester tester) async {
    final _Server server = _Server(_Keycloak())..automatic = true;
    final ({List<AuthSession> handedOn, _Keycloak keycloak}) screen =
        await pumpForAccount(tester, server);

    await fillPrintShop(tester);
    await tapApply(tester);

    expect(find.text(_en.svcApprovedTitle), findsOneWidget);
    expect(find.text(_en.svcApprovedBody), findsOneWidget);
    expect(find.text(_en.svcPendingTitle), findsNothing);

    await tester.tap(find.widgetWithText(AuthPrimaryButton, _en.continueLabel));
    await tester.pumpAndSettle();
    expect(screen.handedOn.single.hasRole(DeliveryRole.applicant), isFalse);
  });

  testWidgets('a refused category comes back to the form in the reader\'s words, and sends again',
      (WidgetTester tester) async {
    final _Server server = _Server(_Keycloak())
      ..refusal = (
        status: 422,
        body: <String, Object?>{
          'message': 'YouDrop is not taking applications for that service yet',
          'code': 'service-category-closed',
        },
      );
    await pumpForAccount(tester, server);

    await fillPrintShop(tester);
    await tapApply(tester);

    expect(_apply, findsOneWidget, reason: 'back on the form, where the answer can be changed');
    expect(find.text(_en.svcErrCategoryClosed), findsOneWidget);
    expect(find.text(_en.svcPendingTitle), findsNothing);

    await tapApply(tester);

    expect(find.text(_en.svcPendingTitle), findsOneWidget);
  });

  testWidgets('promises nothing the platform cannot back', (WidgetTester tester) async {
    await pumpForAccount(tester, _Server(_Keycloak()));

    expect(find.text(_en.svcSignupTitle), findsOneWidget);
    expect(find.text(_en.svcSignupBannerBody), findsOneWidget);
    for (final String unbacked in <String>['same-day', 'Same-day', 'thousands', 'Create Service Account']) {
      expect(find.textContaining(unbacked), findsNothing, reason: '"$unbacked" is the frame\'s copy');
    }
  });

  testWidgets('offers a retry, not a dead form, when the options cannot be read',
      (WidgetTester tester) async {
    final _Server server = _Server(_Keycloak())..optionsStatus = 503;
    await pumpForAccount(tester, server);

    expect(find.text(_en.svcOptionsFailed), findsOneWidget);
    expect(find.text(_en.svcServiceCategoryHint), findsNothing);

    server.optionsStatus = 200;
    await tester.tap(find.text(_en.tryAgain));
    await tester.pumpAndSettle();

    expect(find.text(_en.svcServiceCategoryHint), findsOneWidget);
  });

  testWidgets(
      'somebody with no account proves the address, applies, and has their account created',
      (WidgetTester tester) async {
    _phone(tester);
    final _Server server = _Server(_Keycloak());
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = server;

    await tester.pumpWidget(_app(ServiceProviderSignupScreen(
      api: OnboardingApi(dio),
      authService: AuthService(config: _config, oidcClient: server.keycloak),
      onFinished: (AuthSession _) {},
      onClose: () {},
    )));
    await tester.pumpAndSettle();

    await fillPrintShop(tester);
    expect(_enabled(tester, _apply), isFalse, reason: 'the open form also needs a name, address and passcode');
    await tester.enterText(_field(_en.authOwnerFullName), 'Sam Salem');
    await tester.enterText(_field(_en.authContactEmail), 'Sam@Example.test');
    await tester.enterText(_field(_en.password), '246810');
    await tester.pump();
    expect(_enabled(tester, _apply), isTrue);

    await tapApply(tester);
    expect(server.calls, contains('POST /api/onboarding/verifications'));
    expect(find.text(_en.authVerifyYourEmail), findsOneWidget);

    await tester.enterText(
        find.descendant(of: find.byType(OneTimeCodeField), matching: find.byType(TextField)),
        '123456');
    await _pump(tester);
    if (!server.calls.contains('POST /api/onboarding/verifications/confirm')) {
      await tester.tap(find.widgetWithText(AuthPrimaryButton, _en.verify));
      await _pump(tester);
    }

    final Map<String, dynamic> application = server.bodies['POST /api/onboarding/applications']!;
    expect(application['kind'], 'MERCHANT');
    expect(application['businessName'], 'Al Fakhry Press');
    // The server's spelling of the proved address, with its proof.
    expect(application['contactEmail'], 'sam@example.test');
    expect(application['emailVerificationToken'], 'proof-EMAIL');
    expect((application['details'] as Map<String, dynamic>)['businessType'], 'SERVICES');
    expect(server.bodies['POST /api/onboarding/applications/ref-open/account'], <String, dynamic>{
      'password': '246810',
    });
  });
}

/// Keycloak as the app sees it: a browser round trip and a refresh, each minting a token from the
/// roles the account holds at that moment.
class _Keycloak implements OidcClient {
  final Set<String> roles = <String>{'CUSTOMER'};
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

/// onboarding-service as the signup meets it: the options, the two front doors and the codes.
/// Anything else is recorded and refused, so a stray call shows up.
class _Server implements HttpClientAdapter {
  _Server(this.keycloak);

  final _Keycloak keycloak;
  final List<String> calls = <String>[];
  final Map<String, Map<String, dynamic>> bodies = <String, Map<String, dynamic>>{};

  int optionsStatus = 200;
  List<String> openCategories = <String>['PRINTING', 'TAILORING', 'REPAIRS', 'PHOTOGRAPHY'];

  /// Refuses the next signed-in application with this answer, once.
  ({int status, Map<String, Object?> body})? refusal;

  /// Grants MERCHANT without APPLICANT, as auto-approval does.
  bool automatic = false;

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    final String route = '${options.method} ${options.path}';
    calls.add(route);
    final Object? data = options.data;
    if (data is Map<String, dynamic>) bodies[route] = data;

    switch (route) {
      case 'GET /api/onboarding/service-options':
        if (optionsStatus != 200) {
          return _json(optionsStatus, <String, Object?>{'message': 'Please try again'});
        }
        return _json(200, <String, Object?>{
          'categories': openCategories,
          'areas': <Map<String, String>>[
            <String, String>{'zoneId': 'zone-mar-mikhael', 'name': 'Mar Mikhael'},
            <String, String>{'zoneId': 'zone-hamra', 'name': 'Hamra'},
          ],
        });
      case 'POST /api/onboarding/applications/mine':
        final ({int status, Map<String, Object?> body})? refused = refusal;
        if (refused != null) {
          refusal = null;
          return _json(refused.status, refused.body);
        }
        keycloak.roles.add('MERCHANT');
        if (!automatic) keycloak.roles.add('APPLICANT');
        return _json(201, _receipt(automatic ? 'APPROVED' : 'SUBMITTED', 'ref-1'));
      case 'POST /api/onboarding/verifications':
        return _json(202, <String, Object?>{'expiresAt': '2026-09-14T10:10:00Z'});
      case 'POST /api/onboarding/verifications/confirm':
        final Map<String, dynamic> code = data! as Map<String, dynamic>;
        return _json(200, <String, Object?>{
          'token': 'proof-${code['channel']}',
          'destination': (code['destination'] as String).toLowerCase(),
        });
      case 'POST /api/onboarding/applications':
        return _json(201, _receipt('SUBMITTED', 'ref-open'));
      case 'POST /api/onboarding/applications/ref-open/account':
        return _json(201, <String, Object?>{});
    }
    return _json(404, <String, Object?>{'message': 'not expected in this test: $route'});
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _receipt(String status, String reference) => <String, Object?>{
      'reference': reference,
      'status': status,
      'kind': 'MERCHANT',
      'businessName': 'Al Fakhry Press',
      'service': <String, Object?>{
        'category': 'PRINTING',
        'zoneId': 'zone-mar-mikhael',
        'area': 'Mar Mikhael',
      },
    };

ResponseBody _json(int status, Map<String, Object?> body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
