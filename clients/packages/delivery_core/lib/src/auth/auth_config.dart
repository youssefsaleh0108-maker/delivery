/// Keycloak configuration for one client application (Section 3).
///
/// Each of the three Flutter targets constructs this with its own `clientId` — `mobile-app`,
/// `backoffice-web` or `merchant-portal`.
class AuthConfig {
  const AuthConfig({
    required this.issuer,
    required this.clientId,
    required this.redirectUrl,
    this.scopes = const <String>['openid', 'profile', 'email'],
  });

  /// e.g. `http://localhost:8180/realms/delivery-platform`
  final String issuer;

  final String clientId;

  /// Mobile: a custom scheme registered by the app. Web: a URL on the app's own origin.
  final String redirectUrl;

  final List<String> scopes;

  String get discoveryUrl => '$issuer/.well-known/openid-configuration';

  /// Keycloak's endpoint layout. Derived rather than discovered so a login does not depend on an
  /// extra round trip; the web client still fetches the discovery document when it needs to.
  String get authorizationEndpoint => '$issuer/protocol/openid-connect/auth';

  String get tokenEndpoint => '$issuer/protocol/openid-connect/token';

  String get endSessionEndpoint => '$issuer/protocol/openid-connect/logout';
}
