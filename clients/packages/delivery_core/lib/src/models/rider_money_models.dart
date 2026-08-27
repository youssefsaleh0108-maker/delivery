/// Rider earnings, tips and cash-out models mirroring the Accounting `RiderEarningsController`.
library;

/// Earnings and tips over one span — today, this week — mirroring `RiderEarningsService.Total`.
class EarningsTotal {
  const EarningsTotal({
    required this.earnings,
    required this.tips,
    required this.total,
    required this.jobs,
  });

  final double earnings;
  final double tips;

  /// [earnings] plus [tips], added server-side so the screen never does arithmetic the ledger
  /// might disagree with.
  final double total;

  final int jobs;

  factory EarningsTotal.fromJson(Map<String, dynamic> json) => EarningsTotal(
        earnings: (json['earnings'] as num?)?.toDouble() ?? 0,
        tips: (json['tips'] as num?)?.toDouble() ?? 0,
        total: (json['total'] as num?)?.toDouble() ?? 0,
        jobs: (json['jobs'] as num?)?.toInt() ?? 0,
      );
}

/// One bar of the day-by-day chart.
///
/// [day] is a calendar date in the rider's own timezone, sent as an ISO `yyyy-MM-dd` string with
/// no time component — parsed as such, not shifted to local time, because "Tuesday" must stay
/// Tuesday regardless of where the phone is when it renders.
class EarningsDay {
  const EarningsDay({
    required this.day,
    required this.earnings,
    required this.tips,
    required this.total,
    required this.jobs,
  });

  /// Midnight of the calendar day, no timezone applied.
  final DateTime day;

  final double earnings;
  final double tips;
  final double total;
  final int jobs;

  factory EarningsDay.fromJson(Map<String, dynamic> json) => EarningsDay(
        day: DateTime.tryParse(json['day'] as String? ?? '') ?? DateTime(1970),
        earnings: (json['earnings'] as num?)?.toDouble() ?? 0,
        tips: (json['tips'] as num?)?.toDouble() ?? 0,
        total: (json['total'] as num?)?.toDouble() ?? 0,
        jobs: (json['jobs'] as num?)?.toInt() ?? 0,
      );
}

/// Whose money a job line is, mirroring `RiderLedgerEntry.PayableBy`.
///
/// Not decoration. A figure marked [carrier] is owed by the rider's own company under their
/// employment contract; the platform will never hand it over, and a screen that shows it without
/// saying so is actively misleading.
enum EarningsPayer {
  /// The platform holds it and hands it over on a cash-out.
  platform('PLATFORM', 'Paid by the platform'),

  /// The rider's employer owes it. Shown, never paid out here.
  carrier('CARRIER', 'Paid by your company'),

  /// A payer this client does not know. Treated like [carrier]: never promised as payable here.
  unknown('UNKNOWN', 'Paid elsewhere');

  const EarningsPayer(this.wire, this.label);

  final String wire;
  final String label;

  static EarningsPayer fromWire(String? value) => EarningsPayer.values.firstWhere(
        (EarningsPayer p) => p.wire == value,
        orElse: () => EarningsPayer.unknown,
      );
}

/// One delivered job and what it paid, mirroring the controller's job payload.
class RiderJob {
  const RiderJob({
    required this.orderId,
    required this.earned,
    required this.tip,
    required this.reimbursement,
    required this.payableBy,
    this.fleet,
    this.deliveredAt,
  });

  final String orderId;
  final double earned;

  /// Tip recorded on this job. Zero when nobody tipped.
  final double tip;

  /// Money the rider laid out and gets back — a cash float top-up, not earnings.
  final double reimbursement;

  /// `PLATFORM` or `CARRIER` — which fleet carried the job. Null when the server did not say.
  final String? fleet;

  /// Who owes this line. See [EarningsPayer] for why it must reach the screen.
  final EarningsPayer payableBy;

  final DateTime? deliveredAt;

  factory RiderJob.fromJson(Map<String, dynamic> json) => RiderJob(
        orderId: json['orderId'] as String? ?? '',
        earned: (json['earned'] as num?)?.toDouble() ?? 0,
        tip: (json['tip'] as num?)?.toDouble() ?? 0,
        reimbursement: (json['reimbursement'] as num?)?.toDouble() ?? 0,
        fleet: json['fleet'] as String?,
        payableBy: EarningsPayer.fromWire(json['payableBy'] as String?),
        deliveredAt: _date(json['deliveredAt']),
      );

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

/// Where a cash-out request has got to, mirroring `RiderCashOut.Status`.
enum CashOutStatus {
  /// Asked for; the money is held out of the balance, waiting on a payout.
  requested('REQUESTED', 'Requested'),

  /// Handed over. Terminal.
  paid('PAID', 'Paid'),

  /// Refused; the held money went back to the balance. Terminal.
  rejected('REJECTED', 'Refused'),

  /// A status this client does not know. Shown as-is, never as paid.
  unknown('UNKNOWN', 'Unknown');

  const CashOutStatus(this.wire, this.label);

  final String wire;
  final String label;

  static CashOutStatus fromWire(String? value) => CashOutStatus.values.firstWhere(
        (CashOutStatus s) => s.wire == value,
        orElse: () => CashOutStatus.unknown,
      );

  /// Whether this request still holds money out of the balance.
  bool get isOpen => this == requested;
}

/// One cash-out request, mirroring the controller's cash-out payload.
class CashOut {
  const CashOut({
    required this.id,
    required this.amount,
    required this.currency,
    required this.status,
    this.riderRef,
    this.payoutNote,
    this.requestedAt,
    this.decidedBy,
    this.decidedAt,
    this.decisionNote,
    this.paymentRef,
    this.paidVia,
  });

  final String id;

