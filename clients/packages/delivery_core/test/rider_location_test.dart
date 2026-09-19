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
/// Three layers, each pinned where it lives. The request bodies carry the phone's fix time in
/// UTC. The device source maps every permission answer to the refusal the rider can act on, and
/// never asks when asking would show nothing. And the reporter sends only what the phone produced
/// — only with the app in front, only while the rider is working, never more often than it must.
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
        h.reporter.setDemand(onDuty: false, orderIds: const <String>[]);
        async.elapse(const Duration(minutes: 2));

        expect(h.source.asks, isEmpty);
        expect(h.pings, isEmpty);
        expect(h.reporter.status, RiderLocationStatus.idle);
        h.reporter.dispose();
      });
    });

    test('when the permission is denied, sends nothing and says so — and asks only once', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness()..source.accessResult = RiderLocationAccess.denied;
        h.reporter.setDemand(onDuty: true, orderIds: const <String>[]);
        async.elapse(const Duration(minutes: 1));

        expect(h.pings, isEmpty);
        expect(h.source.reads, 0, reason: 'Nothing is read without the permission.');
        expect(h.reporter.status, RiderLocationStatus.denied);
        expect(h.source.asks.first, isTrue, reason: 'The one automatic prompt.');
        expect(h.source.asks.skip(1), everyElement(isFalse),
            reason: 'Every later check is silent — re-prompting would be nagging.');
        h.reporter.dispose();
      });
    });

    test('the banner button asks again, and a grant starts sending at once', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness()..source.accessResult = RiderLocationAccess.denied;
        h.reporter.setDemand(onDuty: true, orderIds: const <String>[]);
        async.flushMicrotasks();

        h.source.accessResult = RiderLocationAccess.granted;
        h.reporter.askAgain();
        async.flushMicrotasks();

        expect(h.source.asks.last, isTrue);
        expect(h.pings, hasLength(1));
        expect(h.reporter.status, RiderLocationStatus.sharing);
        h.reporter.dispose();
      });
    });

    test('when granted, pings every READY and PICKED_UP order with the real fix', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(onDuty: true, orderIds: const <String>[ready, carried]);
        async.flushMicrotasks();

        expect(h.pings.map((_Ping p) => p.target), <String>[ready, carried]);
        final RiderFix sent = h.pings.first.fix;
        expect(sent.latitude, _Harness.beirutLat);
        expect(sent.longitude, _Harness.beirutLng);
        expect(sent.accuracyM, 6);
        expect(sent.takenAt, h.source.lastTakenAt);
        expect(h.reporter.status, RiderLocationStatus.sharing);
        h.reporter.dispose();
      });
    });

    test('with orders in hand, sends no order-less ping: an order ping is presence already', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(onDuty: true, orderIds: const <String>[carried]);
        async.elapse(const Duration(minutes: 2));

        expect(h.pings.where((_Ping p) => p.target == _Harness.me), isEmpty);
        h.reporter.dispose();
      });
    });

    test('on duty with nothing in hand, sends the order-less ping', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(onDuty: true, orderIds: const <String>[]);
        async.flushMicrotasks();

        expect(h.pings.single.target, _Harness.me);
        h.reporter.dispose();
      });
    });

    test('no fix, no ping', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness()..source.nextFix = () => null;
        h.reporter.setDemand(onDuty: true, orderIds: const <String>[carried]);
        async.elapse(const Duration(minutes: 1));

        expect(h.pings, isEmpty);
        expect(h.reporter.status, RiderLocationStatus.noFix);
        h.reporter.dispose();
      });
    });

    test('a mock-location fix is never sent, and the rider is told why', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness()..source.mocked = true;
        h.reporter.setDemand(onDuty: true, orderIds: const <String>[carried]);
        async.elapse(const Duration(seconds: 30));

        expect(h.pings, isEmpty);
        expect(h.reporter.status, RiderLocationStatus.mocked);
        h.reporter.dispose();
      });
    });

    test('a fix too wide to place the rider on a street is not sent', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness()..source.accuracyM = 1500;
        h.reporter.setDemand(onDuty: true, orderIds: const <String>[carried]);
        async.elapse(const Duration(seconds: 30));

        expect(h.pings, isEmpty);
        h.reporter.dispose();
      });
    });

    test('standing still sends a heartbeat every forty seconds, not every reading', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(onDuty: false, orderIds: const <String>[carried]);
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
        h.reporter.setDemand(onDuty: false, orderIds: const <String>[carried]);
        async.elapse(const Duration(seconds: 65));

        // Moving: sends at 0, 10, 20, 30. Jitter from 40 s on: nothing until the heartbeat at 70.
        expect(h.pings, hasLength(4));
        h.reporter.dispose();
      });
    });

    test('with no delivery in hand, reads half as often', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(onDuty: true, orderIds: const <String>[]);
        async.elapse(const Duration(seconds: 65));

        // Readings at 0, 20, 40 and 60.
        expect(h.source.reads, 4);
        h.reporter.dispose();
      });
    });

    test('going to the background stops everything; coming back re-checks without prompting', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(onDuty: true, orderIds: const <String>[carried]);
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
        h.reporter.setDemand(onDuty: true, orderIds: const <String>[carried]);
        async.elapse(const Duration(seconds: 15));
        h.pings.clear();

        h.reporter.setDemand(onDuty: true, orderIds: const <String>[carried, ready]);
        async.flushMicrotasks();

        expect(h.pings.map((_Ping p) => p.target), containsAll(<String>[ready]));
        h.reporter.dispose();
      });
    });

    test('three clock refusals in a row tell the rider their clock is wrong; a success clears it',
        () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness()..refuseWith = 'FIX_IN_FUTURE';
        h.reporter.setDemand(onDuty: true, orderIds: const <String>[carried]);
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

    test('other refusals are one-off readings: they never blame the clock', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness()..refuseWith = 'IMPLAUSIBLE_JUMP';
        h.reporter.setDemand(onDuty: true, orderIds: const <String>[carried]);
        async.elapse(const Duration(minutes: 1));

        expect(h.reporter.status, isNot(RiderLocationStatus.clockWrong));
        h.reporter.dispose();
      });
    });

    test('location switched off mid-shift is reported as that, not as weak signal', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness();
        h.reporter.setDemand(onDuty: true, orderIds: const <String>[carried]);
        async.flushMicrotasks();

        h.source.nextFix = () => null;
        h.source.accessResult = RiderLocationAccess.servicesOff;
        async.elapse(const Duration(seconds: 10));

        expect(h.reporter.status, RiderLocationStatus.servicesOff);
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

  @override
  Future<RiderLocationAccess> access({required bool ask}) async {
    asks.add(ask);
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

class _Harness {
  _Harness() {
    reporter = RiderLocationReporter(
      source: source,
      pingOrder: (String orderId, RiderFix fix) => _deliver(orderId, fix),
      pingRider: (RiderFix fix) => _deliver(me, fix),
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
