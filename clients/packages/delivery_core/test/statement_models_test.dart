import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counterparty statements as the three apps parse them.
///
/// What is protected here is mostly what the client must NOT do. It must not turn a money string
/// into a double, must not turn a missing figure into a zero, must not read a direction it does not
/// recognise as a credit, and must not treat "no activity" as a failure. Each of those, done wrong,
/// prints a wrong number beside a currency symbol on a screen somebody is paid from.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body);

  final String body;
  final List<RequestOptions> calls = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add(options);
    return ResponseBody.fromString(body, 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// The contract's own example, with the real figures read off the production ledger.
Map<String, dynamic> _statementJson() => <String, dynamic>{
      'kind': 'MERCHANT',
      'ref': '8f1d0c9a-1111-4222-8333-444455556666',
      'name': 'Rose & Crust Pizzeria',
      'from': '2026-08-01',
      'to': '2026-08-29',
      'currency': 'USD',
      'generatedAt': '2026-08-29T05:00:00Z',
      'lines': <dynamic>[
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
      'entries': <dynamic>[
        <String, dynamic>{
          'orderId': 'a1b2c3d4-0000-4000-8000-000000000001',
          'at': '2026-08-23T11:09:40Z',
          'gross': '19.50',
          'commission': '2.44',
          'net': '17.06',
          'paymentMethod': 'CASH',
        },
      ],
      'note': 'Every order in this range was collected in cash at the door.',
    };

Map<String, dynamic> _listingJson() => <String, dynamic>{
      'from': '2026-08-01',
      'to': '2026-08-29',
      'currency': 'USD',
      'counterparties': <dynamic>[
        <String, dynamic>{
          'kind': 'MERCHANT',
          'ref': '8f1d0c9a-1111-4222-8333-444455556666',
          'name': 'Rose & Crust Pizzeria',
          'net': '2121.80',
          'direction': 'WE_OWE',
          'orders': 7,
          'recipient': 'shop@example.com',
          'lastSentAt': '2026-08-20T09:00:00Z',
        },
        <String, dynamic>{
          'kind': 'RIDER',
          'ref': 'rider-9',
          'name': 'Sami H.',
          'net': '0.00',
          'direction': 'SETTLED',
          'orders': 12,
          'recipient': null,
          'lastSentAt': null,
        },
      ],
      'unattributed': <String, dynamic>{
        'amount': '0.00',
        'orders': 0,
        'note': 'Credits the ledger could not attribute to an onboarded counterparty.',
      },
    };

void main() {
  group('the contract shape', () {
    test('a merchant statement parses whole, with the ledger figures untouched', () {
      final Statement statement = Statement.fromJson(_statementJson());

      expect(statement.kind, CounterpartyKind.merchant);
      expect(statement.kindWire, 'MERCHANT');
      expect(statement.ref, '8f1d0c9a-1111-4222-8333-444455556666');
      expect(statement.name, 'Rose & Crust Pizzeria');
      expect(statement.currency, 'USD');
      expect(statement.isEmpty, isFalse);

      // Calendar dates stay the days they were written as, wherever the test runs.
      expect(statement.from!.year, 2026);
      expect(statement.from!.month, 8);
      expect(statement.from!.day, 1);
      expect(statement.to!.day, 29);

      expect(statement.lines, hasLength(2));
      expect(statement.lines.first.label, 'Goods sold');
      expect(statement.lines.first.note, '45 orders');
      expect(statement.lines.last.note, isNull);

      expect(statement.entries, hasLength(1));
      final StatementEntry entry = statement.entries.single;
      expect(entry.orderId, 'a1b2c3d4-0000-4000-8000-000000000001');
      expect(entry.paymentMethod, 'CASH');
      expect(entry.at!.toUtc().hour, 11);

      expect(statement.net.direction, NetDirection.weOwe);
      expect(statement.note, isNotNull);
    });

    test('the Backoffice listing parses, unattributed block included', () {
      final CounterpartyListing listing = CounterpartyListing.fromJson(_listingJson());

      expect(listing.currency, 'USD');
      expect(listing.counterparties, hasLength(2));
      expect(listing.isEmpty, isFalse);
      expect(listing.counterparties.first.kind, CounterpartyKind.merchant);
      expect(listing.counterparties.first.orders, 7);
      expect(listing.counterparties.last.kind, CounterpartyKind.rider);

      expect(listing.unattributed, isNotNull);
      expect(listing.unattributed!.amount!.amount, '0.00');
      expect(listing.unattributed!.orders, 0);
      expect(listing.unattributed!.isClean, isTrue);
    });

    test('a dispatch receipt carries the handle to quote when nothing arrived', () {
      final StatementDispatch dispatch = StatementDispatch.fromJson(<String, dynamic>{
        'sentTo': 'shop@example.com',
        'sentAt': '2026-08-29T05:01:00Z',
        'dispatchId': '11112222-3333-4444-5555-666677778888',
      });

      expect(dispatch.sentTo, 'shop@example.com');
      expect(dispatch.dispatchId, '11112222-3333-4444-5555-666677778888');
      expect(dispatch.sentAt, isNotNull);
    });
  });

  group('money is a string and stays one', () {
    test('the ledger figures survive character for character', () {
      final Statement statement = Statement.fromJson(_statementJson());

      expect(statement.lines.first.amount!.amount, '2425.00');
      expect(statement.lines.last.amount!.amount, '303.20');
      expect(statement.net.amount!.amount, '2121.80');
      expect(statement.entries.single.gross!.amount, '19.50');
      expect(statement.entries.single.commission!.amount, '2.44');
      expect(statement.entries.single.net!.amount, '17.06');
    });

    // The whole reason for the string. Ten cents is not representable as a double, so a client that
    // parsed it would already be wrong before anyone added anything to it.
    test('a tenth of a unit keeps its digits and compares exactly in minor units', () {
      const Money dime = Money('0.10');
      expect(dime.amount, '0.10');
      expect(dime.minorUnits, 10);
      expect(dime.isZero, isFalse);

      // Three of them, counted the way a screen is allowed to count: in integer cents.
      expect(dime.minorUnits! * 3, 30);
    });

    test('minor units are exact across the sizes a real statement holds', () {
      expect(const Money('2425.00').minorUnits, 242500);
      expect(const Money('303.20').minorUnits, 30320);
      expect(const Money('2121.80').minorUnits, 212180);
      expect(const Money('-19.50').minorUnits, -1950);
      expect(const Money('0.00').minorUnits, 0);
      expect(const Money('7').minorUnits, 700);
      expect(const Money('7.5').minorUnits, 750);
    });

    test('a figure this client cannot read is neither zero nor a guess', () {
      // Three decimals is refused rather than rounded: rounding somebody's pay silently is the
      // failure this type exists to prevent.
      const Money odd = Money('1.005');
      expect(odd.minorUnits, isNull);
      expect(odd.isReadable, isFalse);
      expect(odd.isZero, isFalse);
      expect(odd.isNegative, isFalse);
      // Still shown exactly as it arrived.
      expect(odd.amount, '1.005');

      expect(const Money('twelve').minorUnits, isNull);
      expect(const Money('1,200.00').minorUnits, isNull);
    });

    test('a JSON number is refused, not stringified', () {
      // By the time a number reaches this parser it has been through a double, so its digits are no
      // longer the ledger's. Refusing it makes that visible instead of printing it.
      expect(Money.parse(19.5), isNull);
      expect(Money.parse(2121.80), isNull);
      expect(Money.parse(null), isNull);
      expect(Money.parse(''), isNull);
      expect(Money.parse('  2121.80  ')!.amount, '2121.80');
    });

    test('signs are composed, never concatenated', () {
      final Statement statement = Statement.fromJson(_statementJson());

      expect(statement.lines.first.signedAmount, '+2425.00');
      expect(statement.lines.last.signedAmount, '-303.20');
      // WE_OWE reads as money towards the counterparty on their own statement.
      expect(statement.net.signedAmount, '+2121.80');

      // A credit the server itself wrote negative must not render as "+-5.00".
      expect(const Money('-5.00').signedFor(LedgerDirection.credit), '-5.00');
      // And a negative debit is money coming back.
      expect(const Money('-5.00').signedFor(LedgerDirection.debit), '+5.00');
      // An unreadable direction gets no sign invented for it.
      expect(const Money('5.00').signedFor(LedgerDirection.unknown), '5.00');
    });

    // A line dropped on the way in still leaves a net below it, and the two then disagree. Rows
    // are kept whatever map type the decoder handed back.
    test('no line is silently dropped for arriving untyped', () {
      final Statement statement = Statement.fromJson(<String, dynamic>{
        'kind': 'MERCHANT',
        'ref': 'm-1',
        'name': 'Rose & Crust Pizzeria',
        'currency': 'USD',
        'lines': <dynamic>[
          <dynamic, dynamic>{'label': 'Goods sold', 'amount': '2425.00', 'direction': 'CREDIT'},
        ],
        'entries': <dynamic>[
          <dynamic, dynamic>{'orderId': 'o-1', 'gross': '19.50'},
        ],
        'net': <dynamic, dynamic>{'amount': '2121.80', 'direction': 'WE_OWE'},
      });

      expect(statement.lines, hasLength(1));
      expect(statement.lines.single.amount!.amount, '2425.00');
      expect(statement.entries.single.gross!.amount, '19.50');
      expect(statement.net.amount!.amount, '2121.80');
    });

    test('a missing figure is null, never a confident zero', () {
      final StatementLine line = StatementLine.fromJson(<String, dynamic>{
        'label': 'Goods sold',
        'direction': 'CREDIT',
      });

      expect(line.amount, isNull);
      expect(line.signedAmount, isNull);
      expect(line.label, 'Goods sold');

      final StatementNet net = StatementNet.fromJson(<String, dynamic>{'direction': 'WE_OWE'});
      expect(net.amount, isNull);
      expect(net.isSettled, isFalse);

      final UnattributedTotal unattributed =
          UnattributedTotal.fromJson(<String, dynamic>{'orders': 3});
      expect(unattributed.amount, isNull);
      // Three orders and no total is not a clean bill of health.
      expect(unattributed.isClean, isFalse);
    });
  });

  group('unknown values degrade', () {
    test('an unknown line direction is unknown, never a credit', () {
      final StatementLine line = StatementLine.fromJson(<String, dynamic>{
        'label': 'Withholding tax',
        'amount': '12.00',
        'direction': 'WITHHELD',
      });

      expect(line.direction, LedgerDirection.unknown);
      // No sign guessed: a deduction shown as money coming in is a figure somebody budgets against.
      expect(line.signedAmount, '12.00');
    });

    test('an unknown net direction never reads as settled', () {
      final StatementNet net =
          StatementNet.fromJson(<String, dynamic>{'amount': '2121.80', 'direction': 'IN_DISPUTE'});

      expect(net.direction, NetDirection.unknown);
      expect(net.direction.isSettled, isFalse);
      expect(net.isSettled, isFalse);
      expect(net.signedAmount, '2121.80');
    });

    test('SETTLED only counts as settled with a readable zero behind it', () {
      final StatementNet zero =
          StatementNet.fromJson(<String, dynamic>{'amount': '0.00', 'direction': 'SETTLED'});
      expect(zero.isSettled, isTrue);

      final StatementNet contradictory =
          StatementNet.fromJson(<String, dynamic>{'amount': '40.00', 'direction': 'SETTLED'});
      expect(contradictory.isSettled, isFalse);
    });

    test('an unknown kind keeps the server string instead of posing as a merchant', () {
      final Statement statement = Statement.fromJson(<String, dynamic>{
        ..._statementJson(),
        'kind': 'FRANCHISEE',
      });

      expect(statement.kind, isNull);
      expect(statement.kindWire, 'FRANCHISEE');
      expect(CounterpartyKind.fromWire('FRANCHISEE'), isNull);
      expect(CounterpartyKind.fromWire(null), isNull);
      // Still openable: the api takes the wire string precisely so this row is not unreachable.
      expect(statement.ref, isNotEmpty);
    });

    test('a listing row with an unknown kind still lists', () {
      final Map<String, dynamic> json = _listingJson();
      (json['counterparties'] as List<dynamic>).add(<String, dynamic>{
        'kind': 'FRANCHISEE',
        'ref': 'f-1',
        'name': 'Someone new',
        'net': '10.00',
        'direction': 'WE_OWE',
        'orders': 1,
      });

      final CounterpartyListing listing = CounterpartyListing.fromJson(json);
      expect(listing.counterparties, hasLength(3));
      expect(listing.counterparties.last.kind, isNull);
      expect(listing.counterparties.last.kindWire, 'FRANCHISEE');
      expect(listing.counterparties.last.signedNet, '+10.00');
    });

    test('a counterparty reads the platform-voice direction as their own', () {
      expect(NetDirection.weOwe.label, 'We owe them');
      expect(NetDirection.weOwe.selfLabel, 'Owed to you');
      expect(NetDirection.theyOwe.selfLabel, 'You owe');
      expect(NetDirection.theyOwe.asLineDirection, LedgerDirection.debit);
      expect(NetDirection.unknown.asLineDirection, LedgerDirection.unknown);
    });
  });

  group('nulls the contract allows', () {
    test('a never-sent counterparty with no address is ordinary, not broken', () {
      final CounterpartySummary rider =
          CounterpartyListing.fromJson(_listingJson()).counterparties.last;

      expect(rider.recipient, isNull);
      expect(rider.lastSentAt, isNull);
      expect(rider.needsRecipient, isTrue);
      expect(rider.everSent, isFalse);
      expect(rider.direction, NetDirection.settled);
      expect(rider.net!.amount, '0.00');
    });

    test('a resolved recipient and a previous send are read as such', () {
      final CounterpartySummary shop =
          CounterpartyListing.fromJson(_listingJson()).counterparties.first;

      expect(shop.recipient, 'shop@example.com');
      expect(shop.needsRecipient, isFalse);
      expect(shop.everSent, isTrue);
      expect(shop.lastSentAt!.toUtc().year, 2026);
    });

    test('an empty recipient string is treated as no address', () {
      final CounterpartySummary row = CounterpartySummary.fromJson(<String, dynamic>{
        'kind': 'MERCHANT',
        'ref': 'm-1',
        'name': 'Nameless',
        'net': '5.00',
        'direction': 'WE_OWE',
        'orders': 1,
        'recipient': '',
      });

      expect(row.needsRecipient, isTrue);
    });

    test('a listing with no unattributed block is null, not a clean zero', () {
      final Map<String, dynamic> json = _listingJson()..remove('unattributed');
      final CounterpartyListing listing = CounterpartyListing.fromJson(json);

      // An empty total would claim everything was attributed — the exact claim that hid the
      // omnibus bucket in the first place.
      expect(listing.unattributed, isNull);
    });

    test('a statement with no net block is unknown, not zero and not settled', () {
      final Map<String, dynamic> json = _statementJson()..remove('net');
      final Statement statement = Statement.fromJson(json);

      expect(statement.net.direction, NetDirection.unknown);
      expect(statement.net.amount, isNull);
      expect(statement.net.isSettled, isFalse);
    });
  });

  group('an empty statement', () {
    test('no activity in the range is not an error', () {
      final Statement statement = Statement.fromJson(<String, dynamic>{
        'kind': 'MERCHANT',
        'ref': 'm-quiet',
        'name': 'Quiet Corner Bakery',
        'from': '2026-08-01',
        'to': '2026-08-07',
        'currency': 'USD',
        'generatedAt': '2026-08-29T05:00:00Z',
        'lines': <dynamic>[],
        'entries': <dynamic>[],
        'net': <String, dynamic>{'amount': '0.00', 'direction': 'SETTLED'},
        'note': 'No orders in this range.',
      });

      expect(statement.isEmpty, isTrue);
      expect(statement.lines, isEmpty);
      expect(statement.entries, isEmpty);
      expect(statement.net.isSettled, isTrue);
      expect(statement.note, 'No orders in this range.');
    });

    test('missing lists are empty lists, and an empty listing is not an error', () {
      final Statement statement = Statement.fromJson(<String, dynamic>{
        'kind': 'RIDER',
        'ref': 'r-1',
        'name': 'Sami H.',
        'currency': 'USD',
      });

      expect(statement.isEmpty, isTrue);
      expect(statement.from, isNull);
      expect(statement.to, isNull);
      expect(statement.generatedAt, isNull);

      final CounterpartyListing listing = CounterpartyListing.fromJson(<String, dynamic>{
        'from': '2026-08-01',
        'to': '2026-08-29',
        'currency': 'USD',
        'counterparties': <dynamic>[],
        'unattributed': <String, dynamic>{'amount': '0.00', 'orders': 0, 'note': null},
      });

      expect(listing.isEmpty, isTrue);
      expect(listing.unattributed!.isClean, isTrue);
    });
  });

  group('StatementsApi', () {
    Dio dioWith(_FakeAdapter adapter) =>
        Dio(BaseOptions(baseUrl: 'https://gw.test'))..httpClientAdapter = adapter;

    test('the backoffice listing asks for the range as inclusive calendar dates', () async {
      final _FakeAdapter adapter = _FakeAdapter('{"from":"2026-08-01","to":"2026-08-29",'
          '"currency":"USD","counterparties":[],"unattributed":{"amount":"0.00","orders":0}}');
      final CounterpartyListing listing = await StatementsApi(dioWith(adapter))
          .counterparties(from: DateTime(2026, 8, 1), to: DateTime(2026, 8, 29));

      expect(adapter.calls.single.path, '/api/accounting/statements/counterparties');
      // Not shifted to UTC: east of Greenwich that would send July 31st.
      expect(adapter.calls.single.queryParameters['from'], '2026-08-01');
      expect(adapter.calls.single.queryParameters['to'], '2026-08-29');
      expect(listing.isEmpty, isTrue);
    });

    test('a statement is addressed by kind and ref, both encoded', () async {
      final _FakeAdapter adapter = _FakeAdapter(
          '{"kind":"MERCHANT","ref":"m 1","name":"Rose & Crust Pizzeria","currency":"USD",'
          '"lines":[],"entries":[],"net":{"amount":"0.00","direction":"SETTLED"}}');
      final Statement statement = await StatementsApi(dioWith(adapter)).statement(
        kind: CounterpartyKind.merchant.wire,
        ref: 'm 1',
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 8, 29),
      );

      expect(adapter.calls.single.path, '/api/accounting/statements/MERCHANT/m%201');
      expect(statement.name, 'Rose & Crust Pizzeria');
    });

    test('send carries the override address in the body, and the range in the query', () async {
      final _FakeAdapter adapter = _FakeAdapter('{"sentTo":"override@example.com",'
          '"sentAt":"2026-08-29T05:01:00Z","dispatchId":"d-1"}');
      final StatementDispatch dispatch =
          await StatementsApi(dioWith(adapter)).sendStatement(
        kind: 'MERCHANT',
        ref: 'm-1',
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 8, 29),
        recipient: 'override@example.com',
      );

      final RequestOptions call = adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, '/api/accounting/statements/MERCHANT/m-1/send');
      expect(call.queryParameters['to'], '2026-08-29');
      // The body's `to` is the address; the range never travels in it.
      expect((call.data as Map<String, dynamic>)['to'], 'override@example.com');
      expect(dispatch.sentTo, 'override@example.com');
    });

    test('send with no override sends an empty body, meaning "use whoever you resolved"', () async {
      final _FakeAdapter adapter =
          _FakeAdapter('{"sentTo":"shop@example.com","sentAt":null,"dispatchId":"d-2"}');
      await StatementsApi(dioWith(adapter)).sendStatement(
        kind: 'MERCHANT',
        ref: 'm-1',
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 8, 29),
      );

      expect(adapter.calls.single.data, isEmpty);
    });

    // The self-serve route names nobody. If a ref could reach it, a merchant could read a rival's
    // statement — so there is no parameter on the method to pass one.
    test('mine names no counterparty anywhere in the request', () async {
      final _FakeAdapter adapter = _FakeAdapter(
          '{"kind":"MERCHANT","ref":"m-1","name":"Rose & Crust Pizzeria","currency":"USD",'
          '"lines":[],"entries":[],"net":{"amount":"0.00","direction":"SETTLED"}}');
      await StatementsApi(dioWith(adapter))
          .mine(from: DateTime(2026, 8, 1), to: DateTime(2026, 8, 29));

      final RequestOptions call = adapter.calls.single;
      expect(call.path, '/api/accounting/statements/mine');
      expect(call.queryParameters.keys, <String>['from', 'to']);
      expect(call.data, isNull);
    });

    test('an inverted range is refused here rather than sent to be refused there', () async {
      final _FakeAdapter adapter = _FakeAdapter('{}');
      final StatementsApi api = StatementsApi(dioWith(adapter));

      expect(
        () => api.counterparties(from: DateTime(2026, 8, 29), to: DateTime(2026, 8, 1)),
        throwsArgumentError,
      );
      expect(
        () => api.mine(from: DateTime(2026, 8, 29), to: DateTime(2026, 8, 1)),
        throwsArgumentError,
      );
      expect(adapter.calls, isEmpty);
    });

    test('a range longer than the server allows is refused', () async {
      final _FakeAdapter adapter = _FakeAdapter('{}');
      final StatementsApi api = StatementsApi(dioWith(adapter));

      // 367 days inclusive.
      expect(
        () => api.counterparties(from: DateTime(2026, 1, 1), to: DateTime(2027, 1, 2)),
        throwsArgumentError,
      );
      expect(adapter.calls, isEmpty);
    });

    test('the longest allowed range and a single day both go through', () async {
      final _FakeAdapter adapter = _FakeAdapter('{"from":"2026-01-01","to":"2027-01-01",'
          '"currency":"USD","counterparties":[]}');
      final StatementsApi api = StatementsApi(dioWith(adapter));

      // 366 days inclusive — the boundary the server accepts.
      await api.counterparties(from: DateTime(2026, 1, 1), to: DateTime(2027, 1, 1));
      await api.counterparties(from: DateTime(2026, 8, 5), to: DateTime(2026, 8, 5));

      expect(adapter.calls, hasLength(2));
      expect(adapter.calls.last.queryParameters['from'], '2026-08-05');
      expect(adapter.calls.last.queryParameters['to'], '2026-08-05');
    });
  });
}
