/// A delivery company's payroll for the riders it employs. Mirrors
/// `/api/accounting/carrier/payroll`.
///
/// Every amount is a [Money] — the server's own two-decimal string — and never a double; a figure the
/// server did not send parses to null and must render as unknown, never as zero, because "we were not
/// told" and "nothing is owed" are different statements about somebody's pay. Seconds are exact
/// integers; any hours a screen prints are worked out from them for display only.
///
/// None of this is YouDrop's money. The platform does not pay a delivery company's riders: the
/// company keeps its payroll here and records what it paid them.
library;

import 'carrier_cash_models.dart' show CashMethod;
import 'statement_models.dart' show Money;

/// How a company's calendar is cut into pay periods.
enum PayCycle {
  /// The 1st to the 15th, and the 16th to the month's end.
  semiMonthly('SEMI_MONTHLY'),

  /// The calendar month.
  monthly('MONTHLY'),

  /// A calendar this build predates.
  unknown('UNKNOWN');

  const PayCycle(this.wire);

  final String wire;

  static PayCycle fromWire(Object? value) => PayCycle.values.firstWhere(
        (PayCycle c) => c.wire == value,
        orElse: () => PayCycle.unknown,
      );
}

/// Where a pay run is: only ever forward.
enum PayRunStatus {
  /// Computed and recomputable.
  draft('DRAFT'),

  /// Figures frozen; payments being recorded.
  approved('APPROVED'),

  /// Every payslip due has a recorded payment.
  paid('PAID'),

  unknown('UNKNOWN');

  const PayRunStatus(this.wire);

  final String wire;

  static PayRunStatus fromWire(Object? value) => PayRunStatus.values.firstWhere(
        (PayRunStatus s) => s.wire == value,
        orElse: () => PayRunStatus.unknown,
      );
}

/// Where one rider's pay is.
enum PayslipStatus {
  /// On a draft run.
  draft('DRAFT'),

  /// Approved, and no payment recorded yet.
  due('DUE'),

  /// Approved with nothing to hand over: deductions took all of it, or more.
  nothingDue('NOTHING_DUE'),

  /// The company recorded paying it.
  paid('PAID'),

  /// The company recorded a payment that did not go through. Still owed.
  failed('FAILED'),

  unknown('UNKNOWN');

  const PayslipStatus(this.wire);

  final String wire;

  static PayslipStatus fromWire(Object? value) => PayslipStatus.values.firstWhere(
        (PayslipStatus s) => s.wire == value,
        orElse: () => PayslipStatus.unknown,
      );
}

/// Whether a run's figures include attendance hours.
enum PayrollAttendance {
  /// The rules pay nothing by the hour and deduct nothing for lateness.
  notNeeded('NOT_NEEDED'),

  /// Read, and copied into the run at [PayRun.attendanceAt].
  included('INCLUDED'),

  /// Needed and not read. The figures leave hours out; see [PayRun.attendanceReason].
  unavailable('UNAVAILABLE'),

  unknown('UNKNOWN');

  const PayrollAttendance(this.wire);

  final String wire;

  static PayrollAttendance fromWire(Object? value) => PayrollAttendance.values.firstWhere(
        (PayrollAttendance a) => a.wire == value,
        orElse: () => PayrollAttendance.unknown,
      );
}

/// Where a run's delivery counts came from.
enum PayrollDeliveries {
  /// Every order each rider delivered for the company, as Order Manager counted them — fee or none.
  orders('ORDERS'),

  /// Order Manager could not be asked, so only deliveries that earned a fee were counted: free
  /// deliveries are missing. See [PayRun.deliveriesReason].
  ledger('LEDGER'),

  unknown('UNKNOWN');

  const PayrollDeliveries(this.wire);

  final String wire;

  static PayrollDeliveries fromWire(Object? value) => PayrollDeliveries.values.firstWhere(
        (PayrollDeliveries d) => d.wire == value,
        orElse: () => PayrollDeliveries.unknown,
      );
}

/// A rider on a run whose hours the rules need and the run does not have.
class PayrollMissingHours {
  const PayrollMissingHours({required this.riderRef, required this.name, required this.reason});

  final String riderRef;

