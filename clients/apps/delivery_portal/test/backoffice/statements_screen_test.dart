import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_portal/src/backoffice/statements_screen.dart';
import 'package:delivery_portal/src/shell/shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The statements screen, driven through a real [StatementsApi] over a stubbed transport so the
/// contract's JSON — money as strings, direction from the platform's side, the unattributed block —
/// is under test alongside the widgets.
///
/// What these assert is mostly what the screen must NOT do: it must not hide the remainder that
/// belongs to nobody, must not send anything before an operator has seen the address, and must not
/// look like it sent something when it did not. The happy path is the easy half.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.listing, required this.statement, this.send});

  final Map<String, dynamic> listing;
  final Map<String, dynamic> statement;

  /// The send's answer. Null means the ordinary receipt; supply one to make the send fail.
  final (int, Map<String, dynamic>)? send;

  /// Every request, as "METHOD path".
  final List<String> calls = <String>[];

  List<String> get writes =>
      calls.where((String c) => !c.startsWith('GET ')).toList(growable: false);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');

    if (options.path.endsWith('/send')) {
      final (int, Map<String, dynamic>) answer = send ??
          (
            200,
            <String, dynamic>{
              'sentTo': 'shop@example.com',
              'sentAt': '2026-08-29T05:00:00Z',
              'dispatchId': 'dddddddd-0000-4000-8000-000000000000',
            }
          );
      return _body(answer.$2, answer.$1);
    }
    if (options.path.endsWith('/counterparties')) return _body(listing, 200);
    return _body(statement, 200);
  }

  ResponseBody _body(Map<String, dynamic> json, int status) =>
      ResponseBody.fromString(jsonEncode(json), status, headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType]
      });

  @override
  void close({bool force = false}) {}
}

const String _merchantRef = '11111111-1111-4111-8111-111111111111';
const String _riderRef = '22222222-2222-4222-8222-222222222222';

/// Tonight's real production figures: 45 delivered orders, 2425.00 collected, 2121.80 to the shop,
/// 303.20 of commission at 12.5%. Using them means a wrong number on screen is recognisable rather
/// than merely different.
Map<String, dynamic> _listing({Map<String, dynamic>? unattributed}) => <String, dynamic>{
      'from': '2026-08-01',
      'to': '2026-08-29',
      'currency': 'USD',
      'counterparties': <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 'MERCHANT',
          'ref': _merchantRef,
          'name': 'Rose & Crust Pizzeria',
          'net': '2121.80',
          'direction': 'WE_OWE',
          'orders': 45,
          'recipient': 'shop@example.com',
          'lastSentAt': null,
        },
        // No address on file, and owing the platform rather than owed by it — the two states that
        // change what the screen is allowed to do.
        <String, dynamic>{
          'kind': 'RIDER',
          'ref': _riderRef,
          'name': 'Sami Haddad',
          'net': '180.00',
          'direction': 'THEY_OWE',
          'orders': 12,
          'recipient': null,
          'lastSentAt': null,
        },
      ],
      'unattributed': unattributed ??
          <String, dynamic>{
            'amount': '412.50',
            'orders': 9,
            'note': 'Merchant credits that resolved to the omnibus bucket before identity '
                'was carried through settlement.',
          },
    };

Map<String, dynamic> get _statement => <String, dynamic>{
      'kind': 'MERCHANT',
      'ref': _merchantRef,
      'name': 'Rose & Crust Pizzeria',
      'from': '2026-08-01',
      'to': '2026-08-29',
      'currency': 'USD',
      'generatedAt': '2026-08-29T05:00:00Z',
      'lines': <Map<String, dynamic>>[
        <String, dynamic>{
          'label': 'Goods sold',
          'amount': '2425.00',
          'direction': 'CREDIT',
          'note': '45 orders',
        },
        <String, dynamic>{
          'label': 'Platform commission (12.5%)',
          'amount': '303.20',
          'direction': 'DEBIT',
          'note': null,
        },
      ],
      'net': <String, dynamic>{'amount': '2121.80', 'direction': 'WE_OWE'},
      'entries': <Map<String, dynamic>>[
        <String, dynamic>{
          'orderId': 'aaaaaaaa-1111-4111-8111-111111111111',
          'at': '2026-08-23T11:09:40Z',
          'gross': '19.50',
          'commission': '2.44',
          'net': '17.06',
          'paymentMethod': 'CASH',
        },
        <String, dynamic>{
          'orderId': 'bbbbbbbb-2222-4222-8222-222222222222',
          'at': '2026-08-24T18:30:00Z',
          'gross': '31.00',
          'commission': '3.88',
          'net': '27.12',
          'paymentMethod': 'CASH',
        },
      ],
      'note': 'Every order in this period was collected in cash at the door.',
    };

