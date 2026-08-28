import 'package:dio/dio.dart';

/// Client for the forgotten-password flow on the onboarding service.
///
/// Both endpoints are open — the whole point is that the caller cannot sign in — and both are
/// deliberately quiet about what exists: requesting a code for an unknown address succeeds exactly
/// like a known one, and a correct code for an address with no account fails with the same wording
/// as a wrong code. Nothing here is a directory oracle, and no screen should try to be smarter
/// than that.
class PasswordResetApi {
  PasswordResetApi(this._dio);

  final Dio _dio;

  /// Asks for a 6-digit code to be sent to [email].
  ///
  /// Returns normally for known AND unknown addresses (202, empty body) — the screen says "if that
  /// address has an account, a code is on its way" and means it. The code lives 10 minutes, allows
  /// 5 wrong guesses, works once, and cannot confirm a sign-up (purposes are separated).
  ///
  /// Throws on: 400 malformed address, 422 the address was refused, 429 resend cooldown (60s) or
  /// daily cap (8/24h) — the 429s are identical for known and unknown addresses.
  Future<void> request(String email) async {
    await _dio.post<dynamic>(
      '/api/onboarding/password-reset',
      data: <String, dynamic>{'email': email},
    );
  }

  /// Spends the code and sets the new password. 204 on success; the code is consumed
  /// transactionally — one code, one reset.
  ///
  /// Throws on: 400 validation ([newPassword] is 6–128 chars), 422 wrong/expired/spent code or
  /// attempt cap — deliberately the same wording when the code was right but the address has no
  /// account — and 502 when the identity server refused, which is retryable: consumption rolled
  /// back and the same code is still live.
  Future<void> confirm({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _dio.post<dynamic>(
      '/api/onboarding/password-reset/confirm',
      data: <String, dynamic>{
        'email': email,
        'code': code,
        'newPassword': newPassword,
      },
    );
  }
}
