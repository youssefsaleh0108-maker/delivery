import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/carrier/payroll_parts.dart';
import 'package:delivery_portal/src/carrier/payroll_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// A delivery company's payroll page (Figma 112:1162).
///
/// What matters: it asks for its own company's payroll and names nobody; every figure is the
/// server's string; tips are shown and never paid; nothing is frozen or recorded without a
/// confirmation that names the riders and the total; what goes back is the revision and the total
/// that were on screen — so figures that moved are shown, not approved; and a control is only
/// drawn live when what it does is allowed.
class _Server implements HttpClientAdapter {
  _Server(this.respond);

  ResponseBody Function(RequestOptions options) respond;
  final List<RequestOptions> calls = <RequestOptions>[];

  List<RequestOptions> get posts =>
      calls.where((RequestOptions o) => o.method == 'POST').toList(growable: false);

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

const String _base = '/api/accounting/carrier/payroll';

Map<String, dynamic> _period(String from, String to,
        {required bool over, String? runId, String status = 'DRAFT'}) =>
    <String, dynamic>{
      'from': from,
      'to': to,
      'over': over,
      'aligned': true,
      'runId': runId,
      'status': runId == null ? null : status,
      'revision': runId == null ? null : 3,
      'riders': runId == null ? 0 : 2,
      'payable': runId == null ? null : '39.30',
    };

Map<String, dynamic> _periods({bool hasPolicy = true, String? runId = 'run-1', String status = 'DRAFT'}) =>
    <String, dynamic>{
      'zone': 'Asia/Beirut',
      'currency': 'USD',
      'today': '2026-10-20',
      'hasPolicy': hasPolicy,
      'periods': hasPolicy
          ? <dynamic>[
              _period('2026-10-16', '2026-10-31', over: false),
              _period('2026-10-01', '2026-10-15', over: true, runId: runId, status: status),
            ]
          : <dynamic>[],
    };

Map<String, dynamic> _line(String kind, String amount,
        {String source = 'COMPUTED', String? label, String? quantity, String? rate}) =>
    <String, dynamic>{
      'id': 'line-$kind-$amount',
      'kind': kind,
      'source': source,
      'label': label,
      'quantity': quantity,
      'rate': rate,
      'amount': amount,
      'createdByName': source == 'COMPUTED' ? null : 'Kamal M.',
    };

Map<String, dynamic> _run({
  String status = 'DRAFT',
  int revision = 3,
  bool periodOver = true,
  bool needsAcknowledgement = false,
  String attendance = 'INCLUDED',
  String? attendanceReason,
  String deliveries = 'ORDERS',
  String? deliveriesReason,
  String deliveriesAt = '2026-10-20T09:00:00Z',
  bool readBeforePeriodEnd = false,
  List<dynamic> hoursMissingFor = const <dynamic>[],
  String from = '2026-10-01',
  String to = '2026-10-15',
}) {
  final String slipStatus = status == 'DRAFT' ? 'DRAFT' : 'DUE';
  return <String, dynamic>{
    'id': 'run-1',
    'from': from,
    'to': to,
    'status': status,
    'revision': revision,
    'currency': 'USD',
    'computedAt': '2026-10-20T09:00:00Z',
    'approvedAt': null,
    'approvedByName': null,
    'paidAt': null,
    'attendance': attendance,
    'attendanceReason': attendanceReason,
    'attendanceAt': attendance == 'INCLUDED' ? '2026-10-20T09:00:00Z' : null,
    'deliveries': deliveries,
    'deliveriesReason': deliveriesReason,
    'deliveriesAt': deliveriesAt,
    'readBeforePeriodEnd': readBeforePeriodEnd,
    'hoursMissingFor': hoursMissingFor,
    'periodOver': periodOver,
    'jobsSinceComputed': 0,
    'needsAcknowledgement': needsAcknowledgement,
    'periodChanged': false,
    'policy': <String, dynamic>{
      'id': 'policy-1',
      'effectiveFrom': '2026-09-01',
      'payCycle': 'SEMI_MONTHLY',
      'currency': 'USD',
      'perDeliveryRate': '2.35',
      'hourlyRate': '4.00',
      'payManualHours': true,
      'overtimeMultiplier': '1.00',
      'lateDeduction': '0.00',
      'absenceDeduction': '0.00',
      'needsAttendance': true,
      'createdByName': 'Kamal M.',
      'createdAt': '2026-08-30T10:00:00Z',
    },
    'totals': <String, dynamic>{
      'riders': 2,
      'payable': '39.30',
      'average': '19.65',
      'gross': '99.30',
      'bonuses': '25.00',
      'deductions': '60.00',
      'owedByRiders': '0.00',
      'tips': '15.00',
      'cashNetted': '60.00',
      'paid': '0.00',
      'outstanding': status == 'DRAFT' ? '0.00' : '39.30',
      'due': status == 'DRAFT' ? 0 : 2,
      'failed': 0,
      'paidCount': 0,
    },
    'payslips': <dynamic>[
      <String, dynamic>{
        'id': 'slip-youssef',
        'riderRef': 'rider-youssef',
        'name': 'Youssef Kanaan',
        'status': slipStatus,
        'deliveries': 17,
        'workedSeconds': 28800,
        'manualSeconds': 0,
        'overtimeSeconds': 0,
        'lates': 0,
        'absences': 0,
        'hoursUnknown': false,
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
          _line('DELIVERIES', '39.95', quantity: '17', rate: '2.35'),
          _line('HOURS', '32.00', quantity: '8.00', rate: '4.00'),
          _line('BONUS', '25.00', source: 'MANUAL', label: 'Eid bonus'),
          _line('CASH_HELD', '60.00'),
        ],
      },
      <String, dynamic>{
        'id': 'slip-rania',
        'riderRef': 'rider-rania',
        'name': 'Rania Ghandour',
        'status': slipStatus,
        'deliveries': 1,
        'workedSeconds': null,
        'manualSeconds': null,
        'overtimeSeconds': null,
        'lates': null,
        'absences': null,
        'hoursUnknown': true,
        'basePay': '0.00',
        'deliveryPay': '2.35',
        'bonuses': '0.00',
        'deductions': '0.00',
        'gross': '2.35',
        'net': '2.35',
        'tips': '0.00',
        'cashHeld': '30.00',
        'cashNetted': '0.00',
        'paidMethod': null,
        'lines': <dynamic>[
          _line('DELIVERIES', '2.35', quantity: '1', rate: '2.35'),
        ],
      },
    ],
    'corrections': <dynamic>[],
    'history': <dynamic>[],
  };
}

