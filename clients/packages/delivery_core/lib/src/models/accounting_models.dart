/// Accounting models mirroring the reconciliation API (Phase 4).
library;

import 'statement_models.dart' show Money;

/// Which part of a settlement a transaction row is.
///
/// Mirrors `AccountingTransaction.Leg`, and mirrors ALL of it. It used to list four of the ten the
/// service writes, so the back-office ledger called the other six "Unknown" — including both rows
/// dev was listing as unsettled, which were cash remittances. When the service adds a leg, add it
/// here: `settlement_wire_values_test.dart` is the reminder.
///
/// [label] is the English wording, one place for it rather than one per screen; the portal renders
/// a translated one and falls back to this. A value this client has never heard of decodes to
/// [unknown] and is shown by its own wire name — see [AccountingTransaction.legName] — because
/// "CUSTOMER_REFUND" tells an operator something and "Unknown" tells them nothing.
enum SettlementLeg {
  customerDebit('CUSTOMER_DEBIT', 'Customer charged'),
  cashCollected('CASH_COLLECTED', 'Cash taken at the door'),
  merchantCredit('MERCHANT_CREDIT', 'Merchant payout'),
  giftWrapCredit('GIFT_WRAP_CREDIT', 'Gift wrapping'),
  riderCredit('RIDER_CREDIT', 'Rider payout'),
  providerCredit('PROVIDER_CREDIT', 'Delivery company payout'),
  platformCommission('PLATFORM_COMMISSION', 'Commission'),
  platformSubsidy('PLATFORM_SUBSIDY', 'Platform contribution'),
  platformLoss('PLATFORM_LOSS', 'Absorbed after pickup'),
  cashRemittance('CASH_REMITTANCE', 'Cash banked'),
  payout('PAYOUT', 'Paid out'),
  customerRefund('CUSTOMER_REFUND', 'Refund'),
  unknown('UNKNOWN', 'Unknown');

  const SettlementLeg(this.wire, this.label);

  final String wire;
  final String label;

  static SettlementLeg fromWire(String value) => SettlementLeg.values.firstWhere(
        (SettlementLeg l) => l.wire == value,
        orElse: () => SettlementLeg.unknown,
      );
}

/// Mirrors `AccountingTransaction.Status`, and mirrors all of it.
///
/// `SETTLED_IN_CASH` was missing, which is the status of nearly every row the platform writes:
/// with no bank deployed, settlement discharges each leg as it is written. So the ledger called
/// them "Unknown" and no tile or filter could reach them.
enum SettlementStatus {
  /// Created, not yet confirmed by the bank.
  pending('PENDING', 'Pending'),

  /// The bank moved the money.
  posted('POSTED', 'Posted'),

  /// Discharged without a bank: cash at the door, or a platform that has no bank connector.
  ///
  /// Done, and done successfully — as complete as POSTED, and the commoner of the two here. A
  /// screen that treats only POSTED as settled reports a working platform as having settled
  /// nothing.
  settledInCash('SETTLED_IN_CASH', 'Settled in cash'),

  /// The bank refused, or the platform gave up. Recoverable by an operator.
  failed('FAILED', 'Failed'),

  /// Was posted, then reversed because the rest of the settlement could not complete.
  compensated('COMPENSATED', 'Reversed'),

  /// Never posted and never will be — the settlement was unwound around it.
  abandoned('ABANDONED', 'Abandoned'),

  unknown('UNKNOWN', 'Unknown');

  const SettlementStatus(this.wire, this.label);

  final String wire;
  final String label;

  static SettlementStatus fromWire(String value) => SettlementStatus.values.firstWhere(
        (SettlementStatus s) => s.wire == value,
        orElse: () => SettlementStatus.unknown,
      );

  /// Whether this row still needs somebody to do something about it.
  bool get needsAttention => this == pending || this == failed;

  /// Whether the money reached whoever it was for, however it was discharged.
  bool get isSettled => this == posted || this == settledInCash;
}

class AccountingTransaction {
  const AccountingTransaction({
    required this.id,
    required this.orderId,
    required this.leg,
    required this.accountRef,
    required this.amount,
    required this.currency,
    required this.direction,
    required this.status,
    required this.attempts,
    required this.createdAt,
    this.coreBankingRef,
    this.failureReason,
    this.postedAt,
    String? legWire,
    String? statusWire,
  })  : legWire = legWire ?? '',
        statusWire = statusWire ?? '';

