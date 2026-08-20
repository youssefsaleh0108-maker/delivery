import 'auth_config.dart';

// Picks the implementation at compile time. `flutter_appauth` is mobile/desktop only — it has no
// web implementation at all — so the two web portals need a browser redirect flow instead. Both
// sides implement PKCE; the difference is only in how the user agent is driven.
import 'oidc_client_stub.dart'
    if (dart.library.io) 'oidc_client_io.dart'
    if (dart.library.js_interop) 'oidc_client_web.dart';

/// The raw result of an OIDC exchange, before roles are parsed out of it.
class TokenSet {
  const TokenSet({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
}

/// Platform-specific half of the Authorization Code + PKCE flow (Section 3).
abstract interface class OidcClient {
  /// Sends the user to Keycloak.
  ///
  /// On mobile this opens a system browser tab and returns when it redirects back. On web this
  /// navigates the whole page away and **never returns** — the result arrives on the next app load
  /// via [completeRedirect].
  Future<TokenSet?> signIn(AuthConfig config);

  /// Web only: if the current URL carries an authorization code, exchange it for tokens.
  ///
  /// Returns null when there is no code to redeem, which is the normal case on every load that is
  /// not a login callback. On mobile this is always null.
  Future<TokenSet?> completeRedirect(AuthConfig config);

  Future<TokenSet> refresh(AuthConfig config, String refreshToken);

  Future<void> signOut(AuthConfig config, String? refreshToken);
}

OidcClient createOidcClient() => buildOidcClient();