  /// What Keycloak calls them, or null.
  final String? name;

  /// Why, as a code: UNREADABLE, NOT_LISTED, or the whole read's own reason.
  final String? reason;

  factory PayrollMissingHours.fromJson(Map<String, dynamic> json) => PayrollMissingHours(
        riderRef: _text(json['riderRef']) ?? '',
        name: _text(json['name']),
        reason: _text(json['reason']),
      );
}

/// What one payslip line is.
enum PayLineKind {
  deliveries('DELIVERIES'),
  hours('HOURS'),
  overtime('OVERTIME'),

  /// Hours the office typed. Shown whether or not the rules pay them.
  manualHours('MANUAL_HOURS'),
  lateDeduction('LATE_DEDUCTION'),
  absenceDeduction('ABSENCE_DEDUCTION'),

  /// Cash the rider held for the company, kept out of this pay.
  cashHeld('CASH_HELD'),

  /// A named bonus.
  bonus('BONUS'),

  /// A named deduction.
  deduction('DEDUCTION'),

  unknown('UNKNOWN');

  const PayLineKind(this.wire);

  final String wire;

  /// Which side of the payslip the line is on. An unknown kind is on neither.
  bool get isDeduction => switch (this) {
        PayLineKind.lateDeduction ||
        PayLineKind.absenceDeduction ||
        PayLineKind.cashHeld ||
        PayLineKind.deduction =>
          true,
        _ => false,
      };

  static PayLineKind fromWire(Object? value) => PayLineKind.values.firstWhere(
        (PayLineKind k) => k.wire == value,
        orElse: () => PayLineKind.unknown,
      );
}

/// Where a payslip line came from.
enum PayLineSource {
  /// From the rules and the facts.
  computed('COMPUTED'),

  /// A person's named bonus or deduction on a draft.
  manual('MANUAL'),

  /// A correction to an earlier run, paid in this one.
  adjustment('ADJUSTMENT'),

  unknown('UNKNOWN');

  const PayLineSource(this.wire);

  final String wire;

  static PayLineSource fromWire(Object? value) => PayLineSource.values.firstWhere(
        (PayLineSource s) => s.wire == value,
        orElse: () => PayLineSource.unknown,
      );
}

/// What somebody did to a run, as its history lists it.
enum PayrollAction {
  policySet('POLICY_SET'),
  runStarted('RUN_STARTED'),
  runRecomputed('RUN_RECOMPUTED'),
  runDiscarded('RUN_DISCARDED'),
  lineAdded('LINE_ADDED'),
  lineRemoved('LINE_REMOVED'),
  runApproved('RUN_APPROVED'),
  cashNetted('CASH_NETTED'),
  payslipPaid('PAYSLIP_PAID'),
  payslipFailed('PAYSLIP_FAILED'),
  runPaid('RUN_PAID'),
  adjustmentAdded('ADJUSTMENT_ADDED'),
  unknown('UNKNOWN');

  const PayrollAction(this.wire);

  final String wire;

  static PayrollAction fromWire(Object? value) => PayrollAction.values.firstWhere(
        (PayrollAction a) => a.wire == value,
        orElse: () => PayrollAction.unknown,
      );
}

/// One version of a company's pay rules.
class PayPolicy {
  const PayPolicy({
    required this.id,
    required this.effectiveFrom,
    required this.payCycle,
    required this.currency,
    required this.perDeliveryRate,
    required this.hourlyRate,
    required this.payManualHours,
    required this.overtimeMultiplier,
    required this.lateDeduction,
    required this.absenceDeduction,
    required this.needsAttendance,
    required this.createdByName,
    required this.createdAt,
  });

  final String id;

  /// The first day these rules pay, as a calendar day.
  final DateTime? effectiveFrom;
  final PayCycle payCycle;
  final String currency;
  final Money? perDeliveryRate;

  /// Null when the rules pay nothing by the hour.
  final Money? hourlyRate;
  final bool payManualHours;

  /// The server's text, like `1.50`. A factor, not money.
  final String? overtimeMultiplier;
  final Money? lateDeduction;
  final Money? absenceDeduction;

  /// Whether a run under these rules reads attendance at all.
  final bool needsAttendance;
  final String? createdByName;
  final DateTime? createdAt;

