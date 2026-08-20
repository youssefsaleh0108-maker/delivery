import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_portal/src/whatsapp_draft_panel.dart';
import 'package:merchant_portal/src/whatsapp_screen.dart';

/// Serves canned JSON without a backend. Shapes copied from real responses captured by
/// `infra/smoke-test-whatsapp*.js`, so a server-side contract change breaks these tests rather than
/// only showing up at runtime.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.responses);

  /// Path prefix -> JSON body.
  final Map<String, Object> responses;

  final List<String> requested = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.path);
    for (final MapEntry<String, Object> entry in responses.entries) {
      if (options.path.startsWith(entry.key)) {
        return ResponseBody.fromString(
          jsonEncode(entry.value),
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>[Headers.jsonContentType],
          },
        );
      }
    }
    return ResponseBody.fromString('{}', 404);
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(Map<String, Object> responses) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost:8100'));
  dio.httpClientAdapter = _StubAdapter(responses);
  return dio;
}

Map<String, dynamic> _conversation({
  String id = 'c1',
  String name = 'Rana',
  int unread = 2,
  bool archived = false,
}) =>
    <String, dynamic>{
      'id': id,
      'customerWaId': '96171234567',
      'customerName': name,
      'lastMessageAt': '2026-08-16T10:00:00Z',
      'unreadCount': unread,
      'archived': archived,
    };

Map<String, dynamic> _message({
  String id = 'm1',
  String direction = 'INBOUND',
  String? body = 'two shawarma please',
  String type = 'TEXT',
}) =>
    <String, dynamic>{
      'id': id,
      'direction': direction,
      'body': body,
      'messageType': type,
      'sentAt': '2026-08-16T10:00:00Z',
    };

Map<String, dynamic> _draft({
  String id = 'd1',
  List<dynamic> lines = const <dynamic>[],
  String? address,
  bool placeable = false,
  String status = 'OPEN',
}) =>
    <String, dynamic>{
      'id': id,
      'conversationId': 'c1',
      'requestText': 'two shawarma please',
      'lines': lines,
      'estimatedSubtotal': lines.fold<double>(
          0, (double sum, dynamic l) => sum + ((l as Map<String, dynamic>)['lineTotal'] as num)),
      'deliveryAddress': address,
      'deliveryZoneId': null,
      'contactPhone': null,
      'notes': null,
      'status': status,
      'placeable': placeable,
      'orderId': status == 'PLACED' ? 'o1' : null,
      'createdAt': '2026-08-16T10:00:00Z',
      'updatedAt': '2026-08-16T10:00:00Z',
    };

Map<String, dynamic> _line({
  String id = 'l1',
  String name = 'Shawarma',
  int qty = 2,
  double unit = 4.5,
  String summary = '',
}) =>
    <String, dynamic>{
      'id': id,
      'productId': 'p1',
      'productName': name,
      'unitPrice': unit,
      'qty': qty,
      'lineTotal': unit * qty,
      'options': const <dynamic>[],
      'optionsSummary': summary,
    };

/// The delegates are required, not decoration: these screens read their labels from the string
/// table, and without them every finder below reports "0 widgets found" — which reads like a missing
/// widget rather than a missing dependency.
Widget _wrap(Widget child) => MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocaleController.supported,
      home: Scaffold(body: child),
    );

Future<void> _pumpAt(WidgetTester tester, Widget child, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(child));
  await tester.pumpAndSettle();
}

