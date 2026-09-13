import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/carrier/cash_reconciliation_screen.dart';
import 'package:delivery_portal/src/carrier/rider_cash_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The delivery company's rider cash reconciliation (Figma 112:9).
///
/// What matters: it asks for its own company's cash and names nobody; every figure on it is the
/// ledger's string; a rider holding nothing cannot be settled; nothing is cleared without a
/// confirmation naming the rider and the amount; and what goes back to the server is exactly the
/// figure the person at the counter was shown — so cash collected after the page loaded is refused,
/// not swept up uncounted.
class _Server implements HttpClientAdapter {
  _Server(this.respond);

  ResponseBody Function(RequestOptions options) respond;
  final List<RequestOptions> calls = <RequestOptions>[];

  List<RequestOptions> get posts =>
      calls.where((RequestOptions o) => o.method == 'POST').toList(growable: false);

  int get overviewLoads => calls
      .where((RequestOptions o) => o.method == 'GET' && o.path == '/api/accounting/carrier/cash')
      .length;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );

Map<String, dynamic> _rider(
  String ref,
  String? name, {
  required String collected,
  required String earned,
  required String holding,
  required int orders,
  required String standing,
  String? oldest,
  String? lastHandoverAt,
  int? overdueHours,
}) =>
    <String, dynamic>{
      'riderRef': ref,
      'name': name,
      'collected': collected,
      'collections': 1,
      'earned': earned,
      'jobs': 1,
      'holding': holding,
      'orders': orders,
      'oldest': oldest,
      'lastHandoverAt': lastHandoverAt,
      'standing': standing,
      'overdueHours': overdueHours,
    };

Map<String, dynamic> _overview({List<Map<String, dynamic>>? riders}) => <String, dynamic>{
      'day': '2026-10-24',
      'currency': 'USD',
      'overdueAfterHours': 48,
      'totals': <String, dynamic>{
        'withRiders': '180.00',
        'ridersHolding': 2,
        'handedOver': '40.00',
        'handovers': 1,
        'held': '485.50',
        'heldOrders': 3,
        'overdue': '50.00',
        'overdueRiders': 1,
      },
      'riders': riders ??
          <Map<String, dynamic>>[
            _rider('rider-youssef', 'Youssef Kanaan',
                collected: '100.00',
                earned: '2.25',
                holding: '150.00',
                orders: 2,
                standing: 'OVERDUE',
                oldest: '2026-10-21T10:00:00Z',
                overdueHours: 74),
            _rider('rider-michel', 'Michel Barakat',
                collected: '30.00',
                earned: '0.75',
                holding: '30.00',
                orders: 1,
                standing: 'HOLDING',
                oldest: '2026-10-24T09:00:00Z'),
            _rider('rider-rania', 'Rania Ghandour',
                collected: '0.00',
                earned: '0.00',
                holding: '0.00',
                orders: 0,
                standing: 'SETTLED',
                lastHandoverAt: '2026-10-24T08:00:00Z'),
          ],
    };

Map<String, dynamic> _receipt(String rider, String amount) => <String, dynamic>{
      'handoverId': 'h-$rider',
      'riderRef': rider,
      'amount': amount,
      'collections': 2,
      'method': 'CASH',
      'note': null,
      'recordedAt': '2026-10-24T11:00:00Z',
      'replayed': false,
    };

/// Answers the overview on GET and records a hand-over on POST, with the amount the POST confirmed.
ResponseBody _happy(RequestOptions o) {
  if (o.method == 'POST') {
    final String rider = o.path.split('/riders/').last.split('/').first;
    final Map<String, dynamic> body = o.data as Map<String, dynamic>;
    return _json(_receipt(rider, body['expectedAmount'] as String));
  }
  if (o.path.contains('/riders/')) {
    return _json(<String, dynamic>{
      'riderRef': 'rider-youssef',
      'name': 'Youssef Kanaan',
      'currency': 'USD',
      'overdueAfterHours': 48,
      'holding': '150.00',
      'earnedOnHeld': '2.25',
      'standing': 'OVERDUE',
      'overdueHours': 74,
      'firstSeenAt': '2026-10-21T10:00:00Z',
      'held': <dynamic>[],
      'handovers': <dynamic>[],
    });
  }
  return _json(_overview());
}

String _today() {
  final DateTime now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}'
      '-${now.day.toString().padLeft(2, '0')}';
}