  final String id;
  final String orderId;
  final SettlementLeg leg;

  /// What the server called this leg, kept whether or not [leg] recognised it.
  ///
  /// A value newer than this build decodes to [SettlementLeg.unknown], and the screen shows this
  /// instead: an operator can act on "GIFT_WRAP_CREDIT" and can do nothing with "Unknown".
  final String legWire;
  final String accountRef;
  final double amount;
  final String currency;
  final String direction;
  final SettlementStatus status;

  /// What the server called this status, kept for the same reason as [legWire].
  final String statusWire;

  /// The bank's own identifier. This is the number quoted in a dispute.
  final String? coreBankingRef;
  final String? failureReason;
  final int attempts;
  final DateTime createdAt;
  final DateTime? postedAt;

  bool get isDebit => direction == 'DEBIT';

  /// What to call this leg on screen when no translation is to hand: its name, or the server's own
  /// word for a leg this build has never heard of.
  String get legName => leg == SettlementLeg.unknown && legWire.isNotEmpty ? legWire : leg.label;

  /// The same for the status.
  String get statusName =>
      status == SettlementStatus.unknown && statusWire.isNotEmpty ? statusWire : status.label;

  factory AccountingTransaction.fromJson(Map<String, dynamic> json) => AccountingTransaction(
        id: json['id'] as String,
        orderId: json['orderId'] as String,
        leg: SettlementLeg.fromWire(json['leg'] as String? ?? 'UNKNOWN'),
        legWire: json['leg'] as String?,
        statusWire: json['status'] as String?,
        accountRef: json['accountRef'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String? ?? 'USD',
        direction: json['direction'] as String? ?? 'DEBIT',
        status: SettlementStatus.fromWire(json['status'] as String? ?? 'UNKNOWN'),
        coreBankingRef: json['coreBankingRef'] as String?,
        failureReason: json['failureReason'] as String?,
        attempts: json['attempts'] as int? ?? 0,
        createdAt: _date(json['createdAt']) ?? DateTime.now(),
        postedAt: _date(json['postedAt']),
      );
}

/// The landing view's numbers.
///
/// [amountAtRisk] is the one that matters: value debited from customers but not yet paid out, or
/// that failed on the way. A count of rows does not convey that; an amount does.
///
/// Each status carries its two sides apart (RECON-13). An order's debits and its credits are the
/// same money described twice, so a figure that added them reported every unfinished settlement at
/// double its worth; the server sends [debits] and [credits] and adds neither to the other.
class ReconciliationSummary {
  const ReconciliationSummary({
    required this.byStatus,
    required this.unsettledCount,
    required this.amountAtRisk,
  });

  final Map<SettlementStatus, ({int count, double debits, double credits})> byStatus;
  final int unsettledCount;
  final double amountAtRisk;

  bool get isClean => unsettledCount == 0;

  /// How many rows are in this status, whichever way they point.
  int countOf(SettlementStatus status) => byStatus[status]?.count ?? 0;

