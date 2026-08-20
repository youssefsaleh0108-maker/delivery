import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PKCE (RFC 7636) code verifier and challenge generation.
///
/// Deliberately platform-neutral and kept out of `oidc_client_web.dart`: the maths is not
/// browser-specific, and pulling it out means it can be unit-tested against the RFC's own test
/// vector on the Dart VM rather than only exercised inside a real browser redirect.
abstract final class Pkce {
  static final Random _random = Random.secure();

  /// A high-entropy random string, 43-128 characters per RFC 7636 §4.1.
  ///
  /// 64 random bytes base64url-encodes to 86 characters, comfortably inside that range.
  static String generateVerifier([int bytes = 64]) =>
      base64UrlNoPadding(List<int>.generate(bytes, (_) => _random.nextInt(256)));

  /// The S256 challenge: BASE64URL(SHA256(ASCII(verifier))), per RFC 7636 §4.2.
  static String challengeFor(String verifier) =>
      base64UrlNoPadding(sha256.convert(ascii.encode(verifier)).bytes);

  /// Opaque random value for the OAuth `state` parameter (CSRF defence).
  static String generateState([int bytes = 24]) =>
      base64UrlNoPadding(List<int>.generate(bytes, (_) => _random.nextInt(256)));

  /// base64url WITHOUT padding.
  ///
  /// The padding matters: RFC 7636 requires it stripped, and a trailing `=` makes Keycloak reject
  /// the challenge with an unhelpful generic error.
  static String base64UrlNoPadding(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}
