/// Accounting models mirroring the reconciliation API (Phase 4).
library;

/// Which part of a settlement a transaction row is.
///
/// Mirrors `AccountingTransaction.Leg`. Kept as an enum with a label rather than a raw string so
/// three screens cannot each invent their own wording for "PLATFORM_COMMISSION".
enum SettlementLeg {
  customerDebit('CUSTOMER_DEBIT', 'Customer charged'),
  merchantCredit('MERCHANT_CREDIT', 'Merchant payout'),
  platformCommission('PLATFORM_COMMISSION', 'Commission'),
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

/// Mirrors `AccountingTransaction.Status`.
enum SettlementStatus {
  /// Created, not yet confirmed by the bank.
  pending('PENDING', 'Pending'),

  /// The bank moved the money.
  posted('POSTED', 'Posted'),

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
  });

  final String id;
  final String orderId;
  final SettlementLeg leg;
  final String accountRef;
  final double amount;
  final String currency;
  final String direction;
  final SettlementStatus status;

  /// The bank's own identifier. This is the number quoted in a dispute.
  final String? coreBankingRef;
  final String? failureReason;
  final int attempts;
  final DateTime createdAt;
  final DateTime? postedAt;

  bool get isDebit => direction == 'DEBIT';

  factory AccountingTransaction.fromJson(Map<String, dynamic> json) => AccountingTransaction(
        id: json['id'] as String,
        orderId: json['orderId'] as String,
        leg: SettlementLeg.fromWire(json['leg'] as String? ?? 'UNKNOWN'),
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
class ReconciliationSummary {
  const ReconciliationSummary({
    required this.byStatus,
    required this.unsettledCount,
    required this.amountAtRisk,
  });

  final Map<SettlementStatus, ({int count, double amount})> byStatus;
  final int unsettledCount;
  final double amountAtRisk;

  bool get isClean => unsettledCount == 0;

  factory ReconciliationSummary.fromJson(Map<String, dynamic> json) {
    final Map<SettlementStatus, ({int count, double amount})> byStatus =
        <SettlementStatus, ({int count, double amount})>{};

    (json['byStatus'] as Map<String, dynamic>? ?? <String, dynamic>{})
        .forEach((String key, dynamic value) {
      final Map<String, dynamic> entry = value as Map<String, dynamic>;
      byStatus[SettlementStatus.fromWire(key)] = (
        count: (entry['count'] as num?)?.toInt() ?? 0,
        amount: (entry['amount'] as num?)?.toDouble() ?? 0,
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
  });

  final String holderRef;

  /// RIDER today; PROVIDER once a delivery company collects its own COD.
  final String holderKind;
  final double amount;
  final int orders;

  /// When the oldest uncleared collection was taken.
  ///
  /// The part actually worth watching: a large balance collected this morning is a working day,
  /// and the same balance collected three weeks ago is a problem.
  final DateTime oldest;

  /// How long the oldest cash has been out.
  Duration get age => DateTime.now().difference(oldest);

  factory CashHolder.fromJson(Map<String, dynamic> json) => CashHolder(
        holderRef: json['holderRef'] as String,
        holderKind: json['holderKind'] as String? ?? 'RIDER',
        amount: (json['amount'] as num).toDouble(),
        orders: (json['orders'] as num).toInt(),
        oldest: DateTime.parse(json['oldest'] as String),
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