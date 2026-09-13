import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// A delivery company's payroll, as the portal parses it and sends it back.
///
/// What is protected is what a client must NOT do with somebody's pay: turn a money string into a
/// double, turn a missing figure into a zero, guess an unknown status into a known one, send back a
/// total other than the one on screen, or move a pay period's first day by converting through UTC.
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

Map<String, dynamic> runJson({String status = 'DRAFT', int revision = 3}) => <String, dynamic>{
      'id': 'run-1',
      'from': '2026-10-01',
      'to': '2026-10-15',
      'status': status,
      'revision': revision,
      'currency': 'USD',
      'computedAt': '2026-10-20T09:00:00Z',
      'approvedAt': null,
      'approvedByName': null,
      'paidAt': null,
      'attendance': 'INCLUDED',
      'attendanceReason': null,
      'attendanceAt': '2026-10-20T09:00:00Z',
      'deliveries': 'ORDERS',
      'deliveriesReason': null,
      'deliveriesAt': '2026-10-20T09:00:00Z',
      'readBeforePeriodEnd': false,
      'hoursMissingFor': <dynamic>[
        <String, dynamic>{'riderRef': 'rider-rania', 'name': null, 'reason': 'NOT_LISTED'},
      ],
      'periodOver': true,
      'jobsSinceComputed': 2,
      'needsAcknowledgement': false,
      'periodChanged': false,
      'policy': <String, dynamic>{
        'id': 'policy-1',
        'effectiveFrom': '2026-09-01',
        'payCycle': 'SEMI_MONTHLY',
        'currency': 'USD',
        'perDeliveryRate': '2.35',
        'hourlyRate': null,
        'payManualHours': true,
        'overtimeMultiplier': '1.00',
        'lateDeduction': '0.00',
        'absenceDeduction': '0.00',
        'needsAttendance': false,
        'createdByName': 'Kamal M.',
        'createdAt': '2026-08-30T10:00:00Z',
      },
      'totals': <String, dynamic>{
        'riders': 1,
        'payable': '36.95',
        'average': '36.95',
        'gross': '96.95',
        'bonuses': '25.00',
        'deductions': '60.00',
        'owedByRiders': '0.00',
        'tips': '15.00',
        'cashNetted': '60.00',
        'paid': '0.00',
        'outstanding': '0.00',
        'due': 0,
        'failed': 0,
        'paidCount': 0,
      },
      'payslips': <dynamic>[
        <String, dynamic>{
          'id': 'slip-1',
          'riderRef': 'rider-youssef',
          'name': 'Youssef Kanaan',
          'status': 'DRAFT',
          'deliveries': 17,
          'workedSeconds': 28800,
          'manualSeconds': 0,
          'overtimeSeconds': 0,
          'lates': 0,
          'absences': 0,
          'hoursUnknown': false,
          'hoursReason': null,
          'basePay': '32.00',
          'deliveryPay': '39.95',
          'bonuses': '25.00',
          'deductions': '60.00',
          'gross': '96.95',
          'net': '36.95',
          'tips': '15.00',
          'cashHeld': '60.00',
          'cashNetted': '60.00',
          'paidMethod': null,
          'lines': <dynamic>[
            <String, dynamic>{
              'id': 'line-1',
              'kind': 'DELIVERIES',
              'source': 'COMPUTED',
              'label': null,
              'quantity': '17',
              'rate': '2.35',
              'amount': '39.95',
              'createdByName': null,
            },
            <String, dynamic>{
              'id': 'line-2',
              'kind': 'BONUS',
              'source': 'MANUAL',
              'label': 'Eid bonus',
              'quantity': null,
              'rate': null,
              'amount': '25.00',
              'createdByName': 'Kamal M.',
            },
          ],
        },
      ],
      'corrections': <dynamic>[],
      'history': <dynamic>[
        <String, dynamic>{
          'action': 'RUN_STARTED',
          'riderRef': null,
          'riderName': null,
          'actorName': 'Kamal M.',
          'detail': 'revision 1',
          'at': '2026-10-20T09:00:00Z',
        },
      ],
    };

