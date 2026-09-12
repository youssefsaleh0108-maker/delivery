import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/carrier/rider_cash_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// One rider's cash bag and the hand-over at the hub counter (Figma 112:235).
///
/// What matters: the bag is listed order by order with when each note was taken; the summary says
/// the whole balance is owed to the company — not the design's "rider keeps all but a commission",
/// which the ledger contradicts; a figure the ledger does not hold is a dash, never a zero; and the
/// hand-over sends back exactly the balance on screen with the method chosen, or is refused with
/// the current figure.
class _Server implements HttpClientAdapter {
  _Server(this.respond);

  ResponseBody Function(RequestOptions options) respond;
  final List<RequestOptions> calls = <RequestOptions>[];

  List<RequestOptions> get posts =>
      calls.where((RequestOptions o) => o.method == 'POST').toList(growable: false);

  int get pageLoads => calls
      .where((RequestOptions o) =>
          o.method == 'GET' && o.path == '/api/accounting/carrier/cash/riders/rider-youssef')
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

Map<String, dynamic> _settlement({
  String holding = '265.00',
  String standing = 'OVERDUE',
  List<dynamic>? held,
  List<dynamic>? handovers,
}) =>
    <String, dynamic>{
      'riderRef': 'rider-youssef',
      'name': 'Youssef Kanaan',
      'currency': 'USD',
      'overdueAfterHours': 48,
      'holding': holding,
      'earnedOnHeld': '4.50',
      'standing': standing,
      'overdueHours': standing == 'OVERDUE' ? 74 : null,
      'firstSeenAt': '2026-10-21T09:00:00Z',
      'held': held ??
          <dynamic>[
            <String, dynamic>{
              'orderId': 'aaaaaaaa-1111-4111-8111-111111111111',
              'amount': '120.00',
              'collectedAt': '2026-10-21T09:00:00Z',
              // No fee row on the ledger for this job.
              'earned': null,
              'overdue': true,
            },
            <String, dynamic>{
              'orderId': 'bbbbbbbb-2222-4222-8222-222222222222',
              'amount': '145.00',
              'collectedAt': '2026-10-24T09:00:00Z',
              'earned': '4.50',
              'overdue': false,
            },
          ],
      'handovers': handovers ??
          <dynamic>[
            <String, dynamic>{
              'id': 'h-2',
              'riderRef': 'rider-youssef',
              'riderName': 'Youssef Kanaan',
              'amount': '232.00',
              'collections': 4,
              'method': 'CASH',
              'note': null,
              'recordedByName': 'Kamal M.',
              'at': '2026-10-23T18:00:00Z',
            },
            <String, dynamic>{
              'id': 'h-1',
              'riderRef': 'rider-youssef',
              'riderName': 'Youssef Kanaan',
              'amount': '145.00',
              'collections': 2,
              'method': 'BANK_DEPOSIT',
              'note': null,
              'recordedByName': null,
              'at': '2026-10-22T18:00:00Z',
            },
          ],
    };

ResponseBody _happy(RequestOptions o) {
  if (o.method == 'POST') {
    final Map<String, dynamic> body = o.data as Map<String, dynamic>;
    return _json(<String, dynamic>{
      'handoverId': 'h-3',
      'riderRef': 'rider-youssef',
      'amount': body['expectedAmount'],
      'collections': 2,
      'method': body['method'],
      'note': body['note'],
      'recordedAt': '2026-10-24T11:00:00Z',
      'replayed': false,
    });
  }
  if (o.path == '/api/riders/rider-youssef/rating') {
    return _json(<String, dynamic>{
      'riderId': 'rider-youssef',
      'average': 4.8,
      'ratings': 142,
      'stars': <String, dynamic>{'1': 0, '2': 1, '3': 4, '4': 20, '5': 117},
    });
  }
  return _json(_settlement());
}

void main() {
  late _Server server;

  setUp(() => server = _Server(_happy));

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1600);
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
        body: RiderCashScreen(
          api: CarrierCashApi(dio),
          riderRef: 'rider-youssef',
          name: 'Youssef Kanaan',
          orderApi: OrderApi(dio),
          onBack: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  InkWell buttonBehind(WidgetTester tester, String label) => tester.widget<InkWell>(
      find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first);

  testWidgets('lists the bag order by order, with when each was taken and no invented fee',
      (WidgetTester tester) async {
    await pump(tester);

    expect(find.text('#AAAAAAAA'), findsOneWidget);
    expect(find.text('#BBBBBBBB'), findsOneWidget);
    expect(find.text('\$120.00'), findsOneWidget);
    expect(find.text('\$145.00'), findsWidgets);
    // Not "(Today)": the older note says it was taken three days before.
    expect(find.textContaining('2026-10-21'), findsWidgets);
    // The job with no fee on the ledger shows a dash, never 0.00.
    expect(find.text('—'), findsOneWidget);
    expect(find.text('\$0.00'), findsNothing);
  });

  testWidgets('the summary owes the whole balance to the company, and says the rider keeps none',
      (WidgetTester tester) async {
    await pump(tester);

    expect(find.text('Cash due to your company'), findsOneWidget);
    expect(find.text('\$265.00'), findsNWidgets(2));
    expect(find.textContaining('The rider keeps none of this cash'), findsOneWidget);
    // The design's maths and its PIN box have nothing behind them on the platform.
    expect(find.textContaining('Net to Rider'), findsNothing);
    expect(find.textContaining('ommission'), findsNothing);
    expect(find.textContaining('PIN'), findsNothing);
  });

  testWidgets('confirming sends the balance on screen, the method picked and the note',
      (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.text('Cash hand-over'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bank deposit').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bag 12');

    await tester.tap(find.text('Confirm settlement'));
    await tester.pumpAndSettle();

    final Finder dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.textContaining('\$265.00')),
        findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.textContaining('2 orders')),
        findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Yes, record it'));
    await tester.pumpAndSettle();

    final RequestOptions post = server.posts.single;
    expect(post.path, '/api/accounting/carrier/cash/riders/rider-youssef/handovers');
    final Map<String, dynamic> body = post.data as Map<String, dynamic>;
    expect(body['expectedAmount'], '265.00');
    expect(body['method'], 'BANK_DEPOSIT');
    expect(body['note'], 'bag 12');
    expect(body['requestKey'], matches(RegExp(r'^[0-9a-f]{32}$')));

    expect(find.text('Recorded \$265.00 from Youssef Kanaan.'), findsOneWidget);
    expect(server.pageLoads, 2);
  });

  testWidgets('cancelling the confirmation records nothing', (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.text('Confirm settlement'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(server.posts, isEmpty);
  });

  testWidgets('a refused hand-over says what the rider holds now, and reloads',
      (WidgetTester tester) async {
    server.respond = (RequestOptions o) => o.method == 'POST'
        ? _json(<String, dynamic>{
            'error': 'This rider is holding 300.00 for your company now.',
            'code': 'AMOUNT_CHANGED',
            'current': '300.00',
          }, status: 409)
        : _happy(o);
    await pump(tester);

    await tester.tap(find.text('Confirm settlement'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Yes, record it'));
    await tester.pumpAndSettle();

    expect(
      find.text('Youssef Kanaan is now holding \$300.00, not the amount you confirmed. '
          'Nothing was recorded; count it again.'),
      findsOneWidget,
    );
    expect(server.pageLoads, 2);
  });

  testWidgets('a rider holding nothing has nothing to confirm', (WidgetTester tester) async {
    server.respond = (RequestOptions o) => o.path.contains('/rating')
        ? _happy(o)
        : _json(_settlement(holding: '0.00', standing: 'SETTLED', held: <dynamic>[]));
    await pump(tester);

    expect(find.text('Confirm settlement'), findsNothing);
    expect(find.text('Nothing to settle'), findsOneWidget);
    expect(buttonBehind(tester, 'Nothing to settle').onTap, isNull);
    expect(find.text('Settled'), findsOneWidget);
  });

  testWidgets('the history is newest first and names who recorded each hand-over',
      (WidgetTester tester) async {
    await pump(tester);

    final Finder newer = find.textContaining('recorded by Kamal M.');
    final Finder older = find.textContaining('\$145.00 for 2 orders');
    expect(newer, findsOneWidget);
    expect(older, findsOneWidget);
    expect(tester.getTopLeft(newer).dy, lessThan(tester.getTopLeft(older).dy));
  });

  testWidgets('a rider who never worked for the company is not found, not an empty bag',
      (WidgetTester tester) async {
    server.respond = (RequestOptions o) => o.path.contains('/rating')
        ? _happy(o)
        : _json(<String, dynamic>{'error': 'never'}, status: 404);
    await pump(tester);

    final DeliveryStrings t = DeliveryStrings.of(tester.element(find.byType(RiderCashScreen)));
    expect(find.text(t.carrCashRiderNotFound), findsOneWidget);
    expect(find.text('Confirm settlement'), findsNothing);
  });

  testWidgets('shows the rider\'s rating when there is one', (WidgetTester tester) async {
    await pump(tester);

    expect(find.text('4.8'), findsOneWidget);
    expect(find.text('(142 ratings)'), findsOneWidget);
  });

  testWidgets('leaves the rating off when it cannot be read, never a zero',
      (WidgetTester tester) async {
    server.respond = (RequestOptions o) => o.path.contains('/rating')
        ? _json(<String, dynamic>{'error': 'down'}, status: 500)
        : _happy(o);
    await pump(tester);

    expect(find.text('0.0'), findsNothing);
    expect(find.byIcon(Icons.star_border_rounded), findsNothing);
    expect(find.text('Youssef Kanaan'), findsWidgets);
  });
}
