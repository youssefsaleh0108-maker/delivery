/// A delivery company's cash: what its riders hold for it, the hand-overs at its hub, and what it
/// owes the platform. Mirrors `/api/accounting/carrier/cash` and the Back Office's
/// `/api/accounting/float/carriers`.
///
/// Every amount is a [Money] — the server's own two-decimal string — and never a double, for the
/// reason [Money] gives: this is cash somebody is asked to hand over, and the only safe thing a
/// client can do with the figure is show the digits the ledger computed. A missing figure parses to
/// null and must render as unknown, never as zero.
library;

import 'statement_models.dart' show Money;

/// Where one rider stands with their company.
enum RiderCashStanding {
  /// Holding the company's cash, inside the limit.
  holding('HOLDING'),

  /// Holding cash older than the server's limit.
  overdue('OVERDUE'),

  /// Holding none of the company's cash.
  settled('SETTLED'),

  /// A standing this build predates. Shown as neither late nor square.
  unknown('UNKNOWN');

  const RiderCashStanding(this.wire);

  final String wire;

  static RiderCashStanding fromWire(Object? value) => RiderCashStanding.values.firstWhere(
        (RiderCashStanding s) => s.wire == value,
        orElse: () => RiderCashStanding.unknown,
      );
}

/// How a hand-over or a payment was made. Recorded only — nothing moves money because of it.
enum CashMethod {
  cash('CASH'),
  bankDeposit('BANK_DEPOSIT'),
  wallet('WALLET');

  const CashMethod(this.wire);

  final String wire;

  /// Null for a method this build does not know, rather than a guess.
  static CashMethod? fromWire(Object? value) {
    for (final CashMethod m in CashMethod.values) {
      if (m.wire == value) return m;
    }
    return null;
  }
}

/// The page's four headline figures.
class CarrierCashTotals {
  const CarrierCashTotals({
    required this.withRiders,
    required this.ridersHolding,
    required this.handedOver,
    required this.handovers,
    required this.held,
    required this.heldOrders,
    required this.overdue,
    required this.overdueRiders,
  });

  /// Cash the company's riders still hold for it, right now.
  final Money? withRiders;
  final int ridersHolding;

  /// What riders handed to the company on the day asked about.
  final Money? handedOver;
  final int handovers;

  /// What the company itself holds — handed over and not yet paid. What it owes the platform now.
  final Money? held;
  final int heldOrders;

  /// Cash with riders past the limit, counted per collection.
  final Money? overdue;
  final int overdueRiders;

  factory CarrierCashTotals.fromJson(Map<String, dynamic> json) => CarrierCashTotals(
        withRiders: Money.parse(json['withRiders']),
        ridersHolding: _int(json['ridersHolding']),
        handedOver: Money.parse(json['handedOver']),
        handovers: _int(json['handovers']),
        held: Money.parse(json['held']),
        heldOrders: _int(json['heldOrders']),
        overdue: Money.parse(json['overdue']),
        overdueRiders: _int(json['overdueRiders']),
      );
}

/// One rider's line on the reconciliation page.
class RiderCashLine {
  const RiderCashLine({
    required this.riderRef,
    required this.name,
    required this.collected,
    required this.collections,
    required this.earned,
    required this.jobs,
    required this.holding,
    required this.orders,
    required this.oldest,
    required this.lastHandoverAt,
    required this.standing,
    required this.overdueHours,
  });

  final String riderRef;

  /// What the platform's directory calls them, or null. Callers fall back to a short ref.
  final String? name;

  /// Door cash they took for the company on the day.
  final Money? collected;
  final int collections;

  /// What the platform credited the company for their jobs on the day.
  final Money? earned;
  final int jobs;

  /// The company's cash they hold now, whenever they took it — what a hand-over clears.
  final Money? holding;
  final int orders;
  final DateTime? oldest;
  final DateTime? lastHandoverAt;
  final RiderCashStanding standing;

  /// How long the oldest cash has been held, only when that is past the limit.
  final int? overdueHours;

  /// Whether there is anything to hand over. An unreadable balance is not "nothing".
  bool get hasCash => holding != null && !holding!.isZero;

  factory RiderCashLine.fromJson(Map<String, dynamic> json) => RiderCashLine(
        riderRef: json['riderRef'] as String,
        name: _text(json['name']),
        collected: Money.parse(json['collected']),
        collections: _int(json['collections']),
        earned: Money.parse(json['earned']),
        jobs: _int(json['jobs']),
        holding: Money.parse(json['holding']),
        orders: _int(json['orders']),
        oldest: _date(json['oldest']),
        lastHandoverAt: _date(json['lastHandoverAt']),
        standing: RiderCashStanding.fromWire(json['standing']),
        overdueHours: (json['overdueHours'] as num?)?.toInt(),
      );
}

