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

  /// Flipped mid-test to take the bell's inbox down without touching its badge.
  bool failInbox = false;

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
  late NotificationApi notificationApi;

  /// What GET /api/promotions answers. Replaced per test before [pump].
  late List<Map<String, dynamic>> register;

  /// The console bell's two reads. The bell is shared chrome — it is exercised here because this
  /// is the simplest screen carrying one, and the behaviour under test is the widget's, not the
  /// register's.
  late Map<String, dynamic> unreadBody;
  late List<Map<String, dynamic>> inboxBody;

  /// Message ids the bell posted a read for.
  final List<String> markedRead = <String>[];

  setUp(() {
    markedRead.clear();
    unreadBody = <String, dynamic>{'unread': 2};
    inboxBody = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'n1',
        'orderId': null,
        'eventType': 'partner.application',
        'title': 'A shop is waiting to be read',
        'body': 'Falafel King applied 10 minutes ago.',
        'metadata': <String, dynamic>{},
        'read': false,
        'readAt': null,
        'createdAt': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 4))
            .toIso8601String(),
      },
      <String, dynamic>{
        'id': 'n2',
        'orderId': null,
        'eventType': 'promo.exhausted',
        'title': 'WELCOME10 has run out',
        'body': 'The redemption cap was reached.',
        'metadata': <String, dynamic>{},
        'read': false,
        'readAt': null,
        'createdAt': DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 2))
            .toIso8601String(),
      },
      <String, dynamic>{
        'id': 'n3',
        'orderId': null,
        'eventType': 'promo.created',
        'title': 'OLDDEAL was withdrawn',
        'body': '',
        'metadata': <String, dynamic>{},
        // Already read. Opening the panel must not post a read for this one.
        'read': true,
        'readAt': '2026-08-27T09:00:00Z',
        'createdAt': '2026-08-27T08:00:00Z',
      },
    ];
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
      // The bell's endpoints. `/api/notifications`, not `/api/notifications/mine` — the
      // app-notification controller mounts the inbox on the bare collection path.
      if (options.path == '/api/notifications/unread-count') return _json(unreadBody);
      if (options.path == '/api/notifications') {
        if (adapter.failInbox) throw StateError('the inbox is down');
        return _json(inboxBody);
      }
      if (options.path == '/api/notifications/read-all') {
        return _json(<String, dynamic>{'updated': markedRead.length});
      }
      if (options.path.startsWith('/api/notifications/') && options.path.endsWith('/read')) {
        markedRead.add(options.path.split('/')[3]);
        return _json(<String, dynamic>{});
      }
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

    final Dio dio =
        Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;
    api = PromoApi(dio);
    notificationApi = NotificationApi(dio);
  });

  Future<void> pump(WidgetTester tester,
      {Size size = const Size(1500, 1100), bool bell = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      home: Scaffold(
        body: PromotionsScreen(
          api: api,
          // Off by default: a live bell polls, and a screen test about promo codes should not have
          // to dispose a timer it did not ask for.
          notificationApi: bell ? notificationApi : null,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// The bell's poll outlives the test unless the tree goes first.
  Future<void> close(WidgetTester tester) => tester.pumpWidget(const SizedBox());

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

  /// The console bell, in the header slot every frame draws one in.
  group('the notification bell', () {
    testWidgets('carries the unread count and lists the inbox when opened',
        (WidgetTester tester) async {
      await pump(tester, bell: true);

      // The badge is the count, not the design's bare dot: an operator deciding whether to stop
      // what they are doing wants "2", not "some".
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.notifications_none));
      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('A shop is waiting to be read'), findsOneWidget);
      expect(find.text('WELCOME10 has run out'), findsOneWidget);
      expect(find.text('4 mins ago'), findsOneWidget);

      await close(tester);
    });

    testWidgets('marks read exactly the messages it put on screen',
        (WidgetTester tester) async {
      await pump(tester, bell: true);

      await tester.tap(find.byIcon(Icons.notifications_none));
      await tester.pumpAndSettle();

      // The two unread ones, and not the message that was already read. Nothing beyond the loaded
      // page is touched either — clearing messages nobody was shown would be the bell deciding
      // they had been read.
      expect(markedRead..sort(), <String>['n1', 'n2']);
      // The badge goes with them.
      expect(find.text('2'), findsNothing);

      await close(tester);
    });

    testWidgets('an inbox that cannot be read says so instead of showing nothing',
        (WidgetTester tester) async {
      await pump(tester, bell: true);
      // Break the inbox after the badge has already loaded, so the panel is the thing that fails.
      adapter.failInbox = true;

      await tester.tap(find.byIcon(Icons.notifications_none));
      await tester.pumpAndSettle();

      expect(find.text('Could not load notifications.'), findsOneWidget);
      // "Nothing has come in yet" would be a claim about the inbox; this is a fact about the
      // request.
      expect(find.text('Nothing has come in yet.'), findsNothing);

      await close(tester);
    });

    testWidgets('is drawn greyed and inert when the portal has no notification client',
        (WidgetTester tester) async {
      await pump(tester);

      expect(find.byTooltip('Notifications unavailable'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.notifications_none));
      await tester.pumpAndSettle();

      // No panel, and no request: a control that plainly does nothing beats one that silently
      // swallows a poll.
      expect(find.text('Notifications'), findsNothing);
      expect(adapter.calls.any((String c) => c.contains('/api/notifications')), isFalse);
    });
  });
}
