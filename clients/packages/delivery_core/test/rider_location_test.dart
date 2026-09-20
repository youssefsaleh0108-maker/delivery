import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

/// The rider's real position: how it is read, when it is sent, and what the rider is told.
///
/// Each layer pinned where it lives. The request bodies carry the phone's fix time in UTC. The
/// device source maps every permission answer to the refusal the rider can act on, and never asks
/// when asking would show nothing. The reporter sends only what the phone produced — only with the
/// app in front, only while the rider is working, never more often than it must — and puts each
/// fix on exactly one order, the one whose leg the rider is on, or on none when it cannot tell;
/// it explains before the system prompt, and says so when the platform keeps refusing.
void main() {
  group('the ping bodies', () {
    test('carry the fix time in UTC and the accuracy', () async {
      final _Recorder recorder = _Recorder();
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = recorder;
      final DateTime takenAt = DateTime.utc(2026, 9, 19, 10, 0, 5);

      await OrderApi(dio).ping('o-1', 33.8938, 35.5018, accuracyM: 6.5, recordedAt: takenAt);
      await TrackingApi(dio).ping(33.8938, 35.5018,
          accuracyM: 6.5, recordedAt: takenAt.toLocal());

      expect(recorder.paths, <String>[
        '/api/tracking/orders/o-1/ping',
        '/api/tracking/riders/me/ping',
      ]);
      for (final Map<String, dynamic> body in recorder.bodies) {
        expect(body, <String, dynamic>{
          'lat': 33.8938,
          'lng': 35.5018,
          'accuracyM': 6.5,
          'recordedAt': '2026-09-19T10:00:05.000Z',
        });
      }
    });

    test('leave the fix time out when a caller has none, as before', () async {
      final _Recorder recorder = _Recorder();
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = recorder;

      await OrderApi(dio).ping('o-1', 33.8938, 35.5018);

      expect(recorder.bodies.single.containsKey('recordedAt'), isFalse);
    });
  });

  group('the device source', () {
    late _FakeGeolocator platform;
    const DeviceRiderLocationSource source = DeviceRiderLocationSource();

    setUp(() {
      platform = _FakeGeolocator();
      GeolocatorPlatform.instance = platform;
    });

    test('asks for the permission only when it is askable and it is allowed to', () async {
      platform.permission = LocationPermission.denied;

      expect(await source.access(ask: false), RiderLocationAccess.denied);
      expect(platform.requests, 0, reason: 'A re-check must never put a prompt up.');

      expect(await source.access(ask: true), RiderLocationAccess.granted);
      expect(platform.requests, 1);
    });

    test('reports a refusal at the prompt as denied, still askable', () async {
      platform.permission = LocationPermission.denied;
      platform.afterRequest = LocationPermission.denied;

      expect(await source.access(ask: true), RiderLocationAccess.denied);
    });

    test('never asks after a permanent refusal: only the settings page can undo it', () async {
      platform.permission = LocationPermission.deniedForever;

      expect(await source.access(ask: true), RiderLocationAccess.deniedForever);
      expect(platform.requests, 0);
    });

    test('reports the location switch before the permission', () async {
      platform.servicesOn = false;

      expect(await source.access(ask: true), RiderLocationAccess.servicesOff);
      expect(platform.requests, 0);
    });

    test('treats an approximate-only grant as a refusal of its own', () async {
      platform.permission = LocationPermission.whileInUse;
      platform.accuracy = LocationAccuracyStatus.reduced;

      expect(await source.access(ask: true), RiderLocationAccess.approximate);
    });

    test('a precise while-in-use grant is all it needs', () async {
      platform.permission = LocationPermission.whileInUse;

      expect(await source.access(ask: true), RiderLocationAccess.granted);
    });

    test('a reading carries its accuracy, its own time in UTC and whether it was mocked', () async {
      final DateTime takenAt = DateTime.now().toUtc().subtract(const Duration(seconds: 2));
      platform.fresh = _position(33.89, 35.50, accuracy: 7, at: takenAt, mocked: true);

      final RiderFix? fix = await source.current();

      expect(fix, isNotNull);
      expect(fix!.latitude, 33.89);
      expect(fix.longitude, 35.50);
      expect(fix.accuracyM, 7);
      expect(fix.takenAt, takenAt);
      expect(fix.mocked, isTrue);
    });

    test('falls back to a recent last-known position when a reading times out', () async {
      platform.freshError = TimeoutException('no fix in time');
      platform.lastKnown = _position(33.89, 35.50,
          at: DateTime.now().toUtc().subtract(const Duration(seconds: 10)));

      expect(await source.current(), isNotNull);
    });

    test('never sends an old last-known position as if it were current', () async {
      platform.freshError = TimeoutException('no fix in time');
      platform.lastKnown = _position(33.89, 35.50,
          at: DateTime.now().toUtc().subtract(const Duration(minutes: 5)));

      expect(await source.current(), isNull);
    });
  });

  group('the reporter', () {
    const String ready = 'order-ready';
    const String carried = 'order-picked-up';

    test('sends nothing, and asks nothing, while the rider is off duty with no delivery', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(onDuty: false, legs: const <RiderLeg>[]);
        async.elapse(const Duration(minutes: 2));

        expect(h.source.asks, isEmpty);
        expect(h.pings, isEmpty);
        expect(h.explained, 0);
        expect(h.reporter.status, RiderLocationStatus.idle);
        h.reporter.dispose();
      });
    });

    test('when the permission is denied, sends nothing and says so — and asks only once', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness()
          ..source.accessResult = RiderLocationAccess.denied
          ..source.afterPrompt = RiderLocationAccess.denied;
        h.reporter.setDemand(onDuty: true, legs: const <RiderLeg>[]);
        async.elapse(const Duration(minutes: 1));

        expect(h.pings, isEmpty);
        expect(h.source.reads, 0, reason: 'Nothing is read without the permission.');
        expect(h.reporter.status, RiderLocationStatus.denied);
        expect(h.source.asks.where((bool ask) => ask), hasLength(1),
            reason: 'The one automatic prompt; every later check is silent.');
        h.reporter.dispose();
      });
    });

    test('the banner button asks again, and a grant starts sending at once', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness()
          ..source.accessResult = RiderLocationAccess.denied
          ..source.afterPrompt = RiderLocationAccess.denied;
        h.reporter.setDemand(onDuty: true, legs: const <RiderLeg>[]);
        async.flushMicrotasks();

        h.source.afterPrompt = RiderLocationAccess.granted;
        h.reporter.askAgain();
        async.flushMicrotasks();

        expect(h.source.asks.last, isTrue);
        expect(h.pings, hasLength(1));
        expect(h.reporter.status, RiderLocationStatus.sharing);
        h.reporter.dispose();
      });
    });

    test('with orders in hand, sends no order-less ping: an order ping is presence already', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(onDuty: true, legs: <RiderLeg>[_leg(carried, collected: true)]);
        async.elapse(const Duration(minutes: 2));

        expect(h.pings, isNotEmpty);
        expect(h.pings.where((_Ping p) => p.target == _Harness.me), isEmpty);
        h.reporter.dispose();
      });
    });

    test('on duty with nothing in hand, sends the order-less ping', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(onDuty: true, legs: const <RiderLeg>[]);
        async.flushMicrotasks();

        expect(h.pings.single.target, _Harness.me);
        expect(h.reporter.status, RiderLocationStatus.sharing);
        h.reporter.dispose();
      });
    });

    test('no fix, no ping', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness()..source.nextFix = () => null;
        h.reporter.setDemand(onDuty: true, legs: <RiderLeg>[_leg(carried, collected: true)]);
        async.elapse(const Duration(minutes: 1));

        expect(h.pings, isEmpty);
        expect(h.reporter.status, RiderLocationStatus.noFix);
        h.reporter.dispose();
      });
    });

    test('a mock-location fix is never sent, and the rider is told why', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness()..source.mocked = true;
        h.reporter.setDemand(onDuty: true, legs: <RiderLeg>[_leg(carried, collected: true)]);
        async.elapse(const Duration(seconds: 30));

        expect(h.pings, isEmpty);
        expect(h.reporter.status, RiderLocationStatus.mocked);
        h.reporter.dispose();
      });
    });

    test('a fix too wide to place the rider on a street is not sent', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness()..source.accuracyM = 1500;
        h.reporter.setDemand(onDuty: true, legs: <RiderLeg>[_leg(carried, collected: true)]);
        async.elapse(const Duration(seconds: 30));

        expect(h.pings, isEmpty);
        h.reporter.dispose();
      });
    });

    test('standing still sends a heartbeat every forty seconds, not every reading', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(onDuty: false, legs: <RiderLeg>[_leg(carried, collected: true)]);
        async.elapse(const Duration(seconds: 125));

        // Readings at 0, 10, ... 120 — thirteen of them — but sends only at 0, 40, 80 and 120.
        expect(h.source.reads, 13);
        expect(h.pings, hasLength(4));
        h.reporter.dispose();
      });
    });

    test('moving sends every ten seconds, and jitter under 25 m does not count as moving', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        int step = 0;
        // 30 m north per reading for the first 30 s, then a few metres of jitter.
        h.source.nextFix = () {
          step++;
          final double metres = step <= 4 ? 30.0 * step : 120.0 + (step.isEven ? 4 : 0);
          return h.source.fixAt(metresNorth: metres);
        };
        h.reporter.setDemand(onDuty: false, legs: <RiderLeg>[_leg(carried, collected: true)]);
        async.elapse(const Duration(seconds: 65));

        // Moving: sends at 0, 10, 20, 30. Jitter from 40 s on: nothing until the heartbeat at 70.
        expect(h.pings, hasLength(4));
        h.reporter.dispose();
      });
    });

    test('with no delivery in hand, reads half as often', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(onDuty: true, legs: const <RiderLeg>[]);
        async.elapse(const Duration(seconds: 65));

        // Readings at 0, 20, 40 and 60.
        expect(h.source.reads, 4);
        h.reporter.dispose();
      });
    });

    test('going to the background stops everything; coming back re-checks without prompting', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(onDuty: true, legs: <RiderLeg>[_leg(carried, collected: true)]);
        async.elapse(const Duration(seconds: 5));
        final int readsBefore = h.source.reads;
        final int pingsBefore = h.pings.length;

        h.reporter.setForeground(false);
        async.elapse(const Duration(minutes: 5));

        expect(h.source.reads, readsBefore, reason: 'No reading with the app in the background.');
        expect(h.pings.length, pingsBefore, reason: 'No ping with the app in the background.');
        expect(h.reporter.status, RiderLocationStatus.idle);
        expect(h.reporter.needed, isFalse);

        h.reporter.setForeground(true);
        async.flushMicrotasks();

        expect(h.source.asks.last, isFalse,
            reason: 'Back from the settings page: check the answer, do not prompt again.');
        expect(h.pings.length, pingsBefore + 1, reason: 'Sharing resumes straight away.');
        h.reporter.dispose();
      });
    });

    test('a newly claimed order is pinged straight away, not at the next heartbeat', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(onDuty: true, legs: const <RiderLeg>[]);
        async.elapse(const Duration(seconds: 15));
        h.pings.clear();

        h.reporter.setDemand(onDuty: true, legs: <RiderLeg>[_leg(ready)]);
        async.flushMicrotasks();

        expect(h.pings.map((_Ping p) => p.target), <String>[ready]);
        h.reporter.dispose();
      });
    });

    test('three clock refusals in a row tell the rider their clock is wrong; a success clears it',
        () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness()..refuseWith = 'FIX_IN_FUTURE';
        h.reporter.setDemand(onDuty: true, legs: <RiderLeg>[_leg(carried, collected: true)]);
        async.elapse(const Duration(seconds: 15));
        expect(h.reporter.status, isNot(RiderLocationStatus.clockWrong),
            reason: 'Two refusals are a hiccup.');

        async.elapse(const Duration(seconds: 10));
        expect(h.reporter.status, RiderLocationStatus.clockWrong);

        h.refuseWith = null;
        async.elapse(const Duration(seconds: 10));
        expect(h.reporter.status, RiderLocationStatus.sharing);
        h.reporter.dispose();
      });
    });

    // After an upgrade the platform may refuse what it is sent — outside the service area, an
    // impossible jump from an old build's London point — and the rider used to be left looking at
    // "locating" with nobody seeing them. Three refusals in a row say so; they never blame the
    // clock; the first accepted fix clears it.
    test('three other refusals in a row say no usable fix, not "locating", and never the clock',
        () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness()..refuseWith = 'OUTSIDE_SERVICE_AREA';
        h.reporter.setDemand(onDuty: true, legs: <RiderLeg>[_leg(carried, collected: true)]);
        async.elapse(const Duration(seconds: 15));
        expect(h.reporter.status, RiderLocationStatus.locating);

        async.elapse(const Duration(seconds: 10));
        expect(h.reporter.status, RiderLocationStatus.noFix);
        expect(h.reporter.status.hidesRider, isTrue);

        h.refuseWith = null;
        async.elapse(const Duration(seconds: 10));
        expect(h.reporter.status, RiderLocationStatus.sharing);
        h.reporter.dispose();
      });
    });

    test('location switched off mid-shift is reported as that, not as weak signal', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(onDuty: true, legs: <RiderLeg>[_leg(carried, collected: true)]);
        async.flushMicrotasks();

        h.source.nextFix = () => null;
        h.source.accessResult = RiderLocationAccess.servicesOff;
        async.elapse(const Duration(seconds: 10));

        expect(h.reporter.status, RiderLocationStatus.servicesOff);
        h.reporter.dispose();
      });
    });

    // The rider's own map: the phone's reading, whether or not the platform took it.
    test('keeps the phone\'s own latest reading for the rider\'s map, even when it is refused', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness()..refuseWith = 'IMPLAUSIBLE_JUMP';
        h.reporter.setDemand(onDuty: true, legs: const <RiderLeg>[]);
        async.flushMicrotasks();

        expect(h.pings, isEmpty);
        expect(h.reporter.lastFix, isNotNull);
        expect(h.reporter.lastFix!.latitude, _Harness.beirutLat);
        h.reporter.dispose();
      });
    });
  });

  group('the one order a fix goes on', () {
    const String home = 'Hamra Street, Beirut';
    const String other = 'Mar Mikhael, Beirut';

    // One order: its leg is the only one there is.
    test('with one order in hand, every fix goes on it', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(onDuty: true, legs: <RiderLeg>[_leg('a', door: home)]);
        async.elapse(const Duration(seconds: 45));

        expect(h.pings.map((_Ping p) => p.target).toSet(), <String>{'a'});
        h.reporter.dispose();
      });
    });

    // The finding this rule exists for: every fix went on every order in hand, so customer A's
    // map drew the way to customer B's door. Now each fix goes on exactly one order.
    test('with two orders in hand, each fix goes on exactly one of them', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(onDuty: true, legs: <RiderLeg>[
          _leg('a', door: home),
          _leg('b', collected: true, door: other),
        ]);
        async.elapse(const Duration(seconds: 45));

        expect(h.pings, isNotEmpty);
        final Map<DateTime, List<String>> byFix = <DateTime, List<String>>{};
        for (final _Ping p in h.pings) {
          byFix.putIfAbsent(p.fix.takenAt, () => <String>[]).add(p.target);
        }
        expect(byFix.values, everyElement(hasLength(1)));
        h.reporter.dispose();
      });
    });

    // No door in the bag: the rider is on the way to a shop — the one they last claimed.
    test('collecting only, the fix goes on the order last claimed', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(onDuty: true, legs: <RiderLeg>[_leg('a', door: home)]);
        async.flushMicrotasks();

        h.reporter.setDemand(
            onDuty: true, legs: <RiderLeg>[_leg('a', door: home), _leg('b', door: other)]);
        expect(h.reporter.activeOrderId, 'b');
        h.reporter.dispose();
      });
    });

    // With A's order in the bag, a newly claimed B does not take the fixes: the rider may be
    // taking A's order home first, and B's customer must never be shown A's door.
    test('with one door in the bag, another customer\'s claim does not take the fix', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(
            onDuty: true, legs: <RiderLeg>[_leg('a', collected: true, door: home)]);
        async.flushMicrotasks();

        h.reporter.setDemand(onDuty: true, legs: <RiderLeg>[
          _leg('a', collected: true, door: home),
          _leg('b', door: other),
        ]);

        expect(h.reporter.activeOrderId, 'a');
        h.reporter.dispose();
      });
    });

    // Start navigation says where the rider is going; the fixes follow it.
    test('Start navigation puts the fixes on that order at once', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(onDuty: true, legs: <RiderLeg>[
          _leg('a', collected: true, door: home),
          _leg('b', door: other),
        ]);
        async.elapse(const Duration(seconds: 15));
        h.pings.clear();

        h.reporter.headingTo('b');
        async.elapse(const Duration(seconds: 10));

        expect(h.reporter.activeOrderId, 'b');
        expect(h.pings.map((_Ping p) => p.target), everyElement('b'));
        expect(h.pings, isNotEmpty);
        h.reporter.dispose();
      });
    });

    // Two customers' orders in the bag and no word of which door is next: the fix goes on
    // neither — only to the rider's presence — and the rider is told how to fix that.
    test('with two doors in the bag and no Start navigation, the fix goes on no order', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(onDuty: true, legs: <RiderLeg>[
          _leg('a', collected: true, door: home),
          _leg('b', door: other),
        ]);
        async.flushMicrotasks();

        h.reporter.setDemand(onDuty: true, legs: <RiderLeg>[
          _leg('a', collected: true, door: home),
          _leg('b', collected: true, door: other),
        ]);
        async.elapse(const Duration(seconds: 15));

        expect(h.reporter.activeOrderId, isNull);
        expect(h.pings.last.target, _Harness.me);
        expect(h.reporter.status, RiderLocationStatus.legUnknown);
        expect(h.reporter.status.hidesRider, isTrue);

        h.reporter.headingTo('b');
        async.elapse(const Duration(seconds: 10));

        expect(h.pings.last.target, 'b');
        expect(h.reporter.status, RiderLocationStatus.sharing);
        h.reporter.dispose();
      });
    });

    // A pickup changes where the rider goes next: an earlier Start navigation no longer says.
    test('a pickup ends what Start navigation said', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(onDuty: true, legs: <RiderLeg>[
          _leg('a', collected: true, door: home),
          _leg('b', door: other),
        ]);
        async.flushMicrotasks();
        h.reporter.headingTo('b');
        expect(h.reporter.activeOrderId, 'b');

        h.reporter.setDemand(onDuty: true, legs: <RiderLeg>[
          _leg('a', collected: true, door: home),
          _leg('b', collected: true, door: other),
        ]);

        expect(h.reporter.activeOrderId, isNull);
        h.reporter.dispose();
      });
    });

    // A multi-shop basket: every order ends at the same door, so any leg is safe to show.
    test('orders to one door stay shown whichever shop the rider is at', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(onDuty: true, legs: <RiderLeg>[
          _leg('a', collected: true, door: home),
          _leg('b', door: ' hamra street,  BEIRUT '),
        ]);
        async.flushMicrotasks();

        h.reporter.setDemand(onDuty: true, legs: <RiderLeg>[
          _leg('a', collected: true, door: home),
          _leg('b', collected: true, door: ' hamra street,  BEIRUT '),
        ]);

        expect(h.reporter.activeOrderId, 'b');
        expect(h.reporter.status, isNot(RiderLocationStatus.legUnknown));
        h.reporter.dispose();
      });
    });

    // Orders already in hand when the app opens were not claimed in front of it.
    test('orders already in hand at the start are taken in the Active tab\'s order', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(
            onDuty: true, legs: <RiderLeg>[_leg('a', door: home), _leg('b', door: other)]);

        expect(h.reporter.activeOrderId, 'a');
        h.reporter.dispose();
      });
    });
  });

  group('before the phone\'s location prompt', () {
    // The rider reads who sees their location before the system asks for it.
    test('the explanation comes first, and the prompt only if the rider goes on', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness()
          ..source.accessResult = RiderLocationAccess.denied
          ..explainAnswer = true;
        h.reporter.setDemand(onDuty: true, legs: const <RiderLeg>[]);
        async.flushMicrotasks();

        expect(h.events, <String>['explained', 'system prompt'],
            reason: 'The system prompt comes after the explanation, never before it.');
        expect(h.pings, hasLength(1));
        h.reporter.dispose();
      });
    });

    test('"Not now" leaves the permission alone, and "Allow location" explains again', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness()
          ..source.accessResult = RiderLocationAccess.denied
          ..explainAnswer = false;
        h.reporter.setDemand(onDuty: true, legs: const <RiderLeg>[]);
        async.elapse(const Duration(seconds: 30));

        expect(h.explained, 1);
        expect(h.source.asks, everyElement(isFalse), reason: 'No system prompt at all.');
        expect(h.reporter.status, RiderLocationStatus.denied);
        expect(h.pings, isEmpty);

        h.explainAnswer = true;
        h.reporter.askAgain();
        async.flushMicrotasks();

        expect(h.explained, 2);
        expect(h.source.asks.last, isTrue);
        expect(h.pings, hasLength(1));
        h.reporter.dispose();
      });
    });

    // Nothing to explain when there is nothing to ask: the permission is already there.
    test('is not shown when the permission is already granted', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness()..explainAnswer = false;
        h.reporter.setDemand(onDuty: true, legs: const <RiderLeg>[]);
        async.flushMicrotasks();

        expect(h.explained, 0);
        expect(h.pings, hasLength(1));
        h.reporter.dispose();
      });
    });
  });
}

