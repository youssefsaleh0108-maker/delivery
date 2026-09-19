import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/application_documents_step.dart';
import 'package:mobile_app/src/one_time_code.dart';
import 'package:mobile_app/src/service_signup_screen.dart';

/// Applying to offer services from the one-page signup (Figma 126:11).
///
/// Pinned: nothing is sent until the business, the service and the area are chosen, and the pickers
/// offer only what the server has open. What is sent is a MERCHANT application whose details say
/// SERVICES with the category and the area, and the session handed on was refreshed after the grant.
/// Straight after the application is recorded — on both paths — the national ID and commercial
/// registration are asked for, sent from there, and skippable; the last screen says whether they were
/// sent, and points to no place in the app that does not exist. It says plainly that nothing sells
/// until somebody decides — or that auto-approval did, in which case no documents are asked for. A
/// refused answer comes back to the form in the reader's words, and an account whose application is
/// for something else is told so with a way out rather than a retry. And the frame's promises the
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

Finder get _sendDocuments => find.widgetWithText(AuthPrimaryButton, _en.svcDocsSend);

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

/// Taps something on a screen with no endless animation on it.
Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await _pump(tester);
}

/// The file dialog, answered with a scanned PDF.
Future<PickedDocument?> _pickScan(String _) async => PickedDocument(
      bytes: Uint8List.fromList(<int>[37, 80, 68, 70]),
      contentType: 'application/pdf',
      fileName: 'scan.pdf',
    );

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
  Future<({List<AuthSession> handedOn, _Keycloak keycloak, _Documents documents, List<bool> closed})>
      pumpForAccount(WidgetTester tester, _Server server) async {
    _phone(tester);
    final AuthService auth = AuthService(config: _config, oidcClient: server.keycloak);
    final AuthSession account = (await auth.signInWithBroker(AuthService.googleBroker))!;
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = server;
    final List<AuthSession> handedOn = <AuthSession>[];
    final List<bool> closed = <bool>[];
    final _Documents documents = _Documents();

    await tester.pumpWidget(_app(ServiceProviderSignupScreen(
      api: OnboardingApi(dio),
      documentsApi: documents,
      authService: auth,
      account: account,
      pickDocument: _pickScan,
      onFinished: handedOn.add,
      onClose: () => closed.add(true),
    )));
    await tester.pumpAndSettle();
    return (handedOn: handedOn, keycloak: server.keycloak, documents: documents, closed: closed);
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
      'applies as a MERCHANT whose details say SERVICES, asks for the documents, and says honestly that it is waiting',
      (WidgetTester tester) async {
    final _Server server = _Server(_Keycloak());
    final ({
      List<AuthSession> handedOn,
      _Keycloak keycloak,
      _Documents documents,
      List<bool> closed
    }) screen = await pumpForAccount(tester, server);

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

    // Recorded and waiting: the papers a shop's application is judged on come next, and can wait.
    expect(find.text(_en.svcDocsTitle), findsOneWidget);
    expect(find.text(_en.docNationalId), findsOneWidget);
    expect(find.text(_en.docCommercialRegistration), findsOneWidget);
    expect(find.text(_en.svcDocsFootnote), findsOneWidget);
    expect(find.text(_en.wizDocSentOnSubmit), findsNothing, reason: 'the application is already in');
    expect(_enabled(tester, _sendDocuments), isFalse, reason: 'nothing picked yet');
    expect(find.text(_en.svcPendingTitle), findsNothing);

    await _tapText(tester, _en.skipThis);

    // Waiting, said as waiting: nothing here suggests they can sell yet.
    expect(find.text(_en.svcPendingTitle), findsOneWidget);
    expect(find.text(_en.svcPendingBody('sam@gmail.example')), findsOneWidget);
    expect(find.text(_en.statusSubmitted), findsOneWidget);
    expect(find.text(_en.svcReference('ref-1')), findsOneWidget);
    // What happened to the documents — and no pointer to a Settings row that opens the payout page.
    expect(find.text(_en.svcDocsSkipped), findsOneWidget);
    expect(find.textContaining('Settings'), findsNothing);
    expect(screen.documents.sent, isEmpty);
    expect(find.text(_en.svcApprovedTitle), findsNothing);

    await tester.tap(find.widgetWithText(AuthPrimaryButton, _en.continueLabel));
    await tester.pumpAndSettle();
    expect(screen.handedOn.single.hasRole(DeliveryRole.merchant), isTrue);
    expect(screen.handedOn.single.hasRole(DeliveryRole.applicant), isTrue);
  });

  testWidgets('sends the national ID and commercial registration picked right after applying',
      (WidgetTester tester) async {
    final ({
      List<AuthSession> handedOn,
      _Keycloak keycloak,
      _Documents documents,
      List<bool> closed
    }) screen = await pumpForAccount(tester, _Server(_Keycloak()));
    await fillPrintShop(tester);
    await tapApply(tester);

    await _tapText(tester, _en.docNationalId);
    await _tapText(tester, _en.docCommercialRegistration);
    expect(find.text('scan.pdf'), findsNWidgets(2));
    expect(_enabled(tester, _sendDocuments), isTrue);

    await tester.tap(_sendDocuments);
    await _pump(tester);

    expect(screen.documents.sent, <ApplicantDocumentKind>[
      ApplicantDocumentKind.nationalId,
      ApplicantDocumentKind.commercialRegistration,
    ]);
    expect(find.text(_en.svcPendingTitle), findsOneWidget);
    expect(find.text(_en.svcDocsSent), findsOneWidget);
    expect(find.text(_en.svcDocsSkipped), findsNothing);
  });

  testWidgets('a document that did not go through is sent again, and one that did is not',
      (WidgetTester tester) async {
    final ({
      List<AuthSession> handedOn,
      _Keycloak keycloak,
      _Documents documents,
      List<bool> closed
    }) screen = await pumpForAccount(tester, _Server(_Keycloak()));
    await fillPrintShop(tester);
    await tapApply(tester);
    await _tapText(tester, _en.docNationalId);
    await _tapText(tester, _en.docCommercialRegistration);
    screen.documents.failNext = DioException(requestOptions: RequestOptions(path: '/presign'));

    await tester.tap(_sendDocuments);
    await _pump(tester);

    expect(find.text(_en.svcDocsTitle), findsOneWidget, reason: 'still on the documents');
    expect(find.text(_en.wizDocUploadFailed), findsOneWidget);
    expect(screen.documents.sent,
        <ApplicantDocumentKind>[ApplicantDocumentKind.commercialRegistration]);

    await tester.tap(_sendDocuments);
    await _pump(tester);

    expect(screen.documents.sent, <ApplicantDocumentKind>[
      ApplicantDocumentKind.commercialRegistration,
      ApplicantDocumentKind.nationalId,
    ]);
    expect(find.text(_en.svcDocsSent), findsOneWidget);
  });

  testWidgets('says so when auto-approval has already said yes, and asks for no documents',
      (WidgetTester tester) async {
    final _Server server = _Server(_Keycloak())..automatic = true;
    final ({
      List<AuthSession> handedOn,
      _Keycloak keycloak,
      _Documents documents,
      List<bool> closed
    }) screen = await pumpForAccount(tester, server);

    await fillPrintShop(tester);
    await tapApply(tester);

    // A decided application's documents can no longer change.
    expect(find.text(_en.svcDocsTitle), findsNothing);
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
    await _tapText(tester, _en.skipThis);

    expect(find.text(_en.svcPendingTitle), findsOneWidget);
  });

  // The account's shop application lost its roles half way, so the profile menu offered this form;
  // the server refuses to resume a shop's application as a services one.
  testWidgets('an account whose application is for something else is told so, with a way out and no retry',
      (WidgetTester tester) async {
    final _Server server = _Server(_Keycloak())
      ..refusal = (
        status: 422,
        body: <String, Object?>{
          'message': 'This account already has an application to sell goods on YouDrop',
          'code': 'other-application',
        },
      );
    final ({
      List<AuthSession> handedOn,
      _Keycloak keycloak,
      _Documents documents,
      List<bool> closed
    }) screen = await pumpForAccount(tester, server);

    await fillPrintShop(tester);
    await tapApply(tester);

    expect(find.text(_en.accountOtherApplication), findsOneWidget);
    expect(find.widgetWithText(AuthPrimaryButton, _en.tryAgain), findsNothing,
        reason: 'sending the same form again can never change it');
    expect(find.text(_en.svcDocsTitle), findsNothing);
    expect(find.text(_en.svcPendingTitle), findsNothing);

    await tester.tap(find.widgetWithText(AuthPrimaryButton, _en.close));
    await tester.pump();
    expect(screen.closed, <bool>[true]);
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
      'somebody with no account proves the address, applies, has their account created, and is asked for the documents',
      (WidgetTester tester) async {
    _phone(tester);
    final _Server server = _Server(_Keycloak());
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = server;
    final _Documents documents = _Documents();

    await tester.pumpWidget(_app(ServiceProviderSignupScreen(
      api: OnboardingApi(dio),
      documentsApi: documents,
      authService: _PasswordGrant(server.keycloak),
      pickDocument: _pickScan,
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
    // The passcode, with the ticket the submission answered with: the reference names the
    // application, and proves nothing.
    expect(server.bodies['POST /api/onboarding/applications/ref-open/account'], <String, dynamic>{
      'password': '246810',
      'accountTicket': 'ticket-open',
    });

    // Signed in with the passcode just chosen, so the documents can travel — as on the other path.
    expect(find.text(_en.svcDocsTitle), findsOneWidget);
    await _tapText(tester, _en.docNationalId);
    await tester.tap(_sendDocuments);
    await _pump(tester);

    expect(documents.sent, <ApplicantDocumentKind>[ApplicantDocumentKind.nationalId]);
    expect(find.text(_en.svcPendingTitle), findsOneWidget);
    expect(find.text(_en.svcPendingBody('sam@example.test')), findsOneWidget);
    expect(find.text(_en.svcDocsSent), findsOneWidget);
  });

  testWidgets("an address that already has an account is said in the app's words at the passcode",
      (WidgetTester tester) async {
    _phone(tester);
    final _Server server = _Server(_Keycloak())
      ..accountRefusal = (
        status: 422,
        body: <String, Object?>{
          'code': 'account-exists',
          'message': 'An account already uses this email address. Sign in with it, or apply with a '
              'different email.',
        },
      );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = server;

    await tester.pumpWidget(_app(ServiceProviderSignupScreen(
      api: OnboardingApi(dio),
      documentsApi: _Documents(),
      authService: _PasswordGrant(server.keycloak),
      pickDocument: _pickScan,
      onFinished: (AuthSession _) {},
      onClose: () {},
    )));
    await tester.pumpAndSettle();

    await fillPrintShop(tester);
    await tester.enterText(_field(_en.authOwnerFullName), 'Sam Salem');
    await tester.enterText(_field(_en.authContactEmail), 'Sam@Example.test');
    await tester.enterText(_field(_en.password), '246810');
    await tester.pump();
    await tapApply(tester);
    await tester.enterText(
        find.descendant(of: find.byType(OneTimeCodeField), matching: find.byType(TextField)),
        '123456');
    await _pump(tester);
    if (!server.calls.contains('POST /api/onboarding/verifications/confirm')) {
      await tester.tap(find.widgetWithText(AuthPrimaryButton, _en.verify));
      await _pump(tester);
    }

    expect(server.calls, contains('POST /api/onboarding/applications/ref-open/account'));
    // Where a bare 500 used to read "That did not go through", the refusal is named — in the app's
    // own words, not the server's English.
    expect(find.text('${_en.couldNotCreateSignIn} ${_en.wizAccountExists}'), findsOneWidget);
    expect(find.textContaining('An account already uses'), findsNothing);
  });

  testWidgets('a sign-in already made goes straight on to signing in with the passcode chosen',
      (WidgetTester tester) async {
    // A retry whose earlier answer was lost: the sign-in was made and recorded, then the 201 never
    // arrived. Making it again can never succeed, and it does not need to.
    _phone(tester);
    final _Server server = _Server(_Keycloak())
      ..accountRefusal = (
        status: 422,
        body: <String, Object?>{
          'code': 'sign-in-exists',
          'message': 'That application already has a sign-in. Sign in with its email address and '
              'the passcode you chose.',
        },
      );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = server;
    final _PasswordGrant auth = _PasswordGrant(server.keycloak);

    await tester.pumpWidget(_app(ServiceProviderSignupScreen(
      api: OnboardingApi(dio),
      documentsApi: _Documents(),
      authService: auth,
      pickDocument: _pickScan,
      onFinished: (AuthSession _) {},
      onClose: () {},
    )));
    await tester.pumpAndSettle();

    await fillPrintShop(tester);
    await tester.enterText(_field(_en.authOwnerFullName), 'Sam Salem');
    await tester.enterText(_field(_en.authContactEmail), 'Sam@Example.test');
    await tester.enterText(_field(_en.password), '246810');
    await tester.pump();
    await tapApply(tester);
    await tester.enterText(
        find.descendant(of: find.byType(OneTimeCodeField), matching: find.byType(TextField)),
        '123456');
    await _pump(tester);
    if (!server.calls.contains('POST /api/onboarding/verifications/confirm')) {
      await tester.tap(find.widgetWithText(AuthPrimaryButton, _en.verify));
      await _pump(tester);
    }

    expect(server.calls, contains('POST /api/onboarding/applications/ref-open/account'));
    // Signed in with the proved address and the passcode, and on to the documents as after a
    // sign-in made just now — nothing to read, nothing to retry.
    expect(auth.grants, <String>['sam@example.test 246810']);
    expect(find.text(_en.svcDocsTitle), findsOneWidget);
    expect(find.textContaining(_en.couldNotCreateSignIn), findsNothing);
    expect(find.textContaining('already has a sign-in'), findsNothing);
  });

  testWidgets(
      'a ticket the server no longer takes is replaced by a new code on the address, and its proof',
      (WidgetTester tester) async {
    // The ticket's half hour ran out before the passcode reached the server. The reference cannot
    // stand in — delivery companies and back office see references — so the address is proved again.
    _phone(tester);
    final _Server server = _Server(_Keycloak())
      ..refuseOnce = true
      ..accountRefusal = (
        status: 422,
        body: <String, Object?>{
          'code': 'sign-in-proof-rejected',
          'message': 'That confirmation has expired or was already used.',
        },
      );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = server;
    final _PasswordGrant auth = _PasswordGrant(server.keycloak);

    await tester.pumpWidget(_app(ServiceProviderSignupScreen(
      api: OnboardingApi(dio),
      documentsApi: _Documents(),
      authService: auth,
      pickDocument: _pickScan,
      onFinished: (AuthSession _) {},
      onClose: () {},
    )));
    await tester.pumpAndSettle();

    await fillPrintShop(tester);
    await tester.enterText(_field(_en.authOwnerFullName), 'Sam Salem');
    await tester.enterText(_field(_en.authContactEmail), 'Sam@Example.test');
    await tester.enterText(_field(_en.password), '246810');
    await tester.pump();
    await tapApply(tester);
    Future<void> answer(String digits) async {
      final int before = server.confirmed;
      await tester.enterText(
          find.descendant(of: find.byType(OneTimeCodeField), matching: find.byType(TextField)),
          digits);
      await _pump(tester);
      if (server.confirmed == before) {
        await tester.tap(find.widgetWithText(AuthPrimaryButton, _en.verify));
        await _pump(tester);
      }
    }

    await answer('123456');

    // Refused with the ticket; a second code went to the application's address, and the code screen
    // says why it is asking again.
    expect(server.accountBodies.single['accountTicket'], 'ticket-open');
    expect(server.codesSent, <String>['sam@example.test', 'sam@example.test']);
    expect(find.text(_en.wizAccountConfirmAgain), findsOneWidget);
    expect(auth.grants, isEmpty);

    await answer('654321');

    expect(server.accountBodies.last, <String, dynamic>{
      'password': '246810',
      'emailVerificationToken': 'proof-EMAIL-2',
    });
    // The application went once; the sign-in is made and signed in, and the documents follow.
    expect(server.calls.where((String c) => c == 'POST /api/onboarding/applications'), hasLength(1));
    expect(auth.grants, <String>['sam@example.test 246810']);
    expect(find.text(_en.svcDocsTitle), findsOneWidget);
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

/// The password grant the open path signs in with, answered as Keycloak would for a new applicant:
/// the grant itself is a direct HTTP call a widget test cannot make.
class _PasswordGrant extends AuthService {
  _PasswordGrant(_Keycloak keycloak) : super(config: _config, oidcClient: keycloak);

  /// Who signed in with what, in order.
  final List<String> grants = <String>[];

  @override
  Future<AuthSession> signInWithPassword(String username, String password) async {
    grants.add('$username $password');
    return AuthSession(
      accessToken: 'applicant-token',
      refreshToken: null,
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      roles: const <DeliveryRole>{DeliveryRole.merchant, DeliveryRole.applicant},
      subject: 'sam-open',
    );
  }
}

/// The applicant's document endpoints as the signup meets them, without the storage round trip a
/// widget test cannot make: what was sent, and a failure on demand.
class _Documents extends DocumentsApi {
  _Documents() : super(Dio());

  final List<ApplicantDocumentKind> sent = <ApplicantDocumentKind>[];

  /// Fails the next upload with this, once.
  Object? failNext;

  @override
  Future<ApplicantDocument> upload({
    required ApplicantDocumentKind kind,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final Object? failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    sent.add(kind);
    return ApplicantDocument.fromJson(<String, dynamic>{
      'id': 'document-${kind.wire}',
      'kind': kind.wire,
      'status': 'PENDING',
    });
  }
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

  /// Answers the open form's passcode with this instead of making the sign-in.
  ({int status, Map<String, Object?> body})? accountRefusal;

  /// Whether [accountRefusal] answers the next passcode only, and then the sign-in is made.
  bool refuseOnce = false;

  /// Every body the passcode step was sent, in order.
  final List<Map<String, dynamic>> accountBodies = <Map<String, dynamic>>[];

  /// Where each code was sent, in order.
  final List<String> codesSent = <String>[];

  /// How many codes were confirmed: each proof names its number, so an old one tells from a new one.
  int confirmed = 0;

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
        codesSent.add(((data! as Map<String, dynamic>)['destination'] as String).toLowerCase());
        return _json(202, <String, Object?>{'expiresAt': '2026-09-14T10:10:00Z'});
      case 'POST /api/onboarding/verifications/confirm':
        final Map<String, dynamic> code = data! as Map<String, dynamic>;
        confirmed++;
        return _json(200, <String, Object?>{
          // The first proof keeps its plain name; a later one says which it is.
          'token': confirmed == 1 ? 'proof-${code['channel']}' : 'proof-${code['channel']}-$confirmed',
          'destination': (code['destination'] as String).toLowerCase(),
        });
      case 'POST /api/onboarding/applications':
        return _json(201, <String, Object?>{
          ..._receipt('SUBMITTED', 'ref-open'),
          'accountTicket': 'ticket-open',
        });
      case 'POST /api/onboarding/applications/ref-open/account':
        accountBodies.add(Map<String, dynamic>.of(data! as Map<String, dynamic>));
        final ({int status, Map<String, Object?> body})? refusedAccount = accountRefusal;
        if (refusedAccount != null) {
          if (refuseOnce) accountRefusal = null;
          return _json(refusedAccount.status, refusedAccount.body);
        }
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