void main() {
  group('parsing', () {
    test('a run keeps the server\'s own figures, and a figure it did not send stays unknown', () {
      final Map<String, dynamic> json = runJson();
      (json['payslips'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .first
        ..remove('tips')
        ..['net'] = 36.95;
      final PayRun run = PayRun.fromJson(json);

      expect(run.from, DateTime(2026, 10, 1));
      expect(run.to, DateTime(2026, 10, 15));
      expect(run.revision, 3);
      expect(run.attendance, PayrollAttendance.included);
      expect(run.jobsSinceComputed, 2);
      expect(run.deliveries, PayrollDeliveries.orders);
      expect(run.deliveriesAt, DateTime.parse('2026-10-20T09:00:00Z').toLocal());
      expect(run.readBeforePeriodEnd, isFalse);
      // A rider whose hours are missing is kept by reference, and a name nobody knows stays unknown.
      expect(run.hoursMissingFor.single.riderRef, 'rider-rania');
      expect(run.hoursMissingFor.single.name, isNull);
      expect(run.hoursMissingFor.single.reason, 'NOT_LISTED');
      expect(run.totals.payable?.amount, '36.95');
      expect(run.policy?.perDeliveryRate?.amount, '2.35');
      expect(run.policy?.hourlyRate, isNull);

      final Payslip slip = run.payslips.single;
      expect(slip.deliveryPay?.amount, '39.95');
      expect(slip.workedSeconds, 28800);
      // Not sent, and sent as a JSON number: both unknown, never a zero or a double's digits.
      expect(slip.tips, isNull);
      expect(slip.net, isNull);
      expect(slip.lines.map((PayLine l) => l.kind), <PayLineKind>[PayLineKind.deliveries, PayLineKind.bonus]);
      expect(slip.lines.first.quantity, '17');
      expect(slip.lines.first.removable, isFalse);
      expect(slip.lines.last.removable, isTrue);
      expect(run.history.single.action, PayrollAction.runStarted);
    });

    test('unknown statuses and kinds are unknown, never guessed into known ones', () {
      final Map<String, dynamic> json = runJson(status: 'ARCHIVED');
      json['deliveries'] = 'GUESSED';
      final Map<String, dynamic> slip =
          (json['payslips'] as List<dynamic>).cast<Map<String, dynamic>>().first;
      slip['status'] = 'REVERSED';
      (slip['lines'] as List<dynamic>).cast<Map<String, dynamic>>().first['kind'] = 'SPEED_BONUS';

      final PayRun run = PayRun.fromJson(json);

      expect(run.status, PayRunStatus.unknown);
      expect(run.deliveries, PayrollDeliveries.unknown);
      expect(run.isDraft, isFalse);
      expect(run.payslips.single.status, PayslipStatus.unknown);
      expect(run.payslips.single.outstanding, isFalse);
      expect(run.payslips.single.lines.first.kind, PayLineKind.unknown);
      expect(PayLineKind.unknown.isDeduction, isFalse);
    });

    test('cash the pay could not cover, and a net below zero, are said as such', () {
      final Map<String, dynamic> json = runJson();
      final Map<String, dynamic> slip =
          (json['payslips'] as List<dynamic>).cast<Map<String, dynamic>>().first;
      slip['cashHeld'] = '80.00';
      slip['cashNetted'] = '0.00';
      slip['net'] = '-8.00';

      final Payslip parsed = PayRun.fromJson(json).payslips.single;

      expect(parsed.cashNotNetted, isTrue);
      expect(parsed.owesCompany, isTrue);
    });

    test('the period list and the rules page keep calendar days as written', () {
      final PayPeriodsPage periods = PayPeriodsPage.fromJson(<String, dynamic>{
        'zone': 'Asia/Beirut',
        'currency': 'USD',
        'today': '2026-10-20',
        'hasPolicy': true,
        'periods': <dynamic>[
          <String, dynamic>{
            'from': '2026-10-16',
            'to': '2026-10-31',
            'over': false,
            'aligned': true,
            'runId': null,
            'status': null,
            'revision': null,
            'riders': 0,
            'payable': null,
          },
          <String, dynamic>{'from': 'not a day', 'to': '2026-10-15'},
        ],
      });
      expect(periods.periods.single.from, DateTime(2026, 10, 16));
      expect(periods.periods.single.hasRun, isFalse);
      expect(periods.periods.single.payable, isNull);

      final PayPolicyPage page = PayPolicyPage.fromJson(<String, dynamic>{
        'zone': 'Asia/Beirut',
        'currency': 'USD',
        'today': '2026-10-20',
        'current': null,
        'scheduled': <dynamic>[],
        'history': <dynamic>[],
        'defaults': <String, dynamic>{
          'payCycle': 'SEMI_MONTHLY',
          'perDeliveryRate': null,
          'payManualHours': true,
          'overtimeMultiplier': '1.00',
          'lateDeduction': '0.00',
          'absenceDeduction': '0.00',
        },
        'startOptions': <String, dynamic>{
          'SEMI_MONTHLY': <dynamic>['2026-10-16', '2026-11-01'],
          'MONTHLY': <dynamic>['2026-11-01'],
          'WEEKLY': <dynamic>['2026-10-19'],
        },
      });
      expect(page.current, isNull);
      expect(page.defaults.payManualHours, isTrue);
      expect(page.defaults.overtimeMultiplier, '1.00');
      expect(page.startOptions.keys, unorderedEquals(<PayCycle>[PayCycle.semiMonthly, PayCycle.monthly]));
      expect(page.startOptions[PayCycle.semiMonthly], <DateTime>[DateTime(2026, 10, 16), DateTime(2026, 11, 1)]);
    });
  });

  group('the client', () {
    test('reads name no company, and starting a run sends the calendar day it was given', () async {
      final _Adapter adapter = _Adapter((RequestOptions o) =>
          o.path.endsWith('/periods') ? _json(<String, dynamic>{'hasPolicy': false, 'periods': <dynamic>[]}) : _json(runJson(), status: 201));
      final CarrierPayrollApi api = CarrierPayrollApi(_dio(adapter));

      await api.periods();
      await api.start(DateTime(2026, 10, 1, 23, 30));

      expect(adapter.calls[0].path, '/api/accounting/carrier/payroll/periods');
      expect(adapter.calls[0].queryParameters, isEmpty);
      expect(adapter.calls[1].path, '/api/accounting/carrier/payroll/runs');
      expect(adapter.calls[1].data, <String, dynamic>{'periodFrom': '2026-10-01'});
    });

    test('approving sends the revision on screen; a refusal carries its code and the run as it now is', () async {
      final _Adapter adapter = _Adapter((RequestOptions o) => _json(<String, dynamic>{
            'error': 'The figures changed since you looked.',
            'code': 'FIGURES_CHANGED',
            'run': runJson(revision: 4),
          }, status: 409));
      final CarrierPayrollApi api = CarrierPayrollApi(_dio(adapter));

      await expectLater(
        api.approve('run-1', revision: 3),
        throwsA(isA<PayrollRefused>()
            .having((PayrollRefused r) => r.code, 'code', 'FIGURES_CHANGED')
            .having((PayrollRefused r) => r.run?.revision, 'run revision', 4)),
      );
      expect(adapter.calls.single.path, '/api/accounting/carrier/payroll/runs/run-1/approve');
      expect(adapter.calls.single.data,
          <String, dynamic>{'revision': 3, 'acknowledgeMissing': false});
    });

    test('paying everything sends the total as the server wrote it; a moved total comes back as the current figure', () async {
      final _Adapter adapter = _Adapter((RequestOptions o) => _json(<String, dynamic>{
            'error': 'The total waiting for payment is now 4.00.',
            'code': 'TOTAL_CHANGED',
            'current': '4.00',
          }, status: 409));
      final CarrierPayrollApi api = CarrierPayrollApi(_dio(adapter));

      await expectLater(
        api.payAll('run-1', expectedTotal: const Money('6.00'), method: CashMethod.bankDeposit, reference: ' TRX-1 '),
        throwsA(isA<PayrollRefused>()
            .having((PayrollRefused r) => r.current?.amount, 'current', '4.00')),
      );
      expect(adapter.calls.single.data, <String, dynamic>{
        'expectedTotal': '6.00',
        'method': 'BANK_DEPOSIT',
        'reference': 'TRX-1',
      });
    });

    test('payments, lines, corrections and rules go as typed text, never numbers', () async {
      final _Adapter adapter = _Adapter((RequestOptions o) => o.path.endsWith('/policy')
          ? _json((runJson()['policy'] as Map<String, dynamic>), status: 201)
          : _json(runJson()));
      final CarrierPayrollApi api = CarrierPayrollApi(_dio(adapter));

      await api.markPaid('run-1', 'slip-1', method: CashMethod.cash);
      await api.addLine('run-1', riderRef: 'rider-youssef', kind: PayLineKind.bonus, label: 'Eid bonus', amount: '25.00');
      await api.addCorrection('run-1', riderRef: 'rider-youssef', kind: PayLineKind.deduction, amount: '4.50', reason: 'Counted twice');
      await api.savePolicy(
        effectiveFrom: DateTime(2026, 10, 16),
        payCycle: PayCycle.semiMonthly,
        perDeliveryRate: '2.35',
        payManualHours: true,
        overtimeMultiplier: '1.00',
        lateDeduction: '0.00',
        absenceDeduction: '0.00',
      );

      expect(adapter.calls[0].path, '/api/accounting/carrier/payroll/runs/run-1/payslips/slip-1/paid');
      expect(adapter.calls[0].data, <String, dynamic>{'method': 'CASH'});
      expect(adapter.calls[1].data, <String, dynamic>{
        'riderRef': 'rider-youssef',
        'kind': 'BONUS',
        'label': 'Eid bonus',
        'amount': '25.00',
      });
      expect((adapter.calls[2].data as Map<String, dynamic>)['amount'], '4.50');
      expect(adapter.calls[3].data, <String, dynamic>{
        'effectiveFrom': '2026-10-16',
        'payCycle': 'SEMI_MONTHLY',
        'perDeliveryRate': '2.35',
        'payManualHours': true,
        'overtimeMultiplier': '1.00',
        'lateDeduction': '0.00',
        'absenceDeduction': '0.00',
      });
    });

    test('a failure the server did not explain stays Dio\'s, for the page to word', () async {
      final _Adapter adapter = _Adapter((RequestOptions o) => _json(<String, dynamic>{'error': 'boom'}, status: 500));
      final CarrierPayrollApi api = CarrierPayrollApi(_dio(adapter));

      await expectLater(api.recompute('run-1'), throwsA(isA<DioException>()));
      await expectLater(api.run('run-1'), throwsA(isA<DioException>()));
    });
  });
}
