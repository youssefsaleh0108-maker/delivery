import 'package:http/http.dart' as http;
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
        // True only for an http:// issuer — the local dev stack. AppAuth otherwise refuses the
        // discovery call outright and takes the app down with it. See AuthConfig.
        allowInsecureConnections: config.allowInsecureConnections,
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
        allowInsecureConnections: config.allowInsecureConnections,
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
    if (refreshToken == null) {
      return;
    }
    // END THE KEYCLOAK SSO SESSION, not just the local one.
    //
    // Dropping the tokens on the device is not a sign-out the user can see. Keycloak keeps its own
    // browser session, so the next sign-in reuses it and returns a fresh token WITHOUT prompting —
    // the app bounces straight back in and the Sign out button looks broken. Worse on a shared
    // phone, where the next person is silently signed in as the previous one.
    //
    // Same backchannel POST the web client already does; there is no reason for the two to differ.
    // Best effort: a failure here still leaves the device with no tokens, and blocking local
    // sign-out on the network would strand the user signed in when offline.
    try {
      await http.post(
        Uri.parse(config.endSessionEndpoint),
        headers: const <String, String>{'Content-Type': 'application/x-www-form-urlencoded'},
        body: <String, String>{
          'client_id': config.clientId,
          'refresh_token': refreshToken,
        },
      );
    } catch (_) {
      // Ignored on purpose.
    }
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
