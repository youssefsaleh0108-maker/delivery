/// Partner API keys — a carrier's machine credentials, mirroring the `/api/partner-keys` shapes.
library;

/// The one response that ever carries the secret, mirroring the mint endpoint's 201 body.
///
/// A separate class from [PartnerApiKey] for the same reason the server splits the shapes: the
/// secret appears here and NOWHERE else, ever — it is hashed server-side and not stored. The
/// screen shows it once with copy-now UX; a listing can never leak what its model cannot hold.
class PartnerApiKeyCreated {
  const PartnerApiKeyCreated({
    required this.id,
    required this.secret,
    required this.keyPrefix,
    this.label,
    this.createdAt,
  });

  final String id;

  /// The full `ydk_…` credential, shown exactly once. Anyone who loses it revokes the key and
  /// mints another — there is no endpoint that returns it again.
  final String secret;

  /// The first 12 characters of [secret] — the only part listings ever show, enough to match a
  /// key against the config it was pasted into.
  final String keyPrefix;

  /// The human name the carrier gave it, or null when they gave none.
  final String? label;

  final DateTime? createdAt;

  factory PartnerApiKeyCreated.fromJson(Map<String, dynamic> json) => PartnerApiKeyCreated(
        id: json['id'] as String,
        secret: json['secret'] as String,
        keyPrefix: json['keyPrefix'] as String? ?? '',
        label: json['label'] as String?,
        createdAt: _time(json['createdAt']),
      );

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

/// One key as the listing shows it — prefix and provenance, never the secret or its hash.
class PartnerApiKey {
  const PartnerApiKey({
    required this.id,
    required this.keyPrefix,
    required this.revoked,
    this.label,
    this.createdAt,
    this.lastUsedAt,
    this.revokedAt,
  });

  final String id;
  final String keyPrefix;
  final String? label;
  final DateTime? createdAt;

  /// When the key last authenticated a request. Null for a key that has never been used — the
  /// honest answer for one minted and forgotten, and the one that makes it safe to revoke.
  final DateTime? lastUsedAt;

  /// Revoked keys stay in the listing, flagged — the record of what existed, not just what works.
  final bool revoked;
  final DateTime? revokedAt;

  factory PartnerApiKey.fromJson(Map<String, dynamic> json) => PartnerApiKey(
        id: json['id'] as String,
        keyPrefix: json['keyPrefix'] as String? ?? '',
        label: json['label'] as String?,
        createdAt: PartnerApiKeyCreated._time(json['createdAt']),
        lastUsedAt: PartnerApiKeyCreated._time(json['lastUsedAt']),
        revoked: json['revoked'] as bool? ?? false,
        revokedAt: PartnerApiKeyCreated._time(json['revokedAt']),
      );
}
