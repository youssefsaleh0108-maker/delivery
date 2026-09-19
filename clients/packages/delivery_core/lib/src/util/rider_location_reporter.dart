import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'rider_location.dart';

/// What the rider should be told about their location right now.
///
/// [hidesRider] marks the states in which the rider is working and customers cannot see them —
/// the ones the rider app puts a banner up for. Each has its own way out, which is why they are
/// separate states rather than one "location unavailable".
enum RiderLocationStatus {
  /// Nothing needs sharing: off duty with no delivery, or the app is not in the foreground.
  idle(false),

  /// Needed and allowed; the first usable fix has not been sent yet.
  locating(false),

  /// Fixes are reaching the platform.
  sharing(false),

  /// The phone's location switch is off.
  servicesOff(true),

  /// The permission was refused and can still be asked for.
  denied(true),

  /// The permission was refused for good; only the app's settings page can undo it.
  deniedForever(true),

  /// Only an approximate location is allowed, which cannot place a rider on a street.
  approximate(true),

  /// The fixes come from a mock-location app, so none of them is sent.
  mocked(true),

  /// No usable fix: no signal, or nothing precise enough to send, for a while now.
  noFix(true),

  /// The platform keeps refusing the fixes as dated in the future or too old: the phone's clock
  /// is wrong, which only the rider can put right.
  clockWrong(true);

  const RiderLocationStatus(this.hidesRider);

  final bool hidesRider;
}

/// Sends one fix on one of the rider's orders (`POST /api/tracking/orders/{id}/ping`).
typedef RiderOrderPing = Future<void> Function(String orderId, RiderFix fix);

/// Sends one fix with no order (`POST /api/tracking/riders/me/ping`).
typedef RiderPresencePing = Future<void> Function(RiderFix fix);

/// Reports the rider's real position while — and only while — somebody needs it.
///
/// **When.** Only with the app in the foreground ([setForeground]) and the rider either declared on
/// duty or holding a claimed READY or PICKED_UP order ([setDemand]). That is the owner's rule:
/// foreground only, no background-location permission. Leaving either condition stops the timer
/// at once, so a rider who switches to a navigation app or goes off duty stops being tracked, and
/// a customer's map shows them as last seen rather than following them.
///
/// **What.** Only fixes the phone actually produced. There is no fallback position of any kind:
/// no fix, no ping. A fix from a mock-location app is never sent, and neither is one wider than
/// [maxAccuracyM] — the server refuses those too, so sending them would only spend data.
///
/// **How often.** A one-shot reading every [activeInterval] with a delivery in hand (a customer
/// may be watching), every other tick without one (the roster only needs the rider's area). A
/// reading is sent when the rider has moved [minMoveM] since the last one sent, or [heartbeat]
/// has passed — never more often than [sendFloor]. Standing still at a counter therefore costs
/// one ping every forty seconds instead of one every ten, which is what keeps them on the roster
/// (whose presence window is two minutes) and nothing more.
///
/// **Where.** With orders in hand, every fix goes on each order, and nothing else: an order ping
/// already counts as presence on the server, so a second, order-less ping per fix would be the same
/// write twice. The order-less ping is only for a rider on duty with nothing in hand.
///
/// **What the rider is told.** [status]. Permission and settings problems come from the platform
/// and are re-checked on every tick and every return to the foreground, so fixing them in the
/// system settings takes effect without the rider having to do anything else here.
class RiderLocationReporter extends ChangeNotifier {
  RiderLocationReporter({
    required RiderLocationSource source,
    required RiderOrderPing pingOrder,
    RiderPresencePing? pingRider,
  })  : _source = source,
        _pingOrder = pingOrder,
        _pingRider = pingRider;

  /// Reading cadence with a delivery in hand. Matches the tracking service's rider ping interval:
  /// every reduction multiplies writes across every active rider.
  static const Duration activeInterval = Duration(seconds: 10);

  /// The fewest seconds between two sends, whatever the movement.
  static const Duration sendFloor = Duration(seconds: 10);

  /// The longest a rider who is standing still goes without a send.
  static const Duration heartbeat = Duration(seconds: 40);

  /// Movement smaller than this is GPS jitter to a customer's map, not a rider moving.
  static const double minMoveM = 25;

  /// Wider than this and the fix cannot place a rider on a street. The server's own limit.
  static const double maxAccuracyM = 100;

  /// How long a rider stays "sharing" after their last send while readings are unusable — so one
  /// bad reading under a roof does not flash a banner.
  static const Duration sharingGrace = Duration(seconds: 90);

  /// Consecutive clock refusals before the rider is told their phone's clock is wrong. One is a
  /// hiccup; three in a row, ten seconds apart, is the clock.
  static const int clockRefusalsBeforeTelling = 3;

