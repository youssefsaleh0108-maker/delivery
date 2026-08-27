/// Applications to join the platform, as a reviewer sees them.
library;

/// What somebody is applying to be. The commercial relationship, not the Keycloak role.
enum OnboardingKind {
  merchant('MERCHANT', 'Shop'),
  carrier('CARRIER', 'Delivery company');

  const OnboardingKind(this.wire, this.label);

  final String wire;
  final String label;

  static OnboardingKind fromWire(String wire) =>
      OnboardingKind.values.firstWhere((OnboardingKind k) => k.wire == wire,
          orElse: () => OnboardingKind.merchant);
}

enum OnboardingStatus {
  submitted('SUBMITTED', 'Waiting'),
  inReview('IN_REVIEW', 'Being read'),
  approved('APPROVED', 'Approved'),
  rejected('REJECTED', 'Declined'),
  provisioned('PROVISIONED', 'Set up'),
  /// Approved, but setting them up did not finish. Waiting on a person, not on a retry.
  failed('FAILED', 'Setup failed');

  const OnboardingStatus(this.wire, this.label);

  final String wire;
  final String label;

  static OnboardingStatus fromWire(String wire) =>
      OnboardingStatus.values.firstWhere((OnboardingStatus s) => s.wire == wire,
          orElse: () => OnboardingStatus.submitted);

  bool get isDecided =>
      this != OnboardingStatus.submitted && this != OnboardingStatus.inReview;
}

/// A delivery company somebody could apply to ride for.
///
/// An id and a name, which is all the public list returns. Everything else on the record — payout
/// state, score, contact details, the fleet — stays behind a token.
class HiringCompany {
  const HiringCompany({required this.id, required this.name});

  final String id;
  final String name;

  factory HiringCompany.fromJson(Map<String, dynamic> json) =>
      HiringCompany(id: json['id'] as String, name: json['name'] as String? ?? '');
}

class OnboardingApplication {
  const OnboardingApplication({
    required this.id,
    required this.reference,
    required this.kind,
    required this.businessName,
    required this.contactName,
    required this.contactEmail,
    required this.contactPhone,
    required this.emailVerifiedAt,
    required this.phoneVerifiedAt,
    required this.notes,
    required this.status,
    required this.createdAt,
    required this.decidedAt,
    required this.decidedBy,
    required this.rejectionReason,
    required this.provisionedUserRef,
    required this.provisionedEntityId,
    this.details = const <String, String>{},
  });

  final String id;
  final String reference;
  final OnboardingKind kind;
  final String businessName;
  final String contactName;
  final String contactEmail;
  final String? contactPhone;

  /// When the address was proved to reach them.
  ///
  /// Null on applications taken before verification existed, and reading as "not checked" is
  /// exactly right for those — it changes what approving them means, because the account and the
  /// decision are both sent to an address nobody confirmed.
  final DateTime? emailVerifiedAt;
  final DateTime? phoneVerifiedAt;

  final String? notes;
  final OnboardingStatus status;
  final DateTime? createdAt;
  final DateTime? decidedAt;
  final String? decidedBy;
  final String? rejectionReason;
  final String? provisionedUserRef;
  final String? provisionedEntityId;

  /// The wizard's free-form answers — vehicle, work region, business type, and whatever else the
  /// signup flow asked for. The server has carried this since the application form grew steps the
  /// fixed columns above could not hold; it is only now read on this side.
  ///
  /// Flattened to strings, and deliberately so: a reviewer reads these, they are never computed
  /// against. A nested object arrives as its JSON rather than being dropped, because a detail the
  /// reviewer cannot see is worse than one they have to squint at.
  ///
  /// Defaults to empty rather than being required — the applicant's own receipt does not carry it
  /// (it can hold bank details), and older applications predate the field entirely. Every reader
  /// must therefore treat "no details" as ordinary, not as an error.
  final Map<String, String> details;

  bool get emailVerified => emailVerifiedAt != null;
  bool get phoneVerified => phoneVerifiedAt != null;

  factory OnboardingApplication.fromJson(Map<String, dynamic> json) => OnboardingApplication(
        // Tolerant, because two shapes arrive here: the reviewer's full view, and the thin receipt
        // an applicant gets, which carries no id. Parsed strictly this threw on every status
        // lookup — the one call a person with no account is meant to be able to make.
        id: json['id'] as String? ?? '',
        reference: json['reference'] as String? ?? '',
        kind: OnboardingKind.fromWire(json['kind'] as String? ?? 'MERCHANT'),
        businessName: json['businessName'] as String? ?? '',
        contactName: json['contactName'] as String? ?? '',
        contactEmail: json['contactEmail'] as String? ?? '',
        contactPhone: json['contactPhone'] as String?,
        emailVerifiedAt: _time(json['emailVerifiedAt']),
        phoneVerifiedAt: _time(json['phoneVerifiedAt']),
        notes: json['notes'] as String?,
        status: OnboardingStatus.fromWire(json['status'] as String? ?? 'SUBMITTED'),
        createdAt: _time(json['createdAt']),
        decidedAt: _time(json['decidedAt']),
        decidedBy: json['decidedBy'] as String?,
        rejectionReason: json['rejectionReason'] as String?,
        provisionedUserRef: json['provisionedUserRef'] as String?,
        provisionedEntityId: json['provisionedEntityId'] as String?,
        details: _details(json['details']),
      );

  /// Anything that is not a JSON object reads as no details at all, including the null the receipt
  /// shape sends. Values are stringified rather than filtered, so an answer of `false` or `0`
  /// survives instead of vanishing.
  static Map<String, String> _details(dynamic value) {
    if (value is! Map) return const <String, String>{};
    return <String, String>{
      for (final MapEntry<dynamic, dynamic> e in value.entries)
        if (e.value != null) e.key.toString(): e.value.toString(),
    };
  }

  static DateTime? _time(dynamic value) =>
      value == null ? null : DateTime.tryParse(value as String)?.toLocal();
}
