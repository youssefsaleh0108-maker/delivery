import 'package:delivery_portal/src/backoffice/reconciliation_screen.dart';
import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// What matters on a finance screen is that the money reads correctly and that the rows needing
/// attention are the ones on screen by default. Driven through a real [AccountingApi] over a
/// stubbed transport, so the JSON mapping is under test too.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  ResponseBody Function(RequestOptions options) handler;
  final List<String> calls = <String>[];
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.path}?${options.uri.query}');
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, {int status = 200}) => ResponseBody.fromString(body, status,
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
///
/// [flags] is what the server says about each holder, in order; null leaves the flag off, as a
/// server from before the configured limit sends it.
String _floatJson({List<bool?> flags = const <bool?>[null, null]}) {
  String at(Duration ago) => DateTime.now().toUtc().subtract(ago).toIso8601String();
  String flag(bool? value) => value == null ? '' : ',"overdue":$value';
  // In the order the server sends them — largest first — so the oldest-first ordering the screen
  // applies is actually being tested rather than inherited.
  //
  // Ids distinct from the transaction fixtures': both are shortened to their first eight
  // characters on screen, so sharing a prefix would make an assertion about a holder row match a
  // transaction row instead.
  return '''
[{"holderRef":"dddddddd-4444-4444-8444-444444444444","holderKind":"RIDER",
  "amount":42.75,"orders":3,"oldest":"${at(const Duration(minutes: 10))}"${flag(flags[0])}},
 {"holderRef":"eeeeeeee-5555-4555-8555-555555555555","holderKind":"RIDER",
  "amount":13.25,"orders":1,"oldest":"${at(const Duration(hours: 30))}"${flag(flags[1])}}]''';
}

/// Two companies: one holding 485.50 of the platform's cash with 180.00 more still with its riders,
/// and one holding nothing itself while a rider carries 12.00 for it.
const String _carriersJson = '''
{"overdueAfterHours":48,"carriers":[
 {"carrierRef":"77777777-7777-4777-8777-777777777777","held":"485.50","orders":3,
  "oldest":"2026-10-20T09:00:00Z","overdue":false,"withRiders":"180.00","ridersHolding":2,
  "ridersOldest":"2026-10-21T10:00:00Z","lastPaidAt":null},
 {"carrierRef":"99999999-9999-4999-8999-999999999999","held":"0.00","orders":0,
  "oldest":null,"overdue":false,"withRiders":"12.00","ridersHolding":1,
  "ridersOldest":"2026-10-24T10:00:00Z","lastPaidAt":"2026-10-19T10:00:00Z"}]}''';

const String _providersJson = '''
{"content":[{"id":"77777777-7777-4777-8777-777777777777","slug":"libanex","name":"Libanex Express",
  "kind":"EXTERNAL","status":"ACTIVE","canTakeWork":true}],
 "page":0,"size":100,"totalElements":1,"totalPages":1}''';

void main() {
  late _FakeAdapter adapter;
  late AccountingApi api;
  late DeliveryProviderApi providers;
  late String floatJson;
  late ResponseBody Function() carriers;
  late ResponseBody Function(RequestOptions) remit;

  ResponseBody route(RequestOptions options) {
    if (options.path.contains('sync-log')) return _json(_syncLogJson);
    if (options.path.contains('summary')) return _json(_summaryJson);
    if (options.path.contains('unsettled')) return _json(_unsettledJson);
    // Before /float, which its own path also contains.
    if (options.path.contains('remit')) return remit(options);
    if (options.path.contains('/float/carriers')) return carriers();
    if (options.path.contains('delivery-providers')) return _json(_providersJson);
    if (options.path.contains('float')) return _json(floatJson);
    // /transactions?status=POSTED — one posted row, so the filter is observably different.
    return _json('''
[{"id":"t3","orderId":"cccccccc-3333-4333-8333-333333333333","leg":"PLATFORM_COMMISSION",
  "accountRef":"ACC-PLATFORM","amount":5.00,"currency":"USD","direction":"CREDIT",
  "status":"POSTED","coreBankingRef":"bank-ref-9","failureReason":null,"attempts":1,
  "createdAt":"2026-08-09T09:00:00Z","postedAt":"2026-08-09T09:00:02Z"}]''');
  }

  setUp(() {
    floatJson = _floatJson();
    carriers = () => _json(_carriersJson);
    remit = (RequestOptions options) => _json(
        '{"remittanceId":"r1","holderRef":"eeeeeeee-5555-4555-8555-555555555555",'
        '"amount":13.25,"collections":1}');
    adapter = _FakeAdapter(route);
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;
    api = AccountingApi(dio);
    providers = DeliveryProviderApi(dio);
  });

  Future<void> pump(WidgetTester tester, {Size size = const Size(1600, 1000)}) async {
    // Desktop width. The default 800x600 test surface is narrower than any real Backoffice window,
    // and the transaction table's action column lands off-screen in it — which makes a tap fail
    // for reasons that have nothing to do with the code under test.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      theme: DeliveryTheme.light(),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: ReconciliationScreen(api: api, providerApi: providers)),
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

    testWidgets('without the server\'s flag, falls back to flagging cash out longer than a day',
        (WidgetTester tester) async {
      await pump(tester);

      // 30 hours is flagged; 10 minutes is a working day and must not be.
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.textContaining('longer than the platform\'s limit'), findsOneWidget);
    });

    testWidgets('the server\'s own limit decides what is overdue, not the screen\'s',
        (WidgetTester tester) async {
      // A company's rider carrying its cash is held to the carrier limit, two days by default: the
      // server calls the 30-hour bag on time, and the screen takes its word over its own day.
      floatJson = _floatJson(flags: <bool?>[false, false]);
      await pump(tester);

      expect(find.text('Overdue'), findsNothing);
      expect(find.textContaining('longer than the platform\'s limit'), findsNothing);
    });

    testWidgets('a holder the server calls overdue is flagged, however fresh it looks here',
        (WidgetTester tester) async {
      // The other direction: the server's line is the one drawn even where the screen's own day
      // would have let the bag pass, so its flag is shown rather than second-guessed.
      floatJson = _floatJson(flags: <bool?>[true, false]);
      await pump(tester);

      final Finder freshRow =
          find.ancestor(of: find.text('DDDDDDDD'), matching: find.byType(Row)).first;
      expect(find.descendant(of: freshRow, matching: find.text('Overdue')), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.textContaining('longer than the platform\'s limit'), findsOneWidget);
    });

    testWidgets('fits a half-width window', (WidgetTester tester) async {
      // A holder row packs an id, a count, an age, a pill, an amount and a button onto one line,
      // and the tiles above it get narrower as columns are added. Flutter fails a test on
      // overflow, so rendering at a squeezed width at all is the assertion.
      await pump(tester, size: const Size(1000, 800));

      expect(find.text('EEEEEEEE'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Banked'), findsNWidgets(2));
      expect(find.text('Libanex Express'), findsOneWidget);
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

  group('held by delivery companies', () {
    Finder recordPayment() => find.ancestor(
        of: find.text('Record payment'),
        matching: find.byWidgetPredicate((Widget w) => w is ButtonStyleButton));

    testWidgets('lists each company by name, what it owes, and its riders\' cash beside it',
        (WidgetTester tester) async {
      await pump(tester);

      expect(find.text('HELD BY DELIVERY COMPANIES'), findsOneWidget);
      expect(find.text('Libanex Express'), findsOneWidget);
      expect(find.text('\$485.50'), findsOneWidget);
      // Beside the company's figure, never added into it.
      expect(find.textContaining('With its riders: \$180.00'), findsOneWidget);
      expect(find.text('\$665.50'), findsNothing);
      expect(find.textContaining('Never paid'), findsOneWidget);
      // A company the directory could not name is still identified.
      expect(find.text('99999999'), findsOneWidget);
      expect(find.textContaining('Last paid 2026-10-19'), findsOneWidget);
    });

    testWidgets('a company holding nothing cannot be recorded as paying',
        (WidgetTester tester) async {
      await pump(tester);

      final List<ButtonStyleButton> buttons =
          tester.widgetList<ButtonStyleButton>(recordPayment()).toList();
      expect(buttons, hasLength(2));
      expect(buttons[0].enabled, isTrue);
      expect(buttons[1].enabled, isFalse);
      expect(find.textContaining('Holds nothing itself yet'), findsOneWidget);
    });

    testWidgets('asks before recording a payment, and cancelling sends nothing',
        (WidgetTester tester) async {
      await pump(tester);

      await tester.tap(recordPayment().first);
      await tester.pumpAndSettle();

      final Finder dialog = find.byType(AlertDialog);
      expect(find.descendant(of: dialog, matching: find.textContaining('Libanex Express')),
          findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.textContaining('\$485.50')),
          findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.textContaining('3 orders')),
          findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(adapter.calls.any((String c) => c.contains('remit')), isFalse);
    });

    testWidgets('confirming records the payment against the figure shown, once',
        (WidgetTester tester) async {
      remit = (RequestOptions options) => _json(
          '{"remittanceId":"r2","holderRef":"77777777-7777-4777-8777-777777777777",'
          '"amount":485.50,"collections":3,"replayed":false}');
      await pump(tester);

      await tester.tap(recordPayment().first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Bank deposit'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Yes, they paid'));
      await tester.pumpAndSettle();

      final RequestOptions post = adapter.requests.singleWhere(
          (RequestOptions o) => o.method == 'POST');
      expect(post.path, '/api/accounting/float/77777777-7777-4777-8777-777777777777/remit');
      final Map<String, dynamic> body = post.data as Map<String, dynamic>;
      expect(body['expectedAmount'], '485.50');
      expect(body['method'], 'BANK_DEPOSIT');
      expect(body['requestKey'], matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(find.text('Recorded \$485.50 from Libanex Express.'), findsOneWidget);
    });

    testWidgets('a payment refused because a hand-over landed meanwhile says what it holds now',
        (WidgetTester tester) async {
      remit = (RequestOptions options) => _json(
          '{"error":"They are holding 525.50 now.","code":"AMOUNT_CHANGED","current":"525.50"}',
          status: 409);
      await pump(tester);

      await tester.tap(recordPayment().first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Yes, they paid'));
      await tester.pumpAndSettle();

      expect(
        find.text('Libanex Express now holds \$525.50, not the amount you confirmed. '
            'Nothing was recorded.'),
        findsOneWidget,
      );
    });

    testWidgets('when the companies cannot be loaded, the rest of the page still works',
        (WidgetTester tester) async {
      carriers = () => _json('{"error":"down"}', status: 500);
      await pump(tester);

      expect(find.textContaining('could not be loaded just now'), findsOneWidget);
      expect(find.text('AT RISK'), findsOneWidget);
      expect(find.text('EEEEEEEE'), findsOneWidget);
    });

    testWidgets('is not drawn when no company holds or is owed anything',
        (WidgetTester tester) async {
      carriers = () => _json('{"overdueAfterHours":48,"carriers":[]}');
      await pump(tester);

      expect(find.text('HELD BY DELIVERY COMPANIES'), findsNothing);
      // Nothing to name, so the directory is not asked.
      expect(adapter.calls.any((String c) => c.contains('delivery-providers')), isFalse);
    });
  });
}
