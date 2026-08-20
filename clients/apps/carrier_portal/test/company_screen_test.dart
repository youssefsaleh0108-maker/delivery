import 'dart:convert';
import 'dart:typed_data';

import 'package:carrier_portal/src/company_screen.dart';
import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The delivery company's own view.
///
/// What matters here is that a carrier is told the things that decide whether they get work: their
/// score and what it is made of, whether they are taking orders, whether they have any riders, and
/// whether they can actually be paid. Each of those was invisible to them before this screen.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.responses);

  final Map<String, Object> responses;
  final List<String> calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    for (final MapEntry<String, Object> entry in responses.entries) {
      if (options.path.endsWith(entry.key)) {
        return ResponseBody.fromString(jsonEncode(entry.value), 200,
            headers: <String, List<String>>{
              Headers.contentTypeHeader: <String>[Headers.jsonContentType]
            });
      }
    }
    return ResponseBody.fromString('{}', 404);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _company({
  String status = 'ACTIVE',
  bool canTakeWork = true,
  String payoutState = 'VERIFIED',
  String? accountRef = 'ACC-CARRIER',
}) =>
    <String, dynamic>{
      'id': 'p1',
      'slug': 'swift',
      'name': 'Swift Couriers',
      'kind': 'EXTERNAL',
      'status': status,
      'canTakeWork': canTakeWork,
      'ownerRef': null,
      'accountRef': accountRef,
      'contactName': 'Cara',
      'contactPhone': '+100',
      'payoutState': payoutState,
      'payoutCheckedAt': '2026-08-15T09:00:00Z',
      'payoutDetail': 'bank holder: Swift Couriers Ltd',
      'createdAt': '2026-08-01T09:00:00Z',
    };

Map<String, dynamic> _score({int score = 84, bool provisional = false, double completion = 0.96}) =>
    <String, dynamic>{
      'providerId': 'p1',
      'name': 'Swift Couriers',
      'score': score,
      'orders': provisional ? 3 : 120,
      'completionRate': completion,
      'avgSecondsToClaim': 240,
      'avgSecondsOnRoad': 1080,
      'provisional': provisional,
    };

/// The adapter the current test is driving, so an assertion can read what was called.
late _StubAdapter _adapter;

DeliveryProviderApi _api({
  Map<String, dynamic>? company,
  Map<String, dynamic>? score,
  List<String> riders = const <String>['rider-aaaaaaaa', 'rider-bbbbbbbb'],
}) {
  _adapter = _StubAdapter(<String, Object>{
    '/my-company/score': score ?? _score(),
    '/my-company/riders': <String, dynamic>{'providerId': 'p1', 'riders': riders},
    '/my-company/pause': _company(status: 'PAUSED', canTakeWork: false),
    '/my-company/resume': _company(),
    '/my-company': company ?? _company(),
  });
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = _adapter;
  return DeliveryProviderApi(dio);
}

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      theme: DeliveryTheme.light(),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    );

LocaleController _locale() => LocaleController(
      read: () async => null,
      write: (String _) async {},
    );

Future<void> pump(WidgetTester tester, DeliveryProviderApi api,
    {Locale locale = const Locale('en')}) async {
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_wrap(
    CompanyScreen(api: api, locale: _locale(), onSignOut: () async {}),
    locale: locale,
  ));
  await tester.pumpAndSettle();
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  testWidgets('shows the score and what it is made of', (WidgetTester tester) async {
    await pump(tester, _api());

    // The number alone is a verdict nobody can act on; the parts are the target.
    expect(find.text('84'), findsOneWidget);
    expect(find.text('96%'), findsOneWidget);
    expect(find.text('4m'), findsOneWidget);
    expect(find.text('18m'), findsOneWidget);
    expect(find.textContaining('decides how much work'), findsOneWidget);
  });

  testWidgets('a provisional score says so rather than looking earned',
      (WidgetTester tester) async {
    await pump(tester, _api(score: _score(score: 70, provisional: true, completion: 1)));

    expect(find.text(en.tooEarlyToTell), findsOneWidget);
    expect(find.textContaining('benefit of the doubt'), findsOneWidget);
  });

  testWidgets('a carrier can stop taking orders', (WidgetTester tester) async {
    await pump(tester, _api());

    expect(find.text(en.youAreTakingOrders), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, en.pauseNewOrders));
    await tester.pumpAndSettle();

    expect(_adapter.calls.any((String c) => c.contains('POST') && c.contains('/my-company/pause')),
        isTrue);
  });

  testWidgets('a suspended carrier is not offered a button that would fail',
      (WidgetTester tester) async {
    // Suspension is the platform's decision and a carrier cannot resume out of it. A button that
    // silently 422s would be worse than no button.
    await pump(tester, _api(company: _company(status: 'SUSPENDED', canTakeWork: false)));

    expect(find.textContaining('suspended'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, en.startTakingOrders), findsNothing);
  });

  testWidgets('an empty fleet is called out, not left to be inferred',
      (WidgetTester tester) async {
    // A company with no riders looks available and can collect nothing — the most confusing way to
    // be sent no work.
    await pump(tester, _api(riders: const <String>[]));

    expect(find.textContaining('no riders'), findsOneWidget);
  });

  testWidgets('an unconfirmed payout account is flagged', (WidgetTester tester) async {
    await pump(tester, _api(company: _company(payoutState: 'UNCONFIRMED')));

    expect(find.textContaining('has not confirmed'), findsOneWidget);
  });

  testWidgets('and the whole screen works in Arabic', (WidgetTester tester) async {
    await pump(tester, _api(), locale: const Locale('ar'));

    expect(find.text(ar.howYouAreDoing.toUpperCase()), findsOneWidget);
    expect(find.text(en.howYouAreDoing.toUpperCase()), findsNothing);
    expect(Directionality.of(tester.element(find.byType(CompanyScreen))), TextDirection.rtl);
  });
}