void main() {
  group('inbox', () {
    testWidgets('lists who is waiting, with their unread count',
        (WidgetTester tester) async {
      final Dio dio = _dioWith(<String, Object>{
        '/api/whatsapp/conversations': <dynamic>[
          _conversation(name: 'Rana', unread: 2),
          _conversation(id: 'c2', name: 'Sami', unread: 0),
        ],
      });

      await _pumpAt(tester, WhatsAppScreen(api: WhatsAppApi(dio), catalogApi: CatalogApi(dio)),
          const Size(1400, 900));

      expect(find.text('Rana'), findsOneWidget);
      expect(find.text('Sami'), findsOneWidget);
      // A badge only where something is actually waiting.
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('an empty inbox explains what will fill it',
        (WidgetTester tester) async {
      final Dio dio = _dioWith(<String, Object>{
        '/api/whatsapp/conversations': <dynamic>[],
      });

      await _pumpAt(tester, WhatsAppScreen(api: WhatsAppApi(dio), catalogApi: CatalogApi(dio)),
          const Size(1400, 900));

      expect(find.text('No messages yet'), findsOneWidget);
    });

    testWidgets('lays out at a laptop width without overflowing',
        (WidgetTester tester) async {
      // Every UI bug found in this project so far has been an overflow at a particular width, and
      // Flutter fails a test on overflow — so rendering at several sizes is the check.
      final Dio dio = _dioWith(<String, Object>{
        '/api/whatsapp/conversations': <dynamic>[_conversation()],
      });

      await _pumpAt(tester, WhatsAppScreen(api: WhatsAppApi(dio), catalogApi: CatalogApi(dio)),
          const Size(1280, 800));
      await _pumpAt(tester, WhatsAppScreen(api: WhatsAppApi(dio), catalogApi: CatalogApi(dio)),
          const Size(2400, 1200));
    });
  });

  group('thread', () {
    Future<void> pumpThread(WidgetTester tester, List<dynamic> messages) async {
      final Dio dio = _dioWith(<String, Object>{
        '/api/whatsapp/conversations/c1/messages': messages,
        '/api/whatsapp/conversations/c1/read': _conversation(unread: 0),
        '/api/whatsapp/conversations': <dynamic>[_conversation()],
        '/api/whatsapp/drafts/conversations/c1': <dynamic>[],
      });

      await _pumpAt(tester, WhatsAppScreen(api: WhatsAppApi(dio), catalogApi: CatalogApi(dio)),
          const Size(1500, 900));
      await tester.tap(find.text('Rana'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows what the customer wrote, verbatim', (WidgetTester tester) async {
      await pumpThread(tester, <dynamic>[_message(body: '  2 kebab, NO onions  ')]);

      expect(find.text('  2 kebab, NO onions  '), findsOneWidget);
    });

    testWidgets('a voice note shows as a voice note, not an empty bubble',
        (WidgetTester tester) async {
      await pumpThread(tester, <dynamic>[_message(body: null, type: 'AUDIO')]);

      // A merchant seeing nothing where a voice note arrived concludes the platform lost it and
      // chases the wrong problem.
      expect(find.text('Voice note'), findsOneWidget);
    });

    testWidgets('an unsupported type is still named', (WidgetTester tester) async {
      await pumpThread(tester, <dynamic>[_message(body: null, type: 'OTHER')]);

      expect(find.text('Unsupported message'), findsOneWidget);
    });
  });

  group('draft panel', () {
    Future<void> pumpPanel(WidgetTester tester, List<dynamic> drafts) async {
      final Dio dio = _dioWith(<String, Object>{
        '/api/whatsapp/drafts/conversations/c1': drafts,
      });

      await _pumpAt(
        tester,
        WhatsAppDraftPanel(
          api: WhatsAppApi(dio),
          catalogApi: CatalogApi(dio),
          conversation: WhatsAppConversation.fromJson(_conversation()),
          onPlaced: () {},
        ),
        const Size(500, 900),
      );
    }

    testWidgets('with no draft, it offers to start one', (WidgetTester tester) async {
      await pumpPanel(tester, <dynamic>[]);

      // Nothing has been built automatically. That is the whole point: "hi" must not become an
      // order, so the first step is always a merchant's decision.
      expect(find.text('Start an order'), findsOneWidget);
    });

    testWidgets('an empty draft says what to do, and cannot be confirmed',
        (WidgetTester tester) async {
      await pumpPanel(tester, <dynamic>[_draft()]);

      expect(find.text('Nothing added yet'), findsOneWidget);
      final Finder confirm = find.widgetWithText(FilledButton, 'Confirm order');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    });

    testWidgets('lines show quantity, options and a running estimate',
        (WidgetTester tester) async {
      await pumpPanel(tester, <dynamic>[
        _draft(lines: <dynamic>[
          _line(qty: 2, unit: 4.5),
          _line(id: 'l2', name: 'Pizza', qty: 1, unit: 12, summary: 'Choose Size: Large'),
        ]),
      ]);

      expect(find.text('2× Shawarma'), findsOneWidget);
      expect(find.text('Choose Size: Large'), findsOneWidget);
      expect(find.text('21.00'), findsOneWidget);
    });

    testWidgets('the estimate is labelled as an estimate', (WidgetTester tester) async {
      await pumpPanel(tester, <dynamic>[_draft(lines: <dynamic>[_line()])]);

      // A merchant is going to read this number to a customer. It must not look like a promise —
      // the catalog prices the real order at the moment it is confirmed.
      expect(find.textContaining('final total is calculated'), findsOneWidget);
    });

    testWidgets('confirming stays disabled until there is an address',
        (WidgetTester tester) async {
      await pumpPanel(tester, <dynamic>[_draft(lines: <dynamic>[_line()])]);

      final Finder confirm = find.widgetWithText(FilledButton, 'Confirm order');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    });

    testWidgets('and becomes available once the draft is placeable',
        (WidgetTester tester) async {
      await pumpPanel(tester, <dynamic>[
        _draft(lines: <dynamic>[_line()], address: 'Hamra, 3rd floor', placeable: true),
      ]);

      final Finder confirm = find.widgetWithText(FilledButton, 'Confirm order');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    });

    testWidgets('a placed draft leaves the editor and shows in the history',
        (WidgetTester tester) async {
      await pumpPanel(tester, <dynamic>[
        _draft(status: 'PLACED', lines: <dynamic>[_line()], address: 'Hamra'),
      ]);

      // No open draft, so the panel is back to offering a new one — and the placed order is listed
      // rather than silently gone.
      expect(find.text('Start an order'), findsOneWidget);
      expect(find.text('Order placed'), findsOneWidget);
    });
  });
}
