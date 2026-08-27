import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/carrier/settings_screen.dart';
import 'package:delivery_portal/src/shell/console_controls.dart';
import 'package:delivery_portal/src/shell/shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Company Preferences — Figma `carrier-settings` (3:3878).
///
/// The most speculative frame in the carrier set: of the eight things it offers, four have a
/// backend now that the payout endpoints exist. These tests hold that line. A settings page whose
/// controls quietly discard what is typed into them is worse than one that says it is not
/// finished, and the difference between the two is exactly what a reader cannot tell by looking.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({required this.company, this.payout});

  final Object company;

  /// The payout record `/applications/mine/payout` answers, or null for 404 — the bank step was
  /// never done. A PUT stores what was sent and answers it back, like the server does.
  Object? payout;

  final List<String> calls = <String>[];
  final List<Object?> bodies = <Object?>[];

  ResponseBody _json(Object body) =>
      ResponseBody.fromString(jsonEncode(body), 200, headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType]
      });

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    bodies.add(options.data);

    if (options.path.contains('/applications/mine/payout')) {
      if (options.method == 'PUT') {
        final Map<String, dynamic> sent = options.data as Map<String, dynamic>;
        payout = <String, dynamic>{
          'accountHolder': sent['accountHolder'],
          'iban': (sent['iban'] as String).replaceAll(' ', '').toUpperCase(),
          'verificationState': 'CHECKSUM_ONLY',
        };
        return _json(payout!);
      }
      if (payout == null) return ResponseBody.fromString('{}', 404);
      return _json(payout!);
    }
    return _json(company);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _company({
  String? accountRef,
  String payoutState = 'NONE',
  String? contactName = 'Cara Haddad',
}) =>
    <String, dynamic>{
      'id': 'p1',
      'slug': 'swift',
      'name': 'Swift Couriers Services Co.',
      'kind': 'EXTERNAL',
      'status': 'ACTIVE',
      'canTakeWork': true,
      'accountRef': accountRef,
      'contactName': contactName,
      'contactPhone': '+96170000000',
      'payoutState': payoutState,
    };

Map<String, dynamic> _payout({String iban = 'LB62099400000001001901229114'}) =>
    <String, dynamic>{
      'accountHolder': 'Swift Couriers Services Co.',
      'iban': iban,
      'verificationState': 'CHECKSUM_ONLY',
    };

late _StubAdapter _adapter;

({DeliveryProviderApi provider, DocumentsApi documents}) _api({
  Map<String, dynamic>? company,
  Map<String, dynamic>? payout,
}) {
  _adapter = _StubAdapter(company: company ?? _company(), payout: payout);
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))
    ..httpClientAdapter = _adapter;
  return (provider: DeliveryProviderApi(dio), documents: DocumentsApi(dio));
}

LocaleController _locale() => LocaleController(
      read: () async => null,
      write: (String _) async {},
    );

Widget _wrap(Widget child) => MaterialApp(
      locale: const Locale('en'),
      theme: DeliveryTheme.light(),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    );