/// The reconciliation page.
class CarrierCashOverview {
  const CarrierCashOverview({
    required this.day,
    required this.currency,
    required this.overdueAfterHours,
    required this.totals,
    required this.riders,
  });

  /// `yyyy-MM-dd`, the day the day-scoped figures cover.
  final String day;
  final String currency;

  /// The server's limit — the same one the Back Office flags with.
  final int overdueAfterHours;
  final CarrierCashTotals totals;
  final List<RiderCashLine> riders;

  factory CarrierCashOverview.fromJson(Map<String, dynamic> json) => CarrierCashOverview(
        day: json['day'] as String? ?? '',
        currency: json['currency'] as String? ?? '',
        overdueAfterHours: _int(json['overdueAfterHours']),
        totals: CarrierCashTotals.fromJson(
            json['totals'] as Map<String, dynamic>? ?? <String, dynamic>{}),
        riders: (json['riders'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic r) => RiderCashLine.fromJson(r as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// One order's cash still in a rider's bag.
class HeldCollection {
  const HeldCollection({
    required this.orderId,
    required this.amount,
    required this.collectedAt,
    required this.earned,
    required this.overdue,
  });

  final String? orderId;
  final Money? amount;
  final DateTime? collectedAt;

  /// The company's credit for the job, or null when the ledger holds none — not zero.
  final Money? earned;
  final bool overdue;

  factory HeldCollection.fromJson(Map<String, dynamic> json) => HeldCollection(
        orderId: _text(json['orderId']),
        amount: Money.parse(json['amount']),
        collectedAt: _date(json['collectedAt']),
        earned: Money.parse(json['earned']),
        overdue: json['overdue'] == true,
      );
}

/// A recorded hand-over from a rider to their company.
class CashHandover {
  const CashHandover({
    required this.id,
    required this.riderRef,
    required this.riderName,
    required this.amount,
    required this.collections,
    required this.method,
    required this.note,
    required this.recordedByName,
    required this.at,
  });

  final String id;
  final String riderRef;
  final String? riderName;
  final Money? amount;
  final int collections;
  final CashMethod? method;
  final String? note;

  /// Who at the company recorded it, by name, or null when the directory knows none.
  final String? recordedByName;
  final DateTime? at;

  factory CashHandover.fromJson(Map<String, dynamic> json) => CashHandover(
        id: json['id'] as String,
        riderRef: json['riderRef'] as String? ?? '',
        riderName: _text(json['riderName']),
        amount: Money.parse(json['amount']),
        collections: _int(json['collections']),
        method: CashMethod.fromWire(json['method']),
        note: _text(json['note']),
        recordedByName: _text(json['recordedByName']),
        at: _date(json['at']),
      );
}

/// One rider's settlement page.
class RiderCashSettlement {
  const RiderCashSettlement({
    required this.riderRef,
    required this.name,
    required this.currency,
    required this.overdueAfterHours,
    required this.holding,
    required this.earnedOnHeld,
    required this.standing,
    required this.overdueHours,
    required this.firstSeenAt,
    required this.held,
    required this.handovers,
  });

  final String riderRef;
  final String? name;
  final String currency;
  final int overdueAfterHours;

  /// What they hold for the company now: exactly what a hand-over will clear.
  final Money? holding;

  /// What the platform credited the company for the jobs behind that cash, where it has a figure.
  /// None of it is the rider's to keep.
  final Money? earnedOnHeld;
  final RiderCashStanding standing;
  final int? overdueHours;

  /// When they first carried cash for the company, as far as the server can tell.
  final DateTime? firstSeenAt;
  final List<HeldCollection> held;

  /// Newest first.
  final List<CashHandover> handovers;

  bool get hasCash => holding != null && !holding!.isZero;

  factory RiderCashSettlement.fromJson(Map<String, dynamic> json) => RiderCashSettlement(
        riderRef: json['riderRef'] as String,
        name: _text(json['name']),
        currency: json['currency'] as String? ?? '',
        overdueAfterHours: _int(json['overdueAfterHours']),
        holding: Money.parse(json['holding']),
        earnedOnHeld: Money.parse(json['earnedOnHeld']),
        standing: RiderCashStanding.fromWire(json['standing']),
        overdueHours: (json['overdueHours'] as num?)?.toInt(),
        firstSeenAt: _date(json['firstSeenAt']),
        held: (json['held'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic h) => HeldCollection.fromJson(h as Map<String, dynamic>))
            .toList(growable: false),
        handovers: (json['handovers'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic h) => CashHandover.fromJson(h as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// What a recorded hand-over came back as.
class HandoverReceipt {
  const HandoverReceipt({
    required this.handoverId,
    required this.riderRef,
    required this.amount,
    required this.collections,
    required this.replayed,
  });

  final String handoverId;
  final String riderRef;
  final Money? amount;
  final int collections;

  /// True when this answered a repeated request key: the hand-over was already recorded, once.
  final bool replayed;

  factory HandoverReceipt.fromJson(Map<String, dynamic> json) => HandoverReceipt(
        handoverId: json['handoverId'] as String,
        riderRef: json['riderRef'] as String? ?? '',
        amount: Money.parse(json['amount']),
        collections: _int(json['collections']),
        replayed: json['replayed'] == true,
      );
}

/// One payment a company made to the platform.
class CarrierPayment {
  const CarrierPayment({
    required this.id,
    required this.amount,
    required this.collections,
    required this.method,
    required this.at,
  });

  final String id;
  final Money? amount;
  final int collections;
  final CashMethod? method;
  final DateTime? at;

  factory CarrierPayment.fromJson(Map<String, dynamic> json) => CarrierPayment(
        id: json['id'] as String,
        amount: Money.parse(json['amount']),
        collections: _int(json['collections']),
        method: CashMethod.fromWire(json['method']),
        at: _date(json['at']),
      );
}

/// What a company owes the platform, and what it has paid.
class CarrierCashOwed {
  const CarrierCashOwed({
    required this.currency,
    required this.held,
    required this.orders,
    required this.oldest,
    required this.overdue,
    required this.withRiders,
    required this.ridersHolding,
    required this.payments,
  });

  final String currency;

  /// Handed over by its riders and not yet paid — owed now.
  final Money? held;
  final int orders;
  final DateTime? oldest;
  final bool overdue;

  /// Still in its riders' pockets: answered for, but not owed until handed over. Never add the two.
  final Money? withRiders;
  final int ridersHolding;

  /// Newest first.
  final List<CarrierPayment> payments;

  factory CarrierCashOwed.fromJson(Map<String, dynamic> json) => CarrierCashOwed(
        currency: json['currency'] as String? ?? '',
        held: Money.parse(json['held']),
        orders: _int(json['orders']),
        oldest: _date(json['oldest']),
        overdue: json['overdue'] == true,
        withRiders: Money.parse(json['withRiders']),
        ridersHolding: _int(json['ridersHolding']),
        payments: (json['payments'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic p) => CarrierPayment.fromJson(p as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// One delivery company's cash, as the Back Office lists it.
class CarrierCashHolding {
  const CarrierCashHolding({
    required this.carrierRef,
    required this.held,
    required this.orders,
    required this.oldest,
    required this.overdue,
    required this.withRiders,
    required this.ridersHolding,
    required this.lastPaidAt,
  });

  /// The company's provider id.
  final String carrierRef;

  /// What the company holds and owes the platform now — what a payment is recorded against.
  final Money? held;
  final int orders;
  final DateTime? oldest;
  final bool overdue;

  /// What its riders still hold for it. Reported beside [held], never added to it.
  final Money? withRiders;
  final int ridersHolding;
  final DateTime? lastPaidAt;

  bool get holdsCash => held != null && !held!.isZero;

  factory CarrierCashHolding.fromJson(Map<String, dynamic> json) => CarrierCashHolding(
        carrierRef: json['carrierRef'] as String,
        held: Money.parse(json['held']),
        orders: _int(json['orders']),
        oldest: _date(json['oldest']),
        overdue: json['overdue'] == true,
        withRiders: Money.parse(json['withRiders']),
        ridersHolding: _int(json['ridersHolding']),
        lastPaidAt: _date(json['lastPaidAt']),
      );
}

/// The balance was not what the person confirming had counted, so nothing was recorded.
///
/// Carries the current figure, because "the amount changed" with no new amount is an instruction
/// nobody can follow.
class CashAmountChanged implements Exception {
  const CashAmountChanged(this.current);

  /// What is held now, or null if the server did not say.
  final Money? current;

  @override
  String toString() => 'CashAmountChanged(${current?.amount ?? '?'})';
}

int _int(Object? value) => (value as num?)?.toInt() ?? 0;

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;
