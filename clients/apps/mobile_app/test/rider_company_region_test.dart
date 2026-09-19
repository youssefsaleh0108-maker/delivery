import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/application_refusals.dart';
import 'package:mobile_app/src/one_time_code.dart';
import 'package:mobile_app/src/partner_application_screen.dart';

/// A rider who applies to a delivery company is shown the company's region, read-only, instead of
/// being asked where they will work (owner, 2026-09).
///
/// Pinned here: the company is chosen first, and choosing one swaps the map pin, the free-text area
/// and the zones card for the company's region — its zone names, or a dash when it has drawn none —
/// while nothing typed before the choice travels with the application; riding for YouDrop keeps all
/// three; a company that stopped hiring sends the rider back to choose again, and a check that could
/// not be made offers the retry, both in the app's own words — and on the open form, choosing again
/// sends the proofs of address and number already made rather than asking for new codes; and the
/// step holds at 320dp and in Arabic, right to left, where the five regions a company registers with
/// are said in Arabic.
const AuthConfig _config = AuthConfig(
  issuer: 'https://iam.test/realms/delivery-platform',
  clientId: 'mobile-app',
  redirectUrl: 'com.delivery.app://oauth2redirect',
);

const String _notHiring =
    "That delivery company isn't taking riders right now. Choose another company, or ride for "
    'YouDrop.';

