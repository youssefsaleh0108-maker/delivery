/// Client-side mirrors of the delivery-provider DTOs.
///
/// A provider is whoever carries an order to the door. The platform's own fleet is one of these
/// rather than a special case, which is what lets a merchant choose between carriers at all.
library;

enum ProviderKind {
  /// The platform's own riders. Not paid separately, because the platform is already paid.
  platform('PLATFORM', 'In-house'),

  /// An independent delivery company, working for whoever books them.
  external('EXTERNAL', 'Delivery company'),

  /// A merchant's own drivers, working only for that merchant.
  merchant('MERCHANT', 'Own drivers');

  const ProviderKind(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static ProviderKind fromWire(String? value) =>
      ProviderKind.values.firstWhere((ProviderKind k) => k.wireValue == value,
          orElse: () => ProviderKind.external);
}

enum ProviderStatus {
  active('ACTIVE', 'Taking work'),

  /// Their own choice — out of hours, or at capacity.
  paused('PAUSED', 'Paused'),

  /// The platform's choice. Deliberately distinct: only one of these is theirs to undo.
  suspended('SUSPENDED', 'Suspended');

  const ProviderStatus(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static ProviderStatus fromWire(String? value) =>
      ProviderStatus.values.firstWhere((ProviderStatus s) => s.wireValue == value,
          orElse: () => ProviderStatus.active);
}

/// Whether the bank has confirmed a carrier's payout account.
///
/// There is no "refused": an account the bank rejects is never stored, because setting one is
/// refused outright. What can persist is an account nobody has managed to ask about — a bank
/// outage is not the carrier''s fault and must not block onboarding, so it is recorded instead.
enum PayoutState {
  /// No payout account at all. The in-house fleet, and any fleet nobody has set one on.
  none('NONE', 'No account'),

  /// The bank confirmed it exists and can be paid into.
  verified('VERIFIED', 'Verified'),

  /// An account is on file that nobody has been able to check.
  unconfirmed('UNCONFIRMED', 'Unconfirmed');

  const PayoutState(this.wireValue, this.label);

  final String wireValue;
  final String label;

  /// Whether somebody should go and look at this.
  bool get needsAttention => this == PayoutState.unconfirmed;

  static PayoutState fromWire(String? value) =>
      PayoutState.values.firstWhere((PayoutState s) => s.wireValue == value,
          orElse: () => PayoutState.none);
}

class DeliveryProviderInfo {
  const DeliveryProviderInfo({
    required this.id,
    required this.slug,
    required this.name,
    required this.kind,
    required this.status,
    required this.canTakeWork,
    this.ownerRef,
    this.accountRef,
    this.contactName,
    this.contactPhone,
    this.payoutState = PayoutState.none,
    this.payoutCheckedAt,
    this.payoutDetail,
    this.createdAt,
  });

  final String id;
  final String slug;
  final String name;
  final ProviderKind kind;
  final ProviderStatus status;
  final bool canTakeWork;

  /// Whose fleet it is. Set only on a merchant's own drivers.
  final String? ownerRef;

  /// Where they are paid. Null for anyone but BACKOFFICE — choosing a carrier does not require
  /// reading where that carrier banks.
  final String? accountRef;
  final String? contactName;
  final String? contactPhone;

  /// Withheld from the same audiences as [accountRef], for the same reason: it is a fact about a
  /// carrier''s banking, not about their service.
  final PayoutState payoutState;
  final DateTime? payoutCheckedAt;

  /// Why it is unconfirmed, or the name the bank has on the account.
  final String? payoutDetail;

  /// When the carrier was registered — "partner since". Sent on every view of a provider,
  /// including the public one, and optional here only because the receipt-shaped responses that
  /// predate it exist in the wild.
  final DateTime? createdAt;

  bool get isInHouse => kind == ProviderKind.platform;

  factory DeliveryProviderInfo.fromJson(Map<String, dynamic> json) => DeliveryProviderInfo(
        id: json['id'] as String,
        slug: json['slug'] as String,
        name: json['name'] as String,
        kind: ProviderKind.fromWire(json['kind'] as String?),
        status: ProviderStatus.fromWire(json['status'] as String?),
        canTakeWork: json['canTakeWork'] as bool? ?? false,
        ownerRef: json['ownerRef'] as String?,
        accountRef: json['accountRef'] as String?,
        contactName: json['contactName'] as String?,
        contactPhone: json['contactPhone'] as String?,
        payoutState: PayoutState.fromWire(json['payoutState'] as String?),
        payoutCheckedAt: json['payoutCheckedAt'] == null
            ? null
            : DateTime.parse(json['payoutCheckedAt'] as String),
        payoutDetail: json['payoutDetail'] as String?,
        createdAt: json['createdAt'] == null
            ? null
            : DateTime.tryParse(json['createdAt'] as String)?.toLocal(),
      );
}

/// Which carrier a merchant wants, and what happens when that carrier cannot take the job.
class DeliveryPolicy {
  const DeliveryPolicy({
    required this.allowFallback,
    required this.platformDecides,
    this.preferredProviderId,
  });