  factory PayPolicy.fromJson(Map<String, dynamic> json) => PayPolicy(
        id: _text(json['id']) ?? '',
        effectiveFrom: _day(json['effectiveFrom']),
        payCycle: PayCycle.fromWire(json['payCycle']),
        currency: _text(json['currency']) ?? '',
        perDeliveryRate: Money.parse(json['perDeliveryRate']),
        hourlyRate: Money.parse(json['hourlyRate']),
        payManualHours: json['payManualHours'] == true,
        overtimeMultiplier: _text(json['overtimeMultiplier']),
        lateDeduction: Money.parse(json['lateDeduction']),
        absenceDeduction: Money.parse(json['absenceDeduction']),
        needsAttendance: json['needsAttendance'] == true,
        createdByName: _text(json['createdByName']),
        createdAt: _instant(json['createdAt']),
      );
}

/// What a new version of the rules starts from when a company has said nothing.
class PayPolicyDefaults {
  const PayPolicyDefaults({
    required this.payCycle,
    required this.payManualHours,
    required this.overtimeMultiplier,
    required this.lateDeduction,
    required this.absenceDeduction,
  });

  final PayCycle payCycle;
  final bool payManualHours;
  final String? overtimeMultiplier;
  final Money? lateDeduction;
  final Money? absenceDeduction;

  factory PayPolicyDefaults.fromJson(Map<String, dynamic> json) => PayPolicyDefaults(
        payCycle: PayCycle.fromWire(json['payCycle']),
        payManualHours: json['payManualHours'] != false,
        overtimeMultiplier: _text(json['overtimeMultiplier']),
        lateDeduction: Money.parse(json['lateDeduction']),
        absenceDeduction: Money.parse(json['absenceDeduction']),
      );
}

/// The rules page.
class PayPolicyPage {
  const PayPolicyPage({
    required this.zone,
    required this.currency,
    required this.today,
    required this.current,
    required this.scheduled,
    required this.history,
    required this.defaults,
    required this.startOptions,
  });

  final String zone;
  final String currency;
  final DateTime? today;

  /// The rules in force today, or null before the company set any.
  final PayPolicy? current;

  /// Rules set to start after today, earliest first.
  final List<PayPolicy> scheduled;
  final List<PayPolicy> history;
  final PayPolicyDefaults defaults;

  /// The days new rules could start on, per calendar. Only these are offered.
  final Map<PayCycle, List<DateTime>> startOptions;

  factory PayPolicyPage.fromJson(Map<String, dynamic> json) => PayPolicyPage(
        zone: _text(json['zone']) ?? '',
        currency: _text(json['currency']) ?? '',
        today: _day(json['today']),
        current: json['current'] is Map<String, dynamic>
            ? PayPolicy.fromJson(json['current'] as Map<String, dynamic>)
            : null,
        scheduled: _maps(json['scheduled']).map(PayPolicy.fromJson).toList(growable: false),
        history: _maps(json['history']).map(PayPolicy.fromJson).toList(growable: false),
        defaults: PayPolicyDefaults.fromJson(
            json['defaults'] as Map<String, dynamic>? ?? <String, dynamic>{}),
        startOptions: <PayCycle, List<DateTime>>{
          for (final MapEntry<String, dynamic> entry
              in (json['startOptions'] as Map<String, dynamic>? ?? <String, dynamic>{}).entries)
            if (PayCycle.fromWire(entry.key) != PayCycle.unknown)
              PayCycle.fromWire(entry.key): (entry.value as List<dynamic>? ?? <dynamic>[])
                  .map(_day)
                  .whereType<DateTime>()
                  .toList(growable: false),
        },
      );
}

/// One pay period on the period list.
class PayPeriod {
  const PayPeriod({
    required this.from,
    required this.to,
    required this.over,
    required this.aligned,
    required this.runId,
    required this.status,
    required this.revision,
    required this.riders,
    required this.payable,
  });

  final DateTime from;
  final DateTime to;

  /// The period has ended, so its run can be approved.
  final bool over;

  /// False for a run whose period the rules no longer draw, listed so it can be discarded.
  final bool aligned;

