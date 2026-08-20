import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_config.dart';
import 'delivery_role.dart';
import 'oidc_client.dart';

export 'auth_config.dart';

/// The signed-in user, as far as the client is concerned.
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.roles,
    required this.subject,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final Set<DeliveryRole> roles;

  /// The Keycloak `sub` — the same value every service checks ownership against.
  final String? subject;

  bool get isExpired =>
      expiresAt != null &&
      DateTime.now().isAfter(expiresAt!.subtract(const Duration(seconds: 30)));

  bool hasRole(DeliveryRole role) => roles.contains(role);

  /// The signed-in person's display name, from the token's own claims.
  ///
  /// Read from the access token rather than fetched from Keycloak's userinfo endpoint: the claims
  /// are already here, already signed, and an account screen should not need a network round trip
  /// to say who you are. Falls back through name -> username -> email so something always renders.
  String get displayName =>
      _claim('name') ?? _claim('preferred_username') ?? _claim('email') ?? 'Account';

  String? get email => _claim('email');

  String? get username => _claim('preferred_username');

  /// Reads one claim out of the JWT payload.
  ///
  /// No signature verification here, deliberately — this token was just issued to us over TLS by
  /// the endpoint we asked, and every request it authorises is verified server-side anyway. This is
  /// for rendering a name, not for making a trust decision.
  String? _claim(String key) {
    try {
      final List<String> parts = accessToken.split('.');
      if (parts.length < 2) return null;
      // JWT uses base64url without padding; normalize() restores it.
      final String payload =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final Object? value = (jsonDecode(payload) as Map<String, dynamic>)[key];
      final String? text = value is String ? value.trim() : null;
      return (text == null || text.isEmpty) ? null : text;
    } catch (_) {
      // A malformed token must not stop an account screen rendering.
      return null;
    }
  }
}

/// Authorization Code + PKCE against Keycloak, with tokens held in platform secure storage
/// (Section 3).
///
/// The platform difference is hidden in [OidcClient]: on mobile [signIn] returns a session
/// directly, while on web it navigates away and the session materialises on the next load via
/// [restore]. Callers treat both the same — call [restore] at startup, [signIn] on a button.
class AuthService {
  AuthService({
    required AuthConfig config,
    OidcClient? oidcClient,
    FlutterSecureStorage? storage,
  })  : _config = config,
        _oidc = oidcClient ?? createOidcClient(),
        _storage = storage ?? const FlutterSecureStorage();

  static const String _refreshTokenKey = 'delivery.refresh_token';

  final AuthConfig _config;
  final OidcClient _oidc;
  final FlutterSecureStorage _storage;

  AuthSession? _session;

  AuthSession? get session => _session;

  /// Returns null on web, where the browser is navigating away and the result arrives later.
  Future<AuthSession?> signIn() async {
    final TokenSet? tokens = await _oidc.signIn(_config);
    return tokens == null ? null : _adopt(tokens);
  }

  /// Call once at startup, before deciding which screen to show.
  ///
  /// Does two things in order: redeems an authorization code if this load is a web login callback,
  /// then falls back to the stored refresh token so a returning user is not sent to the login
  /// screen on every cold start.
  Future<AuthSession?> restore() async {
    final TokenSet? redirected = await _oidc.completeRedirect(_config);
    if (redirected != null) {
      return _adopt(redirected);
    }

    final String? refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null) {
      return null;
    }
    try {
      return await refresh(refreshToken);
    } catch (_) {
      // Revoked, expired, or the realm was rebuilt. Drop it and make the user sign in again.
      await signOut();
      return null;
    }
  }

  Future<AuthSession> refresh([String? refreshToken]) async {
    final String? token = refreshToken ?? _session?.refreshToken;
    if (token == null) {
      throw StateError('No refresh token available; the user must sign in.');
    }
    return _adopt(await _oidc.refresh(_config, token));
  }

  Future<void> signOut() async {
    final String? refreshToken =
        _session?.refreshToken ?? await _storage.read(key: _refreshTokenKey);
    _session = null;
    await _storage.delete(key: _refreshTokenKey);
    await _oidc.signOut(_config, refreshToken);
  }

  Future<AuthSession> _adopt(TokenSet tokens) async {
    // Only the refresh token is persisted. The access token is short-lived (5 minutes in this
    // realm) and stays in memory, so a stolen device backup yields nothing directly usable.
    if (tokens.refreshToken != null) {
      await _storage.write(key: _refreshTokenKey, value: tokens.refreshToken);
    }

    final AuthSession session = AuthSession(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      expiresAt: tokens.expiresAt,
      roles: TokenRoles.parse(tokens.accessToken),
      subject: TokenRoles.subject(tokens.accessToken),
    );
    _session = session;
    return session;
  }
}