  final String? preferredProviderId;

  /// Whether another carrier may step in. Turning this off means an order the chosen carrier
  /// cannot take waits rather than going out with somebody else.
  final bool allowFallback;

  /// True when there is no preference at all — the state every merchant starts in.
  final bool platformDecides;

  factory DeliveryPolicy.fromJson(Map<String, dynamic> json) => DeliveryPolicy(
        preferredProviderId: json['preferredProviderId'] as String?,
        allowFallback: json['allowFallback'] as bool? ?? true,
        platformDecides: json['platformDecides'] as bool? ?? true,
      );
}

/// How a carrier is performing, as the platform measures it.
///
/// The components travel with the number on purpose. A carrier told only that they scored 61 cannot
/// act on it; "you deliver 82% of what you take, and take 14 minutes to claim" is a target.
class CarrierScore {
  const CarrierScore({
    required this.providerId,
    required this.name,
    required this.score,
    required this.orders,
    required this.completionRate,
    required this.provisional,
    this.avgSecondsToClaim,
    this.avgSecondsOnRoad,
  });

  final String providerId;
  final String name;

  /// 0-100. Completion gates it; the timings only modulate within that.
  final int score;

  /// How many orders the score is based on.
  final int orders;

  /// 0-1. Delivered over dispatched.
  final double completionRate;

  /// True while there is too little history for the score to mean much — a new carrier sits at a
  /// neutral score rather than at zero, so that it gets work and can earn a record.
  final bool provisional;

  final int? avgSecondsToClaim;
  final int? avgSecondsOnRoad;

  Duration? get timeToClaim =>
      avgSecondsToClaim == null ? null : Duration(seconds: avgSecondsToClaim!);

  Duration? get timeOnRoad =>
      avgSecondsOnRoad == null ? null : Duration(seconds: avgSecondsOnRoad!);

  factory CarrierScore.fromJson(Map<String, dynamic> json) => CarrierScore(
        providerId: json['providerId'] as String,
        name: json['name'] as String,
        score: (json['score'] as num).toInt(),
        orders: (json['orders'] as num).toInt(),
        completionRate: (json['completionRate'] as num).toDouble(),
        provisional: json['provisional'] as bool? ?? false,
        avgSecondsToClaim: (json['avgSecondsToClaim'] as num?)?.toInt(),
        avgSecondsOnRoad: (json['avgSecondsOnRoad'] as num?)?.toInt(),
      );
}
/// What a delivery company has earned, and what the work in flight is worth.
///
/// Two figures rather than one because they are different promises: delivered work is money owed,
/// work in flight is money expected, and a carrier deciding whether to take another job needs to
/// know which is which.
class CarrierEarnings {
  const CarrierEarnings({
    required this.delivered,
    required this.active,
    required this.earned,
    required this.expected,
    required this.savedByOffers,
    required this.cutPercentage,
    required this.windowDays,
  });

  final int delivered;
  final int active;

  /// What the company keeps on finished work, after the platform's cut.
  final double earned;

  /// What work in flight is worth if it all completes.
  final double expected;

  /// What the platform chose not to take, because an offer was running.
  ///
  /// Shown rather than quietly pocketed on the platform's side: a discount nobody is told about
  /// changes nothing about who a carrier chooses to work for, which is the point of granting one.
  final double savedByOffers;

  final double cutPercentage;
  final int windowDays;

  factory CarrierEarnings.fromJson(Map<String, dynamic> json) => CarrierEarnings(
        delivered: (json['delivered'] as num?)?.toInt() ?? 0,
        active: (json['active'] as num?)?.toInt() ?? 0,
        earned: (json['earned'] as num?)?.toDouble() ?? 0,
        expected: (json['expected'] as num?)?.toDouble() ?? 0,
        savedByOffers: (json['savedByOffers'] as num?)?.toDouble() ?? 0,
        cutPercentage: (json['cutPercentage'] as num?)?.toDouble() ?? 0,
        windowDays: (json['windowDays'] as num?)?.toInt() ?? 30,
      );
}

/// One circle of a carrier's working area, as the company draws it (Figma 88:107).
class CoverageZone {
  const CoverageZone({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMetres,
    required this.active,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final int radiusMetres;

  /// Off means "not tonight", not "gone" — a paused zone keeps its circle for the morning.
  final bool active;

  factory CoverageZone.fromJson(Map<String, dynamic> json) => CoverageZone(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        radiusMetres: (json['radiusMetres'] as num?)?.toInt() ?? 0,
        active: json['active'] as bool? ?? true,
      );

  CoverageZone copyWith({
    String? name,
    double? latitude,
    double? longitude,
    int? radiusMetres,
    bool? active,
  }) =>
      CoverageZone(
        id: id,
        name: name ?? this.name,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        radiusMetres: radiusMetres ?? this.radiusMetres,
        active: active ?? this.active,
      );
}