  /// Null when the period has no run yet.
  final String? runId;
  final PayRunStatus? status;
  final int? revision;
  final int riders;

  /// Null when nothing has been computed — not zero.
  final Money? payable;

  bool get hasRun => runId != null;

  /// Null when the server sent no readable first and last day: such a period cannot be shown.
  static PayPeriod? fromJson(Map<String, dynamic> json) {
    final DateTime? from = _day(json['from']);
    final DateTime? to = _day(json['to']);
    if (from == null || to == null) return null;
    return PayPeriod(
      from: from,
      to: to,
      over: json['over'] == true,
      aligned: json['aligned'] != false,
      runId: _text(json['runId']),
      status: json['status'] == null ? null : PayRunStatus.fromWire(json['status']),
      revision: _intOrNull(json['revision']),
      riders: _int(json['riders']),
      payable: Money.parse(json['payable']),
    );
  }
}

class PayPeriodsPage {
  const PayPeriodsPage({
    required this.zone,
    required this.currency,
    required this.today,
    required this.hasPolicy,
    required this.periods,
  });

  final String zone;
  final String currency;
  final DateTime? today;

  /// False until the company has set its pay rules.
  final bool hasPolicy;

  /// Latest first.
  final List<PayPeriod> periods;

  factory PayPeriodsPage.fromJson(Map<String, dynamic> json) => PayPeriodsPage(
        zone: _text(json['zone']) ?? '',
        currency: _text(json['currency']) ?? '',
        today: _day(json['today']),
        hasPolicy: json['hasPolicy'] == true,
        periods: _maps(json['periods'])
            .map(PayPeriod.fromJson)
            .whereType<PayPeriod>()
            .toList(growable: false),
      );
}

/// One line of a payslip.
class PayLine {
  const PayLine({
    required this.id,
    required this.kind,
    required this.source,
    required this.label,
    required this.quantity,
    required this.rate,
    required this.amount,
    required this.createdByName,
  });

  final String id;
  final PayLineKind kind;
  final PayLineSource source;

  /// A person's words on a named line or a correction; null on a computed one.
  final String? label;

  /// Deliveries, hours or days, as the server wrote it for display.
  final String? quantity;

  /// The rate applied, as the server wrote it. Null where there is none.
  final String? rate;
  final Money? amount;
  final String? createdByName;

  /// Only a named line a person added can be taken off a draft.
  bool get removable => source == PayLineSource.manual;

  factory PayLine.fromJson(Map<String, dynamic> json) => PayLine(
        id: _text(json['id']) ?? '',
        kind: PayLineKind.fromWire(json['kind']),
        source: PayLineSource.fromWire(json['source']),
        label: _text(json['label']),
        quantity: _text(json['quantity']),
        rate: _text(json['rate']),
        amount: Money.parse(json['amount']),
        createdByName: _text(json['createdByName']),
      );
}

/// One rider's pay in one run.
class Payslip {
  const Payslip({
    required this.id,
    required this.riderRef,
    required this.name,
    required this.status,
    required this.deliveries,
    required this.workedSeconds,
    required this.manualSeconds,
    required this.overtimeSeconds,
    required this.lates,
    required this.absences,
    required this.hoursUnknown,
    required this.hoursReason,
    required this.basePay,
    required this.deliveryPay,
    required this.bonuses,
    required this.deductions,
    required this.gross,
    required this.net,
    required this.tips,
    required this.cashHeld,
    required this.cashNetted,
    required this.paidMethod,
    required this.paidReference,
    required this.paidAt,
    required this.paidByName,
    required this.failureReason,
    required this.failedAt,
    required this.failedByName,
    required this.lines,
  });

  final String id;
  final String riderRef;

  /// What Keycloak calls them, or null.
  final String? name;
  final PayslipStatus status;
  final int deliveries;

  /// Duty time the rider app recorded. Null when no attendance was read for this rider.
  final int? workedSeconds;

  /// Hours the office typed, for days the app recorded nothing.
  final int? manualSeconds;
  final int? overtimeSeconds;
  final int? lates;
  final int? absences;

  /// The rules pay or judge hours and none were read for this rider.
  final bool hoursUnknown;