  /// Timers are not exact. Comparing elapsed time with the tick length itself would fail by
  /// milliseconds and silently halve every cadence above.
  static const Duration _timerSlack = Duration(seconds: 2);

  final RiderLocationSource _source;
  final RiderOrderPing _pingOrder;
  final RiderPresencePing? _pingRider;

  RiderLocationStatus _status = RiderLocationStatus.idle;

  bool _foreground = true;
  bool _onDuty = false;
  List<String> _orderIds = const <String>[];

  bool _running = false;
  bool _disposed = false;

  /// Bumped on every stop, so work that finishes after the app went to the background can tell it
  /// no longer has anything to report to.
  int _generation = 0;

  /// The operating system's prompt gets one automatic showing per session; after that only the
  /// rider asks for it again ([askAgain]). Re-prompting on every tick would be nagging, and after
  /// two refusals Android stops showing it anyway.
  bool _asked = false;

  RiderLocationAccess? _access;
  Timer? _timer;
  int _ticks = 0;
  bool _sampling = false;
  bool _forceNext = false;
  RiderFix? _lastSent;
  DateTime? _lastSentAt;
  int _clockRefusals = 0;

  /// What to tell the rider. See [RiderLocationStatus.hidesRider].
  RiderLocationStatus get status => _status;

  /// Whether the rider's location is wanted right now.
  bool get needed => _foreground && (_onDuty || _orderIds.isNotEmpty);

  /// When a fix last reached the platform, by this phone's clock. Null until one has.
  DateTime? get lastSentAt => _lastSentAt;

