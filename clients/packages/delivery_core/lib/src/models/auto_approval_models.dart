/// Whether an application of a given kind is approved by a person or by the platform itself.
library;

import 'onboarding_models.dart';

/// Where the value in force came from.
///
/// The distinction is the whole reason this record carries anything beyond three booleans. `CONFIG`
/// means nobody has ever made this decision in the portal and the deployed environment's default is
/// what is running — so the switch showing "on" is the deployment's opinion, not somebody's. `PORTAL`
/// means a named operator set it deliberately, and [AutoApprovalSettings.lastChangedBy] says who.
///
/// Unknown wire values degrade rather than throw, in the same shape [ApplicantDocumentKind] uses:
/// the typed value goes null and the server's own spelling is kept in
/// [AutoApprovalDecision.sourceWire]. A `firstWhere ... orElse` default was the other option and is
/// wrong here — both of the constants below are a claim about who is answerable for the value, and
/// guessing either one of them for a source this build has never heard of puts a claim on screen
/// that nothing supports.
enum AutoApprovalSource {
  /// No portal decision has ever been recorded for this kind; the environment default is in force.
  config('CONFIG', 'From deployment config'),

  /// Somebody set this deliberately from the portal.
  portal('PORTAL', 'Set in the portal');

  const AutoApprovalSource(this.wire, this.label);

  final String wire;
  final String label;

  /// Null for a source this client does not know — rendered by its wire string, never guessed at.
  static AutoApprovalSource? fromWire(String? value) {
    for (final AutoApprovalSource s in AutoApprovalSource.values) {
      if (s.wire == value) return s;
    }
    return null;
  }
}

/// One kind's answer: whether it approves itself, and on whose authority.
class AutoApprovalDecision {
  const AutoApprovalDecision({
    required this.automatic,
    required this.sourceWire,
    this.source,
  });

  /// True when an application of this kind is approved without a person reading it.
  final bool automatic;

  /// The typed source, or null for one this build does not know. [sourceWire] holds the server's
  /// string either way.
  final AutoApprovalSource? source;

  /// The source exactly as the server spelled it.
  final String sourceWire;

  /// A label safe to put in front of an operator: the known source's words, or the server's own
  /// spelling for one this build has never seen. Never a guess about which of the two it is.
  ///
  /// The third case is a source the server did not send at all, which used to fall through to the
  /// empty string and render as a blank chip — losing exactly the distinction this type exists to
  /// carry. It is said out loud instead, and this getter is the one answer: the settings panel
  /// renders it rather than reimplementing the same three cases beside it.
  String get sourceLabel {
    if (source != null) return source!.label;
    return sourceWire.isEmpty ? 'Source not stated' : sourceWire;
  }

  /// Whether a person set this. False for both `CONFIG` and an unrecognised source — the second is
  /// unknown, and treating unknown as "somebody chose this" would invent an accountable human.
  bool get chosenInPortal => source == AutoApprovalSource.portal;

  factory AutoApprovalDecision.fromJson(Map<String, dynamic> json) => AutoApprovalDecision(
        // Anything that is not a bool — absent, null, or a type the server should never send —
        // reads as false. The safe default is the one where a person still reads the application:
        // a parsing slip must not draw an open gate as a closed one. Written as an `is` test
        // rather than `as bool?` because the cast throws on a String or an int, which would take
        // the whole settings parse down and, on the review queue, silently draw no line at all.
        automatic: json['automatic'] is bool ? json['automatic'] as bool : false,
        source: AutoApprovalSource.fromWire(json['source'] as String?),
        sourceWire: json['source'] as String? ?? '',
      );
}

/// The three switches and the audit line under them, mirroring the admin auto-approval response.
class AutoApprovalSettings {
  const AutoApprovalSettings({
    required this.rider,
    required this.merchant,
    required this.carrier,
    this.lastChangedBy,
    this.lastChangedAt,
  });

  final AutoApprovalDecision rider;
  final AutoApprovalDecision merchant;
  final AutoApprovalDecision carrier;

  /// The Keycloak subject or username of whoever last saved from the portal. Null when nobody ever
  /// has — which is a different fact from "changed by somebody we cannot name".
  final String? lastChangedBy;

  /// When that happened, in local time. Null for the same reason.
  final DateTime? lastChangedAt;

  /// The decision for one applicant kind, so callers that already hold an [OnboardingKind] — the
  /// review queue does — do not each re-derive the mapping.
  AutoApprovalDecision forKind(OnboardingKind kind) => switch (kind) {
        OnboardingKind.rider => rider,
        OnboardingKind.merchant => merchant,
        OnboardingKind.carrier => carrier,
      };

  /// The kinds approving themselves right now, in the order the settings screen lists them.
  List<OnboardingKind> get automaticKinds => <OnboardingKind>[
        for (final OnboardingKind kind in <OnboardingKind>[
          OnboardingKind.rider,
          OnboardingKind.merchant,
          OnboardingKind.carrier,
        ])
          if (forKind(kind).automatic) kind,
      ];

  factory AutoApprovalSettings.fromJson(Map<String, dynamic> json) => AutoApprovalSettings(
        rider: _decision(json['rider']),
        merchant: _decision(json['merchant']),
        carrier: _decision(json['carrier']),
        lastChangedBy: json['lastChangedBy'] as String?,
        lastChangedAt: _time(json['lastChangedAt']),
      );

  /// A kind the server omitted reads as "not automatic, source unknown" rather than throwing. The
  /// contract promises all three, so this only fires against a server that has broken it — and a
  /// screen that still renders is what lets an operator see the other two and fix the one.
  static AutoApprovalDecision _decision(dynamic value) => value is Map<String, dynamic>
      ? AutoApprovalDecision.fromJson(value)
      : const AutoApprovalDecision(automatic: false, sourceWire: '');

  static DateTime? _time(dynamic value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}
