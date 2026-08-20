import 'package:backoffice_web/src/reconciliation_screen.dart';
import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// What matters on a finance screen is that the money reads correctly and that the rows needing
/// attention are the ones on screen by default. Driven through a real [AccountingApi] over a
/// stubbed transport, so the JSON mapping is under test too.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<String> calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.path}?${options.uri.query}');
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body) => ResponseBody.fromString(body, 200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    });

const String _summaryJson = '''
{"byStatus":{"POSTED":{"count":9,"amount":300.00},
             "FAILED":{"count":1,"amount":35.00},
             "PENDING":{"count":2,"amount":15.00},
             "COMPENSATED":{"count":1,"amount":20.00},
             "ABANDONED":{"count":1,"amount":2.50}},
 "unsettledCount":3,"amountAtRisk":50.00}''';

const String _unsettledJson = '''
[
 {"id":"t1","orderId":"aaaaaaaa-1111-4111-8111-111111111111","leg":"MERCHANT_CREDIT",
  "accountRef":"ACC-FROZEN","amount":35.00,"currency":"USD","direction":"CREDIT",
  "status":"FAILED","coreBankingRef":null,
  "failureReason":"ACCOUNT_FROZEN: Account is FROZEN","attempts":1,
  "createdAt":"2026-08-09T10:00:00Z","postedAt":null},
 {"id":"t2","orderId":"bbbbbbbb-2222-4222-8222-222222222222","leg":"CUSTOMER_DEBIT",
  "accountRef":"ACC-CUSTOMER","amount":15.00,"currency":"USD","direction":"DEBIT",
  "status":"PENDING","coreBankingRef":null,"failureReason":null,"attempts":0,
  "createdAt":"2026-08-09T10:05:00Z","postedAt":null}
]''';

const String _syncLogJson = '''
[{"id":"s1","provider":"SIMULATOR","outcome":"REJECTED",
  "requestPayload":"{\\"accountRef\\":\\"ACC-FROZEN\\",\\"amountMinor\\":3500}",
  "responsePayload":"{\\"status\\":\\"REJECTED\\"}",
  "syncedAt":"2026-08-09T10:00:05Z"}]''';

/// Ages are relative to the moment the test runs, because the thing under test is how old the cash
/// is. A frozen timestamp would drift from "30 hours ago" into "a year ago" and the overdue
/// assertions would keep passing for the wrong reason.
String _floatJson() {
  String at(Duration ago) => DateTime.now().toUtc().subtract(ago).toIso8601String();
  // In the order the server sends them — largest first — so the oldest-first ordering the screen
  // applies is actually being tested rather than inherited.
  //
  // Ids distinct from the transaction fixtures': both are shortened to their first eight
  // characters on screen, so sharing a prefix would make an assertion about a holder row match a
  // transaction row instead.
  return '''
[{"holderRef":"dddddddd-4444-4444-8444-444444444444","holderKind":"RIDER",
  "amount":42.75,"orders":3,"oldest":"${at(const Duration(minutes: 10))}"},
 {"holderRef":"eeeeeeee-5555-4555-8555-555555555555","holderKind":"RIDER",
  "amount":13.25,"orders":1,"oldest":"${at(const Duration(hours: 30))}"}]''';
}