  /// Why not, when [hoursUnknown]: NOT_LISTED when attendance shows no time of theirs with the company
  /// in the period, UNREADABLE for figures that could not be believed, or the whole read's reason.
  final String? hoursReason;

  /// Paid for hours: ordinary, overtime, and typed hours when the rules pay them.
  final Money? basePay;
  final Money? deliveryPay;
  final Money? bonuses;
  final Money? deductions;
  final Money? gross;

  /// Can be negative: the rider owes the company what deductions took beyond the pay.
  final Money? net;

  /// The rider's own money — never in gross or net.
  final Money? tips;

  /// What the rider held for the company when computed.
  final Money? cashHeld;

  /// The part of it kept out of this pay: all of it, or none.
  final Money? cashNetted;
  final CashMethod? paidMethod;
  final String? paidReference;
  final DateTime? paidAt;
  final String? paidByName;
  final String? failureReason;
  final DateTime? failedAt;
  final String? failedByName;
  final List<PayLine> lines;

  /// The rider holds company cash this pay could not cover, so it stays theirs to hand over.
  bool get cashNotNetted =>
      (cashHeld?.minorUnits ?? 0) > 0 && (cashNetted?.minorUnits ?? -1) == 0;

  /// Deductions took more than the pay.
  bool get owesCompany => net?.isNegative ?? false;

  /// A payment can be recorded against it.
  bool get outstanding => status == PayslipStatus.due || status == PayslipStatus.failed;

  factory Payslip.fromJson(Map<String, dynamic> json) => Payslip(
        id: _text(json['id']) ?? '',
        riderRef: _text(json['riderRef']) ?? '',
        name: _text(json['name']),
        status: PayslipStatus.fromWire(json['status']),
        deliveries: _int(json['deliveries']),
        workedSeconds: _intOrNull(json['workedSeconds']),
        manualSeconds: _intOrNull(json['manualSeconds']),
        overtimeSeconds: _intOrNull(json['overtimeSeconds']),
        lates: _intOrNull(json['lates']),
        absences: _intOrNull(json['absences']),
        hoursUnknown: json['hoursUnknown'] == true,
        hoursReason: _text(json['hoursReason']),
        basePay: Money.parse(json['basePay']),
        deliveryPay: Money.parse(json['deliveryPay']),
        bonuses: Money.parse(json['bonuses']),
        deductions: Money.parse(json['deductions']),
        gross: Money.parse(json['gross']),
        net: Money.parse(json['net']),
        tips: Money.parse(json['tips']),
        cashHeld: Money.parse(json['cashHeld']),
        cashNetted: Money.parse(json['cashNetted']),
        paidMethod: CashMethod.fromWire(json['paidMethod']),
        paidReference: _text(json['paidReference']),
        paidAt: _instant(json['paidAt']),
        paidByName: _text(json['paidByName']),
        failureReason: _text(json['failureReason']),
        failedAt: _instant(json['failedAt']),
        failedByName: _text(json['failedByName']),
        lines: _maps(json['lines']).map(PayLine.fromJson).toList(growable: false),
      );
}

/// A run's headline figures, all from its payslips.
class PayRunTotals {
  const PayRunTotals({
    required this.riders,
    required this.payable,
    required this.average,
    required this.gross,
    required this.bonuses,
    required this.deductions,
    required this.owedByRiders,
    required this.tips,
    required this.cashNetted,
    required this.paid,
    required this.outstanding,
    required this.due,
    required this.failed,
    required this.paidCount,
  });

  final int riders;

  /// What the company pays out: the positive nets.
  final Money? payable;

  /// Payable over riders; null with nobody on the run.
  final Money? average;
  final Money? gross;
  final Money? bonuses;
  final Money? deductions;
  final Money? owedByRiders;
  final Money? tips;
  final Money? cashNetted;
  final Money? paid;

  /// Approved and not yet recorded as paid, failed payments included.
  final Money? outstanding;
  final int due;
  final int failed;
  final int paidCount;