void main() {
  late _Server server;
  String? savedName;
  String? savedCsv;

  setUp(() {
    server = _Server(_happy);
    savedName = null;
    savedCsv = null;
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = server;
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
      home: Scaffold(
        body: CarrierCashScreen(
          api: CarrierCashApi(dio),
          saveFile: (String name, String content, {String mimeType = 'text/csv'}) {
            savedName = name;
            savedCsv = content;
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// The button behind each label with this text, in row order.
  ///
  /// The nearest InkWell only: a table row is tappable too (it opens the rider's page), so every
  /// row button has the row's own InkWell further up, and that one says nothing about the button.
  List<InkWell> buttons(WidgetTester tester, String label) {
    final Finder labels = find.text(label);
    return <InkWell>[
      for (int i = 0; i < labels.evaluate().length; i++)
        tester.widget<InkWell>(
            find.ancestor(of: labels.at(i), matching: find.byType(InkWell)).first),
    ];
  }

  testWidgets('asks for its own company\'s cash, for today, and names no company',
      (WidgetTester tester) async {
    await pump(tester);

    final RequestOptions first = server.calls.first;
    expect(first.method, 'GET');
    expect(first.path, '/api/accounting/carrier/cash');
    // The day and nothing else. Whose cash comes back is the token's to decide.
    expect(first.queryParameters, <String, dynamic>{'day': _today()});
  });

  testWidgets('the cards and the rows are the ledger\'s own figures', (WidgetTester tester) async {
    await pump(tester);

    expect(find.text('\$180.00'), findsOneWidget);
    expect(find.text('\$40.00'), findsOneWidget);
    // What the company itself owes YouDrop — the card the design's "Disputed" became.
    expect(find.text('\$485.50'), findsOneWidget);
    expect(find.text('\$50.00'), findsOneWidget);
    expect(find.text('Owed to YouDrop'), findsOneWidget);

    expect(find.text('Youssef Kanaan'), findsOneWidget);
    expect(find.text('\$150.00'), findsOneWidget);
    expect(find.text('\$2.25'), findsOneWidget);
    // The design's commission and rider-earnings columns are not figures the ledger has.
    expect(find.textContaining('ommission'), findsNothing);
    expect(find.textContaining('Rider earnings'), findsNothing);
  });

  testWidgets('an overdue rider is badged with the hours; a square rider cannot be settled',
      (WidgetTester tester) async {
    await pump(tester);

    expect(find.text('Overdue 74h'), findsOneWidget);
    expect(find.text('Holding cash'), findsOneWidget);
    expect(find.text('Settled'), findsOneWidget);

    final List<InkWell> settle = buttons(tester, 'Settle');
    expect(settle, hasLength(3));
    expect(settle[0].onTap, isNotNull);
    expect(settle[1].onTap, isNotNull);
    // Rania holds 0.00. The design draws this button live; pressing it would record nothing.
    expect(settle[2].onTap, isNull);
  });

  testWidgets('Settle asks first, naming the rider, the amount and the orders',
      (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.text('Settle').first);
    await tester.pumpAndSettle();

    final Finder dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.textContaining('Youssef Kanaan')),
        findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.textContaining('\$150.00')),
        findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.textContaining('2 orders')),
        findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    // A stray click must not be enough to clear a rider's balance for good.
    expect(server.posts, isEmpty);
  });

  testWidgets('confirming records the figure that was on screen, with a key, and reloads',
      (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.text('Settle').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Yes, record it'));
    await tester.pumpAndSettle();

    final RequestOptions post = server.posts.single;
    expect(post.path, '/api/accounting/carrier/cash/riders/rider-youssef/handovers');
    final Map<String, dynamic> body = post.data as Map<String, dynamic>;
    expect(body['expectedAmount'], '150.00');
    expect(body['method'], 'CASH');
    expect(body['requestKey'], matches(RegExp(r'^[0-9a-f]{32}$')));

    expect(find.text('Recorded \$150.00 from Youssef Kanaan.'), findsOneWidget);
    expect(server.overviewLoads, 2);
  });

  testWidgets('a balance that moved since the page loaded is refused with the new figure',
      (WidgetTester tester) async {
    server.respond = (RequestOptions o) => o.method == 'POST'
        ? _json(<String, dynamic>{
            'error': 'This rider is holding 165.00 for your company now.',
            'code': 'AMOUNT_CHANGED',
            'current': '165.00',
          }, status: 409)
        : _happy(o);
    await pump(tester);

    await tester.tap(find.text('Settle').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Yes, record it'));
    await tester.pumpAndSettle();

    expect(
      find.text('Youssef Kanaan is now holding \$165.00, not the amount you confirmed. '
          'Nothing was recorded; count it again.'),
      findsOneWidget,
    );
    // Reloaded, so the page now shows what the server holds rather than the refused figure.
    expect(server.overviewLoads, 2);
  });

  testWidgets('Settle selected records each ticked rider once, against their own figure',
      (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.byTooltip('Select every rider holding cash'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.text('Settle selected'));
    await tester.pumpAndSettle();

    final Finder dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.text('Record 2 hand-overs')),
        findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Total \$180.00')), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Yes, record it'));
    await tester.pumpAndSettle();

    expect(server.posts, hasLength(2));
    final Map<String, String> sent = <String, String>{
      for (final RequestOptions p in server.posts)
        p.path.split('/riders/').last.split('/').first:
            (p.data as Map<String, dynamic>)['expectedAmount'] as String,
    };
    expect(sent, <String, String>{'rider-youssef': '150.00', 'rider-michel': '30.00'});
    // Two confirmations' worth of keys, never one shared.
    expect(
      server.posts.map((RequestOptions p) => (p.data as Map<String, dynamic>)['requestKey']).toSet(),
      hasLength(2),
    );
    expect(find.textContaining('Recorded 2 of 2.'), findsOneWidget);
  });

  testWidgets('staff of no company are told so, not shown an empty page',
      (WidgetTester tester) async {
    server.respond = (_) => _json(<String, dynamic>{
          'error': 'This account is not staff of a delivery company.',
          'code': 'NO_COMPANY',
        }, status: 403);
    await pump(tester);

    final DeliveryStrings t = DeliveryStrings.of(tester.element(find.byType(CarrierCashScreen)));
    expect(find.text(t.noCompanyYet), findsOneWidget);
    expect(find.text(t.carrCashNobodyYet), findsNothing);
  });

  testWidgets('an outage is a retry, never "nobody is holding cash"', (WidgetTester tester) async {
    server.respond = (_) => _json(<String, dynamic>{'error': 'down'}, status: 503);
    await pump(tester);

    expect(find.text('None of your riders has carried cash for your company yet.'), findsNothing);
    expect(find.textContaining('could not be loaded just now'), findsOneWidget);

    server.respond = _happy;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Youssef Kanaan'), findsOneWidget);
  });

  testWidgets('a company whose riders never carried cash says so, with nothing to export',
      (WidgetTester tester) async {
    server.respond = (_) => _json(_overview(riders: <Map<String, dynamic>>[]));
    await pump(tester);

    expect(find.text('None of your riders has carried cash for your company yet.'), findsOneWidget);
    expect(buttons(tester, 'Export CSV').single.onTap, isNull);
  });

  testWidgets('Export CSV writes a header and one line per rider, figures as the ledger wrote them',
      (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.text('Export CSV'));
    await tester.pumpAndSettle();

    expect(savedName, 'rider-cash-2026-10-24.csv');
    final List<String> lines =
        savedCsv!.split('\r\n').where((String l) => l.isNotEmpty).toList(growable: false);
    expect(lines, hasLength(4));
    expect(
      lines.first,
      'Rider,Rider ID,Collected,Fees earned for you,Cash to hand over,Orders held,'
      'Oldest collection,Last hand-over,Status',
    );
    expect(lines[1],
        'Youssef Kanaan,rider-youssef,100.00,2.25,150.00,2,2026-10-21T10:00:00.000Z,,Overdue');
    expect(lines[3], startsWith('Rania Ghandour,rider-rania,0.00,0.00,0.00,0,,'));
  });

  testWidgets('Export CSV cannot slip a formula into the hub\'s spreadsheet',
      (WidgetTester tester) async {
    // A rider's name is whatever they typed into their own account. A cell that starts with = + - @
    // (or a tab or carriage return) runs as a formula when the file is opened, so every text cell
    // leads with an apostrophe and is quoted — while a figure the ledger wrote, minus sign and all,
    // stays a number.
    Map<String, dynamic> named(String ref, String name, {String earned = '0.00'}) => _rider(
          ref,
          name,
          collected: '0.00',
          earned: earned,
          holding: '0.00',
          orders: 0,
          standing: 'SETTLED',
        );
    server.respond = (_) => _json(_overview(riders: <Map<String, dynamic>>[
          named('rider-1', '=HYPERLINK("http://evil.example","Payslip")', earned: '-0.75'),
          named('rider-2', '+1+1'),
          named('rider-3', '-2+3'),
          named('rider-4', '@SUM(A1:A9)'),
          named('rider-5', '\t=1+1'),
          named('rider-6', '\r=1+1'),
          named('rider-7', 'Kanaan, Youssef'),
        ]));
    await pump(tester);

    await tester.tap(find.text('Export CSV'));
    await tester.pumpAndSettle();

    final String csv = savedCsv!;
    expect(csv,
        contains('\r\n"\'=HYPERLINK(""http://evil.example"",""Payslip"")",rider-1,0.00,-0.75,'));
    expect(csv, contains('\r\n"\'+1+1",rider-2,'));
    expect(csv, contains('\r\n"\'-2+3",rider-3,'));
    expect(csv, contains('\r\n"\'@SUM(A1:A9)",rider-4,'));
    expect(csv, contains('\r\n"\'\t=1+1",rider-5,'));
    expect(csv, contains('\r\n"\'\r=1+1",rider-6,'));
    // Ordinary text is quoted only where RFC 4180 already asked for it, and never marked.
    expect(csv, contains('\r\n"Kanaan, Youssef",rider-7,'));
    expect(csv, isNot(contains('\r\n=')));
  });

  testWidgets('View opens the rider\'s settlement page in place, and Back returns to the list',
      (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.text('View').first);
    await tester.pumpAndSettle();

    expect(find.byType(RiderCashScreen), findsOneWidget);
    expect(
      server.calls.any((RequestOptions o) =>
          o.path == '/api/accounting/carrier/cash/riders/rider-youssef'),
      isTrue,
    );
    expect(find.text('Rider Settlement Detail'), findsOneWidget);

    await tester.tap(find.text('Back to reconciliation'));
    await tester.pumpAndSettle();

    expect(find.byType(RiderCashScreen), findsNothing);
    expect(find.text('Rider Cash Reconciliation'), findsOneWidget);
  });
}