void main() {
  late _FakeAdapter adapter;
  late AccountingApi api;

  setUp(() {
    adapter = _FakeAdapter((RequestOptions options) {
      if (options.path.contains('sync-log')) return _json(_syncLogJson);
      if (options.path.contains('summary')) return _json(_summaryJson);
      if (options.path.contains('unsettled')) return _json(_unsettledJson);
      // Before /float, which its own path also contains.
      if (options.path.contains('remit')) {
        return _json('{"remittanceId":"r1","holderRef":"eeeeeeee-5555-4555-8555-555555555555",'
            '"amount":13.25,"collections":1}');
      }
      if (options.path.contains('float')) return _json(_floatJson());
      // /transactions?status=POSTED — one posted row, so the filter is observably different.
      return _json('''
[{"id":"t3","orderId":"cccccccc-3333-4333-8333-333333333333","leg":"PLATFORM_COMMISSION",
  "accountRef":"ACC-PLATFORM","amount":5.00,"currency":"USD","direction":"CREDIT",
  "status":"POSTED","coreBankingRef":"bank-ref-9","failureReason":null,"attempts":1,
  "createdAt":"2026-08-09T09:00:00Z","postedAt":"2026-08-09T09:00:02Z"}]''');
    });
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;
    api = AccountingApi(dio);
  });

  Future<void> pump(WidgetTester tester, {Size size = const Size(1600, 1000)}) async {
    // Desktop width. The default 800x600 test surface is narrower than any real Backoffice window,
    // and the transaction table's action column lands off-screen in it — which makes a tap fail
    // for reasons that have nothing to do with the code under test.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      home: Scaffold(body: ReconciliationScreen(api: api)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('leads with the money at risk, not a row count', (WidgetTester tester) async {
    await pump(tester);

    // "3 unsettled" says nothing about whether to worry; "$50.00" does.
    // Labels are upper-cased by StatTile at render, so that is what is on screen.
    expect(find.text('AT RISK'), findsOneWidget);
    expect(find.text('\$50.00'), findsOneWidget);
    // The footnote splits what is at risk into what is merely waiting and what has actually
    // failed — 2 pending, 1 failed.
    expect(find.text('2·1'), findsOneWidget);
  });

  testWidgets('opens on the work list, not on everything', (WidgetTester tester) async {
    await pump(tester);

    expect(adapter.calls.any((String c) => c.contains('/unsettled')), isTrue);
    expect(adapter.calls.any((String c) => c.contains('status=')), isFalse);
  });

  testWidgets('shows the failed leg with its account and amount', (WidgetTester tester) async {
    await pump(tester);

    expect(find.text('Merchant payout'), findsOneWidget);
    expect(find.text('ACC-FROZEN'), findsOneWidget);
    // A credit is signed, so a debit and a credit of the same size are not confusable.
    expect(find.text('+\$35.00'), findsOneWidget);
    expect(find.text('−\$15.00'), findsOneWidget);
  });

  testWidgets('a leg the bank never accepted has no reference', (WidgetTester tester) async {
    await pump(tester);

    // The missing reference is itself the signal that nothing moved.
    expect(find.text('—'), findsNWidgets(2));
  });

  testWidgets('the failure reason is one hover away', (WidgetTester tester) async {
    await pump(tester);

    // Matched on the message rather than by position: the toolbar's Refresh button is also a
    // Tooltip, and .first would silently assert about the wrong widget.
    final Iterable<Tooltip> tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip));
    expect(
      tooltips.where((Tooltip t) => (t.message ?? '').contains('FROZEN')),
      hasLength(1),
    );
  });

  testWidgets('filtering by status asks the server for that status',
      (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Posted'));
    await tester.pumpAndSettle();

    expect(adapter.calls.any((String c) => c.contains('status=POSTED')), isTrue);
    expect(find.text('Commission'), findsOneWidget);
    expect(find.text('bank-ref-9'), findsOneWidget);
  });

  testWidgets('the sync log shows what was sent and what came back',
      (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.byIcon(Icons.receipt_long_outlined).first);
    await tester.pumpAndSettle();

    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('Received'), findsOneWidget);
    // The first question in a dispute is what we actually sent.
    expect(find.textContaining('ACC-FROZEN'), findsWidgets);
    expect(find.textContaining('REJECTED'), findsWidgets);
  });

  group('cash on hand', () {
    testWidgets('is counted as its own exposure, in money', (WidgetTester tester) async {
      await pump(tester);

      // Not "2 holders": the question is how much of the platform's money is in somebody's bag.
      // Upper-cased on screen by both the tile label and the section heading.
      expect(find.text('CASH ON HAND'), findsWidgets);
      expect(find.text('\$56.00'), findsOneWidget);
      expect(find.textContaining('2 holding'), findsOneWidget);
    });

    testWidgets('lists the oldest first, not the largest', (WidgetTester tester) async {
      await pump(tester);

      // The server sends largest-first. The biggest balance is usually just the busiest rider;
      // the oldest one is the question worth asking, so the screen re-orders.
      final double oldest = tester.getTopLeft(find.text('EEEEEEEE')).dy;
      final double largest = tester.getTopLeft(find.text('DDDDDDDD')).dy;
      expect(oldest, lessThan(largest));
    });

    testWidgets('flags cash that has been out longer than a day', (WidgetTester tester) async {
      await pump(tester);

      // 30 hours is flagged; 10 minutes is a working day and must not be.
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.textContaining('longer than a day'), findsOneWidget);
    });

    testWidgets('fits a half-width window', (WidgetTester tester) async {
      // A holder row packs an id, a count, an age, a pill, an amount and a button onto one line,
      // and the tiles above it get narrower as columns are added. Flutter fails a test on
      // overflow, so rendering at a squeezed width at all is the assertion.
      await pump(tester, size: const Size(1000, 800));

      expect(find.text('EEEEEEEE'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Banked'), findsNWidgets(2));
    });

    testWidgets('asks before recording a hand-over', (WidgetTester tester) async {
      await pump(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Banked').first);
      await tester.pumpAndSettle();

      // The confirmation has to name the amount and the count, because that is what the operator
      // is checking against the notes in their hand.
      final Finder dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.textContaining('\$13.25')),
          findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.textContaining('1 order')),
          findsOneWidget);
    });

    testWidgets('cancelling records nothing', (WidgetTester tester) async {
      await pump(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Banked').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      // The expensive mistake: a rider marked square with the platform while still holding the
      // cash. There is no way back from it, so a stray click must not be enough.
      expect(adapter.calls.any((String c) => c.contains('remit')), isFalse);
    });

    testWidgets('confirming records it against that holder', (WidgetTester tester) async {
      await pump(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Banked').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Yes, they banked it'));
      await tester.pumpAndSettle();

      // Against the holder whose row was tapped — the oldest — not whichever the server listed
      // first.
      expect(
        adapter.calls.any((String c) => c.contains('eeeeeeee-5555-4555-8555-555555555555/remit')),
        isTrue,
      );
      expect(find.textContaining('Recorded \$13.25'), findsOneWidget);
    });
  });
}