  factory PayRunTotals.fromJson(Map<String, dynamic> json) => PayRunTotals(
        riders: _int(json['riders']),
        payable: Money.parse(json['payable']),
        average: Money.parse(json['average']),
        gross: Money.parse(json['gross']),
        bonuses: Money.parse(json['bonuses']),
        deductions: Money.parse(json['deductions']),
        owedByRiders: Money.parse(json['owedByRiders']),
        tips: Money.parse(json['tips']),
        cashNetted: Money.parse(json['cashNetted']),
        paid: Money.parse(json['paid']),
        outstanding: Money.parse(json['outstanding']),
        due: _int(json['due']),
        failed: _int(json['failed']),
        paidCount: _int(json['paidCount']),
      );
}

/// A correction recorded against an approved run, paid in the rider's next one.
class PayCorrection {
  const PayCorrection({
    required this.id,
    required this.riderRef,
    required this.riderName,
    required this.kind,
    required this.amount,
    required this.reason,
    required this.createdByName,
    required this.createdAt,
    required this.appliedRunId,
  });

  final String id;
  final String riderRef;
  final String? riderName;
  final PayLineKind kind;
  final Money? amount;
  final String reason;
  final String? createdByName;
  final DateTime? createdAt;

  /// The later run that paid it; null while it waits for one.
  final String? appliedRunId;

  factory PayCorrection.fromJson(Map<String, dynamic> json) => PayCorrection(
        id: _text(json['id']) ?? '',
        riderRef: _text(json['riderRef']) ?? '',
        riderName: _text(json['riderName']),
        kind: PayLineKind.fromWire(json['kind']),
        amount: Money.parse(json['amount']),
        reason: _text(json['reason']) ?? '',
        createdByName: _text(json['createdByName']),
        createdAt: _instant(json['createdAt']),
        appliedRunId: _text(json['appliedRunId']),
      );
}

/// One entry of a run's history.
class PayrollEvent {
  const PayrollEvent({
    required this.action,
    required this.riderName,
    required this.actorName,
    required this.at,
  });

  final PayrollAction action;
  final String? riderName;
  final String? actorName;
  final DateTime? at;

  factory PayrollEvent.fromJson(Map<String, dynamic> json) => PayrollEvent(
        action: PayrollAction.fromWire(json['action']),
        riderName: _text(json['riderName']),
        actorName: _text(json['actorName']),
        at: _instant(json['at']),
      );
}

/// One pay run's page.
class PayRun {
  const PayRun({
    required this.id,
    required this.from,
    required this.to,
    required this.status,
    required this.revision,
    required this.currency,
    required this.computedAt,
    required this.approvedAt,
    required this.approvedByName,
    required this.paidAt,
    required this.attendance,
    required this.attendanceReason,
    required this.attendanceAt,
    required this.deliveries,
    required this.deliveriesReason,
    required this.deliveriesAt,
    required this.readBeforePeriodEnd,
    required this.hoursMissingFor,
    required this.periodOver,
    required this.jobsSinceComputed,
    required this.needsAcknowledgement,
    required this.periodChanged,
    required this.policy,
    required this.totals,
    required this.payslips,
    required this.corrections,
    required this.history,
  });

  final String id;
  final DateTime? from;
  final DateTime? to;
  final PayRunStatus status;

  /// Which computation of the figures this is. Approval names the one the approver saw.
  final int revision;
  final String currency;
  final DateTime? computedAt;
  final DateTime? approvedAt;
  final String? approvedByName;
  final DateTime? paidAt;
  final PayrollAttendance attendance;

  /// Why hours are unavailable, as a code: NOT_DEPLOYED, REFUSED, PERIOD_REFUSED, UNREACHABLE,
  /// MISMATCH, UNREADABLE or NOT_READ.
  final String? attendanceReason;

  /// When the hours in the figures were read.
  final DateTime? attendanceAt;

  /// Where the delivery counts came from.
  final PayrollDeliveries deliveries;

  /// Why deliveries could not be counted from orders, as a code: NOT_DEPLOYED, REFUSED,
  /// PERIOD_REFUSED, UNREACHABLE, MISMATCH or UNREADABLE.
  final String? deliveriesReason;

  /// When the figures were last read afresh.
  final DateTime? deliveriesAt;

  /// The figures were last read before the period ended, so the rest of it is missing from them: a
  /// draft is recomputed before it can be approved.
  final bool readBeforePeriodEnd;

