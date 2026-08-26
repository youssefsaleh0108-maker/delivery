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
/// The most speculative frame in the carrier set: of the eight things it offers, three have a
/// backend. These tests hold that line. A settings page whose controls quietly discard what is
/// typed into them is worse than one that says it is not finished, and the difference between the
/// two is exactly what a reader cannot tell by looking.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body);

  final Object body;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    return ResponseBody.fromString(jsonEncode(body), 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    });
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

DeliveryProviderApi _api({Map<String, dynamic>? company}) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))
    ..httpClientAdapter = _StubAdapter(company ?? _company());
  return DeliveryProviderApi(dio);
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

Future<void> pump(WidgetTester tester, DeliveryProviderApi api,
    {LocaleController? locale, double width = 1180}) async {
  tester.view.physicalSize = Size(width, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_wrap(
    CarrierSettingsScreen(api: api, locale: locale ?? _locale()),
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

  testWidgets('an IBAN the portal is not given is not invented', (WidgetTester tester) async {
    // `accountRef` is withheld from every audience but the Backoffice on purpose. A masked string
    // that looked like a real IBAN would be the app inventing one.
    await pump(tester, _api());

    expect(find.text('Held by the platform, not shown here'), findsOneWidget);
    expect(find.textContaining('SA80'), findsNothing);
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
    // persist what neither of them can change.
    expect(tester.widget<ConsoleTintButton>(find.byType(ConsoleTintButton)).onPressed, isNull);
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
