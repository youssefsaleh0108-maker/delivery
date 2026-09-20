import 'dart:math';

import 'package:delivery_core/delivery_core.dart';
import 'package:flutter/foundation.dart';

/// `--dart-define=RIDER_SIMULATED_GPS=true`: asks a DEBUG build to simulate the rider's GPS.
///
/// Only ever read together with `kDebugMode`, at the one place a location source is chosen
/// (`main.dart`). Both are compile-time constants there, so in a profile or release build the
/// simulated branch is dead code and the simulator is compiled out — whatever defines the build
/// was given. There is no switch in any build a rider installs that fakes a position.
const bool riderGpsSimulationRequested = bool.fromEnvironment('RIDER_SIMULATED_GPS');

/// `--dart-define=RIDER_SIM_ORIGIN=33.8938,35.5018`: where the simulated rider starts when they
/// hold no order with a shop pin. Unset means no fallback, and then no position at all.
const String _originDefine = String.fromEnvironment('RIDER_SIM_ORIGIN');

/// A rider walking around a shop, for exercising the tracking pipeline on an emulator or a desk.
///
/// **Debug builds only.** The constructor refuses to run anywhere else, as a second lock behind
/// the compile-time guard at the call site: even a build that somehow reached this class could not
/// produce one fake position.
///
/// **Where it starts.** At the shop pin of the rider's first live order, so the ETA a customer is
/// shown measures from somewhere plausible; failing that, at `RIDER_SIM_ORIGIN`. With neither, it
/// has no position and says so — it never invents a city. The London constant this replaces put a
/// rider three thousand kilometres from every door in Lebanon.
///
/// **How it moves.** Up to about 20 m per axis per reading: slow enough that the tracking service's
/// jump check believes it, fast enough that the reporter's 25 m distance filter sees movement some
/// of the time and a heartbeat the rest.
class SimulatedRiderLocationSource extends RiderLocationSource {
  SimulatedRiderLocationSource({required this.shopPin, Random? random})
      : _random = random ?? Random() {
    ensureDebugBuild(kDebugMode);
  }

  /// The pin of the shop the rider is heading to, if there is one.
  final Future<({double lat, double lng})?> Function() shopPin;

  final Random _random;
  ({double lat, double lng})? _position;

  /// Throws unless [debugBuild]. The constructor passes `kDebugMode`.
  @visibleForTesting
  static void ensureDebugBuild(bool debugBuild) {
    if (!debugBuild) {
      throw UnsupportedError('The simulated rider location exists only in debug builds.');
    }
  }

  /// `"lat,lng"` to a point, or null for anything that is not two in-range numbers.
  @visibleForTesting
  static ({double lat, double lng})? parseOrigin(String raw) {
    final List<String> parts = raw.split(',');
    if (parts.length != 2) return null;
    final double? lat = double.tryParse(parts[0].trim());
    final double? lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) return null;
    return (lat: lat, lng: lng);
  }

  @override
  Future<RiderLocationAccess> access({required bool ask}) async => RiderLocationAccess.granted;

  @override
  Future<RiderFix?> current() async {
    final ({double lat, double lng})? from = _position ?? await _origin();
    if (from == null) return null;
    final ({double lat, double lng}) next = (
      lat: from.lat + (_random.nextDouble() - 0.5) * 0.0004,
      lng: from.lng + (_random.nextDouble() - 0.5) * 0.0004,
    );
    _position = next;
    return RiderFix(
      latitude: next.lat,
      longitude: next.lng,
      accuracyM: 8,
      takenAt: DateTime.now().toUtc(),
    );
  }

  Future<({double lat, double lng})?> _origin() async {
    try {
      final ({double lat, double lng})? pin = await shopPin();
      if (pin != null) return pin;
    } catch (_) {
      // No shop to start at; the define is the only other honest start.
    }
    return parseOrigin(_originDefine);
  }

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> openLocationSettings() async {}
}
