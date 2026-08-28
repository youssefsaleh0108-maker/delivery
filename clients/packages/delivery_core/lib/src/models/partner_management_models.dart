/// Partner record corrections, audit and suspension, mirroring the onboarding-service shapes.
library;

import 'onboarding_models.dart';

/// A partner's fixed record as the management endpoints return it, mirroring `PartnerRecordView`.
///
/// Thinner than [OnboardingApplication] on purpose: this is the record being corrected, not the
/// application being reviewed — no notes, no decision trail, no wizard answers.
class PartnerRecordView {
  const PartnerRecordView({
    required this.id,
    required this.kind,
    required this.status,
    required this.businessName,
    required this.contactName,
    required this.contactEmail,
    this.contactPhone,
    this.emailVerifiedAt,
    this.phoneVerifiedAt,
  });

  final String id;
  final OnboardingKind kind;
  final OnboardingStatus status;
  final String businessName;
  final String contactName;

  /// The contact address — NOT the sign-in username, which an edit never changes.
  final String contactEmail;
  final String? contactPhone;

  /// When the address was proved to reach them. Null when never checked — and editing the email
  /// deliberately keeps this, while editing the phone nulls [phoneVerifiedAt]: a new number is a
  /// number nobody has confirmed, and the record says so.
  final DateTime? emailVerifiedAt;
  final DateTime? phoneVerifiedAt;

  factory PartnerRecordView.fromJson(Map<String, dynamic> json) => PartnerRecordView(
        id: json['id'] as String,
        kind: OnboardingKind.fromWire(json['kind'] as String? ?? 'MERCHANT'),
        status: OnboardingStatus.fromWire(json['status'] as String? ?? 'SUBMITTED'),
        businessName: json['businessName'] as String? ?? '',
        contactName: json['contactName'] as String? ?? '',
        contactEmail: json['contactEmail'] as String? ?? '',
        contactPhone: json['contactPhone'] as String?,
        emailVerifiedAt: _time(json['emailVerifiedAt']),
        phoneVerifiedAt: _time(json['phoneVerifiedAt']),
      );

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

/// One correction on the record: who changed which field from what to what, and when.
///
/// Newest first in the list this arrives in; an empty list means the record was never edited.
class PartnerAuditEntry {
  const PartnerAuditEntry({
    required this.field,
    required this.actor,
    this.oldValue,
    this.newValue,
    this.at,
  });

  /// The field name as the server spells it (`businessName`, `contactPhone`, …).
  final String field;

  final String? oldValue;
  final String? newValue;

  /// The Keycloak subject of whoever made the change.
  final String actor;

  final DateTime? at;

  factory PartnerAuditEntry.fromJson(Map<String, dynamic> json) => PartnerAuditEntry(
        field: json['field'] as String? ?? '',
        oldValue: json['oldValue'] as String?,
        newValue: json['newValue'] as String?,
        actor: json['actor'] as String? ?? '',
        at: PartnerRecordView._time(json['at']),
      );
}

/// Why a partner was suspended, mirroring the server's reason enum.
///
/// Required on every suspension — "suspended" with no reason is not a record anybody can act on
/// later — and null on reinstatement rows, which need none.
enum SuspensionReason {
  fraud('FRAUD', 'Fraud'),
  abuse('ABUSE', 'Abuse'),
  nonPayment('NON_PAYMENT', 'Non-payment'),
  policyViolation('POLICY_VIOLATION', 'Policy violation'),
  partnerRequest('PARTNER_REQUEST', 'Partner request'),
  other('OTHER', 'Other');

  const SuspensionReason(this.wire, this.label);

  final String wire;
  final String label;

  /// Null for a reason this client does not know — rendered by its wire string, never guessed at.
  static SuspensionReason? fromWire(String? value) {
    for (final SuspensionReason r in SuspensionReason.values) {
      if (r.wire == value) return r;
    }
    return null;
  }
}

/// One turn of the switch, mirroring `StandingChangeView`.
class StandingChange {
  const StandingChange({
    required this.suspended,
    required this.actor,
    this.reason,
    this.reasonWire,
    this.reasonNote,
    this.at,
  });

  /// True on a suspension row, false on a reinstatement.
  final bool suspended;

  /// Why — null on reinstatement rows, and null for a reason this build does not know, in which
  /// case [reasonWire] still holds the server's spelling.
  final SuspensionReason? reason;

  /// The reason exactly as the server spelled it, or null when the row carried none.
  final String? reasonWire;

  /// The free-text note beside the reason, or null when none was given.
  final String? reasonNote;

  /// The Keycloak subject of whoever flipped it.
  final String actor;

  final DateTime? at;

  factory StandingChange.fromJson(Map<String, dynamic> json) => StandingChange(
        suspended: json['suspended'] as bool? ?? false,
        reason: SuspensionReason.fromWire(json['reason'] as String?),
        reasonWire: json['reason'] as String?,
        reasonNote: json['reasonNote'] as String?,
        actor: json['actor'] as String? ?? '',
        at: PartnerRecordView._time(json['at']),
      );
}

/// Where the partner stands right now, mirroring `PartnerStandingView`.
class PartnerStanding {
  const PartnerStanding({
    required this.suspended,
    this.lastChange,
  });

  final bool suspended;

  /// The most recent turn of the switch, or null when the standing has never been touched.
  final StandingChange? lastChange;

  factory PartnerStanding.fromJson(Map<String, dynamic> json) => PartnerStanding(
        suspended: json['suspended'] as bool? ?? false,
        lastChange: json['lastChange'] is Map<String, dynamic>
            ? StandingChange.fromJson(json['lastChange'] as Map<String, dynamic>)
            : null,
      );
}

/// The standing plus its whole history, mirroring the suspension GET.
class PartnerSuspensionRecord {
  const PartnerSuspensionRecord({
    required this.suspended,
    required this.history,
    this.lastChange,
  });

  final bool suspended;
  final StandingChange? lastChange;

  /// Every turn of the switch, newest first. Empty when the standing was never touched.
  final List<StandingChange> history;

  factory PartnerSuspensionRecord.fromJson(Map<String, dynamic> json) => PartnerSuspensionRecord(
        suspended: json['suspended'] as bool? ?? false,
        lastChange: json['lastChange'] is Map<String, dynamic>
            ? StandingChange.fromJson(json['lastChange'] as Map<String, dynamic>)
            : null,
        history: (json['history'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic c) => StandingChange.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}
