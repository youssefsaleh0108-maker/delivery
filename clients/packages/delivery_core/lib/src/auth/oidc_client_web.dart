import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'auth_config.dart';
import 'oidc_client.dart';
import 'pkce.dart';

/// Browser implementation of Authorization Code + PKCE.
///
/// Written by hand rather than taken from a package: `flutter_appauth` has no web support at all,
/// and the alternatives' web support is thin enough that owning ~100 lines is the lower risk. The
/// flow is the standard one and the only browser-specific parts are the redirect and where the
/// code verifier is parked across it.
OidcClient buildOidcClient() => _WebOidcClient();

class _WebOidcClient implements OidcClient {
  static const String _verifierKey = 'delivery.pkce_verifier';
  static const String _stateKey = 'delivery.oauth_state';

  @override
  Future<TokenSet?> signIn(AuthConfig config, {Map<String, String>? extraParams}) async {
    final String verifier = Pkce.generateVerifier();
    final String state = Pkce.generateState();

    // sessionStorage, not localStorage: the verifier is single-use and scoped to this tab, and it
    // must not outlive the browser session if the redirect is abandoned.
    web.window.sessionStorage.setItem(_verifierKey, verifier);
    web.window.sessionStorage.setItem(_stateKey, state);

    final Uri authorizeUrl = Uri.parse(config.authorizationEndpoint).replace(
      queryParameters: <String, String>{
        // FIRST, so the fixed half below wins on any key collision. Spread last, a caller could
        // replace client_id or the PKCE challenge by passing one in.
        ...?extraParams,
        'client_id': config.clientId,
        'redirect_uri': config.redirectUrl,
        'response_type': 'code',
        'scope': config.scopes.join(' '),
        'state': state,
        'code_challenge': Pkce.challengeFor(verifier),
        'code_challenge_method': 'S256',
      },
    );

    // Navigates the page away. Nothing after this runs; the result is picked up by
    // completeRedirect() on the next load.
    web.window.location.assign(authorizeUrl.toString());
    return null;
  }

  @override
  Future<TokenSet?> completeRedirect(AuthConfig config) async {
    final Uri current = Uri.parse(web.window.location.href);
    final String? code = current.queryParameters['code'];
    final String? returnedState = current.queryParameters['state'];

    // Keycloak reports failures as query parameters rather than a non-200, so check for them here.
    final String? error = current.queryParameters['error'];
    if (error != null) {
      _clearUrl();
      throw StateError(
          'Sign-in failed: $error ${current.queryParameters['error_description'] ?? ''}'.trim());
    }

    if (code == null) {
      return null;
    }

    final String? verifier = web.window.sessionStorage.getItem(_verifierKey);
    final String? expectedState = web.window.sessionStorage.getItem(_stateKey);
    web.window.sessionStorage.removeItem(_verifierKey);
    web.window.sessionStorage.removeItem(_stateKey);

    // Strip the code from the address bar before anything can go wrong with it: an authorization
    // code sitting in browser history, or copied out of the URL bar, is a credential leak.
    _clearUrl();

    if (verifier == null) {
      throw StateError('No PKCE verifier for this callback — start the sign-in again.');
    }
    // CSRF defence: a code delivered with a state we did not issue is not ours.
    if (expectedState == null || returnedState != expectedState) {
      throw StateError('OAuth state mismatch — the sign-in was not started by this tab.');
    }

    return _exchange(config, <String, String>{
      'grant_type': 'authorization_code',
      'client_id': config.clientId,
      'redirect_uri': config.redirectUrl,
      'code': code,
      'code_verifier': verifier,
    });
  }

  @override
  Future<TokenSet> refresh(AuthConfig config, String refreshToken) {
    return _exchange(config, <String, String>{
      'grant_type': 'refresh_token',
      'client_id': config.clientId,
      'refresh_token': refreshToken,
    });
  }

  @override
  Future<void> signOut(AuthConfig config, String? refreshToken) async {
    if (refreshToken == null) {
      return;
    }
    // Best effort: end the Keycloak SSO session too, so the next sign-in actually prompts instead
    // of silently reusing the session. A failure here is not worth blocking local sign-out on.
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

  Future<TokenSet> _exchange(AuthConfig config, Map<String, String> body) async {
    final http.Response response = await http.post(
      Uri.parse(config.tokenEndpoint),
      headers: const <String, String>{'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );

    if (response.statusCode != 200) {
      throw StateError('Token endpoint returned ${response.statusCode}: ${response.body}');
    }

    final Map<String, dynamic> json =
        jsonDecode(response.body) as Map<String, dynamic>;
    final String? accessToken = json['access_token'] as String?;
    if (accessToken == null) {
      throw StateError('Token endpoint returned no access_token.');
    }

    final int? expiresIn = (json['expires_in'] as num?)?.toInt();
    return TokenSet(
      accessToken: accessToken,
      refreshToken: json['refresh_token'] as String?,
      expiresAt:
          expiresIn == null ? null : DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }

  /// Removes the OAuth query parameters without reloading the page.
  void _clearUrl() {
    final Uri current = Uri.parse(web.window.location.href);
    final String clean = current.replace(queryParameters: <String, String>{}).toString();
    web.window.history.replaceState(null, '', clean.endsWith('?')
        ? clean.substring(0, clean.length - 1)
        : clean);
  }

}
