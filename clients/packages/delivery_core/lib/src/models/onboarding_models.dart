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
      );

  static DateTime? _time(dynamic value) =>
      value == null ? null : DateTime.tryParse(value as String)?.toLocal();
}