Future<void> pump(
    WidgetTester tester, ({DeliveryProviderApi provider, DocumentsApi documents}) apis,
    {LocaleController? locale, double width = 1180}) async {
  tester.view.physicalSize = Size(width, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_wrap(
    CarrierSettingsScreen(
      api: apis.provider,
      locale: locale ?? _locale(),
      documentsApi: apis.documents,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('draws the design four cards', (WidgetTester tester) async {
    await pump(tester, _api());

    expect(find.text('Company Preferences'), findsOneWidget);
    expect(find.text('Carrier Identity'), findsOneWidget);
    expect(find.text('Payout Details'), findsOneWidget);
    expect(find.text('Configuration Preferences'), findsOneWidget);
    expect(find.text('API Integration Endpoint'), findsOneWidget);
  });

  testWidgets('shows the company record it really has', (WidgetTester tester) async {
    await pump(tester, _api());

    expect(find.text('Registered Legal Name'), findsOneWidget);
    expect(find.text('Swift Couriers Services Co.'), findsOneWidget);
    expect(find.text('Cara Haddad'), findsOneWidget);
    expect(find.text('+96170000000'), findsOneWidget);
  });

  testWidgets('a bank step never done reads "Not set yet", not an invented number',
      (WidgetTester tester) async {
    // The payout endpoint answers 404. A masked string that looked like a real IBAN would be the
    // app inventing one.
    await pump(tester, _api());

    expect(find.text('Not set yet'), findsNWidgets(2));
    expect(find.widgetWithText(ConsoleTintButton, 'Add bank account'), findsOneWidget);
    expect(find.textContaining('•'), findsNothing);
  });

  testWidgets('a stored IBAN is shown masked, never in full', (WidgetTester tester) async {
    await pump(tester, _api(payout: _payout()));

    expect(find.text('Swift Couriers Services Co.'), findsWidgets);
    // First four, last four, dots between — recognisable, not copyable.
    expect(find.text('LB62 •••••••••••••••••••• 9114'), findsOneWidget);
    expect(find.textContaining('LB62099400000001001901229114'), findsNothing);
    // The bank check's own verdict rides along.
    expect(find.text('Format checked'), findsOneWidget);
    expect(find.widgetWithText(ConsoleTintButton, 'Update bank account'), findsOneWidget);
  });

  testWidgets('the dialog PUTs holder and IBAN together and re-reads the record',
      (WidgetTester tester) async {
    await pump(tester, _api());

    await tester.tap(find.widgetWithText(ConsoleTintButton, 'Add bank account'));
    await tester.pumpAndSettle();

    // Dead until both fields carry something — the pair replaces the record together.
    final Finder save = find.widgetWithText(ConsolePrimaryButton, 'Save bank account');
    expect(tester.widget<ConsolePrimaryButton>(save).onPressed, isNull);

    final Finder fields =
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), 'Swift Couriers Services Co.');
    await tester.enterText(fields.at(1), 'LB62 0994 0000 0001 0019 0122 9114');
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(
      _adapter.calls.any(
          (String c) => c.startsWith('PUT') && c.contains('/applications/mine/payout')),
      isTrue,
    );
    // Sent as typed — the server normalises, not the client.
    expect(
      _adapter.bodies.any((Object? b) =>
          b is Map && b['iban'] == 'LB62 0994 0000 0001 0019 0122 9114'),
      isTrue,
    );
    // The card now shows the stored account, masked.
    expect(find.text('LB62 •••••••••••••••••••• 9114'), findsOneWidget);
  });

  testWidgets('an unverified payout account is visible on the card', (WidgetTester tester) async {
    await pump(tester, _api(company: _company(payoutState: 'UNCONFIRMED')));

    expect(find.widgetWithText(ConsoleStatusPill, 'Unconfirmed'), findsOneWidget);
  });

  testWidgets('the language toggle is live and everything else is not',
      (WidgetTester tester) async {
    final LocaleController locale = _locale();
    await pump(tester, _api(), locale: locale);

    expect(locale.isArabic, isFalse);
    await tester.tap(find.text('العربية'));
    await tester.pumpAndSettle();
    expect(locale.isArabic, isTrue);

    // The three drawn-but-unbacked controls: the logo upload, the API key, and the save that would
    // persist what neither of them can change. The bank-account button beside them is live now, so
    // the dead one is named rather than found by type.
    expect(
        tester
            .widget<ConsoleTintButton>(
                find.widgetWithText(ConsoleTintButton, 'Upload Logo'))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<ConsolePrimaryButton>(
                find.widgetWithText(ConsolePrimaryButton, 'Save Settings Configuration'))
            .onPressed,
        isNull);
    expect(find.text('No API key has been issued'), findsOneWidget);
  });

  testWidgets('every dead affordance is chipped rather than left to look working',
      (WidgetTester tester) async {
    await pump(tester, _api());

    // Global search, logo upload, bank partner, dispatch regions, API key.
    expect(find.byType(ConsoleComingSoonChip), findsNWidgets(5));
  });

  // Two columns at 1180 and 1020, one below 980. An overflow fails the test.
  for (final double width in <double>[1180, 1020, 764]) {
    testWidgets('lays out at a ${width.toInt()}px content column', (WidgetTester tester) async {
      await pump(tester, _api(), width: width);
      expect(tester.takeException(), isNull);
    });
  }
}