// ---------------------------------------------------------------------------------------- fakes

class _Recorder implements HttpClientAdapter {
  final List<String> paths = <String>[];
  final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    paths.add(options.path);
    bodies.add(Map<String, dynamic>.from(options.data as Map<dynamic, dynamic>));
    return ResponseBody.fromString(jsonEncode(<String, dynamic>{}), 202,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        });
  }

  @override
  void close({bool force = false}) {}
}

Position _position(double lat, double lng,
        {double accuracy = 5, required DateTime at, bool mocked = false}) =>
    Position(
      latitude: lat,
      longitude: lng,
      timestamp: at,
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
      isMocked: mocked,
    );

class _FakeGeolocator extends GeolocatorPlatform {
  bool servicesOn = true;
  LocationPermission permission = LocationPermission.denied;
  LocationPermission afterRequest = LocationPermission.whileInUse;
  LocationAccuracyStatus accuracy = LocationAccuracyStatus.precise;
  int requests = 0;
  Position? fresh;
  Object? freshError;
  Position? lastKnown;

  @override
  Future<bool> isLocationServiceEnabled() async => servicesOn;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    permission = afterRequest;
    return permission;
  }

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async => accuracy;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    final Object? error = freshError;
    if (error != null) throw error;
    return fresh!;
  }

  @override
  Future<Position?> getLastKnownPosition({bool forceLocationManager = false}) async => lastKnown;
}

