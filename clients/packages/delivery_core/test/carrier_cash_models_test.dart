import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// A delivery company's cash, as the portal parses it and sends it back.
///
/// What is protected is mostly what the client must NOT do with somebody's cash: turn a money
/// string into a double, turn a missing figure into a zero, send back a figure other than the one
/// the person at the counter was shown, or move the day it asks about by converting through UTC.
/// Each of those, done wrong, clears or chases the wrong amount of real notes.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  final List<RequestOptions> calls = <RequestOptions>[];

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

Dio _dio(_Adapter adapter) =>
    Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;

Map<String, dynamic> _overviewJson() => <String, dynamic>{
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
      'riders': <dynamic>[
        <String, dynamic>{
          'riderRef': 'rider-youssef',
          'name': 'Youssef Kanaan',
          'collected': '100.00',
          'collections': 1,
          'earned': '2.25',
          'jobs': 1,
          'holding': '150.00',
          'orders': 2,
          'oldest': '2026-10-21T10:00:00Z',
          'lastHandoverAt': null,
          'standing': 'OVERDUE',
          'overdueHours': 74,
        },
        <String, dynamic>{
          'riderRef': 'rider-rania',
          'name': null,
          'collected': '0.00',
          'collections': 0,
          'earned': '0.00',
          'jobs': 0,
          'holding': '0.00',
          'orders': 0,
          'oldest': null,
          'lastHandoverAt': '2026-10-24T08:00:00Z',
          'standing': 'SETTLED',
          'overdueHours': null,
        },
        <String, dynamic>{
          'riderRef': 'rider-odd',
          'name': '   ',
          // A number, as a server that forgot the contract would send it.
          'collected': 12.5,
          'collections': 1,
          'earned': null,
          'jobs': 0,
          'holding': null,
          'orders': 1,
          'oldest': null,
          'lastHandoverAt': null,
          'standing': 'DISPUTED',
          'overdueHours': null,
        },
      ],
    };

