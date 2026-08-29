import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_portal/src/carrier/statement_screen.dart';
import 'package:delivery_portal/src/shell/shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The carrier's own statement, read-only, off `/statements/mine`.
///
/// The two things worth pinning down are that it asks for nobody in particular — the route takes no
/// ref, and a carrier must not be able to steer it at somebody else — and that a figure the ledger
/// did not send renders as unknown rather than as a confident zero. A carrier reading "0.00" where
/// the platform actually meant "we cannot separate that out" would budget against it.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body, {this.status = 200});

  final Map<String, dynamic> body;
  final int status;

  final List<String> calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.uri.path}?${options.uri.query}');
    return ResponseBody.fromString(jsonEncode(body), status,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

/// A carrier statement as the foundation actually emits one: a delivery-fees line and NO commission
/// line, because a catalog order always has a merchant on it too and the platform's cut cannot be
/// separated out of the residue. The note is where the server says so.
Map<String, dynamic> _statement({
  List<Map<String, dynamic>>? lines,
  String? note = 'The platform\'s share is not separable on orders that also have a shop on them, '
      'so no commission line is shown. The net is exact.',
}) =>
    <String, dynamic>{
      'kind': 'CARRIER',
      'ref': '33333333-3333-4333-8333-333333333333',
      'name': 'Beirut Wheels',
      'from': '2026-08-01',
      'to': '2026-08-29',
      'currency': 'USD',
      'generatedAt': '2026-08-29T05:00:00Z',
      'lines': lines ??
          <Map<String, dynamic>>[
            <String, dynamic>{
              'label': 'Delivery fees',
              'amount': '318.75',
              'direction': 'CREDIT',
              'note': '61 jobs',
            },
          ],
      'net': <String, dynamic>{'amount': '318.75', 'direction': 'WE_OWE'},
      'entries': <Map<String, dynamic>>[
        <String, dynamic>{
          'orderId': 'aaaaaaaa-1111-4111-8111-111111111111',
          'at': '2026-08-23T11:09:40Z',
          'gross': '5.25',
          'commission': '0.53',
          'net': '4.72',
          'paymentMethod': 'CASH',
        },
        <String, dynamic>{
          'orderId': 'bbbbbbbb-2222-4222-8222-222222222222',
          'at': '2026-08-24T18:30:00Z',
          'gross': '6.00',
          'commission': null,
          'net': '6.00',
          'paymentMethod': 'CASH',
        },
      ],
      if (note != null) 'note': note,
    };

void main() {
  StatementsApi apiFor(_StubAdapter a) {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = a;
    return StatementsApi(dio);
  }

  Future<void> pump(WidgetTester tester, _StubAdapter adapter,
      {double width = 1400}) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      home: Scaffold(body: CarrierStatementScreen(api: apiFor(adapter))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('asks for its own statement and names nobody', (WidgetTester tester) async {
    final _StubAdapter adapter = _StubAdapter(_statement());
    await pump(tester, adapter);

    expect(adapter.calls, hasLength(1));
    // No ref anywhere in the path. Whose statement comes back is decided by the token.
    expect(adapter.calls.single, startsWith('GET /api/accounting/statements/mine?'));
    expect(adapter.calls.single, contains('from='));
    expect(adapter.calls.single, contains('to='));
  });

  testWidgets('shows what is itemised, the fees earned and the net', (WidgetTester tester) async {
    await pump(tester, _StubAdapter(_statement()));

    // NOT a "Jobs" count. This card used to be labelled that and read entries.length, which is the
    // number of rows that came back — and the server trims that list. This very fixture shows why:
    // two entries beside a credit line whose own words, three assertions down, say "61 jobs". A
    // company reading "Jobs 2" for a month its riders carried 61 disputes the net, and the net is
    // right. The card now says how many are itemised, which is a fact about the list.
    expect(find.text('Jobs'), findsNothing);
    expect(find.text('Itemised below'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('of the jobs in this period'), findsOneWidget);

    // The line's own label and note, which are the server's words rather than this screen's.
    expect(find.text('Delivery fees'), findsOneWidget);
    expect(find.text('318.75'), findsWidgets);
    expect(find.text('61 jobs'), findsOneWidget);

    expect(find.text('Net (USD)'), findsOneWidget);
    // The counterparty's wording, not the operator's: this company is reading its own statement.
    expect(find.text('Owed to you'), findsOneWidget);
    expect(find.text('We owe them'), findsNothing);
  });

  testWidgets('a cut the ledger cannot separate shows as unknown, never as zero',
      (WidgetTester tester) async {
    await pump(tester, _StubAdapter(_statement()));

    expect(find.text('Platform\'s cut'), findsOneWidget);
    expect(find.text('not itemised for this period'), findsOneWidget);
    expect(find.text('0.00'), findsNothing);
    // And the server's explanation is on the page rather than left to be guessed at.
    expect(find.textContaining('not separable on orders that also have a shop'), findsOneWidget);
  });

  testWidgets('and shows it plainly when the ledger did separate it',
      (WidgetTester tester) async {
    await pump(
      tester,
      _StubAdapter(_statement(
        lines: <Map<String, dynamic>>[
          <String, dynamic>{
            'label': 'Delivery fees',
            'amount': '318.75',
            'direction': 'CREDIT',
            'note': '61 jobs',
          },
          <String, dynamic>{
            'label': 'Platform commission (10%)',
            'amount': '31.88',
            'direction': 'DEBIT',
            'note': null,
          },
        ],
        note: null,
      )),
    );

    expect(find.text('Platform commission (10%)'), findsOneWidget);
    // Signed by the model from the line's own direction, so a deduction cannot read as income.
    expect(find.text('-31.88'), findsOneWidget);
    expect(find.text('Platform\'s cut'), findsNothing);
  });

  testWidgets('itemises the jobs behind the total', (WidgetTester tester) async {
    await pump(tester, _StubAdapter(_statement()));

    expect(find.byType(ConsoleTable), findsOneWidget);
    expect(find.text('#AAAAAAAA'), findsOneWidget);
    expect(find.text('#BBBBBBBB'), findsOneWidget);
    expect(find.text('4.72'), findsOneWidget);
    expect(find.text('0.53'), findsOneWidget);
    // The second order carries no commission figure. A dash, because a missing number is not a
    // zero. Scoped to the table: the "Platform's cut" card above it is drawing one too, for the
    // same reason.
    expect(
      find.descendant(of: find.byType(ConsoleTable), matching: find.text('—')),
      findsOneWidget,
    );
    expect(find.text('CASH'), findsNWidgets(2));
  });

  testWidgets('an empty period reads as an answer, not as a failure',
      (WidgetTester tester) async {
    await pump(
      tester,
      _StubAdapter(<String, dynamic>{
        'kind': 'CARRIER',
        'ref': '33333333-3333-4333-8333-333333333333',
        'name': 'Beirut Wheels',
        'currency': 'USD',
        'lines': <dynamic>[],
        'entries': <dynamic>[],
        'net': <String, dynamic>{'amount': '0.00', 'direction': 'SETTLED'},
      }),
    );

    expect(find.text('Nothing in this period'), findsOneWidget);
    expect(find.textContaining('That is an answer, not a failure'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
  });

  testWidgets('a role with no statement is told so, not shown a stack trace',
      (WidgetTester tester) async {
    await pump(
      tester,
      _StubAdapter(<String, dynamic>{'message': 'forbidden'}, status: 403),
    );

    expect(find.textContaining('This account has no statement of its own'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
  });

  for (final double width in <double>[1400, 1180, 1020]) {
    testWidgets('lays out at a ${width.toInt()}px window', (WidgetTester tester) async {
      await pump(tester, _StubAdapter(_statement()), width: width);
      expect(tester.takeException(), isNull);
      expect(find.text('Delivery fees'), findsOneWidget);
    });
  }
}