/// A source that produces whatever the test scripts, stamped with the fake clock.
class _ScriptedSource extends RiderLocationSource {
  RiderLocationAccess accessResult = RiderLocationAccess.granted;
  final List<bool> asks = <bool>[];
  int reads = 0;
  double accuracyM = 6;
  bool mocked = false;
  DateTime? lastTakenAt;
  RiderFix? Function()? nextFix;

  RiderFix fixAt({double metresNorth = 0}) {
    final DateTime now = clock.now().toUtc();
    lastTakenAt = now;
    return RiderFix(
      latitude: _Harness.beirutLat + metresNorth / 111195.08,
      longitude: _Harness.beirutLng,
      accuracyM: accuracyM,
      takenAt: now,
      mocked: mocked,
    );
  }

  /// What the system prompt leaves the permission at, when one is shown: the rider's answer.
  RiderLocationAccess afterPrompt = RiderLocationAccess.granted;

  /// Shared with the harness, to see the prompt land after the explanation.
  List<String>? events;

  @override
  Future<RiderLocationAccess> access({required bool ask}) async {
    asks.add(ask);
    // Only a refusal that can still be asked about shows the prompt — as on a phone.
    if (ask && accessResult == RiderLocationAccess.denied) {
      events?.add('system prompt');
      accessResult = afterPrompt;
    }
    return accessResult;
  }