  /// The riders whose hours the rules need and this run does not have, named, in payslip order.
  final List<PayrollMissingHours> hoursMissingFor;
  final bool periodOver;

  /// Deliveries of the period that reached the ledger after the figures were computed.
  final int jobsSinceComputed;

  /// Approving this draft means approving it without some riders' hours, or with deliveries counted
  /// only from jobs that earned a fee.
  final bool needsAcknowledgement;

  /// The rules now cut these days into a different period; the draft can only be discarded.
  final bool periodChanged;
  final PayPolicy? policy;
  final PayRunTotals totals;
  final List<Payslip> payslips;
  final List<PayCorrection> corrections;

  /// Newest first.
  final List<PayrollEvent> history;

  bool get isDraft => status == PayRunStatus.draft;

  factory PayRun.fromJson(Map<String, dynamic> json) => PayRun(
        id: _text(json['id']) ?? '',
        from: _day(json['from']),
        to: _day(json['to']),
        status: PayRunStatus.fromWire(json['status']),
        revision: _int(json['revision']),
        currency: _text(json['currency']) ?? '',
        computedAt: _instant(json['computedAt']),
        approvedAt: _instant(json['approvedAt']),
        approvedByName: _text(json['approvedByName']),
        paidAt: _instant(json['paidAt']),
        attendance: PayrollAttendance.fromWire(json['attendance']),
        attendanceReason: _text(json['attendanceReason']),
        attendanceAt: _instant(json['attendanceAt']),
        deliveries: PayrollDeliveries.fromWire(json['deliveries']),
        deliveriesReason: _text(json['deliveriesReason']),
        deliveriesAt: _instant(json['deliveriesAt']),
        readBeforePeriodEnd: json['readBeforePeriodEnd'] == true,
        hoursMissingFor: _maps(json['hoursMissingFor'])
            .map(PayrollMissingHours.fromJson)
            .toList(growable: false),
        periodOver: json['periodOver'] == true,
        jobsSinceComputed: _int(json['jobsSinceComputed']),
        needsAcknowledgement: json['needsAcknowledgement'] == true,
        periodChanged: json['periodChanged'] == true,
        policy: json['policy'] is Map<String, dynamic>
            ? PayPolicy.fromJson(json['policy'] as Map<String, dynamic>)
            : null,
        totals: PayRunTotals.fromJson(json['totals'] as Map<String, dynamic>? ?? <String, dynamic>{}),
        payslips: _maps(json['payslips']).map(Payslip.fromJson).toList(growable: false),
        corrections: _maps(json['corrections']).map(PayCorrection.fromJson).toList(growable: false),
        history: _maps(json['history']).map(PayrollEvent.fromJson).toList(growable: false),
      );
}

/// Something asked of payroll that the server refused, with its reason. Nothing was written.
class PayrollRefused implements Exception {
  const PayrollRefused({
    required this.code,
    this.status,
    this.message,
    this.run,
    this.current,
    this.runId,
  });

  /// What a page words: FIGURES_CHANGED, NEEDS_ACKNOWLEDGEMENT, CASH_CHANGED, PERIOD_OPEN, …
  final String code;
  final int? status;

  /// The server's English, for a log. Pages word [code] instead.
  final String? message;

  /// The run as it now is, when the server sent it.
  final PayRun? run;

  /// The current total, after TOTAL_CHANGED.
  final Money? current;

  /// The run already there, after RUN_EXISTS.
  final String? runId;

  @override
  String toString() => 'PayrollRefused($code)';
}

int _int(Object? value) => (value as num?)?.toInt() ?? 0;

int? _intOrNull(Object? value) => (value as num?)?.toInt();

String? _text(Object? value) => value is String && value.trim().isNotEmpty ? value : null;

DateTime? _instant(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

/// A calendar day exactly as written — never through UTC, which moves the day east of Greenwich.
DateTime? _day(Object? value) {
  if (value is! String) return null;
  final RegExpMatch? match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value.trim());
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

List<Map<String, dynamic>> _maps(Object? value) =>
    (value as List<dynamic>? ?? <dynamic>[]).whereType<Map<String, dynamic>>().toList(growable: false);
