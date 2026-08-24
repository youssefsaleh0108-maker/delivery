import 'dart:convert';

/// The realm roles issued by Keycloak (Section 3).
///
/// The Mobile App is a single codebase serving both Customer and Delivery Rider, and branches its
/// navigation on which of these the token carries — so this enum is what decides whether a user
/// sees the order-placement flow or the delivery queue.
enum DeliveryRole {
  customer('CUSTOMER'),
  delivery('DELIVERY'),
  merchant('MERCHANT'),
  /// Staff of a delivery company: administers their own carrier, not the platform.
  carrier('CARRIER'),
  backoffice('BACKOFFICE'),

  /// Applied to sell, carry or deliver and waiting on a decision.
  ///
  /// Grants nothing. It is what an account holds between choosing a passcode at the end of the
  /// application and somebody approving it, so the app can show the application's progress instead
  /// of a shop that does not exist yet.
  applicant('APPLICANT');

  const DeliveryRole(this.claimValue);

  final String claimValue;

  static DeliveryRole? fromClaim(String value) {
    final String normalised = value.toUpperCase();
    for (final DeliveryRole role in DeliveryRole.values) {
      if (role.claimValue == normalised) {
        return role;
      }
    }
    // Keycloak realms carry built-in roles (offline_access, uma_authorization) that mean nothing
    // to this app. Unknown roles are ignored rather than treated as an error.
    return null;
  }
}

/// Reads realm roles out of an access token.
///
/// This mirrors the backend's `KeycloakRealmRoleConverter`, and deliberately only drives UI
/// decisions. Nothing here is a security control: the client can be modified, so every request is
/// authorised again server-side against the same claim (Section 3).
abstract final class TokenRoles {
  static Set<DeliveryRole> parse(String accessToken) {
    final Map<String, dynamic>? claims = decodeClaims(accessToken);
    if (claims == null) {
      return const <DeliveryRole>{};
    }

    final Object? realmAccess = claims['realm_access'];
    if (realmAccess is! Map) {
      return const <DeliveryRole>{};
    }

    final Object? roles = realmAccess['roles'];
    if (roles is! List) {
      return const <DeliveryRole>{};
    }

    return roles
        .whereType<String>()
        .map(DeliveryRole.fromClaim)
        .whereType<DeliveryRole>()
        .toSet();
  }

  /// The Keycloak user id (`sub`) — the same value the backend uses for ownership checks.
  static String? subject(String accessToken) =>
      decodeClaims(accessToken)?['sub'] as String?;

  /// Decodes the JWT payload WITHOUT verifying the signature. That is fine for reading a claim to
  /// choose a screen; it would not be fine for an authorisation decision, which is why none are
  /// made here.
  static Map<String, dynamic>? decodeClaims(String jwt) {
    final List<String> parts = jwt.split('.');
    if (parts.length != 3) {
      return null;
    }
    try {
      final String normalised = base64Url.normalize(parts[1]);
      final String payload = utf8.decode(base64Url.decode(normalised));
      final Object? decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
