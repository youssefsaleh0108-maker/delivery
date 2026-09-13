import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Whether YouDrop can be reached right now — learned from the app's own traffic, not from the
/// phone's network settings.
///
/// **Why not the operating system's signal** (`connectivity_plus` and friends). What that reports
/// is whether an interface is up, and in Lebanon the common failure is an interface that is up
/// with nothing behind it: the building's Wi-Fi router is on the generator while the ISP's
/// cabinet down the street is not, or mobile data shows full bars and moves nothing. An OS signal
/// says "online" in exactly the cases this exists for, and a banner that says online while every
/// request fails is worse than no banner. It would also be a new plugin and, on some platforms, a
/// new permission, for a worse answer.
///
/// **What proves reachability is a response from the platform.** So:
///
/// * any response through the shared Dio — 2xx, 4xx and 5xx alike — means reachable. A 401 or a
///   422 is the gateway answering; it says nothing about the network;
/// * a request that fails with **no response** for a network reason — refused, reset, DNS, a
///   connect or send timeout — means unreachable ([isUnreachable]);
/// * a receive timeout changes nothing. The request left and the server is slow; calling that
///   "offline" would put the banner up every time a busy endpoint takes twenty seconds;
/// * while unreachable, a probe (one tiny request, any status counts) re-checks on a backoff from
///   [minProbeDelay] to [maxProbeDelay], so the return of the connection is noticed even when no
///   screen is asking for anything.
///
/// Starts out online. The first failed request is the first moment there is evidence otherwise,
/// and a banner on every cold start would be a lie on the phones that are fine.
///
/// Rider and merchant traffic goes through the same Dio and keeps this honest there too; only the
/// customer shell draws it today.
class ConnectivityService extends ChangeNotifier implements ValueListenable<bool> {
  ConnectivityService({
    this.minProbeDelay = const Duration(seconds: 2),
    this.maxProbeDelay = const Duration(seconds: 30),
  }) : _nextDelay = minProbeDelay;

  final Duration minProbeDelay;
  final Duration maxProbeDelay;

  bool _online = true;
  Future<bool> Function()? _probe;
  Timer? _probeTimer;
  Duration _nextDelay;
  bool _probing = false;
  bool _disposed = false;

  /// True unless the last evidence was a request that could not reach the platform.
  bool get isOnline => _online;

  @override
  bool get value => _online;

  /// Installs the re-check used while unreachable: it resolves true when the platform answered
  /// with anything at all. [ApiClient.create] installs one against the gateway; a test installs a
  /// fake.
  void useProbe(Future<bool> Function() probe) {
    _probe = probe;
    if (!_online) _schedule();
  }

  /// A response arrived. Cancels any pending re-check.
  void reportReachable() {
    _probeTimer?.cancel();
    _probeTimer = null;
    _nextDelay = minProbeDelay;
    if (_online) return;
    _online = true;
    notifyListeners();
  }

  /// A request failed without reaching the platform.
  void reportUnreachable() {
    if (!_online) return;
    _online = false;
    _nextDelay = minProbeDelay;
    _schedule();
    notifyListeners();
  }

  /// Checks now instead of waiting out the backoff — for a customer tapping "try again", or an
  /// app coming back to the foreground. A no-op while online or while a check is in flight.
  Future<void> recheck() async {
    final Future<bool> Function()? probe = _probe;
    if (_online || probe == null || _probing || _disposed) return;
    _probing = true;
    bool reached = false;
    try {
      reached = await probe();
    } catch (_) {
      reached = false;
    } finally {
      _probing = false;
    }
    if (_disposed) return;
    if (reached) {
      reportReachable();
    } else {
      _schedule();
    }
  }

  void _schedule() {
    if (_probe == null || _disposed || _online) return;
    _probeTimer?.cancel();
    final Duration delay = _nextDelay;
    _nextDelay = Duration(
        microseconds: math.min(delay.inMicroseconds * 2, maxProbeDelay.inMicroseconds));
    _probeTimer = Timer(delay, recheck);
  }

  @override
  void dispose() {
    _disposed = true;
    _probeTimer?.cancel();
    super.dispose();
  }

  /// A request that never reached the platform, for a reason that is the network's.
  ///
  /// The only failures that say "offline". Anything with a response is the platform answering, and
  /// a receive timeout is a slow server, not a missing network.
  static bool isUnreachable(DioException e) =>
      e.response == null &&
      (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout);

  /// A request whose outcome nobody knows: it may never have arrived, or it may have been acted
  /// on with the answer lost on the way back.
  ///
  /// The case an Idempotency-Key exists for. A placement that ends like this must be retried with
  /// the SAME key — never with a new one, and never simply abandoned as if it had failed.
  static bool outcomeUnknown(DioException e) =>
      isUnreachable(e) ||
      (e.response == null && e.type == DioExceptionType.receiveTimeout);
}

/// Feeds [ConnectivityService] from every request the shared Dio makes. Installed by
/// [ApiClient.create]; see [ConnectivityService] for what counts as what.
class ConnectivityInterceptor extends Interceptor {
  ConnectivityInterceptor(this._connectivity);

  final ConnectivityService _connectivity;

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _connectivity.reportReachable();
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response != null) {
      _connectivity.reportReachable();
    } else if (ConnectivityService.isUnreachable(err)) {
      _connectivity.reportUnreachable();
    }
    handler.next(err);
  }
}
