import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// One reading from the phone's location sensor, as the rider app reports it.
///
/// Richer than [LocationFix] on purpose. A map picker only needs a point to centre on; a rider's
/// report is judged by the tracking service on how precise it is, when it was taken and whether it
/// came from a mock-location app, so all three travel with the point.
class RiderFix {
  const RiderFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.takenAt,
    this.mocked = false,
  });

  /// WGS-84, the datum the maps and the server use.
  final double latitude;
  final double longitude;

  /// The sensor's own radius of uncertainty, in metres.
  final double accuracyM;

  /// When the sensor took the fix, in UTC. Not when the app received it: a cached last-known
  /// position can be minutes old, and that age is exactly what the server checks.
  final DateTime takenAt;

  /// True when Android says the fix came from a mock-location provider — a "fake GPS" app chosen
  /// in developer options. Never sent: it is a fake position however it was produced.
  final bool mocked;

  /// How old the fix is at [now].
  Duration ageAt(DateTime now) => now.toUtc().difference(takenAt.toUtc());
}

/// Whether the rider app may read the phone's location right now — and if not, which of the
/// refusals it is, because each one has a different way out.
enum RiderLocationAccess {
  /// Location is allowed, precisely, while the app is in use.
  granted,

  /// The phone's location switch is off. The way out is the system location settings.
  servicesOff,

  /// The permission was refused, but the app may still ask again.
  denied,

  /// Refused for good (or asked too often). Only this app's settings page can undo it.
  deniedForever,

  /// Allowed, but only "approximate" — a fix kilometres wide, which cannot place a rider on a
  /// street and which the server refuses. The way out is the app's settings page.
  approximate,

  /// The platform could not say: no plugin (tests, desktop), or a browser without the API.
  unavailable,
}

/// Where the rider's position comes from.
///
/// An interface so the rider screen can be driven by a scripted source in tests and, in debug
/// builds only, by a simulator — never by anything that invents a position in a release build.
abstract class RiderLocationSource {
  const RiderLocationSource();

  /// Checks whether the location may be read. With [ask] true and the permission still askable,
  /// the operating system's prompt is shown first — foreground ("while using the app") only.
  Future<RiderLocationAccess> access({required bool ask});

  /// One fresh fix, or null when the sensor gives none in time. Never throws.
  Future<RiderFix?> current();

  /// This app's page in the system settings — the way back from a permanent refusal or an
  /// approximate-only grant.
  Future<void> openAppSettings();

  /// The system's location switch.
  Future<void> openLocationSettings();
}

/// The phone's real location, through geolocator.
///
/// One-shot readings rather than a position stream. The rider app samples on its own timer, so a
/// stream would only add a second cadence to reason about — and geolocator's Android stream
/// silently delivers nothing if its bound service has not connected yet, where a one-shot does not
/// depend on the service at all. Between samples the GPS is free to idle, which a continuous
/// stream at the same rate would not allow.
///
/// Foreground only, by construction: nothing here requests background location, and no
/// foreground-service notification config is ever passed — the one thing that would let
/// geolocator keep reading with the app closed.
class DeviceRiderLocationSource extends RiderLocationSource {
  const DeviceRiderLocationSource();

  /// How long one reading may take before it is given up on. Under the rider app's shortest
  /// sampling interval, so a slow fix never overlaps the next attempt.
  static const Duration readingTimeout = Duration(seconds: 8);

  /// The oldest last-known position used when a fresh reading times out. Half the server's age
  /// limit, so it still arrives inside it; older and it says where the rider was, not is.
  static const Duration lastKnownMaxAge = Duration(seconds: 30);

  @override
  Future<RiderLocationAccess> access({required bool ask}) async {
    try {
      // On the web the browser's prompt is also the service switch, so there is nothing to check.
      if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) {
        return RiderLocationAccess.servicesOff;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      // Only "denied" is askable. Asking after "deniedForever" shows nothing and answers at once,
      // so the app would look as if it asked when it did not.
      if (permission == LocationPermission.denied && ask) {
        permission = await Geolocator.requestPermission();
      }
      switch (permission) {
        case LocationPermission.denied:
          return RiderLocationAccess.denied;
        case LocationPermission.deniedForever:
          return RiderLocationAccess.deniedForever;
        case LocationPermission.unableToDetermine:
          return RiderLocationAccess.unavailable;
        case LocationPermission.whileInUse:
        case LocationPermission.always:
          // "Always" is never asked for, but a rider may have granted it in settings; it changes
          // nothing here, where every reading happens with the app open.
          break;
      }

      if (!kIsWeb && await _isApproximate()) {
        return RiderLocationAccess.approximate;
      }
      return RiderLocationAccess.granted;
    } catch (_) {
      // No plugin (flutter test, desktop) or a platform error: nothing can be read either way.
      return RiderLocationAccess.unavailable;
    }
  }

  /// Android 12+ and iOS 14+ let a person grant location while withholding precision.
  Future<bool> _isApproximate() async {
    try {
      return await Geolocator.getLocationAccuracy() == LocationAccuracyStatus.reduced;
    } catch (_) {
      // Older platforms have no such setting; the per-fix accuracy check still applies.
      return false;
    }
  }

  @override
  Future<RiderFix?> current() async {
    try {
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: readingTimeout,
        ),
      );
      return _fixOf(position);
    } catch (_) {
      // A timeout indoors is normal, and the phone's last-known position may still be recent —
      // but only a recent one is used. Unlike the map pickers, which happily centre on an old
      // position, a rider's report claims to be where they are now.
      try {
        final Position? last = await Geolocator.getLastKnownPosition();
        if (last == null) return null;
        final RiderFix fix = _fixOf(last);
        return fix.ageAt(DateTime.now()) <= lastKnownMaxAge ? fix : null;
      } catch (_) {
        return null;
      }
    }
  }

  static RiderFix _fixOf(Position position) => RiderFix(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyM: position.accuracy,
        takenAt: position.timestamp.toUtc(),
        mocked: position.isMocked,
      );

  @override
  Future<void> openAppSettings() async {
    if (kIsWeb) return;
    try {
      await Geolocator.openAppSettings();
    } catch (_) {
      // A settings screen that fails to open is not worth a crash.
    }
  }

  @override
  Future<void> openLocationSettings() async {
    if (kIsWeb) return;
    try {
      await Geolocator.openLocationSettings();
    } catch (_) {}
  }
}
