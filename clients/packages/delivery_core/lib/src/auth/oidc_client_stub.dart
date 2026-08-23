import 'auth_config.dart';
import 'oidc_client.dart';

/// Fallback for a platform with neither `dart:io` nor `dart:js_interop`. Never selected in
/// practice; it exists so the conditional import in `oidc_client.dart` always resolves.
OidcClient buildOidcClient() => const _UnsupportedOidcClient();

class _UnsupportedOidcClient implements OidcClient {
  const _UnsupportedOidcClient();

  Never _fail() => throw UnsupportedError(
      'No OIDC implementation is available for this platform.');

  @override
  Future<TokenSet?> signIn(AuthConfig config, {Map<String, String>? extraParams}) => _fail();

  @override
  Future<TokenSet?> completeRedirect(AuthConfig config) async => null;

  @override
  Future<TokenSet> refresh(AuthConfig config, String refreshToken) => _fail();

  @override
  Future<void> signOut(AuthConfig config, String? refreshToken) => _fail();
}
