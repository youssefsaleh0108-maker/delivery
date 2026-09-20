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

  /// No usable fix: no signal, nothing precise enough to send, or the platform keeps refusing
  /// what is sent (outside the service area, an impossible jump) — for a while now.
  noFix(true),

  /// The platform keeps refusing the fixes as dated in the future or too old: the phone's clock
  /// is wrong, which only the rider can put right.
  clockWrong(true),

  /// The rider carries orders to more than one door and has not said which they are heading to,
  /// so no customer is shown them: a fix put on either order could show one customer the way to
  /// the other's door. Start navigation on one says which.
  legUnknown(true);

  const RiderLocationStatus(this.hidesRider);

  final bool hidesRider;
}

/// One of the rider's claimed orders, as the reporter needs it: which leg it is on, and where it
/// ends.
@immutable
class RiderLeg {
  const RiderLeg({required this.orderId, required this.collected, required this.dropOff});

  final String orderId;

  /// True once the order is picked up: its leg runs to the customer's door. Before that, to the
  /// shop.
  final bool collected;

  /// Where the order ends — its delivery address, as the order carries it. Two orders with the
  /// same address end at the same door.
  final String dropOff;

  /// The door, compared loosely: the same address typed with different spacing or capitals is
  /// one door, not two.
  String get door => dropOff.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  @override
  bool operator ==(Object other) =>
      other is RiderLeg &&
      other.orderId == orderId &&
      other.collected == collected &&
      other.dropOff == dropOff;

  @override
  int get hashCode => Object.hash(orderId, collected, dropOff);
}

/// Sends one fix on one of the rider's orders (`POST /api/tracking/orders/{id}/ping`).
typedef RiderOrderPing = Future<void> Function(String orderId, RiderFix fix);

/// Sends one fix with no order (`POST /api/tracking/riders/me/ping`).
typedef RiderPresencePing = Future<void> Function(RiderFix fix);

/// Asked right before the operating system's location prompt would be shown. True lets the prompt
/// go ahead; false leaves the permission as it is.
typedef RiderLocationExplanation = Future<bool> Function();

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
/// **Where — the active leg.** A fix goes on exactly one order: the one whose leg the rider is on
/// now, meaning the stop they are heading to — its shop before pickup, its door after. The server
/// shows a rider only to the customer (and, before pickup, the shop) of the order their latest fix
/// went on, so this choice is who sees the rider. It is read off the rider's own acts, newest
/// first ([activeOrderId]):
///
/// 1. **Start navigation** on an order ([headingTo]) is the rider saying where they are going. It
///    stands until they collect or hand over an order, which changes where they go next.
/// 2. Otherwise the order they last **claimed** (heading to its shop) or **picked up** (heading on
///    with it), or, with no such act seen yet, the first order on the Active tab.
///
/// …and never an order whose door is not where the rider can be heading. A rider can only be
/// heading to a customer's door if they carry that customer's order, so the doors that matter are
/// those of the orders already picked up. With none, any leg is safe: the rider is on the way to
/// a shop. With one door in the bag, the fix goes on an order to that door (the pointer if it is
/// one, the first such order if not) — never on another customer's order, which could show that
/// customer the way to this door. With two or more doors in the bag and no Start navigation since
/// the last pickup or hand-over, nobody can say which door is next: the fix goes on no order —
/// only to the rider's presence, so the fleet still sees them — and the rider is told
/// ([RiderLocationStatus.legUnknown]) that tapping Start navigation on the delivery they are
/// heading to is what puts it on that customer's map.
///
/// **What the rider is told.** [status]. Permission and settings problems come from the platform
/// and are re-checked (never re-prompted) before every reading and on every return to the
/// foreground, so fixing them in the system settings takes effect without the rider having to do
/// anything else here. Refusals from the tracking service surface too: three clock refusals in a
/// row as [RiderLocationStatus.clockWrong], three of any other kind as
/// [RiderLocationStatus.noFix] — never left looking like "locating".
///
/// **Before the prompt.** When the operating system's permission prompt is about to be shown,
/// [explainBeforeAsking] is asked first: the rider reads who will see their location, when, and
/// for how long, and only then sees the system's question.
class RiderLocationReporter extends ChangeNotifier {
  RiderLocationReporter({
    required RiderLocationSource source,
    required RiderOrderPing pingOrder,
    RiderPresencePing? pingRider,
    RiderLocationExplanation? explainBeforeAsking,
  })  : _source = source,
        _pingOrder = pingOrder,
        _pingRider = pingRider,
        _explainBeforeAsking = explainBeforeAsking;

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