  @override
  Future<RiderFix?> current() async {
    reads++;
    final RiderFix? Function()? scripted = nextFix;
    return scripted != null ? scripted() : fixAt();
  }

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> openLocationSettings() async {}
}

class _Ping {
  _Ping(this.target, this.fix);

  final String target;
  final RiderFix fix;
}

RiderLeg _leg(String orderId, {bool collected = false, String door = 'Hamra Street, Beirut'}) =>
    RiderLeg(orderId: orderId, collected: collected, dropOff: door);

class _Harness {
  _Harness() {
    source.events = events;
    reporter = RiderLocationReporter(
      source: source,
      pingOrder: (String orderId, RiderFix fix) => _deliver(orderId, fix),
      pingRider: (RiderFix fix) => _deliver(me, fix),
      explainBeforeAsking: () async {
        explained++;
        events.add('explained');
        return explainAnswer;
      },
    );
  }

  static const double beirutLat = 33.8938;
  static const double beirutLng = 35.5018;
  static const String me = 'me';

  final _ScriptedSource source = _ScriptedSource();
  final List<_Ping> pings = <_Ping>[];
  late final RiderLocationReporter reporter;

  /// When set, every ping is refused with this 422 reason.
  String? refuseWith;

  /// What the rider answers in the explanation shown before the system prompt.
  bool explainAnswer = true;
  int explained = 0;

  /// The explanation and the system prompt, in the order they happened.
  final List<String> events = <String>[];

  Future<void> _deliver(String target, RiderFix fix) async {
    final String? reason = refuseWith;
    if (reason != null) {
      final RequestOptions request = RequestOptions(path: '/ping');
      throw DioException(
        requestOptions: request,
        response: Response<dynamic>(
          requestOptions: request,
          statusCode: 422,
          data: <String, dynamic>{'reason': reason},
        ),
      );
    }
    pings.add(_Ping(target, fix));
  }
}