  /// The app came to the foreground ([foreground] true) or left it.
  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    _reconcile();
  }

  /// What the rider is doing: declared on duty or not, and the orders in their hands that a
  /// customer may be watching — claimed READY and PICKED_UP ones.
  void setDemand({required bool onDuty, required Iterable<String> orderIds}) {
    final List<String> ids = <String>[
      for (final String id in orderIds.toSet()) id,
    ];
    final bool added = ids.any((String id) => !_orderIds.contains(id));
    _onDuty = onDuty;
    _orderIds = ids;
    _reconcile();
    if (added && _running && _access == RiderLocationAccess.granted) {
      // A newly claimed order's customer should see the rider now, not after the next movement
      // or heartbeat.
      _forceNext = true;
      unawaited(sample());
    }
  }

  /// The banner's "allow" button: shows the system prompt again.
  Future<void> askAgain() async {
    if (!_running) return;
    await _checkAccess(ask: true, generation: _generation);
    if (_access == RiderLocationAccess.granted) {
      await sample();
    }
  }

  /// The banner's settings button: the location switch when that is what is off, otherwise this
  /// app's own page.
  Future<void> openSettings() => _status == RiderLocationStatus.servicesOff
      ? _source.openLocationSettings()
      : _source.openAppSettings();

  void _reconcile() {
    if (_disposed) return;
    if (needed) {
      if (!_running) unawaited(_start());
    } else {
      _stop();
    }
  }

  Future<void> _start() async {
    _running = true;
    final int generation = ++_generation;
    _ticks = 0;
    _setStatus(RiderLocationStatus.locating);
    _timer = Timer.periodic(activeInterval, (_) => unawaited(_tick()));

    final bool ask = !_asked;
    _asked = true;
    await _checkAccess(ask: ask, generation: generation);
    if (generation == _generation && _access == RiderLocationAccess.granted) {
      // The first fix now, rather than one tick from now.
      await sample();
    }
  }

  void _stop() {
    if (!_running) return;
    _running = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
    // Asked again on the next start: the rider may be coming back from the settings page.
    _access = null;
    _setStatus(RiderLocationStatus.idle);
  }

  Future<void> _tick() async {
    if (!_running || _sampling) return;
    _ticks++;
    if (_orderIds.isEmpty && _ticks.isOdd) return;
    if (_access != RiderLocationAccess.granted) {
      await _checkAccess(ask: false, generation: _generation);
      if (_access != RiderLocationAccess.granted) return;
    }
    await sample();
  }

  Future<void> _checkAccess({required bool ask, required int generation}) async {
    final RiderLocationAccess access = await _source.access(ask: ask);
    if (generation != _generation || _disposed) return;
    _access = access;
    switch (access) {
      case RiderLocationAccess.granted:
        if (_status.hidesRider) _setStatus(RiderLocationStatus.locating);
      case RiderLocationAccess.servicesOff:
        _setStatus(RiderLocationStatus.servicesOff);
      case RiderLocationAccess.denied:
        _setStatus(RiderLocationStatus.denied);
      case RiderLocationAccess.deniedForever:
        _setStatus(RiderLocationStatus.deniedForever);
      case RiderLocationAccess.approximate:
        _setStatus(RiderLocationStatus.approximate);
      case RiderLocationAccess.unavailable:
        _setStatus(RiderLocationStatus.noFix);
    }
  }

  /// One reading, and a send if one is due. The timer calls it; tests call it directly.
  @visibleForTesting
  Future<void> sample() async {
    if (!_running || _sampling) return;
    _sampling = true;
    final int generation = _generation;
    try {
      final RiderFix? fix = await _source.current();
      if (generation != _generation) return;
      final DateTime now = clock.now();

      if (fix == null) {
        // No reading at all. Ask the platform why before calling it weak signal: the switch may
        // have been turned off from the notification shade, which changes nothing else here.
        await _checkAccess(ask: false, generation: generation);
        if (_access == RiderLocationAccess.granted) _unusable(now);
        return;
      }
      if (fix.mocked) {
        _setStatus(RiderLocationStatus.mocked);
        return;
      }
      if (fix.accuracyM > maxAccuracyM) {
        _unusable(now);
        return;
      }
      if (_due(fix, now)) {
        await _send(fix, generation);
      } else if (_status.hidesRider) {
        // A good reading that is not due means a fix was sent within the heartbeat, so the rider
        // is on the map; a banner left over from a mock app or a weak spot is no longer true.
        _setStatus(RiderLocationStatus.sharing);
      }
    } finally {
      _sampling = false;
    }
  }

  void _unusable(DateTime now) {
    final DateTime? sentAt = _lastSentAt;
    if (sentAt == null || now.difference(sentAt) > sharingGrace) {
      _setStatus(RiderLocationStatus.noFix);
    }
  }

  bool _due(RiderFix fix, DateTime now) {
    final RiderFix? last = _lastSent;
    final DateTime? sentAt = _lastSentAt;
    if (last == null || sentAt == null) return true;
    final Duration since = now.difference(sentAt) + _timerSlack;
    if (since < sendFloor) return false;
    return _forceNext || metresBetween(last, fix) >= minMoveM || since >= heartbeat;
  }

  Future<void> _send(RiderFix fix, int generation) async {
    final List<String> orders = List<String>.of(_orderIds);
    final RiderPresencePing? pingRider = _pingRider;
    final List<_Outcome> outcomes = <_Outcome>[];
    if (orders.isNotEmpty) {
      for (final String orderId in orders) {
        // Backgrounded halfway through: the rest of this fix stays on the phone.
        if (generation != _generation) break;
        outcomes.add(await _attempt(() => _pingOrder(orderId, fix)));
      }
    } else if (_onDuty && pingRider != null) {
      outcomes.add(await _attempt(() => pingRider(fix)));
    } else {
      return;
    }

    if (outcomes.contains(_Outcome.delivered)) {
      _lastSent = fix;
      _lastSentAt = clock.now();
      _forceNext = false;
      _clockRefusals = 0;
      if (generation == _generation) _setStatus(RiderLocationStatus.sharing);
    } else if (outcomes.contains(_Outcome.clockRefused)) {
      _clockRefusals++;
      if (generation == _generation && _clockRefusals >= clockRefusalsBeforeTelling) {
        _setStatus(RiderLocationStatus.clockWrong);
      }
    }
  }

  /// One ping, its failure reduced to what the reporter acts on. A dropped ping is replaced by the
  /// next one, so nothing here is ever surfaced as an error.
  static Future<_Outcome> _attempt(Future<void> Function() ping) async {
    try {
      await ping();
      return _Outcome.delivered;
    } on DioException catch (e) {
      if (e.response?.statusCode == 422 && _isClockReason(e.response?.data)) {
        return _Outcome.clockRefused;
      }
      return _Outcome.failed;
    } catch (_) {
      return _Outcome.failed;
    }
  }

  static bool _isClockReason(Object? body) {
    final Object? reason = body is Map ? body['reason'] : null;
    return reason == 'FIX_IN_FUTURE' || reason == 'FIX_TOO_OLD';
  }

  /// Great-circle distance in metres, on the same sphere the tracking service measures with.
  static double metresBetween(RiderFix a, RiderFix b) {
    const double earthRadiusM = 6371008.8;
    double rad(double degrees) => degrees * math.pi / 180;
    final double dLat = rad(b.latitude - a.latitude);
    final double dLng = rad(b.longitude - a.longitude);
    final double h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(a.latitude)) * math.cos(rad(b.latitude)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * earthRadiusM * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  void _setStatus(RiderLocationStatus status) {
    if (_disposed || _status == status) return;
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _running = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

enum _Outcome { delivered, clockRefused, failed }