  /// Consecutive refusals of one kind before the rider is told. One is a hiccup; three in a row,
  /// ten seconds apart, is the clock, or a position the platform will not take.
  static const int refusalsBeforeTelling = 3;

  /// Timers are not exact. Comparing elapsed time with the tick length itself would fail by
  /// milliseconds and silently halve every cadence above.
  static const Duration _timerSlack = Duration(seconds: 2);

  final RiderLocationSource _source;
  final RiderOrderPing _pingOrder;
  final RiderPresencePing? _pingRider;
  final RiderLocationExplanation? _explainBeforeAsking;

  RiderLocationStatus _status = RiderLocationStatus.idle;

  bool _foreground = true;
  bool _onDuty = false;
  List<RiderLeg> _legs = const <RiderLeg>[];

  /// Whether a demand has been seen yet. The orders present at the first one were not claimed in
  /// front of this reporter, so they say nothing about where the rider is heading.
  bool _seeded = false;

  /// The order the rider last claimed or picked up, or tapped Start navigation on.
  String? _lastActedOn;

  /// The order the rider last tapped Start navigation on, until a pickup or hand-over.
  String? _headingTo;

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
  RiderFix? _lastFix;
  int _clockRefusals = 0;
  int _otherRefusals = 0;

  /// What to tell the rider. See [RiderLocationStatus.hidesRider].
  RiderLocationStatus get status => _status;

  /// Whether the rider's location is wanted right now.
  bool get needed => _foreground && (_onDuty || _legs.isNotEmpty);

  /// When a fix last reached the platform, by this phone's clock. Null until one has.
  DateTime? get lastSentAt => _lastSentAt;

  /// The phone's own latest usable reading — not mocked, precise enough — whether or not it has
  /// been sent or accepted. What the rider's own map shows: where the rider is, not what the
  /// platform last stored (which, after an upgrade, can be an old build's simulated position).
  RiderFix? get lastFix => _lastFix;

  /// The order the next fix goes on, or null for none — see the class comment for the rule.
  String? get activeOrderId {
    final List<RiderLeg> legs = _legs;
    if (legs.isEmpty) return null;

    final RiderLeg? navigated = _legOf(_headingTo, legs);
    if (navigated != null) return navigated.orderId;

    final Set<String> carriedDoors = <String>{
      for (final RiderLeg leg in legs)
        if (leg.collected) leg.door,
    };
    if (carriedDoors.length > 1) return null;

    final List<RiderLeg> safe = carriedDoors.isEmpty
        ? legs
        : <RiderLeg>[
            for (final RiderLeg leg in legs)
              if (leg.door == carriedDoors.single) leg,
          ];
    return (_legOf(_lastActedOn, safe) ?? safe.first).orderId;
  }

  static RiderLeg? _legOf(String? orderId, List<RiderLeg> legs) {
    if (orderId == null) return null;
    for (final RiderLeg leg in legs) {
      if (leg.orderId == orderId) return leg;
    }
    return null;
  }

