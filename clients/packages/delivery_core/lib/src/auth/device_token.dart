import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Registers this device for push, against the signed-in account.
///
/// The token is written to the user's own Keycloak profile through the Account API, using their
/// access token. Not through a platform service: the realm's user-profile config already declares
/// `fcmToken` as editable by "user", and routing it through a service instead would mean giving
/// that service manage-users — the right to rewrite anybody's profile — to store a value the owner
/// is allowed to store themselves.
///
/// Notifications Manager reads the same attribute when it turns an order event into a push, so
/// nothing else has to change for a device to start receiving them.
class DeviceTokenRegistrar {
  DeviceTokenRegistrar({
    required Dio dio,
    required String issuer,
    FirebaseMessaging? messaging,
  })  : _dio = dio,
        _issuer = issuer,
        _messaging = messaging ?? FirebaseMessaging.instance;

  static const String _attribute = 'fcmToken';

  final Dio _dio;
  final String _issuer;
  final FirebaseMessaging _messaging;

  /// Asks for permission, reads the token and saves it. Safe to call on every sign-in.
  ///
  /// Every failure is swallowed. Push is an enhancement — a denied permission, a device with no
  /// Play Services, or a Firebase project that has not been configured yet must not stop somebody
  /// using the app, and none of those are things the person signing in can act on.
  Future<void> register() async {
    try {
      final NotificationSettings settings = await _messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      final String? token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;

      await _save(token);

      // The token is rotated by the OS — on reinstall, on restore to a new device, and
      // occasionally on its own. Without this the platform keeps pushing to a token that stopped
      // existing, which fails silently at the provider and looks like push simply not working.
      _messaging.onTokenRefresh.listen(_save);
    } catch (_) {
      // Deliberately quiet. See the note above.
    }
  }

  Future<void> _save(String token) async {
    // Read, merge, write. Keycloak's account endpoint replaces the representation it is given, so
    // posting only the attribute would clear the name and email off the profile.
    final Response<dynamic> current = await _dio.get<dynamic>('$_issuer/account');
    final Map<String, dynamic> profile =
        Map<String, dynamic>.from(current.data as Map<String, dynamic>);

    final Map<String, dynamic> attributes =
        Map<String, dynamic>.from(profile['attributes'] as Map<String, dynamic>? ?? <String, dynamic>{});
    if (attributes[_attribute] is List &&
        (attributes[_attribute] as List<dynamic>).firstOrNull == token) {
      // Already ours. Writing it again on every launch is a round trip that changes nothing.
      return;
    }
    attributes[_attribute] = <String>[token];
    profile['attributes'] = attributes;

    await _dio.post<dynamic>('$_issuer/account', data: profile);
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
