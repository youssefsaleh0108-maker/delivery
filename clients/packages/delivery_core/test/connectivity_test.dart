import 'dart:async';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// What counts as "offline", pinned — because both mistakes are visible to every customer.
///
/// Calling a 401 or a slow server "offline" puts a banner up over a working app and has checkout
/// offer to queue orders that would have gone through. Missing a real outage leaves the customer
/// tapping a button that can never work. The rule: a response of ANY status is the platform
/// answering; only a request that never reached it, for a network reason, is offline.
void main() {
  /// Answers every request with whatever [next] says, without opening a socket.
  ({Dio dio, ConnectivityService connectivity}) harness(
      FutureOr<ResponseBody> Function(RequestOptions options) next) {
    final ConnectivityService connectivity = ConnectivityService();
    addTearDown(connectivity.dispose);
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway.test'))
      ..httpClientAdapter = _ScriptedAdapter(next)
      ..interceptors.add(ConnectivityInterceptor(connectivity));
    return (dio: dio, connectivity: connectivity);
  }

  ResponseBody status(int code) => ResponseBody.fromString('{}', code, headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      });

  Never fail(RequestOptions options, DioExceptionType type) =>
      throw DioException(requestOptions: options, type: type);

  test('a request that cannot connect goes offline, and the next answer comes back online',
      () async {
    bool down = true;
    final h = harness((RequestOptions o) =>
        down ? fail(o, DioExceptionType.connectionError) : status(200));

    await expectLater(h.dio.get<dynamic>('/api/orders/mine'), throwsA(isA<DioException>()));
    expect(h.connectivity.isOnline, isFalse);

    down = false;
    await h.dio.get<dynamic>('/api/orders/mine');
    expect(h.connectivity.isOnline, isTrue);
  });

  test('connect and send timeouts are the network too', () async {
    for (final DioExceptionType type in <DioExceptionType>[
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
    ]) {
      final h = harness((RequestOptions o) => fail(o, type));
      await expectLater(h.dio.get<dynamic>('/x'), throwsA(isA<DioException>()));
      expect(h.connectivity.isOnline, isFalse, reason: '$type');
    }
  });

  test('a 401, a 422 or a 503 is the platform answering, never "offline"', () async {
    int code = 401;
    final h = harness((RequestOptions o) => status(code));

    for (final int c in <int>[401, 422, 503]) {
      code = c;
      await expectLater(h.dio.get<dynamic>('/x'), throwsA(isA<DioException>()));
      expect(h.connectivity.isOnline, isTrue, reason: 'HTTP $c');
    }

    // And an answer of any status is what ends an outage.
    h.connectivity.reportUnreachable();
    code = 404;
    await expectLater(h.dio.get<dynamic>('/x'), throwsA(isA<DioException>()));
    expect(h.connectivity.isOnline, isTrue);
  });

  test('a receive timeout is a slow server, not a missing network', () async {
    final h = harness((RequestOptions o) => fail(o, DioExceptionType.receiveTimeout));

    await expectLater(h.dio.get<dynamic>('/x'), throwsA(isA<DioException>()));

    expect(h.connectivity.isOnline, isTrue);
  });

  test('while offline, the probe re-checks on its own until the platform answers', () async {
    final ConnectivityService connectivity = ConnectivityService(
      minProbeDelay: const Duration(milliseconds: 1),
      maxProbeDelay: const Duration(milliseconds: 4),
    );
    addTearDown(connectivity.dispose);
    int probes = 0;
    connectivity.useProbe(() async => ++probes >= 3);
    final List<bool> seen = <bool>[];
    connectivity.addListener(() => seen.add(connectivity.isOnline));

    connectivity.reportUnreachable();
    for (int i = 0; i < 100 && !connectivity.isOnline; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(connectivity.isOnline, isTrue);
    expect(probes, 3, reason: 'two failed probes, then the one that got through, then nothing');
    expect(seen, <bool>[false, true]);
  });

  test('which failures leave a placement\'s outcome unknown', () {
    final RequestOptions o = RequestOptions(path: '/api/orders');
    DioException of(DioExceptionType type, {int? code}) => DioException(
        requestOptions: o,
        type: type,
        response: code == null ? null : Response<dynamic>(requestOptions: o, statusCode: code));

    // It may have arrived and been placed: retry with the same key.
    expect(ConnectivityService.outcomeUnknown(of(DioExceptionType.connectionError)), isTrue);
    expect(ConnectivityService.outcomeUnknown(of(DioExceptionType.receiveTimeout)), isTrue);
    // The server answered: whatever it said is the outcome.
    expect(ConnectivityService.outcomeUnknown(of(DioExceptionType.badResponse, code: 422)),
        isFalse);
    // Only the first kind is "offline".
    expect(ConnectivityService.isUnreachable(of(DioExceptionType.receiveTimeout)), isFalse);
  });
}

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._next);

  final FutureOr<ResponseBody> Function(RequestOptions options) _next;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
          Future<void>? cancelFuture) async =>
      _next(options);

  @override
  void close({bool force = false}) {}
}