  /// The app came to the foreground ([foreground] true) or left it.
  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    _reconcile();
  }

  /// What the rider is doing: declared on duty or not, and the orders in their hands that a
  /// customer may be watching — claimed READY and PICKED_UP ones, in the Active tab's order.
  void setDemand({required bool onDuty, required Iterable<RiderLeg> legs}) {
    final Map<String, RiderLeg> byId = <String, RiderLeg>{
      for (final RiderLeg leg in legs) leg.orderId: leg,
    };
    final List<RiderLeg> next = byId.values.toList();
    final String? activeBefore = activeOrderId;
    final Map<String, RiderLeg> before = <String, RiderLeg>{
      for (final RiderLeg leg in _legs) leg.orderId: leg,
    };

    bool added = false;
    bool movedOn = false;
    for (final RiderLeg leg in next) {
      final RiderLeg? was = before[leg.orderId];
      if (was == null) {
        added = true;
        // A claim: heading to its shop. Not on the first demand — those orders were already in
        // hand when this reporter started, and were not claimed in front of it.
        if (_seeded) _lastActedOn = leg.orderId;
      } else if (leg.collected && !was.collected) {
        // A pickup: the rider goes on with it — or to another shop, or another door. Where the
        // bag holds several doors, only Start navigation can say which.
        _lastActedOn = leg.orderId;
        movedOn = true;
      }
    }
    if (before.keys.any((String id) => !byId.containsKey(id))) {
      // Handed over or cancelled: the next stop is somewhere new.
      movedOn = true;
    }
    if (movedOn) _headingTo = null;
    _seeded = true;

    _onDuty = onDuty;
    _legs = next;
    _reconcile();
    if ((added || activeOrderId != activeBefore) && _running) {
      // A newly claimed order's customer, or the customer whose leg just began, should see the
      // rider now rather than after the next movement or heartbeat.
      _sendSoon();
    }
  }

  /// The rider tapped Start navigation on [orderId]: that order's next stop is where they are
  /// heading, and it is the order their fixes go on until they collect or hand over an order.
  void headingTo(String orderId) {
    if (_legOf(orderId, _legs) == null) return;
    final String? activeBefore = activeOrderId;
    _headingTo = orderId;
    _lastActedOn = orderId;
    if (activeOrderId != activeBefore && _running) _sendSoon();
  }

  void _sendSoon() {
    _forceNext = true;
    if (_access == RiderLocationAccess.granted) unawaited(sample());
  }

  /// The banner's "allow" button: shows the system prompt again — after the explanation.
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
    if (_legs.isEmpty && _ticks.isOdd) return;
    if (_access != RiderLocationAccess.granted) {
      await _checkAccess(ask: false, generation: _generation);
      if (_access != RiderLocationAccess.granted) return;
    }
    await sample();
  }

  /// Checks the permission, and — when [ask] and the system would show its prompt — explains
  /// first, then lets the prompt show only if the rider goes on.
  Future<void> _checkAccess({required bool ask, required int generation}) async {
    RiderLocationAccess access = await _source.access(ask: false);
    if (generation != _generation || _disposed) return;
    if (ask && access == RiderLocationAccess.denied) {
      final RiderLocationExplanation? explain = _explainBeforeAsking;
      final bool goOn = explain == null || await explain();
      if (generation != _generation || _disposed) return;
      if (goOn) {
        access = await _source.access(ask: true);
        if (generation != _generation || _disposed) return;
      }
    }
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
      _lastFix = fix;
      if (_due(fix, now)) {
        await _send(fix, generation);
      } else if (_status.hidesRider && _status != RiderLocationStatus.legUnknown &&
          _clockRefusals < refusalsBeforeTelling &&
          _otherRefusals < refusalsBeforeTelling) {
        // A good reading that is not due means a fix was sent within the heartbeat, so the rider
        // is on the map; a banner left over from a mock app or a weak spot is no longer true.
        _setStatus(RiderLocationStatus.sharing);
      }
      // The rider's own map follows the phone even when nothing else changed.
      if (!_disposed) notifyListeners();
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
    final String? orderId = activeOrderId;
    final RiderPresencePing? pingRider = _pingRider;
    final _Outcome outcome;
    final bool onNoOrder;
    if (orderId != null) {
      onNoOrder = false;
      outcome = await _attempt(() => _pingOrder(orderId, fix));
    } else if ((_onDuty || _legs.isNotEmpty) && pingRider != null) {
      // Between jobs — or carrying orders to several doors with no word of which is next, when
      // the fix goes to the rider's presence and on no customer's order.
      onNoOrder = _legs.isNotEmpty;
      outcome = await _attempt(() => pingRider(fix));
    } else {
      if (_legs.isNotEmpty) _setStatus(RiderLocationStatus.legUnknown);
      return;
    }
    if (generation != _generation) return;

    switch (outcome) {
      case _Outcome.delivered:
        _lastSent = fix;
        _lastSentAt = clock.now();
        _forceNext = false;
        _clockRefusals = 0;
        _otherRefusals = 0;
        _setStatus(onNoOrder ? RiderLocationStatus.legUnknown : RiderLocationStatus.sharing);
      case _Outcome.clockRefused:
        _otherRefusals = 0;
        _clockRefusals++;
        if (_clockRefusals >= refusalsBeforeTelling) {
          _setStatus(RiderLocationStatus.clockWrong);
        }
      case _Outcome.refused:
        // Outside the service area, an impossible jump, too imprecise: the fix did not reach
        // anybody's map. Said as no usable fix once it keeps happening, rather than "locating".
        _clockRefusals = 0;
        _otherRefusals++;
        if (_otherRefusals >= refusalsBeforeTelling) {
          _setStatus(RiderLocationStatus.noFix);
        }
      case _Outcome.failed:
        break;
    }
  }

  /// One ping, its failure reduced to what the reporter acts on. A dropped ping is replaced by the
  /// next one, so nothing here is ever surfaced as an error.
  static Future<_Outcome> _attempt(Future<void> Function() ping) async {
    try {
      await ping();
      return _Outcome.delivered;
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        return _isClockReason(e.response?.data) ? _Outcome.clockRefused : _Outcome.refused;
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

enum _Outcome { delivered, clockRefused, refused, failed }
