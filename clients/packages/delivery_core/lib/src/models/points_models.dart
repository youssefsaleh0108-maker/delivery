/// The points ledger as the clients read it.
library;

/// One movement: earned on an order, adjusted, or held for a redemption.
class PointsEntry {
  const PointsEntry({
    required this.points,
    required this.reason,
    this.orderId,
    this.createdAt,
  });

  /// Signed: an earn is positive, a redemption hold negative.
  final int points;

  /// The wire reason, e.g. `ORDER_EARNED`, `REDEMPTION_HOLD`.
  final String reason;

  final String? orderId;
  final DateTime? createdAt;

  factory PointsEntry.fromJson(Map<String, dynamic> json) => PointsEntry(
        points: (json['points'] as num).toInt(),
        reason: json['reason'] as String? ?? '',
        orderId: json['orderId'] as String?,
        createdAt: json['createdAt'] == null
            ? null
            : DateTime.tryParse(json['createdAt'] as String),
      );
}

/// The customer's loyalty standing, when the balance carries one.
class LoyaltyStanding {
  const LoyaltyStanding({
    required this.lifetimeEarned,
    required this.ordersCompleted,
    required this.tier,
    required this.tierFloor,
    this.nextTier,
    this.nextTierAt,
    required this.pointsToNextTier,
    required this.cashbackValue,
    required this.currency,
  });

  final int lifetimeEarned;
  final int ordersCompleted;

  /// Wire tier names: BRONZE, SILVER, GOLD, PLATINUM.
  final String tier;
  final int tierFloor;

  /// Null from the top rung.
  final String? nextTier;
  final int? nextTierAt;
  final int pointsToNextTier;

  /// What the SPENDABLE balance is worth at today's rate — display, not a payout.
  final double cashbackValue;
  final String currency;

  /// Progress from this tier's floor to the next one, 0..1. Full at the top rung.
  double get progressToNextTier {
    final int? nextAt = nextTierAt;
    if (nextAt == null || nextAt <= tierFloor) return 1;
    final double p = (lifetimeEarned - tierFloor) / (nextAt - tierFloor);
    return p.clamp(0, 1);
  }

  factory LoyaltyStanding.fromJson(Map<String, dynamic> json) => LoyaltyStanding(
        lifetimeEarned: (json['lifetimeEarned'] as num?)?.toInt() ?? 0,
        ordersCompleted: (json['ordersCompleted'] as num?)?.toInt() ?? 0,
        tier: json['tier'] as String? ?? 'BRONZE',
        tierFloor: (json['tierFloor'] as num?)?.toInt() ?? 0,
        nextTier: json['nextTier'] as String?,
        nextTierAt: (json['nextTierAt'] as num?)?.toInt(),
        pointsToNextTier: (json['pointsToNextTier'] as num?)?.toInt() ?? 0,
        cashbackValue: (json['cashbackValue'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String? ?? 'USD',
      );
}

/// The `/api/points/balance` answer.
class PointsBalance {
  const PointsBalance({
    required this.points,
    required this.value,
    this.loyalty,
  });

  /// The spendable balance.
  final int points;

  /// What it is worth at today's rate.
  final double value;

  /// Present only for a customer; the working kinds' points are earnings, not standing.
  final LoyaltyStanding? loyalty;

  factory PointsBalance.fromJson(Map<String, dynamic> json) => PointsBalance(
        points: (json['points'] as num?)?.toInt() ?? 0,
        value: (json['value'] as num?)?.toDouble() ?? 0,
        loyalty: json['loyalty'] == null
            ? null
            : LoyaltyStanding.fromJson(json['loyalty'] as Map<String, dynamic>),
      );
}