void main() {
  late _FakeAdapter adapter;

  StatementsApi apiFor(_FakeAdapter a) {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = a;
    return StatementsApi(dio);
  }

  setUp(() {
    adapter = _FakeAdapter(listing: _listing(), statement: _statement);
  });

  /// A real Backoffice window. The table is 1080 wide before the page's own 32px padding, and a
  /// narrower surface puts the Send column into a horizontal scroller where a tap misses it for
  /// reasons that have nothing to do with the code under test.
  Future<void> pump(WidgetTester tester, {_FakeAdapter? with_}) async {
    tester.view.physicalSize = const Size(1500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      home: Scaffold(body: StatementsScreen(api: apiFor(with_ ?? adapter))),
    ));
    await tester.pumpAndSettle();
  }

  group('the listing', () {
    testWidgets('names everyone who traded and which way the money points',
        (WidgetTester tester) async {
      await pump(tester);

      expect(find.text('Rose & Crust Pizzeria'), findsOneWidget);
      expect(find.text('Sami Haddad'), findsOneWidget);

      // The figure is the server's own string, rendered unchanged.
      expect(find.text('2121.80'), findsOneWidget);
      expect(find.text('180.00'), findsOneWidget);

      // Direction is always from the PLATFORM's side, and the two must never read alike: one is
      // ordinary business, the other is somebody to chase.
      expect(find.text('We owe them'), findsOneWidget);
      expect(find.text('They owe us'), findsOneWidget);

      // The currency is stated once, in the heading, rather than forty times down the column.
      expect(find.text('Net (USD)'), findsOneWidget);
    });

    testWidgets('nobody has been sent anything until somebody sends it',
        (WidgetTester tester) async {
      await pump(tester);

      expect(find.text('Never'), findsNWidgets(2));
    });
  });

  group('the unattributed remainder', () {
    testWidgets('is on the page in money, not hidden behind the rows',
        (WidgetTester tester) async {
      await pump(tester);

      // The reason the block is in the contract at all: a listing that shows only the rows
      // balances on screen and not in the bank.
      expect(find.text('Not attributed to anybody'), findsOneWidget);
      expect(find.textContaining('412.50 USD across 9 orders'), findsOneWidget);
      expect(find.textContaining('omnibus bucket'), findsOneWidget);
    });

    testWidgets('a genuinely clean period says so rather than saying nothing',
        (WidgetTester tester) async {
      // Silence and "it all adds up" have to look different, because silence is what let the
      // omnibus bucket survive.
      await pump(
        tester,
        with_: _FakeAdapter(
          listing: _listing(
            unattributed: <String, dynamic>{'amount': '0.00', 'orders': 0, 'note': null},
          ),
          statement: _statement,
        ),
      );

      expect(find.text('Not attributed to anybody'), findsNothing);
      expect(find.textContaining('Every figure in this period is attributed'), findsOneWidget);
    });

    testWidgets('a server that sent no block at all is not read as a clean one',
        (WidgetTester tester) async {
      final Map<String, dynamic> listing = _listing()..remove('unattributed');
      await pump(tester, with_: _FakeAdapter(listing: listing, statement: _statement));

      expect(find.textContaining('sent no unattributed total'), findsOneWidget);
      expect(find.textContaining('Every figure in this period is attributed'), findsNothing);
    });
  });

  group('drilling in', () {
    testWidgets('renders the summary lines, the bottom line and the orders behind them',
        (WidgetTester tester) async {
      await pump(tester);

      await tester.tap(find.text('Rose & Crust Pizzeria'));
      await tester.pumpAndSettle();

      expect(adapter.calls.any((String c) => c.endsWith('/MERCHANT/$_merchantRef')), isTrue);

      // The lines, with the sign composed from each line's own direction.
      expect(find.text('Goods sold'), findsOneWidget);
      expect(find.text('+2425.00'), findsOneWidget);
      expect(find.text('Platform commission (12.5%)'), findsOneWidget);
      expect(find.text('-303.20'), findsOneWidget);
      expect(find.text('45 orders'), findsOneWidget);

      // The bottom line, with the currency spelled out because this one is read on its own.
      expect(find.text('2121.80 USD'), findsOneWidget);

      // The rows somebody points at in a dispute.
      expect(find.text('#AAAAAAAA'), findsOneWidget);
      expect(find.text('#BBBBBBBB'), findsOneWidget);
      expect(find.text('17.06'), findsOneWidget);
      expect(find.textContaining('of 19.50 · cut 2.44'), findsOneWidget);

      // And the server's own caveat, which is where a total that would otherwise look wrong gets
      // explained.
      expect(find.textContaining('collected in cash at the door'), findsOneWidget);
    });
  });

  group('sending', () {
    testWidgets('names the address it would go to, and sends nothing until confirmed',
        (WidgetTester tester) async {
      await pump(tester);

      await tester.tap(find.widgetWithText(ConsoleButton, 'Send').first);
      await tester.pumpAndSettle();

      final Finder dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      // The whole point of the step: the operator sees who it is going to before it goes.
      expect(find.descendant(of: dialog, matching: find.text('shop@example.com')),
          findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('Sends to')), findsOneWidget);
      // And the figures they are about to put in front of a real shop.
      expect(find.descendant(of: dialog, matching: find.textContaining('2121.80 USD')),
          findsOneWidget);

      // Nothing has left the browser.
      expect(adapter.writes, isEmpty);
    });

    testWidgets('cancelling sends nothing', (WidgetTester tester) async {
      await pump(tester);

      await tester.tap(find.widgetWithText(ConsoleButton, 'Send').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ConsoleButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(adapter.writes, isEmpty);
      expect(find.text('Never'), findsNWidgets(2));
    });

    testWidgets('confirming posts to that counterparty and records when it went',
        (WidgetTester tester) async {
      await pump(tester);

      await tester.tap(find.widgetWithText(ConsoleButton, 'Send').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ConsoleButton, 'Send statement'));
      await tester.pumpAndSettle();

      expect(adapter.writes, <String>['POST /api/accounting/statements/MERCHANT/$_merchantRef/send']);
      expect(find.textContaining('Statement sent to shop@example.com'), findsOneWidget);

      // The merchant's row is no longer "Never" — the rider's still is.
      expect(find.text('Never'), findsOneWidget);
    });

    testWidgets('a send that failed says so and does not claim it went',
        (WidgetTester tester) async {
      await pump(
        tester,
        with_: _FakeAdapter(
          listing: _listing(),
          statement: _statement,
          send: (502, <String, dynamic>{'message': 'the mail relay refused the message'}),
        ),
      );

      await tester.tap(find.widgetWithText(ConsoleButton, 'Send').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ConsoleButton, 'Send statement'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Not sent: the mail relay refused the message'), findsOneWidget);
      expect(find.textContaining('Statement sent to'), findsNothing);
      // The row must still read as never sent. A stamp here would be the screen agreeing with a
      // send that never happened.
      expect(find.text('Never'), findsNWidgets(2));
    });

    testWidgets('the two 409s are told apart, because they ask for different things',
        (WidgetTester tester) async {
      await pump(
        tester,
        with_: _FakeAdapter(
          listing: _listing(),
          statement: _statement,
          send: (
            409,
            <String, dynamic>{
              'code': 'ALREADY_SENT',
              'sentTo': 'shop@example.com',
              'sentAt': '2026-08-28T09:00:00Z',
              'dispatchId': 'eeeeeeee-0000-4000-8000-000000000000',
            }
          ),
        ),
      );

      await tester.tap(find.widgetWithText(ConsoleButton, 'Send').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ConsoleButton, 'Send statement'));
      await tester.pumpAndSettle();

      expect(find.textContaining('this period already went out to shop@example.com'),
          findsOneWidget);
      expect(find.text('Never'), findsNWidgets(2));
    });

    testWidgets('a counterparty with no address on file has to be given one',
        (WidgetTester tester) async {
      await pump(tester);

      // The rider row. The send route answers 409 without an address, so offering a Send that
      // could only fail would be a button that lies.
      await tester.tap(find.widgetWithText(ConsoleButton, 'Send').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('No address is on file'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Disabled until there is somewhere to send it.
      final ConsoleButton confirm =
          tester.widget<ConsoleButton>(find.widgetWithText(ConsoleButton, 'Send statement'));
      expect(confirm.onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'finance@courier.example');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ConsoleButton, 'Send statement'));
      await tester.pumpAndSettle();

      expect(adapter.writes,
          <String>['POST /api/accounting/statements/RIDER/$_riderRef/send']);
    });
  });

  testWidgets('lays out at a laptop width without overflowing', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1180, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      home: Scaffold(body: StatementsScreen(api: apiFor(adapter))),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Rose & Crust Pizzeria'), findsOneWidget);
  });
}
