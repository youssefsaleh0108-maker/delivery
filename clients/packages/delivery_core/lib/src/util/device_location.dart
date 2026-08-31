import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Where the phone is right now — or the reason it will not say.
///
/// A sealed result rather than a nullable point, because the pickers word each refusal
/// differently: services off is "turn on location", denied is "allow the permission", and a
/// timeout is "could not get a fix". Collapsing those into null forced one vague message for
/// three different problems.
sealed class DeviceLocationResult {
  const DeviceLocationResult();
}

/// A fix. [latitude]/[longitude] are WGS84, the same datum the maps and the server use.
class LocationFix extends DeviceLocationResult {
  const LocationFix(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

/// Location services are off system-wide. [DeviceLocation.openLocationSettings] is the way out.
class LocationServicesOff extends DeviceLocationResult {
  const LocationServicesOff();
}

/// Asked, and refused — but askable again next time.
class LocationDenied extends DeviceLocationResult {
  const LocationDenied();
}

/// Refused permanently. Only the app's OS settings page can undo this, so the UI should offer
/// [DeviceLocation.openAppSettings] rather than asking again into a void.
class LocationDeniedForever extends DeviceLocationResult {
  const LocationDeniedForever();
}

/// The sensor did not answer in time, or the platform has no implementation (tests, desktop).
class LocationFailed extends DeviceLocationResult {
  const LocationFailed();
}

/// One question — "where is this device?" — asked the polite way: services first, then
/// permission, then the fix itself, each refusal reported as its own case.
///
/// Static and dependency-free so the pickers can call it directly; widget tests never reach it
/// because every picker treats [LocationFailed] as "carry on without", which is also what the
/// missing plugin produces under `flutter test`.
class DeviceLocation {
  const DeviceLocation._();

  /// How long a fix may take before it is called a failure. Long enough for a cold GPS under an
  /// open sky, short enough that the picker's spinner is not a lie.
  static const Duration timeout = Duration(seconds: 12);

  static Future<DeviceLocationResult> current() async {
    try {
      // On web the browser owns this dialog and the service question is meaningless — the
      // permission prompt IS the service prompt — so the check is skipped there.
      if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) {
        return const LocationServicesOff();
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return const LocationDenied();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationDeniedForever();
      }

      try {
        final Position position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            // High, not best: a shop pin and a delivery door both live at street precision, and
            // `best` keeps the GPS hunting well past the point anybody is still watching a
            // spinner.
            accuracy: LocationAccuracy.high,
            timeLimit: timeout,
          ),
        );
        return LocationFix(position.latitude, position.longitude);
      } catch (_) {
        // A fresh fix timing out is the NORMAL indoor case — under a roof, between Beirut
        // buildings, in a basement shop. The phone's fused last-known position is usually
        // minutes old and street-accurate, and a slightly stale pin the user can nudge beats a
        // button that just fails. Only when the phone has never had a fix at all does this fall
        // through to failure.
        final Position? last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          return LocationFix(last.latitude, last.longitude);
        }
        return const LocationFailed();
      }
    } catch (_) {
      // A platform without the plugin, a browser that refused — all the same to the caller: no
      // fix, carry on from the fallback view.
      return const LocationFailed();
    }
  }

  /// Opens the system's location-services screen (the master switch). No-op on web.
  static Future<void> openLocationSettings() async {
    if (kIsWeb) return;
    try {
      await Geolocator.openLocationSettings();
    } catch (_) {
      // The settings screen failing to open is not worth a crash.
    }
  }

  /// Opens this app's own settings page — the only way back from [LocationDeniedForever].
  static Future<void> openAppSettings() async {
    if (kIsWeb) return;
    try {
      await Geolocator.openAppSettings();
    } catch (_) {}
  }
}
