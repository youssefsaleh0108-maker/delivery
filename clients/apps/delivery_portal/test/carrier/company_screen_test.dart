import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/carrier/company_screen.dart';
import 'package:delivery_portal/src/shell/console_controls.dart';
import 'package:delivery_portal/src/shell/shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Riders Management — Figma `carrier-riders` (3:3589).
///
/// The design's table has seven columns and the platform can fill two of them. What matters here is
/// that the other five say "not recorded" rather than showing a number a company would act on, that
/// the drawn-but-unbacked "Add New Rider" button cannot be pressed into a dead end, and that the
/// two live things this page has always done — the score, and the switch that stops work arriving —
/// still work after the restyle.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.responses, {this.failing = const <String>{}});

  final Map<String, Object> responses;
  final Set<String> failing;
  final List<String> calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');

    for (final String path in failing) {
      if (options.path.contains(path)) {
        return ResponseBody.fromString('{"message":"no"}', 404);
      }
    }

    final List<String> matches = responses.keys
        .where((String key) => options.path.contains(key))
        .toList()
      ..sort((String a, String b) => b.length.compareTo(a.length));

    if (matches.isEmpty) return ResponseBody.fromString('{}', 404);
    return ResponseBody.fromString(jsonEncode(responses[matches.first]), 200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _company({
  String status = 'ACTIVE',
  bool canTakeWork = true,
}) =>
    <String, dynamic>{
      'id': 'p1',
      'slug': 'swift',
      'name': 'Swift Couriers',
      'kind': 'EXTERNAL',
      'status': status,
      'canTakeWork': canTakeWork,
      'ownerRef': null,
      'accountRef': 'ACC-CARRIER',
      'contactName': 'Cara',
      'contactPhone': '+100',
      'payoutState': 'VERIFIED',
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

Map<String, dynamic> _job({
  required String id,
  String status = 'DELIVERED',
  String? riderId = 'rider-aaaaaaaa',
}) =>
    <String, dynamic>{
      'id': id,
      'customerId': 'c1',
      'merchantId': 'm1',
      'riderId': riderId,
      'status': status,
      'totalAmount': 50.0,
      'deliveryAddress': '12 Bliss Street',
      'deliveryFee': 5.0,
      'contactPhone': '+100',
      'notes': null,
      'items': <dynamic>[],
      'availableActions': <dynamic>[],
      'placedAt': '2026-08-16T09:00:00Z',
      'deliveredAt': status == 'DELIVERED' ? '2026-08-16T10:00:00Z' : null,
      'cancelReason': null,
    };

Map<String, dynamic> _page(List<Map<String, dynamic>> jobs) => <String, dynamic>{
      'content': jobs,
      'page': 0,
      'size': 100,
      'totalElements': jobs.length,
      'totalPages': 1,
    };

late _StubAdapter _adapter;

({DeliveryProviderApi provider, OrderApi order}) _apis({
  Map<String, dynamic>? company,
  Map<String, dynamic>? score,
  List<String> riders = const <String>['rider-aaaaaaaa', 'rider-bbbbbbbb'],
  List<Map<String, dynamic>>? jobs,
  Set<String> failing = const <String>{},
}) {
  _adapter = _StubAdapter(
    <String, Object>{
      '/my-company/score': score ?? _score(),
      '/my-company/riders': <String, dynamic>{'providerId': 'p1', 'riders': riders},
      '/my-company/pause': _company(status: 'PAUSED', canTakeWork: false),
      '/my-company/resume': _company(),
      '/my-company': company ?? _company(),
      '/orders/carrier': _page(jobs ??
          <Map<String, dynamic>>[
            _job(id: 'aaaaaaaa11'),
            _job(id: 'bbbbbbbb22', status: 'PICKED_UP', riderId: 'rider-bbbbbbbb'),
          ]),
    },
    failing: failing,
  );
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = _adapter;
  return (provider: DeliveryProviderApi(dio), order: OrderApi(dio));
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
      home: Scaffold(body: child),
    );

Future<void> pump(WidgetTester tester, ({DeliveryProviderApi provider, OrderApi order}) apis,
    {Locale locale = const Locale('en'), double width = 1180}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_wrap(
    CompanyScreen(api: apis.provider, orderApi: apis.order),
    locale: locale,
  ));
  await tester.pumpAndSettle();
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  testWidgets('is the design table, with all seven columns', (WidgetTester tester) async {
    await pump(tester, _apis());

    expect(find.text('Riders Management'), findsOneWidget);
    for (final String column in <String>[
      'Rider Name',
      'Status',
      'Region',
      'Deliveries',
      'Rating',
      'Join Date',
      'Actions',
    ]) {
      expect(find.text(column), findsOneWidget, reason: column);
    }
    expect(find.byType(ConsoleNameCell), findsNWidgets(2));
  });

  testWidgets('fills the columns it can and dashes the ones it cannot',
      (WidgetTester tester) async {
    // rider-aa carried one delivered job; rider-bb is out on one that has not finished.
    await pump(tester, _apis());

    expect(find.text('RIDER-AA'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('On a job'), findsOneWidget);
    // Region, Rating and Join Date have no backend at all — three dashes on each of two rows,
    // plus the status of the rider who is not out.
    expect(find.text('—'), findsNWidgets(7));
    expect(find.textContaining('are not recorded for a rider'), findsOneWidget);
  });

  testWidgets('a job board that did not load does not become a row of zeroes',
      (WidgetTester tester) async {
    await pump(tester, _apis(failing: const <String>{'/orders/carrier'}));

    expect(find.text('0'), findsNothing);
    expect(find.textContaining('could not be read just now'), findsOneWidget);
  });

  testWidgets('Add New Rider is drawn, inert, and explained', (WidgetTester tester) async {
    // Riders reach a fleet by applying and being approved. There is no endpoint that creates one
    // directly, so the design's primary button must not open a form nothing can submit.
    await pump(tester, _apis());

    final Finder button = find.widgetWithText(ConsolePrimaryButton, 'Add New Rider');
    expect(button, findsOneWidget);
    expect(tester.widget<ConsolePrimaryButton>(button).onPressed, isNull);
    expect(find.byType(ConsoleComingSoonChip), findsWidgets);
  });

  testWidgets('shows the score and what it is made of', (WidgetTester tester) async {
    await pump(tester, _apis());

    // The number alone is a verdict nobody can act on; the parts are the target.
    expect(find.text('84'), findsOneWidget);
    expect(find.text('96%'), findsOneWidget);
    expect(find.text('4m'), findsOneWidget);
    expect(find.text('18m'), findsOneWidget);
    expect(find.textContaining('decides how much work'), findsOneWidget);
  });

  testWidgets('a provisional score says so rather than looking earned',
      (WidgetTester tester) async {
    await pump(tester, _apis(score: _score(score: 70, provisional: true, completion: 1)));

    expect(find.text(en.tooEarlyToTell), findsOneWidget);
    expect(find.textContaining('benefit of the doubt'), findsOneWidget);
  });

  testWidgets('a carrier can still stop taking orders', (WidgetTester tester) async {
    await pump(tester, _apis());

    expect(find.text(en.youAreTakingOrders), findsOneWidget);
    await tester.tap(find.widgetWithText(ConsolePrimaryButton, en.pauseNewOrders));
    await tester.pumpAndSettle();

    expect(_adapter.calls.any((String c) => c.contains('POST') && c.contains('/my-company/pause')),
        isTrue);
  });

  testWidgets('a suspended carrier is not offered a button that would fail',
      (WidgetTester tester) async {
    // Suspension is the platform's decision and a carrier cannot resume out of it. A button that
    // silently fails would be worse than no button.
    await pump(tester, _apis(company: _company(status: 'SUSPENDED', canTakeWork: false)));

    expect(find.textContaining('suspended'), findsOneWidget);
    expect(find.widgetWithText(ConsolePrimaryButton, en.startTakingOrders), findsNothing);
  });

  testWidgets('an empty fleet is called out, not left to be inferred',
      (WidgetTester tester) async {
    // A company with no riders looks available and can collect nothing — the most confusing way to
    // be sent no work.
    await pump(tester, _apis(riders: const <String>[]));

    expect(find.textContaining('no riders'), findsOneWidget);
  });

  testWidgets('the parts that are still translated stay translated',
      (WidgetTester tester) async {
    // The console's own chrome is English-only in this wave; the score and availability cards were
    // localised before it and stay that way.
    await pump(tester, _apis(), locale: const Locale('ar'));

    expect(find.text(ar.howYouAreDoing), findsOneWidget);
    expect(find.text(en.howYouAreDoing), findsNothing);
    expect(Directionality.of(tester.element(find.byType(CompanyScreen))), TextDirection.rtl);
  });

  // What a 1440 / 1280 / 1024 window leaves the content column once the 260px rail has its share.
  // The table scrolls sideways below its own minimum rather than compressing; the cards under it
  // stack. An overflow fails the test.
  for (final double width in <double>[1180, 1020, 764]) {
    testWidgets('lays out at a ${width.toInt()}px content column', (WidgetTester tester) async {
      await pump(tester, _apis(), width: width);
      expect(tester.takeException(), isNull);
    });
  }
}