Widget _app(Widget home, Locale locale) => MaterialApp(
      locale: locale,
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

Future<void> _choose(WidgetTester tester, String row) async {
  final Finder target = find.text(row);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// Taps Submit and lets the application go out. The finishing phase draws a spinner, so this pumps
/// rather than settles.
Future<void> _submit(WidgetTester tester, DeliveryStrings t) async {
  final Finder submit = find.widgetWithText(AuthPrimaryButton, t.authSubmitApplication);
  await tester.ensureVisible(submit);
  await tester.pumpAndSettle();
  await tester.tap(submit);
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder _areaField() =>
    find.byWidgetPredicate((Widget w) => w is AuthField && w.label == 'Preferred area');

Finder _mapOrItsPlaceholder() =>
    find.byWidgetPredicate((Widget w) => w is FlutterMap || w is AuthMapPlaceholder);

int _hiringReads(_Server server) =>
    server.calls.where((String c) => c == 'GET /api/onboarding/hiring-companies').length;

/// The text field inside the wizard's [AuthField] labelled [label].
Finder _fieldOf(String label) => find.descendant(
    of: find.byWidgetPredicate((Widget w) => w is AuthField && w.label == label),
    matching: find.byType(TextField));

/// Lets a request go out and its answer land. The code steps draw a caret that never settles, so
/// this pumps rather than settles.
Future<void> _pumpABit(WidgetTester tester) async {
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Types the six digits of a code into the code step, which confirms it on the last one.
Future<void> _enterCode(WidgetTester tester, String code) async {
  await tester.enterText(
      find.descendant(of: find.byType(OneTimeCodeField), matching: find.byType(TextField)), code);
  await _pumpABit(tester);
}

int _codesAskedFor(_Server server, String channel) =>
    server.codesSent.where((String c) => c == channel).length;

/// The rider wizard on the open form — nobody signed in — filled in with an address, a number and a
/// passcode, and walked to its last step: who they ride for.
Future<DeliveryStrings> _openTheOpenFormAtTheLastStep(WidgetTester tester, _Server server,
    {required void Function(AuthSession) onSignedIn}) async {
  final DeliveryStrings t = await DeliveryStrings.delegate.load(const Locale('en'));
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = server;

  await tester.pumpWidget(_app(
      PartnerApplicationScreen(
        api: OnboardingApi(dio),
        documentsApi: DocumentsApi(dio),
        kind: PartnerKind.rider,
        authService: _PasswordGrant(server.keycloak),
        onSignedIn: onSignedIn,
        onClose: () {},
      ),
      const Locale('en')));
  await tester.pumpAndSettle();
  await _tapButton(tester, t.authGetStarted);
  await tester.enterText(_fieldOf(t.authFullName), 'Sam Salem');
  await tester.enterText(_fieldOf(t.authEmailAddress), 'Sam@Example.test');
  await tester.enterText(_fieldOf(t.authPhoneNumber), '71 123 456');
  await tester.enterText(_fieldOf(t.password), '246810');
  await tester.pump();
  await _tapButton(tester, t.authNext); // -> vehicle
  await _tapButton(tester, t.authNext); // -> documents
  await _tapButton(tester, t.authNext); // -> who they ride for
  return t;
}

/// The rider wizard for a signed-in Google account, walked to its last step: who they ride for.
Future<DeliveryStrings> _openAtTheLastStep(WidgetTester tester, _Server server,
    {Locale locale = const Locale('en')}) async {
  final DeliveryStrings t = await DeliveryStrings.delegate.load(locale);
  final AuthService auth = AuthService(config: _config, oidcClient: server.keycloak);
  final AuthSession account = (await auth.signInWithBroker(AuthService.googleBroker))!;
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = server;

  await tester.pumpWidget(_app(
      PartnerApplicationScreen(
        api: OnboardingApi(dio),
        documentsApi: DocumentsApi(dio),
        kind: PartnerKind.rider,
        authService: auth,
        account: account,
        onSignedIn: (_) {},
        onClose: () {},
      ),
      locale));
  await tester.pumpAndSettle();
  await _tapButton(tester, t.authGetStarted);
  await _tapButton(tester, t.authNext); // -> vehicle
  await _tapButton(tester, t.authNext); // -> documents
  await _tapButton(tester, t.authNext); // -> who they ride for
  return t;
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
      "a company rider sees the company's region, read-only, and no pin, area or zones card",
      (WidgetTester tester) async {
    _phone(tester);
    final _Server server = _Server();
    final DeliveryStrings t = await _openAtTheLastStep(tester, server);

    // Who they ride for comes first; until they say, the step still asks where they will work.
    expect(tester.getTopLeft(find.text('WHO WILL YOU RIDE FOR?')).dy,
        lessThan(tester.getTopLeft(_areaField()).dy));
    await tester.enterText(
        find.descendant(of: _areaField(), matching: find.byType(TextField)), 'Verdun');
    await tester.pump();

    // A company that has drawn no zone yet: a dash, never an invented place.
    await _choose(tester, 'Fresh Fleet');
    expect(find.text('DELIVERY REGION'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(
        find.byWidgetPredicate((Widget w) =>
            w is Semantics && w.properties.label == 'No delivery region listed yet'),
        findsOneWidget);

    await _choose(tester, 'Swift Couriers');
    expect(find.text('Achrafieh'), findsOneWidget);
    expect(find.text('Hamra'), findsOneWidget);
    expect(find.text('—'), findsNothing);
    expect(
        find.text('Set by Swift Couriers. You deliver where the company delivers, so there is no '
            'area to choose.'),
        findsOneWidget);
    // Nothing to choose, so nothing drawn as a choice: no map, no area, no zones card, no field.
    expect(_mapOrItsPlaceholder(), findsNothing);
    expect(_areaField(), findsNothing);
    expect(find.text('No zones to pick'), findsNothing);
    expect(find.byType(TextField), findsNothing);

    await _submit(tester, t);
    final Map<String, dynamic> sent = server.applications.single;
    expect(sent['targetProviderId'], 'swift-id');
    final Map<String, dynamic> details = sent['details'] as Map<String, dynamic>;
    expect(details['ridesFor'], 'Swift Couriers');
    expect(details.containsKey('preferredArea'), isFalse,
        reason: 'typed before the company was chosen, and no longer theirs to say');
    expect(details.containsKey('workLatitude'), isFalse);
    expect(details.containsKey('workLongitude'), isFalse);
  });

  testWidgets('a rider riding for YouDrop keeps the pin, the area and the zones card',
      (WidgetTester tester) async {
    _phone(tester);
    final _Server server = _Server();
    final DeliveryStrings t = await _openAtTheLastStep(tester, server);

    await _choose(tester, 'YouDrop');
    expect(_mapOrItsPlaceholder(), findsOneWidget);
    expect(_areaField(), findsOneWidget);
    expect(find.text('No zones to pick'), findsOneWidget);
    expect(find.text('DELIVERY REGION'), findsNothing);

    await tester.enterText(
        find.descendant(of: _areaField(), matching: find.byType(TextField)), 'Verdun');
    await tester.pump();
    await _submit(tester, t);

    final Map<String, dynamic> sent = server.applications.single;
    expect(sent['targetProviderId'], isNull);
    final Map<String, dynamic> details = sent['details'] as Map<String, dynamic>;
    expect(details['preferredArea'], 'Verdun');
    expect(details['ridesFor'], 'YOUDROP');
  });

  testWidgets("a company that stopped hiring sends the rider back to choose again, in the app's words",
      (WidgetTester tester) async {
    _phone(tester);
    final _Server server = _Server()
      ..refusal = (
        status: 422,
        body: <String, Object?>{
          'message': 'That delivery company is not taking riders right now. Choose another '
              'company, or ride for YouDrop',
          'code': 'company-not-hiring',
        },
      );
    final DeliveryStrings t = await _openAtTheLastStep(tester, server);
    await _choose(tester, 'Swift Couriers');
    await _submit(tester, t);
    await tester.pumpAndSettle();

    expect(find.text(_notHiring), findsOneWidget);
    expect(find.textContaining('is not taking riders'), findsNothing,
        reason: "the server's English is not what the rider reads");
    // Back on the step rather than offered a retry that could only be refused again: the list is
    // read afresh, the company has left it, and nothing is chosen.
    expect(find.widgetWithText(AuthPrimaryButton, t.tryAgain), findsNothing);
    expect(find.widgetWithText(AuthPrimaryButton, t.authSubmitApplication), findsOneWidget);
    expect(_hiringReads(server), 2);
    expect(find.text('Swift Couriers'), findsNothing);
    expect(find.text('Fresh Fleet'), findsOneWidget);
    expect(find.text('DELIVERY REGION'), findsNothing);
  });

  testWidgets("a company that could not be checked is said in the app's words, with the retry that fixes it",
      (WidgetTester tester) async {
    _phone(tester);
    final _Server server = _Server()
      ..refusal = (
        status: 503,
        body: <String, Object?>{
          'message': 'We could not check that delivery company just now. Please try again in a '
              'moment.',
          'code': 'hiring-companies-unavailable',
        },
      );
    final DeliveryStrings t = await _openAtTheLastStep(tester, server);
    await _choose(tester, 'Swift Couriers');
    await _submit(tester, t);

    expect(find.text("We couldn't check that delivery company just now. Try again in a moment."),
        findsOneWidget);
    expect(find.widgetWithText(AuthPrimaryButton, t.tryAgain), findsOneWidget);
    expect(_hiringReads(server), 1);
  });

  // The server refuses a company that is not hiring before it records anything, and a proof is only
  // spent with the record — so after choosing again, the proofs already made are still good.
  // Asking for new codes made the rider wait on two more messages, and a code asked for within a
  // minute of the last one is refused outright.
  testWidgets(
      'on the open form, a rider sent back to choose again sends the proofs they already made, '
      'with no new codes', (WidgetTester tester) async {
    _phone(tester);
    AuthSession? signedIn;
    final _Server server = _Server()
      ..refusal = (
        status: 422,
        body: <String, Object?>{
          'message': 'That delivery company is not taking riders right now.',
          'code': 'company-not-hiring',
        },
      );
    final DeliveryStrings t = await _openTheOpenFormAtTheLastStep(tester, server,
        onSignedIn: (AuthSession session) => signedIn = session);
    await _choose(tester, 'Swift Couriers');
    await _submit(tester, t);
    expect(find.text(t.authVerifyYourEmail), findsOneWidget);
    await _enterCode(tester, '123456');
    expect(find.text(t.authVerifyYourNumber), findsOneWidget);
    await _enterCode(tester, '654321');
    await tester.pumpAndSettle();

    // Refused, and back on the step with the company gone from the list.
    expect(find.text(_notHiring), findsOneWidget);
    expect(server.applications, hasLength(1));
    expect(find.text('Swift Couriers'), findsNothing);

    await _choose(tester, 'Fresh Fleet');
    await _submit(tester, t);
    await _pumpABit(tester);

    // Straight out again: no code step, and no code asked for.
    expect(_codesAskedFor(server, 'EMAIL'), 1);
    expect(_codesAskedFor(server, 'PHONE'), 1);
    expect(find.text(t.authVerifyYourEmail), findsNothing);
    expect(find.text(t.authVerifyYourNumber), findsNothing);
    expect(server.applications, hasLength(2));
    final Map<String, dynamic> resent = server.applications.last;
    expect(resent['targetProviderId'], 'fresh-id');
    expect(resent['contactEmail'], 'sam@example.test');
    expect(resent['emailVerificationToken'], 'proof-EMAIL-1');
    expect(resent['contactPhone'], '+96171123456');
    expect(resent['phoneVerificationToken'], 'proof-PHONE-1');
    // And the rest of the way: the sign-in is made with the passcode and the rider is signed in.
    expect(server.calls, contains('POST /api/onboarding/applications/ref-open/account'));
    expect(signedIn, isNotNull);
  });

  testWidgets(
      'on the open form, a number changed after the refusal is proved again, and only the number',
      (WidgetTester tester) async {
    _phone(tester);
    final _Server server = _Server()
      ..refusal = (
        status: 422,
        body: <String, Object?>{
          'message': 'That delivery company is not taking riders right now.',
          'code': 'company-not-hiring',
        },
      );
    final DeliveryStrings t =
        await _openTheOpenFormAtTheLastStep(tester, server, onSignedIn: (_) {});
    await _choose(tester, 'Swift Couriers');
    await _submit(tester, t);
    await _enterCode(tester, '123456');
    await _enterCode(tester, '654321');
    await tester.pumpAndSettle();
    expect(find.text(_notHiring), findsOneWidget);

    // Back to the first step for a different number, then on to the company again.
    for (int step = 0; step < 3; step++) {
      await tester.tap(find.byType(AuthBackButton));
      await tester.pumpAndSettle();
    }
    await tester.enterText(_fieldOf(t.authPhoneNumber), '03 555 666');
    await tester.pump();
    await _tapButton(tester, t.authNext);
    await _tapButton(tester, t.authNext);
    await _tapButton(tester, t.authNext);
    await _choose(tester, 'Fresh Fleet');
    await _submit(tester, t);

    // The address is still the one proved, so no code for it; the number is new, so one for it.
    expect(_codesAskedFor(server, 'EMAIL'), 1);
    expect(_codesAskedFor(server, 'PHONE'), 2);
    expect(find.text(t.authVerifyYourNumber), findsOneWidget);
    await _enterCode(tester, '112233');

    final Map<String, dynamic> resent = server.applications.last;
    expect(server.applications, hasLength(2));
    expect(resent['emailVerificationToken'], 'proof-EMAIL-1');
    expect(resent['contactPhone'], '+9613555666');
    expect(resent['phoneVerificationToken'], 'proof-PHONE-2');
  });

  test('the two company answers are said in English and in Arabic, and nothing else is claimed',
      () async {
    final DeliveryStrings en = await DeliveryStrings.delegate.load(const Locale('en'));
    final DeliveryStrings ar = await DeliveryStrings.delegate.load(const Locale('ar'));
    DioException answer(int status, String code) {
      final RequestOptions request = RequestOptions(path: '/api/onboarding/applications');
      return DioException(
        requestOptions: request,
        response: Response<dynamic>(
          requestOptions: request,
          statusCode: status,
          data: <String, Object?>{'message': 'the server English', 'code': code},
        ),
      );
    }

    expect(riderCompanyRefusal(en, answer(422, 'company-not-hiring')), _notHiring);
    expect(riderCompanyRefusal(ar, answer(422, 'company-not-hiring')),
        ar.riderRegionCompanyNotHiring);
    expect(ar.riderRegionCompanyNotHiring, isNot(en.riderRegionCompanyNotHiring));
    expect(riderCompanyRefusal(ar, answer(503, 'hiring-companies-unavailable')),
        ar.riderRegionCompaniesUnavailable);
    expect(riderCompanyRefusal(en, answer(422, 'already-partner')), isNull);
    expect(riderCompanyRefusal(en, StateError('offline')), isNull);
    expect(isCompanyNotHiring(answer(422, 'company-not-hiring')), isTrue);
    expect(isCompanyNotHiring(answer(503, 'hiring-companies-unavailable')), isFalse);
  });

  testWidgets('holds at 320dp with a long company name and long region names',
      (WidgetTester tester) async {
    _phone(tester);
    const String company = 'Swift Couriers and Logistics of Greater Beirut and Mount Lebanon';
    const String region = 'Mar Mikhael and the streets below the Gemmayze stairs to Saifi';
    final _Server server = _Server()
      ..hiring = <Map<String, Object?>>[
        <String, Object?>{
          'id': 'long-id',
          'name': company,
          'regions': <String>[region, 'Achrafieh'],
        },
      ];
    await _openAtTheLastStep(tester, server);

    // This step, at the narrowest phone the app supports.
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    await tester.pumpAndSettle();
    await _choose(tester, company);

    expect(find.text(region), findsOneWidget);
    expect(tester.getSize(find.text(region)).width, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('in Arabic the region reads right to left, in Arabic words',
      (WidgetTester tester) async {
    _phone(tester);
    const String company = 'سويفت للتوصيل';
    final _Server server = _Server()
      ..hiring = <Map<String, Object?>>[
        <String, Object?>{
          'id': 'swift-id',
          'name': company,
          'regions': <String>['الأشرفية', 'الحمرا'],
        },
      ];
    final DeliveryStrings ar =
        await _openAtTheLastStep(tester, server, locale: const Locale('ar'));

    await _choose(tester, company);

    expect(find.text(ar.riderRegionLabel), findsOneWidget);
    expect(find.text(ar.riderRegionSetBy(company)), findsOneWidget);
    expect(find.text('الأشرفية'), findsOneWidget);
    expect(find.text('الحمرا'), findsOneWidget);
    expect(Directionality.of(tester.element(find.text('الأشرفية'))), TextDirection.rtl);
    // The pin leads the row, and in Arabic a row starts on the right.
    expect(tester.getCenter(find.byIcon(Icons.place_outlined).first).dx,
        greaterThan(tester.getCenter(find.text('الأشرفية')).dx));
    expect(_mapOrItsPlaceholder(), findsNothing);
  });

  // A company with no zones is listed with the regions it registered with, which the server sends
  // in English whatever the phone's language.
  testWidgets('in Arabic, the regions a company registered with are said in Arabic',
      (WidgetTester tester) async {
    _phone(tester);
    final _Server server = _Server()
      ..hiring = <Map<String, Object?>>[
        <String, Object?>{
          'id': 'fresh-id',
          'name': 'Fresh Fleet',
          'regions': <String>['Beirut'],
        },
      ];
    await _openAtTheLastStep(tester, server, locale: const Locale('ar'));

    await _choose(tester, 'Fresh Fleet');

    expect(find.text('بيروت'), findsOneWidget);
    expect(find.text('Beirut'), findsNothing);
  });

  testWidgets("in Arabic, a delivery company's coverage chips are said in Arabic",
      (WidgetTester tester) async {
    _phone(tester);
    final DeliveryStrings ar = await DeliveryStrings.delegate.load(const Locale('ar'));
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = _Server();
    await tester.pumpWidget(_app(
        PartnerApplicationScreen(
          api: OnboardingApi(dio),
          documentsApi: DocumentsApi(dio),
          kind: PartnerKind.carrier,
          authService: AuthService(config: _config, oidcClient: _Keycloak()),
          onSignedIn: (_) {},
          onClose: () {},
        ),
        const Locale('ar')));
    await tester.pumpAndSettle();
    await _tapButton(tester, ar.carrRegisterCompany);

    for (final String area in <String>['بيروت', 'جبل لبنان', 'الشمال', 'الجنوب', 'البقاع']) {
      expect(find.widgetWithText(YdChip, area), findsOneWidget, reason: area);
    }
    expect(find.widgetWithText(YdChip, 'Beirut'), findsNothing);
  });

  test('only the five registered regions are translated, by their exact names; any other name is shown as it is',
      () async {
    final DeliveryStrings ar = await DeliveryStrings.delegate.load(const Locale('ar'));
    final DeliveryStrings en = await DeliveryStrings.delegate.load(const Locale('en'));

    expect(areaLabel(ar, 'Beirut'), 'بيروت');
    expect(areaLabel(ar, 'Mount Lebanon'), 'جبل لبنان');
    expect(areaLabel(ar, 'North'), 'الشمال');
    expect(areaLabel(ar, 'South'), 'الجنوب');
    expect(areaLabel(ar, 'Bekaa'), 'البقاع');
    expect(areaLabel(en, 'Mount Lebanon'), 'Mount Lebanon');
    // A zone a company drew and named is its own words.
    expect(areaLabel(ar, 'Achrafieh'), 'Achrafieh');
    expect(areaLabel(ar, 'beirut'), 'beirut');
    expect(areaLabel(ar, 'الحمرا'), 'الحمرا');
  });
}

/// A password sign-in without Keycloak: the account the open form just made, signed in.
class _PasswordGrant extends AuthService {
  _PasswordGrant(_Keycloak keycloak) : super(config: _config, oidcClient: keycloak);

  @override
  Future<AuthSession> signInWithPassword(String username, String password) async => AuthSession(
        accessToken: 'applicant-token',
        refreshToken: null,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        roles: const <DeliveryRole>{DeliveryRole.delivery, DeliveryRole.applicant},
        subject: 'sam-open',
      );
}

/// Keycloak as the app sees it: a browser round trip and a refresh, each minting a token from the
/// roles the account holds at that moment.
class _Keycloak implements OidcClient {
  final Set<String> roles = <String>{};

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
      refreshToken: 'refresh',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
  }

  @override
  Future<TokenSet?> signIn(AuthConfig config, {Map<String, String>? extraParams}) async => _mint();

  @override
  Future<TokenSet?> completeRedirect(AuthConfig config) async => null;

  @override
  Future<TokenSet> refresh(AuthConfig config, String refreshToken) async => _mint();

  @override
  Future<void> signOut(AuthConfig config, String? refreshToken) async {}
}

/// onboarding-service's open list of who is hiring — each company with its region already resolved,
/// zones or else registered regions — its application endpoints, signed-in and open, and the open
/// form's verification pair. Anything else the screen calls is recorded and refused, so a stray call
/// shows up.
class _Server implements HttpClientAdapter {
  final _Keycloak keycloak = _Keycloak();
  final List<String> calls = <String>[];
  final List<Map<String, dynamic>> applications = <Map<String, dynamic>>[];

  /// The channel of every code asked for, in order.
  final List<String> codesSent = <String>[];

  /// How many codes each channel has had confirmed: the proof a confirmation hands out names its
  /// channel and its number, so a test can tell an old proof from a new one.
  final Map<String, int> _confirmed = <String, int>{};

  /// Who is hiring: one company with two zones, and one that has drawn none.
  List<Map<String, Object?>> hiring = <Map<String, Object?>>[
    <String, Object?>{
      'id': 'swift-id',
      'name': 'Swift Couriers',
      'regions': <String>['Achrafieh', 'Hamra'],
    },
    <String, Object?>{'id': 'fresh-id', 'name': 'Fresh Fleet', 'regions': <String>[]},
  ];

  /// Answers the next application with this instead of taking it, once. A company-not-hiring refusal
  /// also takes the company off the list, as Order Manager's list would already have.
  ({int status, Map<String, Object?> body})? refusal;

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    final String route = '${options.method} ${options.path}';
    calls.add(route);

    if (route == 'GET /api/onboarding/hiring-companies') return _json(200, hiring);

    if (route == 'POST /api/onboarding/verifications') {
      codesSent.add((options.data as Map<String, dynamic>)['channel'] as String);
      return _json(202, <String, Object?>{'expiresAt': '2026-09-19T10:10:00Z'});
    }
    if (route == 'POST /api/onboarding/verifications/confirm') {
      final Map<String, dynamic> code = options.data as Map<String, dynamic>;
      final String channel = code['channel'] as String;
      final int count = _confirmed[channel] = (_confirmed[channel] ?? 0) + 1;
      final String typed = code['destination'] as String;
      return _json(200, <String, Object?>{
        'token': 'proof-$channel-$count',
        // The server's spelling: an address in small letters, a number with its country code.
        'destination': channel == 'EMAIL'
            ? typed.toLowerCase()
            : '+961${typed.replaceAll(' ', '').replaceFirst(RegExp('^0'), '')}',
      });
    }

    if (route == 'POST /api/onboarding/applications/mine' ||
        route == 'POST /api/onboarding/applications') {
      final Map<String, dynamic> body = options.data as Map<String, dynamic>;
      applications.add(body);
      final ({int status, Map<String, Object?> body})? refused = refusal;
      if (refused != null) {
        refusal = null;
        if (refused.body['code'] == 'company-not-hiring') {
          hiring = hiring
              .where((Map<String, Object?> c) => c['id'] != body['targetProviderId'])
              .toList();
        }
        return _json(refused.status, refused.body);
      }
      if (route == 'POST /api/onboarding/applications') {
        return _json(201, <String, Object?>{
          'reference': 'ref-open',
          'status': 'SUBMITTED',
          'kind': 'RIDER',
          'businessName': body['businessName'],
        });
      }
      keycloak.roles
        ..add('APPLICANT')
        ..add('DELIVERY');
      return _json(201, <String, Object?>{
        'reference': 'ref-1',
        'status': 'SUBMITTED',
        'kind': 'RIDER',
        'businessName': body['businessName'],
      });
    }
    if (route == 'POST /api/onboarding/applications/ref-open/account') {
      return _json(201, <String, Object?>{});
    }
    return _json(404, <String, Object?>{'message': 'not expected in this test'});
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