  factory ReconciliationSummary.fromJson(Map<String, dynamic> json) {
    final Map<SettlementStatus, ({int count, double debits, double credits})> byStatus =
        <SettlementStatus, ({int count, double debits, double credits})>{};

    (json['byStatus'] as Map<String, dynamic>? ?? <String, dynamic>{})
        .forEach((String key, dynamic value) {
      final Map<String, dynamic> entry = value as Map<String, dynamic>;
      // A server from before the split sent one "amount" that was the two sides added together.
      // It is deliberately not read: the counts are what the tiles show, and that figure was the
      // bug.
      byStatus[SettlementStatus.fromWire(key)] = (
        count: (entry['count'] as num?)?.toInt() ?? 0,
        debits: (entry['debits'] as num?)?.toDouble() ?? 0,
        credits: (entry['credits'] as num?)?.toDouble() ?? 0,
      );
    });

    return ReconciliationSummary(
      byStatus: byStatus,
      unsettledCount: (json['unsettledCount'] as num?)?.toInt() ?? 0,
      amountAtRisk: (json['amountAtRisk'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// One conversation with the bank about one leg.
class SyncLogEntry {
  const SyncLogEntry({
    required this.id,
    required this.outcome,
    required this.syncedAt,
    this.provider,
    this.requestPayload,
    this.responsePayload,
  });

  final String id;
  final String? provider;
  final String outcome;
  final String? requestPayload;
  final String? responsePayload;
  final DateTime syncedAt;

  factory SyncLogEntry.fromJson(Map<String, dynamic> json) => SyncLogEntry(
        id: json['id'] as String,
        provider: json['provider'] as String?,
        outcome: json['outcome'] as String? ?? 'UNKNOWN',
        requestPayload: json['requestPayload']?.toString(),
        responsePayload: json['responsePayload']?.toString(),
        syncedAt: _date(json['syncedAt']) ?? DateTime.now(),
      );
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

/// Somebody holding platform cash that has not reached a bank account yet.
///
/// A cash collection creates an obligation and deliberately touches no bank, because no bank saw
/// it. This is the record of that obligation until the takings are banked.
class CashHolder {
  const CashHolder({
    required this.holderRef,
    required this.holderKind,
    required this.amount,
    required this.orders,
    required this.oldest,
    this.overdue,
    this.owed,
    this.carrierRef,
  });

  final String holderRef;

  /// RIDER; PROVIDER for a delivery company holding what its riders handed it; or MERCHANT for a
  /// shop holding what its counter took for pickup orders.
  final String holderKind;

  /// The delivery company a rider's line is owed to, or null when the line is owed to the platform.
  ///
  /// A rider can carry the platform's cash and a company's at once, and the server lists each debt
  /// as its own line (RECON-03). A company's line is the company's to take in at its hub, never the
  /// platform's to record as banked.
  final String? carrierRef;

  final double amount;
  final int orders;

  /// When the oldest uncleared collection was taken.
  ///
  /// The part actually worth watching: a large balance collected this morning is a working day,
  /// and the same balance collected three weeks ago is a problem.
  final DateTime oldest;

  /// Whether the server's own limit calls this late. Null from a server that predates the field,
  /// in which case the screen falls back to its own rule.
  final bool? overdue;

  /// The figure a payment through the remit route is recorded against, exactly as the ledger wrote
  /// it: what the operator confirms.
  ///
  /// For a shop it is what the shop owes out of its till — the platform's commission; the rest of
  /// the till is the shop's own share, which it keeps. For a rider's line owed to the platform it is
  /// the whole line. Null on a rider's line owed to a delivery company, which is not the platform's
  /// to record, and when the server did not say — never a zero.
  final Money? owed;

  /// A delivery company rather than a rider.
  bool get isCarrier => holderKind == 'PROVIDER';

  /// A shop holding cash its counter took for pickup orders, rather than a rider.
  bool get isShop => holderKind == 'MERCHANT';

  /// A rider's cash owed to their delivery company rather than to the platform (RECON-03).
  bool get isOwedToCompany => carrierRef != null;

  /// How long the oldest cash has been out.
  Duration get age => DateTime.now().difference(oldest);

  factory CashHolder.fromJson(Map<String, dynamic> json) => CashHolder(
        holderRef: json['holderRef'] as String,
        holderKind: json['holderKind'] as String? ?? 'RIDER',
        amount: (json['amount'] as num).toDouble(),
        orders: (json['orders'] as num).toInt(),
        oldest: DateTime.parse(json['oldest'] as String),
        overdue: json['overdue'] is bool ? json['overdue'] as bool : null,
        owed: Money.parse(json['owed']),
        carrierRef: json['carrierRef'] is String && (json['carrierRef'] as String).isNotEmpty
            ? json['carrierRef'] as String
            : null,
      );
}

/// What a remittance covered.
class Remittance {
  const Remittance({required this.holderRef, required this.amount, required this.collections, this.id});

  /// Null when there was nothing outstanding — banking nothing is not an error.
  final String? id;
  final String holderRef;
  final double amount;
  final int collections;

  bool get isEmpty => collections == 0;

  factory Remittance.fromJson(Map<String, dynamic> json) => Remittance(
        id: json['remittanceId'] as String?,
        holderRef: json['holderRef'] as String,
        amount: (json['amount'] as num).toDouble(),
        collections: (json['collections'] as num).toInt(),
      );
}