void main() {
  group('the overview', () {
    test('keeps every figure exactly as the server wrote it', () {
      final CarrierCashOverview o = CarrierCashOverview.fromJson(_overviewJson());

      expect(o.day, '2026-10-24');
      expect(o.overdueAfterHours, 48);
      expect(o.totals.withRiders?.amount, '180.00');
      expect(o.totals.handedOver?.amount, '40.00');
      expect(o.totals.held?.amount, '485.50');
      expect(o.totals.overdue?.amount, '50.00');
      expect(o.totals.overdueRiders, 1);

      final RiderCashLine youssef = o.riders.first;
      expect(youssef.name, 'Youssef Kanaan');
      expect(youssef.holding?.amount, '150.00');
      expect(youssef.standing, RiderCashStanding.overdue);
      expect(youssef.overdueHours, 74);
      expect(youssef.oldest, DateTime.parse('2026-10-21T10:00:00Z').toLocal());
      expect(youssef.lastHandoverAt, isNull);
    });

    test('a figure sent as a number, a blank name or a new standing is unknown, not guessed', () {
      final RiderCashLine odd = CarrierCashOverview.fromJson(_overviewJson()).riders[2];

      // A JSON number has been through a double already; its digits are not the ledger's.
      expect(odd.collected, isNull);
      expect(odd.earned, isNull);
      expect(odd.name, isNull);
      expect(odd.standing, RiderCashStanding.unknown);
    });

    test('there is cash to hand over only when the balance is readable and not zero', () {
      final List<RiderCashLine> riders = CarrierCashOverview.fromJson(_overviewJson()).riders;

      expect(riders[0].hasCash, isTrue);
      expect(riders[1].hasCash, isFalse);
      // Unknown is not "nothing", but it is not something to clear either.
      expect(riders[2].hasCash, isFalse);
    });

    test('asks for the calendar day picked, and names no company', () async {
      final _Adapter adapter = _Adapter((_) => _json(_overviewJson()));
      final CarrierCashApi api = CarrierCashApi(_dio(adapter));

      // Late evening: converting through UTC would move this to the 25th east of Greenwich, or
      // the 24th west of it — either way not reliably the day on the chip.
      await api.overview(day: DateTime(2026, 10, 24, 23, 30));
      await api.overview();

      expect(adapter.calls[0].path, '/api/accounting/carrier/cash');
      expect(adapter.calls[0].queryParameters, <String, dynamic>{'day': '2026-10-24'});
      // Today is the server's to decide when no day is given.
      expect(adapter.calls[1].queryParameters, isEmpty);
    });
  });

  group('one rider', () {
    test('a job with no fee on the ledger stays unknown, and the history names the recorder', () {
      final RiderCashSettlement s = RiderCashSettlement.fromJson(<String, dynamic>{
        'riderRef': 'rider-youssef',
        'name': 'Youssef Kanaan',
        'currency': 'USD',
        'overdueAfterHours': 48,
        'holding': '265.00',
        'earnedOnHeld': '4.50',
        'standing': 'HOLDING',
        'overdueHours': null,
        'firstSeenAt': '2026-10-21T09:00:00Z',
        'held': <dynamic>[
          <String, dynamic>{
            'orderId': 'aaaaaaaa-1111-4111-8111-111111111111',
            'amount': '120.00',
            'collectedAt': '2026-10-21T09:00:00Z',
            'earned': null,
            'overdue': true,
          },
        ],
        'handovers': <dynamic>[
          <String, dynamic>{
            'id': 'h-1',
            'riderRef': 'rider-youssef',
            'riderName': 'Youssef Kanaan',
            'amount': '232.00',
            'collections': 4,
            'method': 'BANK_DEPOSIT',
            'note': null,
            'recordedByName': 'Kamal M.',
            'at': '2026-10-23T18:00:00Z',
          },
        ],
      });

      expect(s.hasCash, isTrue);
      expect(s.held.single.earned, isNull);
      expect(s.held.single.overdue, isTrue);
      expect(s.handovers.single.method, CashMethod.bankDeposit);
      expect(s.handovers.single.recordedByName, 'Kamal M.');
      expect(s.handovers.single.amount?.amount, '232.00');
    });

    test('cash a pay run kept from pay is known for what it is, and is not a method anyone records', () {
      expect(CashMethod.fromWire('PAYROLL_DEDUCTION'), CashMethod.payrollDeduction);
      expect(CashMethod.recordable,
          <CashMethod>[CashMethod.cash, CashMethod.bankDeposit, CashMethod.wallet]);
      expect(CashMethod.payrollDeduction.isRecordable, isFalse);
      expect(CashMethod.recordable.every((CashMethod m) => m.isRecordable), isTrue);
    });
  });

  group('recording a hand-over', () {
    test('sends back the figure that was on screen, the method and the key, as given', () async {
      final _Adapter adapter = _Adapter((_) => _json(<String, dynamic>{
            'handoverId': 'h-9',
            'riderRef': 'rider-youssef',
            'amount': '150.00',
            'collections': 2,
            'method': 'CASH',
            'note': 'counted twice',
            'recordedAt': '2026-10-24T11:00:00Z',
            'replayed': false,
          }));
      final CarrierCashApi api = CarrierCashApi(_dio(adapter));

      final HandoverReceipt receipt = await api.recordHandover(
        'rider-youssef',
        expected: const Money('150.00'),
        requestKey: 'abcdef0123456789',
        method: CashMethod.wallet,
        note: '  counted twice ',
      );

      final RequestOptions call = adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, '/api/accounting/carrier/cash/riders/rider-youssef/handovers');
      expect(call.data, <String, dynamic>{
        // The server's own string, never a number.
        'expectedAmount': '150.00',
        'method': 'WALLET',
        'note': 'counted twice',
        'requestKey': 'abcdef0123456789',
      });
      expect(receipt.amount?.amount, '150.00');
      expect(receipt.collections, 2);
      expect(receipt.replayed, isFalse);
    });

    test('a moved balance comes back as the current figure, not a bare failure', () async {
      final _Adapter adapter = _Adapter((_) => _json(<String, dynamic>{
            'error': 'This rider is holding 515.00 for your company now.',
            'code': 'AMOUNT_CHANGED',
            'current': '515.00',
          }, status: 409));
      final CarrierCashApi api = CarrierCashApi(_dio(adapter));

      await expectLater(
        api.recordHandover('rider-youssef',
            expected: const Money('485.00'), requestKey: 'abcdef0123456789'),
        throwsA(isA<CashAmountChanged>()
            .having((CashAmountChanged e) => e.current?.amount, 'current', '515.00')),
      );
    });

    test('any other refusal is left as the transport error it was', () async {
      final _Adapter adapter = _Adapter((_) => _json(<String, dynamic>{
            'error': 'That request key has already been used for something else',
            'code': 'REQUEST_KEY_REUSED',
          }, status: 409));
      final CarrierCashApi api = CarrierCashApi(_dio(adapter));

      await expectLater(
        api.recordHandover('rider-youssef',
            expected: const Money('485.00'), requestKey: 'abcdef0123456789'),
        throwsA(isA<DioException>()),
      );
    });

    test('a request key is fresh every time and in the shape the server accepts', () {
      final String a = CarrierCashApi.newRequestKey();
      final String b = CarrierCashApi.newRequestKey();

      expect(a, matches(RegExp(r'^[0-9a-f]{32}$')));
      // The server's own rule for a key.
      expect(a, matches(RegExp(r'^[A-Za-z0-9_-]{8,64}$')));
      expect(a, isNot(b));
    });
  });

  group('the Back Office', () {
    test('a remittance with nothing confirmed banks everything, exactly as it always did', () async {
      final _Adapter adapter = _Adapter((_) => _json(<String, dynamic>{
            'holderRef': 'rider-1',
            'amount': 0,
            'collections': 0,
          }));
      final AccountingApi api = AccountingApi(_dio(adapter));

      await api.remit('rider-1');

      expect(adapter.calls.single.path, '/api/accounting/float/rider-1/remit');
      expect(adapter.calls.single.data, isNull);
    });

    test('a company payment is recorded against the counted figure, with a key', () async {
      final _Adapter adapter = _Adapter((_) => _json(<String, dynamic>{
            'remittanceId': 'r-1',
            'holderRef': 'provider-77',
            'amount': 485.5,
            'collections': 3,
            'replayed': false,
          }));
      final AccountingApi api = AccountingApi(_dio(adapter));

      await api.remit('provider-77',
          expected: const Money('485.50'),
          method: CashMethod.bankDeposit,
          requestKey: 'abcdef0123456789');

      expect(adapter.calls.single.data, <String, dynamic>{
        'expectedAmount': '485.50',
        'method': 'BANK_DEPOSIT',
        'requestKey': 'abcdef0123456789',
      });
    });

    test('a company payment refused because the balance moved says what it is now', () async {
      final _Adapter adapter = _Adapter((_) => _json(<String, dynamic>{
            'error': 'They are holding 525.00 now.',
            'code': 'AMOUNT_CHANGED',
            'current': '525.00',
          }, status: 409));
      final AccountingApi api = AccountingApi(_dio(adapter));

      await expectLater(
        api.remit('provider-77', expected: const Money('485.50')),
        throwsA(isA<CashAmountChanged>()
            .having((CashAmountChanged e) => e.current?.amount, 'current', '525.00')),
      );
    });

    test('lists what each company holds beside what its riders hold, never summed', () async {
      final _Adapter adapter = _Adapter((_) => _json(<String, dynamic>{
            'overdueAfterHours': 48,
            'carriers': <dynamic>[
              <String, dynamic>{
                'carrierRef': 'provider-77',
                'held': '485.50',
                'orders': 3,
                'oldest': '2026-10-20T09:00:00Z',
                'overdue': true,
                'withRiders': '180.00',
                'ridersHolding': 2,
                'ridersOldest': '2026-10-21T10:00:00Z',
                'lastPaidAt': null,
              },
              <String, dynamic>{
                'carrierRef': 'provider-quiet',
                'held': '0.00',
                'orders': 0,
                'oldest': null,
                'overdue': false,
                'withRiders': '12.00',
                'ridersHolding': 1,
                'ridersOldest': '2026-10-24T10:00:00Z',
                'lastPaidAt': '2026-10-19T10:00:00Z',
              },
            ],
          }));
      final AccountingApi api = AccountingApi(_dio(adapter));

      final List<CarrierCashHolding> carriers = await api.carriersFloat();

      expect(adapter.calls.single.path, '/api/accounting/float/carriers');
      expect(carriers.first.held?.amount, '485.50');
      expect(carriers.first.withRiders?.amount, '180.00');
      expect(carriers.first.overdue, isTrue);
      expect(carriers.first.holdsCash, isTrue);
      expect(carriers.first.lastPaidAt, isNull);
      expect(carriers.last.holdsCash, isFalse);
    });

    test('a holder the server did not flag leaves the overdue call to the screen', () {
      final CashHolder old = CashHolder.fromJson(<String, dynamic>{
        'holderRef': 'rider-1',
        'holderKind': 'RIDER',
        'amount': 13.25,
        'orders': 1,
        'oldest': '2026-10-20T09:00:00Z',
      });
      final CashHolder company = CashHolder.fromJson(<String, dynamic>{
        'holderRef': 'provider-77',
        'holderKind': 'PROVIDER',
        'amount': 485.5,
        'orders': 3,
        'oldest': '2026-10-20T09:00:00Z',
        'overdue': false,
      });

      expect(old.overdue, isNull);
      expect(old.isCarrier, isFalse);
      expect(company.overdue, isFalse);
      expect(company.isCarrier, isTrue);
    });
  });
}
