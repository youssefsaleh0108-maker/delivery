import 'package:flutter_appauth/flutter_appauth.dart';

import 'auth_config.dart';
import 'oidc_client.dart';

/// Mobile/desktop implementation: AppAuth drives a system browser tab and handles PKCE for us.
OidcClient buildOidcClient() => _AppAuthOidcClient();

class _AppAuthOidcClient implements OidcClient {
  final FlutterAppAuth _appAuth = const FlutterAppAuth();

  @override
  Future<TokenSet?> signIn(AuthConfig config) async {
    final AuthorizationTokenResponse response = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        config.clientId,
        config.redirectUrl,
        discoveryUrl: config.discoveryUrl,
        scopes: config.scopes,
        // PKCE is on by default and is what makes a public client safe here: there is no client
        // secret to ship inside an app binary.
      ),
    );
    return _toTokenSet(
      response.accessToken,
      response.refreshToken,
      response.accessTokenExpirationDateTime,
    );
  }

  /// Not a web build, so there is never a redirect to complete on startup.
  @override
  Future<TokenSet?> completeRedirect(AuthConfig config) async => null;

  @override
  Future<TokenSet> refresh(AuthConfig config, String refreshToken) async {
    final TokenResponse response = await _appAuth.token(
      TokenRequest(
        config.clientId,
        config.redirectUrl,
        discoveryUrl: config.discoveryUrl,
        refreshToken: refreshToken,
        scopes: config.scopes,
      ),
    );
    final TokenSet? tokens = _toTokenSet(
      response.accessToken,
      response.refreshToken,
      response.accessTokenExpirationDateTime,
    );
    if (tokens == null) {
      throw StateError('Keycloak returned no access token on refresh.');
    }
    return tokens;
  }

  @override
  Future<void> signOut(AuthConfig config, String? refreshToken) async {
    // Nothing to do server-side for a public client: the refresh token is discarded locally by
    // AuthService, and the short-lived access token expires on its own.
  }

  TokenSet? _toTokenSet(String? accessToken, String? refreshToken, DateTime? expiresAt) {
    if (accessToken == null) {
      return null;
    }
    return TokenSet(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
    );
  }
}
