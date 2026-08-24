import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';

/// Fingerprint or face unlock for a session that is already on this device.
///
/// What this is NOT: a way of authenticating to the platform. The server never learns that a
/// fingerprint was used, and no credential is derived from it. The refresh token in secure storage
/// is what signs the person in, exactly as before — this decides whether the app hands that token
/// over on launch, or asks who is holding the phone first.
///
/// That is the whole value. Before it, restoring a session meant anybody who picked up an unlocked
/// phone had the account open in one tap, including a rider's job queue and a customer's addresses.
class BiometricLock {
  BiometricLock({LocalAuthentication? auth, FlutterSecureStorage? storage})
      : _auth = auth ?? LocalAuthentication(),
        _storage = storage ?? const FlutterSecureStorage();

  /// Per account, like the addresses: two people sharing a phone should not share the choice, and
  /// one of them turning it on must not lock the other out of their own session.
  static const String _keyPrefix = 'delivery.biometric.';

  final LocalAuthentication _auth;
  final FlutterSecureStorage _storage;

  /// Whether this phone can do it at all: hardware present AND an enrolled finger or face.
  ///
  /// Both halves matter. A phone with a sensor and nothing enrolled reports the hardware happily
  /// and then fails at the prompt, so offering the option on hardware alone produces a setting that
  /// Whether anybody on this device turned it on.
  ///
  /// The sign-in screen has no session yet, so it cannot ask about a particular account — it needs
  /// to know whether to offer the key at all before it knows whose key it would be.
  Future<bool> isEnabledForAnyone() async {
    try {
      final Map<String, String> all = await _storage.readAll();
      return all.entries.any((MapEntry<String, String> e) =>
          e.key.startsWith(_keyPrefix) && e.value == 'true');
    } catch (_) {
      return false;
    }
  }

  /// cannot be used.
  Future<bool> get isAvailable async {
    try {
      final bool supported = await _auth.isDeviceSupported();
      final bool canCheck = await _auth.canCheckBiometrics;
      final List<BiometricType> enrolled = await _auth.getAvailableBiometrics();
      // Logged because every "the fingerprint does not work" report comes down to which of these
      // three is false, and none of them is visible from the outside.
      debugPrint('BIOMETRICS supported=$supported canCheck=$canCheck enrolled=$enrolled');
      return supported && canCheck && enrolled.isNotEmpty;
    } on PlatformException catch (e) {
      // The code distinguishes 'no finger enrolled' from 'sensor locked out' from 'the plugin is
      // not wired up', and none of those look any different on screen.
      debugPrint('BIOMETRICS availability check failed: ${e.code} ${e.message}');
      return false;
    }
  }

  Future<bool> isEnabledFor(String? userId) async {
    if (userId == null) return false;
    try {
      return await _storage.read(key: '$_keyPrefix$userId') == 'true';
    } catch (_) {
      // Unreadable means not enabled. Failing open here would unlock; failing closed only asks for
      // a passcode, which is the safe direction to be wrong in.
      return false;
    }
  }

  Future<void> setEnabledFor(String? userId, bool enabled) async {
    if (userId == null) return;
    final String key = '$_keyPrefix$userId';
    if (enabled) {
      await _storage.write(key: key, value: 'true');
    } else {
      await _storage.delete(key: key);
    }
  }

  /// Shows the system prompt. True only on a positive identification.
  ///
  /// [reason] is what the OS shows the user. Anything thrown is treated as "not verified" — a
  /// locked-out sensor, a cancelled prompt and a missing enrolment all mean the same thing here,
  /// which is that the session stays closed.
  Future<BiometricResult> authenticate(String reason) async {
    try {
      final bool ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          // The system passcode is a legitimate fallback: it is the same secret that unlocks the
          // phone, and refusing it would strand somebody with a wet or injured finger.
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      return ok ? BiometricResult.ok : BiometricResult.refused;
    } on PlatformException catch (e) {
      // The code distinguishes 'no finger enrolled' from 'sensor locked out' from 'the plugin is
      // not wired up', and none of those look any different on screen.
      debugPrint('BIOMETRICS prompt failed: ${e.code} ${e.message}');
      if (e.code == auth_error.notEnrolled || e.code == auth_error.notAvailable) {
        return BiometricResult.unavailable;
      }
      return BiometricResult.refused;
    }
  }
}

enum BiometricResult {
  ok,

  /// Wrong finger, cancelled, or too many attempts. The session stays locked and the passcode is
  /// still a way through.
  refused,

  /// The sensor or the enrolment went away since the setting was turned on — a finger removed in
  /// phone settings, most likely. Treated as "stop asking", not as a failure to retry.
  unavailable,
}