ResponseBody _happy(RequestOptions o) {
  if (o.path.endsWith('/periods')) return _json(_periods());
  if (o.method == 'POST' && o.path.endsWith('/pay')) return _json(_run(status: 'PAID'));
  if (o.method == 'POST' && o.path.endsWith('/approve')) return _json(_run(status: 'APPROVED'));
  return _json(_run());
}

void main() {
  late _Server server;
  late DeliveryStrings t;
  String? savedName;
  String? savedCsv;

  setUpAll(() async {
    t = await DeliveryStrings.delegate.load(const Locale('en'));
  });

  setUp(() {
    server = _Server(_happy);
    savedName = null;
    savedCsv = null;
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1700, 1400);
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
        body: CarrierPayrollScreen(
          api: CarrierPayrollApi(dio),
          saveFile: (String name, String content, {String mimeType = 'text/csv'}) {
            savedName = name;
            savedCsv = content;
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// The ink well of the button with this label: null onTap is a button drawn but not live.
  InkWell button(WidgetTester tester, String label) => tester.widget<InkWell>(
      find.ancestor(of: find.text(label).first, matching: find.byType(InkWell)).first);

  testWidgets('asks for its own company\'s periods and the run waiting to be paid, naming nobody',
      (WidgetTester tester) async {
    await pump(tester);

    expect(server.calls[0].path, '$_base/periods');
    expect(server.calls[0].queryParameters, isEmpty);
    // The latest period that is over is the one to pay — not the one still running.
    expect(server.calls[1].path, '$_base/runs/run-1');
    expect(find.text(t.payrollPeriodLabel('Oct 1, 2026', 'Oct 15, 2026')), findsOneWidget);
  });

  testWidgets('the cards and the ledger are the payslips\' own figures, tips shown and not paid',
      (WidgetTester tester) async {
    await pump(tester);

    expect(find.text('\$39.30'), findsOneWidget);
    expect(find.text('2 Riders'), findsOneWidget);
    expect(find.text('\$19.65'), findsOneWidget);
    expect(find.text('\$36.95'), findsOneWidget);
    expect(find.text('\$96.95'), findsOneWidget);
    expect(find.text('-\$60.00'), findsOneWidget);
    expect(find.text('\$15.00'), findsOneWidget);
    expect(find.byTooltip(t.payrollTipsNote), findsNWidgets(2));
    // Rania's hours were not read: her base pay is unknown, not nothing.
    expect(find.byTooltip(t.payrollHoursUnknown), findsOneWidget);
    expect(find.text(t.payrollStatusDraft), findsNWidgets(2));
    // The design's speed bonus and payment rail are not things this platform has.
    expect(find.textContaining('delivery speeds'), findsNothing);
    expect(find.text('Process All Payments'), findsNothing);
  });

  testWidgets('without pay rules the page asks for them and offers nothing it cannot do',
      (WidgetTester tester) async {
    server.respond = (RequestOptions o) => _json(_periods(hasPolicy: false));
    await pump(tester);

    expect(find.text(t.payrollNoRulesTitle), findsOneWidget);
    expect(find.text(t.payrollStart), findsNothing);
    expect(find.text(t.payrollApprove), findsNothing);
    expect(server.calls.single.path, '$_base/periods');
  });

  testWidgets('a period with no run offers to start one, and starting sends its first day',
      (WidgetTester tester) async {
    bool started = false;
    server.respond = (RequestOptions o) {
      if (o.method == 'POST') {
        started = true;
        return _json(_run(), status: 201);
      }
      if (o.path.endsWith('/periods')) return _json(_periods(runId: started ? 'run-1' : null));
      return _json(_run());
    };
    await pump(tester);

    expect(find.text(t.payrollNoRunTitle), findsOneWidget);
    await tester.tap(find.text(t.payrollStart));
    await tester.pumpAndSettle();

    final RequestOptions post = server.posts.single;
    expect(post.path, '$_base/runs');
    expect(post.data, <String, dynamic>{'periodFrom': '2026-10-01'});
    expect(find.text('Youssef Kanaan'), findsOneWidget);
  });

  testWidgets('Approve asks first, naming the riders, the total and the cash kept; Cancel sends nothing',
      (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.text(t.payrollApprove));
    await tester.pumpAndSettle();

    final Finder dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text(t.payrollApproveBody(2, '\$39.30'))),
        findsOneWidget);
    expect(
        find.descendant(
            of: dialog, matching: find.text(t.payrollApproveCash('\$60.00', 'Oct 15, 2026'))),
        findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, t.cancel));
    await tester.pumpAndSettle();
    expect(server.posts, isEmpty);
  });

  testWidgets('approving sends the revision on screen; figures that moved are shown, not approved',
      (WidgetTester tester) async {
    int revision = 3;
    server.respond = (RequestOptions o) {
      if (o.path.endsWith('/periods')) return _json(_periods());
      if (o.method == 'POST') {
        revision = 4;
        return _json(<String, dynamic>{
          'error': 'The figures changed since you looked.',
          'code': 'FIGURES_CHANGED',
          'run': _run(revision: 4),
        }, status: 409);
      }
      return _json(_run(revision: revision));
    };
    await pump(tester);

    await tester.tap(find.text(t.payrollApprove));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, t.payrollApproveYes));
    await tester.pumpAndSettle();

    final RequestOptions post = server.posts.single;
    expect(post.path, '$_base/runs/run-1/approve');
    expect(post.data, <String, dynamic>{'revision': 3, 'acknowledgeMissing': false});
    expect(find.text(t.payrollErrFiguresChanged), findsOneWidget);
    expect(find.textContaining(t.payrollRunRevision(4)), findsOneWidget);
  });

  testWidgets('missing hours are named rider by rider, and must be acknowledged before approving',
      (WidgetTester tester) async {
    server.respond = (RequestOptions o) => o.path.endsWith('/periods')
        ? _json(_periods())
        : _json(_run(
            needsAcknowledgement: true,
            hoursMissingFor: <dynamic>[
              <String, dynamic>{
                'riderRef': 'rider-rania',
                'name': 'Rania Ghandour',
                'reason': 'UNREADABLE',
              },
            ],
          ));
    await pump(tester);

    // Youssef's hours were read; only Rania's are missing, and the page says whose.
    final String named = t.payrollHoursMissingFor(1, 'Rania Ghandour');
    expect(find.text(named), findsOneWidget);
    expect(find.text(t.payrollHoursMissing), findsNothing);
    await tester.tap(find.text(t.payrollApprove));
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text(named)),
        findsOneWidget);
    FilledButton approve() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, t.payrollApproveYes));
    expect(approve().onPressed, isNull);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(approve().onPressed, isNotNull);
    await tester.tap(find.widgetWithText(FilledButton, t.payrollApproveYes));
    await tester.pumpAndSettle();

    expect(server.posts.single.data, <String, dynamic>{'revision': 3, 'acknowledgeMissing': true});
  });

  testWidgets('hours that could not be read at all are said for the run, and everyone left without them is named',
      (WidgetTester tester) async {
    server.respond = (RequestOptions o) => o.path.endsWith('/periods')
        ? _json(_periods())
        : _json(_run(
            attendance: 'UNAVAILABLE',
            attendanceReason: 'UNREACHABLE',
            needsAcknowledgement: true,
            hoursMissingFor: <dynamic>[
              <String, dynamic>{'riderRef': 'rider-youssef', 'name': 'Youssef Kanaan'},
              <String, dynamic>{'riderRef': 'rider-rania-0001', 'name': null},
            ],
          ));
    await pump(tester);

    expect(find.text(t.payrollHoursMissing), findsOneWidget);
    await tester.tap(find.text(t.payrollApprove));
    await tester.pumpAndSettle();

    // A rider Keycloak knows no name for is named by a short reference, never left out.
    expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(t.payrollHoursMissingFor(2, 'Youssef Kanaan, RIDER-RA'))),
        findsOneWidget);
  });

  testWidgets('deliveries counted only from paid jobs are said, and acknowledged at approval',
      (WidgetTester tester) async {
    server.respond = (RequestOptions o) => o.path.endsWith('/periods')
        ? _json(_periods())
        : _json(_run(
            deliveries: 'LEDGER',
            deliveriesReason: 'NOT_DEPLOYED',
            needsAcknowledgement: true,
          ));
    await pump(tester);

    expect(find.text(t.payrollDeliveriesNotDeployed), findsOneWidget);
    await tester.tap(find.text(t.payrollApprove));
    await tester.pumpAndSettle();

    expect(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.text(t.payrollApproveDeliveriesLedger)),
        findsOneWidget);
    expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, t.payrollApproveYes)).onPressed,
        isNull);
  });

  testWidgets('figures read before the period ended ask for a recompute, and Approve is not live',
      (WidgetTester tester) async {
    server.respond = (RequestOptions o) => o.path.endsWith('/periods')
        ? _json(_periods())
        : _json(_run(readBeforePeriodEnd: true, deliveriesAt: '2026-10-10T09:00:00Z'));
    await pump(tester);

    expect(button(tester, t.payrollApprove).onTap, isNull);
    // Worded with the moment of the read, which the reader's own clock prints.
    expect(find.textContaining(t.payrollReadBeforeEnd(' ').split(' ').last),
        findsOneWidget);
  });

  testWidgets('Approve is drawn but not live while the period is still running',
      (WidgetTester tester) async {
    server.respond = (RequestOptions o) => o.path.endsWith('/periods')
        ? _json(<String, dynamic>{
            'zone': 'Asia/Beirut',
            'currency': 'USD',
            'today': '2026-10-20',
            'hasPolicy': true,
            'periods': <dynamic>[
              _period('2026-10-16', '2026-10-31', over: false, runId: 'run-1'),
            ],
          })
        : _json(_run(from: '2026-10-16', to: '2026-10-31', periodOver: false));
    await pump(tester);

    expect(button(tester, t.payrollApprove).onTap, isNull);
    expect(find.text(t.payrollPeriodOpen('Oct 31, 2026')), findsOneWidget);
  });

  testWidgets('an approved run records all payments against the total waiting, and sends that total',
      (WidgetTester tester) async {
    server.respond = (RequestOptions o) {
      if (o.path.endsWith('/periods')) return _json(_periods(status: 'APPROVED'));
      if (o.method == 'POST') return _json(_run(status: 'PAID'));
      return _json(_run(status: 'APPROVED'));
    };
    await pump(tester);

    expect(find.text(t.payrollApprove), findsNothing);
    await tester.tap(find.text(t.payrollPayAll));
    await tester.pumpAndSettle();
    expect(find.text(t.payrollPayAllTitle(2, '\$39.30')), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, t.payrollRecordYes));
    await tester.pumpAndSettle();

    final RequestOptions post = server.posts.single;
    expect(post.path, '$_base/runs/run-1/pay');
    expect(post.data, <String, dynamic>{'expectedTotal': '39.30', 'method': 'CASH'});
  });

  testWidgets('the payslip breaks the pay down, and a draft offers edits and nothing else',
      (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.text(t.payrollPayslip).first);
    await tester.pumpAndSettle();

    expect(find.text(t.payrollLineDeliveries(17, '\$2.35')), findsOneWidget);
    expect(find.text(t.payrollLineHours('8.00', '\$4.00')), findsOneWidget);
    expect(find.text(t.payrollLineBonus('Eid bonus')), findsOneWidget);
    expect(find.text(t.payrollLineCash), findsOneWidget);
    expect(find.text(t.payrollTipsInfo('\$15.00')), findsOneWidget);
    expect(find.text(t.payrollAddBonus), findsOneWidget);
    expect(find.text(t.payrollAddDeduction), findsOneWidget);
    // Only a line a person added can come off, and only the bonus here is one.
    expect(find.byTooltip(t.payrollRemove), findsOneWidget);
    expect(find.text(t.payrollMarkPaid), findsNothing);
    expect(find.text(t.payrollAddCorrection), findsNothing);
  });

  testWidgets('a rider holding more company cash than their pay is told it stays for the hub',
      (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.text(t.payrollPayslip).last);
    await tester.pumpAndSettle();

    // Cash collected by the period's last day: what the rider took since is not this run's.
    expect(find.text(t.payrollCashKept('\$30.00', 'Oct 15, 2026')), findsOneWidget);
    expect(find.text(t.payrollHoursUnknown), findsOneWidget);
  });

  testWidgets('the export is the payslips as the server wrote them', (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.text(t.payrollExport));
    await tester.pumpAndSettle();

    expect(savedName, 'payroll-2026-10-01.csv');
    final List<String> lines = savedCsv!.trim().split('\r\n');
    expect(lines, hasLength(3));
    expect(lines[1], 'Youssef Kanaan,rider-youssef,32.00,39.95,25.00,15.00,60.00,96.95,36.95,Draft');
    // Rania's hours were not read: her base pay is blank, as the table shows a dash.
    expect(lines[2], 'Rania Ghandour,rider-rania,,2.35,0.00,0.00,0.00,2.35,2.35,Draft');
  });

  testWidgets('staff of no company are told so, not shown an empty payroll',
      (WidgetTester tester) async {
    server.respond = (RequestOptions o) => _json(<String, dynamic>{
          'error': 'This account is not staff of a delivery company.',
          'code': 'NO_COMPANY',
        }, status: 403);
    await pump(tester);

    expect(find.text(t.noCompanyYet), findsOneWidget);
    expect(find.text(t.payrollNobody), findsNothing);
  });

  testWidgets('a rider attendance does not list is told so on their payslip, not that reading failed',
      (WidgetTester tester) async {
    final Map<String, dynamic> run = _run();
    ((run['payslips'] as List<dynamic>).last as Map<String, dynamic>)['hoursReason'] = 'NOT_LISTED';
    server.respond =
        (RequestOptions o) => o.path.endsWith('/periods') ? _json(_periods()) : _json(run);
    await pump(tester);

    await tester.tap(find.text(t.payrollPayslip).last);
    await tester.pumpAndSettle();

    expect(find.text(t.payrollHoursNotListed), findsOneWidget);
    expect(find.text(t.payrollHoursUnknown), findsNothing);
  });

  test('a line\'s count is worded with each language\'s own plurals, never "1 deliveries"', () async {
    final DeliveryStrings ar = await DeliveryStrings.delegate.load(const Locale('ar'));
    PayLine line(String kind, String quantity) => PayLine.fromJson(<String, dynamic>{
          'id': 'line-$kind-$quantity',
          'kind': kind,
          'source': 'COMPUTED',
          'quantity': quantity,
          'rate': '2.00',
          'amount': '2.00',
        });

    expect(payLineText(t, line('DELIVERIES', '1'), 'USD'), t.payrollLineDeliveries(1, '\$2.00'));
    expect(payLineText(t, line('DELIVERIES', '1'), 'USD'), startsWith('1 delivery '));
    expect(payLineText(t, line('DELIVERIES', '17'), 'USD'), startsWith('17 deliveries '));
    expect(payLineText(t, line('LATE_DEDUCTION', '1'), 'USD'), startsWith('1 late day '));
    expect(payLineText(t, line('ABSENCE_DEDUCTION', '1'), 'USD'), startsWith('1 absence '));
    expect(payLineText(t, line('ABSENCE_DEDUCTION', '3'), 'USD'), startsWith('3 absences '));

    // One, two, a few (3–10) and many (11–99) are four different words in Arabic.
    expect(payLineText(ar, line('DELIVERIES', '1'), 'USD'), contains('توصيلة واحدة'));
    expect(payLineText(ar, line('DELIVERIES', '2'), 'USD'), contains('توصيلتان'));
    expect(payLineText(ar, line('DELIVERIES', '3'), 'USD'), contains('توصيلات'));
    expect(payLineText(ar, line('DELIVERIES', '11'), 'USD'),
        allOf(contains('توصيلة'), isNot(contains('توصيلات')), isNot(contains('واحدة'))));
    expect(payLineText(ar, line('LATE_DEDUCTION', '2'), 'USD'), contains('يوما تأخير'));
    expect(payLineText(ar, line('LATE_DEDUCTION', '5'), 'USD'), contains('أيام تأخير'));
    expect(payLineText(ar, line('ABSENCE_DEDUCTION', '1'), 'USD'), contains('يوم غياب واحد'));

    // A count the server did not write as a whole number is not guessed at.
    expect(payLineText(t, line('DELIVERIES', '2.5'), 'USD'), t.payrollLineOther);
  });
}