  /// Present on the operator's queue; the rider's own list carries it too but a rider screen has
  /// no use for it.
  final String? riderRef;

  final double amount;
  final String currency;
  final CashOutStatus status;

  /// What the rider wrote when asking — "pay to my Wish account", etc. Null when they wrote
  /// nothing.
  final String? payoutNote;

  final DateTime? requestedAt;

  /// Who decided and when. All null while [CashOutStatus.requested].
  final String? decidedBy;
  final DateTime? decidedAt;

  /// The operator's note on the decision — for a rejection, why. Null when none was written.
  final String? decisionNote;

  /// The operator's reference for the actual transfer. Null until paid, and null after that too
  /// when the operator recorded none.
  final String? paymentRef;

  /// How the money moved — "cash", a transfer app. Null when not recorded.
  final String? paidVia;

  factory CashOut.fromJson(Map<String, dynamic> json) => CashOut(
        id: json['id'] as String,
        riderRef: json['riderRef'] as String?,
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String? ?? '',
        status: CashOutStatus.fromWire(json['status'] as String?),
        payoutNote: json['payoutNote'] as String?,
        requestedAt: RiderJob._date(json['requestedAt']),
        decidedBy: json['decidedBy'] as String?,
        decidedAt: RiderJob._date(json['decidedAt']),
        decisionNote: json['decisionNote'] as String?,
        paymentRef: json['paymentRef'] as String?,
        paidVia: json['paidVia'] as String?,
      );
}

/// What the platform owes and what can be asked for, mirroring the controller's balance payload.
class RiderBalance {
  const RiderBalance({
    required this.currency,
    required this.balance,
    required this.available,
    required this.cashFloatHeld,
    required this.minimumCashOut,
    required this.payoutIsAutomated,
    this.openCashOut,
  });

  final String currency;

  /// What the platform owes before anything is netted off.
  final double balance;

  /// What can actually be asked for, after cash the rider is still carrying. Negative means they
  /// are holding more of the platform's money than it owes them — shown that way rather than
  /// clamped, because a zero would read as having earned nothing.
  final double available;

  /// The difference: platform cash the rider is carrying.
  final double cashFloatHeld;

  final double minimumCashOut;

  /// Whether a payout happens without a person. False today — the screen must promise a manual
  /// hand-over, not an instant transfer.
  final bool payoutIsAutomated;

  /// The request already in flight, or null when there is none. Only one may be open at a time —
  /// the server answers 409 to a second.
  final CashOut? openCashOut;

  factory RiderBalance.fromJson(Map<String, dynamic> json) => RiderBalance(
        currency: json['currency'] as String? ?? '',
        balance: (json['balance'] as num?)?.toDouble() ?? 0,
        available: (json['available'] as num?)?.toDouble() ?? 0,
        cashFloatHeld: (json['cashFloatHeld'] as num?)?.toDouble() ?? 0,
        minimumCashOut: (json['minimumCashOut'] as num?)?.toDouble() ?? 0,
        payoutIsAutomated: json['payoutIsAutomated'] as bool? ?? false,
        openCashOut: json['openCashOut'] == null
            ? null
            : CashOut.fromJson(json['openCashOut'] as Map<String, dynamic>),
      );
}

/// Everything the Earnings screen needs in one call, mirroring `GET /api/rider/earnings`.
///
/// One shape rather than four, because the screen renders them together: a balance from one moment
/// beside a total from another reads as the arithmetic not adding up.
class RiderEarnings {
  const RiderEarnings({
    required this.currency,
    required this.zone,
    required this.today,
    required this.thisWeek,
    required this.series,
    required this.balance,
  });

  final String currency;

  /// The timezone the days were bucketed in — the server's default unless the app asked for one.
  final String zone;

  final EarningsTotal today;
  final EarningsTotal thisWeek;
  final List<EarningsDay> series;
  final RiderBalance balance;

  factory RiderEarnings.fromJson(Map<String, dynamic> json) => RiderEarnings(
        currency: json['currency'] as String? ?? '',
        zone: json['zone'] as String? ?? '',
        today: EarningsTotal.fromJson(json['today'] as Map<String, dynamic>? ?? <String, dynamic>{}),
        thisWeek:
            EarningsTotal.fromJson(json['thisWeek'] as Map<String, dynamic>? ?? <String, dynamic>{}),
        series: (json['series'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => EarningsDay.fromJson(e as Map<String, dynamic>))
            .toList(),
        balance:
            RiderBalance.fromJson(json['balance'] as Map<String, dynamic>? ?? <String, dynamic>{}),
      );
}

/// How a tip reached the rider, mirroring `RiderEarningsService.TipMethod`.
enum TipMethod {
  /// Notes handed over at the door. Recorded so it shows in earnings, and deliberately excluded
  /// from the balance — the platform never held this money.
  cash('CASH', 'Cash at the door'),

  /// Charged by the platform and owed to the rider. Refused by the server until a payment
  /// processor is configured — a client should not offer it while that is so.
  online('ONLINE', 'Online');

  const TipMethod(this.wire, this.label);

  final String wire;
  final String label;
}

/// The confirmation a customer gets back after tipping.
///
/// Deliberately without the rider's id — the server never echoes it, so a customer cannot use the
/// tip endpoint to read a rider's identifier.
class TipReceipt {
  const TipReceipt({
    required this.orderId,
    required this.amount,
    required this.currency,
    this.tippedAt,
  });

  final String orderId;
  final double amount;
  final String currency;
  final DateTime? tippedAt;

  factory TipReceipt.fromJson(Map<String, dynamic> json) => TipReceipt(
        orderId: json['orderId'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String? ?? '',
        tippedAt: RiderJob._date(json['tippedAt']),
      );
}
