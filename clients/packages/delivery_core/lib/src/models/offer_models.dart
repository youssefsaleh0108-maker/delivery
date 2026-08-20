/// Who stops paying, and therefore which fee the platform absorbs.
enum OfferAudience {
  /// The customer is not charged the delivery fee. The carrier still gets it.
  customer,

  /// No commission is taken from the merchant. They keep the whole goods amount.
  merchant,

  /// No platform cut of the delivery fee. The delivery company keeps all of it.
  carrier;

  String get wire => switch (this) {
        OfferAudience.customer => 'CUSTOMER',
        OfferAudience.merchant => 'MERCHANT',
        OfferAudience.carrier => 'CARRIER',
      };

  static OfferAudience parse(String? value) => switch (value) {
        'MERCHANT' => OfferAudience.merchant,
        'CARRIER' => OfferAudience.carrier,
        _ => OfferAudience.customer,
      };
}

/// A fee the platform has agreed to absorb.
class FeeWaiverOffer {
  const FeeWaiverOffer({
    required this.id,
    required this.audience,
    required this.title,
    required this.active,
    required this.live,
    required this.minSubtotal,
    required this.startsAt,
    this.subtitle,
    this.endsAt,
    this.storeId,
    this.merchantRef,
    this.providerId,
    this.createdBy,
  });

  final String id;
  final OfferAudience audience;
  final String title;
  final String? subtitle;

  /// Below this the offer does not apply.
  final double minSubtotal;

  final DateTime startsAt;

  /// Null runs until withdrawn.
  final DateTime? endsAt;

  /// Whether it has been withdrawn.
  final bool active;

  /// Whether it is applying to orders *right now* — which `active` alone does not say: an offer
  /// can be active and not yet started, or active and already over.
  final bool live;

  /// Narrowing, one per audience. Null means everyone in that audience.
  final String? storeId;
  final String? merchantRef;
  final String? providerId;

  final String? createdBy;

  factory FeeWaiverOffer.fromJson(Map<String, dynamic> json) => FeeWaiverOffer(
        id: json['id'] as String,
        audience: OfferAudience.parse(json['audience'] as String?),
        title: json['title'] as String,
        subtitle: json['subtitle'] as String?,
        minSubtotal: (json['minSubtotal'] as num?)?.toDouble() ?? 0,
        startsAt: DateTime.parse(json['startsAt'] as String).toLocal(),
        endsAt: json['endsAt'] == null
            ? null
            : DateTime.parse(json['endsAt'] as String).toLocal(),
        active: json['active'] as bool? ?? true,
        live: json['live'] as bool? ?? false,
        storeId: json['storeId'] as String?,
        merchantRef: json['merchantRef'] as String?,
        providerId: json['providerId'] as String?,
        createdBy: json['createdBy'] as String?,
      );
}

/// What a basket qualifies for, before the customer commits to it.
///
/// Asked of the server rather than worked out in the app: only the server knows whether a promotion
/// is running, whether this shop is in it, and whether the platform can still afford it.
class OfferPreview {
  const OfferPreview({
    required this.deliveryFeeWaived,
    required this.merchantFeeWaived,
    required this.deliveryFeeCharged,
    this.offerTitle,
  });

  final bool deliveryFeeWaived;
  final bool merchantFeeWaived;

  /// What the customer will actually pay for delivery.
  final double deliveryFeeCharged;

  /// What to call it on screen, so the customer knows why it is free.
  final String? offerTitle;

  factory OfferPreview.fromJson(Map<String, dynamic> json) => OfferPreview(
        deliveryFeeWaived: json['deliveryFeeWaived'] as bool? ?? false,
        merchantFeeWaived: json['merchantFeeWaived'] as bool? ?? false,
        deliveryFeeCharged: (json['deliveryFeeCharged'] as num?)?.toDouble() ?? 0,
        offerTitle: json['offerTitle'] as String?,
      );
}

/// What the platform earned over the budget window, and what it gave back.
class OfferBudget {
  const OfferBudget({
    required this.earned,
    required this.budget,
    required this.given,
    required this.givenCustomer,
    required this.givenMerchant,
    required this.givenCarrier,
    required this.remaining,
    required this.usedPercent,
    required this.kept,
    required this.capPercentage,
    required this.allowance,
    required this.windowDays,
  });

  /// What would have been kept with no offers at all. The denominator.
  final double earned;

  /// The ceiling: [capPercentage] of [earned].
  final double budget;

  final double given;
  final double givenCustomer;
  final double givenMerchant;
  final double givenCarrier;

  /// What is still available to give away. Never negative.
  final double remaining;

  /// How full the budget is, 0–100.
  final double usedPercent;

  /// What the platform actually kept — the number that pays the bills. Can be negative.
  final double kept;

  final double capPercentage;

  /// Money put behind offers regardless of revenue, so a platform with no orders yet can still run
  /// the promotion meant to bring them.
  final double allowance;

  final int windowDays;

  /// Whether the budget is spent. Nothing more will be waived until earnings catch up.
  bool get exhausted => remaining <= 0;

  factory OfferBudget.fromJson(Map<String, dynamic> json) => OfferBudget(
        earned: (json['earned'] as num?)?.toDouble() ?? 0,
        budget: (json['budget'] as num?)?.toDouble() ?? 0,
        given: (json['given'] as num?)?.toDouble() ?? 0,
        givenCustomer: (json['givenCustomer'] as num?)?.toDouble() ?? 0,
        givenMerchant: (json['givenMerchant'] as num?)?.toDouble() ?? 0,
        givenCarrier: (json['givenCarrier'] as num?)?.toDouble() ?? 0,
        remaining: (json['remaining'] as num?)?.toDouble() ?? 0,
        usedPercent: (json['usedPercent'] as num?)?.toDouble() ?? 0,
        kept: (json['kept'] as num?)?.toDouble() ?? 0,
        capPercentage: (json['capPercentage'] as num?)?.toDouble() ?? 0,
        allowance: (json['allowance'] as num?)?.toDouble() ?? 0,
        windowDays: (json['windowDays'] as num?)?.toInt() ?? 30,
      );
}
