import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_portal/src/backoffice/promotions_screen.dart';
import 'package:delivery_portal/src/shell/console_controls.dart';
import 'package:delivery_portal/src/shell/shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The promo code register — the admin side of the promotions backend.
///
/// Two decisions mirror the server exactly — create, and deactivate — and these tests hold the
/// register to the same honesty bar as the rest of the consoles: redemption counts and money given
/// away are the server's numbers, a withdrawn code stays a record with nothing to press, and
/// minting sends exactly what was typed.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<String> calls = <String>[];
  final List<Object?> bodies = <Object?>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    bodies.add(options.data);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body) => ResponseBody.fromString(jsonEncode(body), 200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    });

Map<String, dynamic> _code({
  String id = 'c1',
  String code = 'WELCOME10',
  String kind = 'PERCENT_OFF',
  double? value = 10,
  int redeemedCount = 4,
  int? maxRedemptions = 100,
  double givenAway = 61.5,
  bool active = true,
  bool live = true,
}) =>
    <String, dynamic>{
      'id': id,
      'code': code,
      'kind': kind,
      'value': value,
      'minSubtotal': null,
      'startsAt': null,
      'endsAt': null,
      'maxRedemptions': maxRedemptions,
      'maxPerCustomer': null,
      'redeemedCount': redeemedCount,
      'givenAway': givenAway,
      'active': active,
      'live': live,
      'createdBy': 'operator-1234-5678',
      'createdAt': '2026-08-20T09:00:00Z',
    };

void main() {
  late _FakeAdapter adapter;
  late PromoApi api;

  /// What GET /api/promotions answers. Replaced per test before [pump].
  late List<Map<String, dynamic>> register;

  setUp(() {
    register = <Map<String, dynamic>>[
      _code(),
      _code(
          id: 'c2',
          code: 'OLDDEAL',
          kind: 'AMOUNT_OFF',
          value: 5,
          redeemedCount: 250,
          maxRedemptions: null,
          givenAway: 1250,
          active: false,
          live: false),
    ];

    adapter = _FakeAdapter((RequestOptions options) {
      if (options.method == 'POST' && options.path.endsWith('/deactivate')) {
        return _json(_code(active: false, live: false));
      }
      if (options.method == 'POST' && options.path.endsWith('/api/promotions')) {
        final Map<String, dynamic> sent = options.data as Map<String, dynamic>;
        return _json(_code(
            id: 'c9',
            code: sent['code'] as String,
            kind: sent['kind'] as String,
            redeemedCount: 0,
            givenAway: 0));
      }
      return _json(register);
    });

    api = PromoApi(
        Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter);
  });

  Future<void> pump(WidgetTester tester, {Size size = const Size(1500, 1100)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      home: Scaffold(body: PromotionsScreen(api: api)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lists the register with real redemption counts and real cost',
      (WidgetTester tester) async {
    await pump(tester);

    expect(find.text('WELCOME10'), findsOneWidget);
    expect(find.text('OLDDEAL'), findsOneWidget);
    // The server's numbers, in the server's shapes: capped codes read n of cap, uncapped read n.
    expect(find.text('4 of 100'), findsOneWidget);
    expect(find.text('250'), findsOneWidget);
    expect(find.text('\$61.50'), findsOneWidget);
    expect(find.text('\$1250.00'), findsOneWidget);
    // One live code, counted on the tab.
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('Withdrawn'), findsWidgets);
  });

  testWidgets('a withdrawn code keeps its record and offers nothing to press',
      (WidgetTester tester) async {
    await pump(tester);

    // One withdraw action for the live code; the withdrawn one gets a dash, because the server
    // has no delete and no reactivate and the screen must not invent either.
    expect(find.byTooltip('Withdraw this code'), findsOneWidget);
  });

  testWidgets('withdrawing asks first, says it is not reversible, then posts',
      (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.byTooltip('Withdraw this code'));
    await tester.pumpAndSettle();

    expect(find.text('Withdraw WELCOME10?'), findsOneWidget);
    expect(find.textContaining('cannot be switched back on'), findsOneWidget);

    await tester.tap(find.widgetWithText(ConsoleButton, 'Withdraw'));
    await tester.pumpAndSettle();

    expect(
      adapter.calls.any(
          (String c) => c.contains('POST') && c.contains('/api/promotions/c1/deactivate')),
      isTrue,
    );
  });

  testWidgets('cancelling the withdrawal posts nothing', (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.byTooltip('Withdraw this code'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ConsoleButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(adapter.calls.any((String c) => c.contains('deactivate')), isFalse);
  });

  group('minting', () {
    testWidgets('is dead until the code has the server\'s own shape',
        (WidgetTester tester) async {
      await pump(tester);

      await tester.tap(find.widgetWithText(ConsolePrimaryButton, 'New Code'));
      await tester.pumpAndSettle();

      final Finder mint = find.widgetWithText(ConsoleButton, 'Mint the code');
      expect(tester.widget<ConsoleButton>(mint.hitTestable()).onPressed, isNull);

      // Two characters is under the server's 3-32; the button must not offer the round trip.
      await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)).first,
        'AB',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<ConsoleButton>(mint.hitTestable()).onPressed, isNull);
    });

    testWidgets('sends what was typed and reloads the register',
        (WidgetTester tester) async {
      await pump(tester);

      await tester.tap(find.widgetWithText(ConsolePrimaryButton, 'New Code'));
      await tester.pumpAndSettle();

      final Finder fields =
          find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
      await tester.enterText(fields.at(0), 'SUMMER25');
      await tester.enterText(fields.at(1), '25');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ConsoleButton, 'Mint the code').hitTestable());
      await tester.pumpAndSettle();

      expect(
        adapter.calls
            .any((String c) => c.contains('POST') && c.endsWith('/api/promotions')),
        isTrue,
      );
      expect(
        adapter.bodies.any((Object? b) =>
            b is Map &&
            b['code'] == 'SUMMER25' &&
            b['kind'] == 'PERCENT_OFF' &&
            b['value'] == 25),
        isTrue,
      );
      // The register was asked again after the mint rather than guessed at locally.
      expect(
        adapter.calls
            .where((String c) => c.contains('GET') && c.endsWith('/api/promotions'))
            .length,
        greaterThan(1),
      );
    });
  });

  testWidgets('searches the codes already loaded', (WidgetTester tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField).last, 'old');
    await tester.pumpAndSettle();

    expect(find.text('OLDDEAL'), findsOneWidget);
    expect(find.text('WELCOME10'), findsNothing);
  });

  /// Flutter fails a test on a layout overflow, so rendering at the widths the console is opened
  /// on is the cheapest check there is.
  for (final Size window in <Size>[
    const Size(1440, 900),
    const Size(1280, 800),
    const Size(1024, 720),
  ]) {
    testWidgets('lays out at ${window.width.round()}px', (WidgetTester tester) async {
      await pump(tester, size: window);
      expect(find.byType(ConsoleTable), findsOneWidget);
    });
  }
}
