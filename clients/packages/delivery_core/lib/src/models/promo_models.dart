/// Promo code models mirroring the Order Manager promotions API.
library;

/// What a code does, mirroring `com.delivery.order.domain.PromoCode.Kind`.
enum PromoKind {
  /// `value` percent off the goods. Not off delivery.
  percentOff('PERCENT_OFF', '% off'),

  /// `value` off the bill.
  amountOff('AMOUNT_OFF', 'Amount off'),

  /// The delivery fee the customer would otherwise have been charged.
  freeDelivery('FREE_DELIVERY', 'Free delivery');

  const PromoKind(this.wire, this.label);

  final String wire;
  final String label;

  /// Null for an unknown or absent kind — a quote for an invalid code carries none, and inventing
  /// one would claim a discount type the server never named.
  static PromoKind? fromWire(String? value) {
    for (final PromoKind k in PromoKind.values) {
      if (k.wire == value) return k;
    }
    return null;
  }
}

/// Why a code did or did not apply, mirroring `PromotionService.Reason`.
///
/// A stable machine-readable value so the basket can localise the sentence rather than render the
/// server's English one. [PromoQuote.message] stays available as the fallback.
enum PromoQuoteReason {
  ok('OK', 'The code was applied'),
  unknownCode('UNKNOWN_CODE', 'That code was not recognised'),
  notActive('NOT_ACTIVE', 'That code is no longer available'),
  notStarted('NOT_STARTED', 'That code cannot be used yet'),
  expired('EXPIRED', 'That code has expired'),
  belowMinimum('BELOW_MINIMUM', 'Your basket is below the minimum for that code'),
  fullyRedeemed('FULLY_REDEEMED', 'That code has been fully redeemed'),
  customerLimitReached('CUSTOMER_LIMIT_REACHED', 'You have already used that code'),
  nothingToDiscount('NOTHING_TO_DISCOUNT', 'That code is worth nothing on this order'),

  /// A reason this client does not know yet. Rendered as "did not apply", never as a discount.
  unknown('UNKNOWN', 'That code did not apply');

  const PromoQuoteReason(this.wire, this.label);

  final String wire;
  final String label;

  static PromoQuoteReason fromWire(String? value) => PromoQuoteReason.values.firstWhere(
        (PromoQuoteReason r) => r.wire == value,
        orElse: () => PromoQuoteReason.unknown,
      );
}

/// What a code would be worth on this basket, mirroring `PromotionController.ValidateResponse`.
///
/// Advisory by design: the number here decides what the Discounts line shows while the customer is
/// still typing. The discount actually applied is recomputed at placement against the basket the
/// server priced itself, so this can be shown without ever being trusted.
class PromoQuote {
  const PromoQuote({
    required this.valid,
    required this.reason,
    required this.discount,
    this.message,
    this.code,
    this.kind,
  });

  /// Whether the code would apply to this basket.
  final bool valid;

  /// Why, or why not. [PromoQuoteReason.ok] exactly when [valid] is true.
  final PromoQuoteReason reason;

  /// The server's own English sentence for [reason]. A fallback for a reason this build does not
  /// know; null when the server sent none.
  final String? message;

  /// The canonical stored code — never the string the customer typed. Null when the code was not
  /// recognised, because there is nothing canonical to echo.
  final String? code;

  /// What sort of discount it is. Null when [valid] is false.
  final PromoKind? kind;

  /// What would come off, already clamped server-side so it can never exceed the basket. Zero when
  /// the code does not apply.
  final double discount;

  factory PromoQuote.fromJson(Map<String, dynamic> json) => PromoQuote(
        valid: json['valid'] as bool? ?? false,
        reason: PromoQuoteReason.fromWire(json['reason'] as String?),
        message: json['message'] as String?,
        code: json['code'] as String?,
        kind: PromoKind.fromWire(json['kind'] as String?),
        discount: (json['discount'] as num?)?.toDouble() ?? 0,
      );
}

/// One code on the operator's register, mirroring `PromotionController.CodeResponse`.
///
/// BACKOFFICE only — a customer never sees this shape, only [PromoQuote].
class PromoCodeDetails {
  const PromoCodeDetails({
    required this.id,
    required this.code,
    required this.kind,
    required this.redeemedCount,
    required this.givenAway,
    required this.active,
    required this.live,
    this.value,
    this.minSubtotal,
    this.startsAt,
    this.endsAt,
    this.maxRedemptions,
    this.maxPerCustomer,
    this.createdBy,
    this.createdAt,
  });

  final String id;
  final String code;

  /// Falls back to [PromoKind.amountOff] rather than null: a register row without a kind cannot be
  /// rendered at all, and amount-off is the reading that claims the least.
  final PromoKind kind;

  /// Percent for [PromoKind.percentOff], money for [PromoKind.amountOff]. Null for
  /// [PromoKind.freeDelivery], where the shop's own fee is the value.
  final double? value;

  /// The basket floor. Null means no minimum.
  final double? minSubtotal;

  /// Null means it started the moment it was created.
  final DateTime? startsAt;

  /// Null means it runs until it is withdrawn.
  final DateTime? endsAt;

  /// Null is unlimited.
  final int? maxRedemptions;

  /// Null is unlimited.
  final int? maxPerCustomer;

  /// How many times it has been used, against [maxRedemptions].
  final int redeemedCount;

  /// What it has cost the platform so far.
  final double givenAway;

  /// Whether the operator has withdrawn it.
  final bool active;

  /// Whether it is applying to orders right now — which [active] alone does not say, because a
  /// code can be active and not yet started.
  final bool live;

  final String? createdBy;
  final DateTime? createdAt;

  factory PromoCodeDetails.fromJson(Map<String, dynamic> json) => PromoCodeDetails(
        id: json['id'] as String,
        code: json['code'] as String? ?? '',
        kind: PromoKind.fromWire(json['kind'] as String?) ?? PromoKind.amountOff,
        value: (json['value'] as num?)?.toDouble(),
        minSubtotal: (json['minSubtotal'] as num?)?.toDouble(),
        startsAt: _date(json['startsAt']),
        endsAt: _date(json['endsAt']),
        maxRedemptions: (json['maxRedemptions'] as num?)?.toInt(),
        maxPerCustomer: (json['maxPerCustomer'] as num?)?.toInt(),
        redeemedCount: (json['redeemedCount'] as num?)?.toInt() ?? 0,
        givenAway: (json['givenAway'] as num?)?.toDouble() ?? 0,
        active: json['active'] as bool? ?? false,
        live: json['live'] as bool? ?? false,
        createdBy: json['createdBy'] as String?,
        createdAt: _date(json['createdAt']),
      );

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}
