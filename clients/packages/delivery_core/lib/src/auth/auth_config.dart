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

  /// Whether AppAuth may talk to this issuer over plain HTTP.
  ///
  /// AppAuth's `DefaultConnectionBuilder` permits HTTPS only and throws
  /// `IllegalArgumentException: only https connections are permitted` on anything else — which on
  /// Android is an uncaught exception on a background thread, so the app does not surface a login
  /// error, it dies. Android's `network_security_config` does not help: that governs the platform's
  /// cleartext policy, and this check is AppAuth's own, applied independently.
  ///
  /// The local stack is HTTP-only (Section 10 requires TLS everywhere in real environments, and
  /// there is no certificate on a laptop), so device testing needs this relaxed. Derived from the
  /// issuer scheme rather than exposed as a flag: it can only ever be true for an `http://` issuer,
  /// so a staging or production deployment cannot accidentally ship with it on.
  bool get allowInsecureConnections => issuer.startsWith('http://');

  /// Keycloak's endpoint layout. Derived rather than discovered so a login does not depend on an
  /// extra round trip; the web client still fetches the discovery document when it needs to.
  String get authorizationEndpoint => '$issuer/protocol/openid-connect/auth';

  String get tokenEndpoint => '$issuer/protocol/openid-connect/token';

  String get endSessionEndpoint => '$issuer/protocol/openid-connect/logout';
}
