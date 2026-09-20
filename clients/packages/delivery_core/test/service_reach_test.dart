import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// PT-8: telling "this service is not deployed" apart from "this service answered".
///
/// The whole of the fix rests on this one distinction, and it rests on a detail of the wire — the
/// edge answers an unrouted path in plain text, every service of ours answers in JSON — so it is
/// pinned here rather than only through a screen.
DioException _answer(int status, {String? contentType, String body = ''}) {
  final RequestOptions request = RequestOptions(path: '/api/pos/stores/s1/shifts/current');
  return DioException(
    requestOptions: request,
    response: Response<dynamic>(
      requestOptions: request,
      statusCode: status,
      data: body,
      headers: Headers.fromMap(<String, List<String>>{
        if (contentType != null) Headers.contentTypeHeader: <String>[contentType],
      }),
    ),
  );
}

void main() {
  group('isServiceNotRouted', () {
    test('the edge\'s own 404 for a path it routes nowhere', () {
      expect(
          isServiceNotRouted(_answer(404,
              contentType: 'text/plain; charset=utf-8', body: '404 page not found\n')),
          isTrue);
      // Traefik has been seen to send no content type at all; our services always send one.
      expect(isServiceNotRouted(_answer(404)), isTrue);
    });

    test('a service\'s own 404 is not it — that is an answer', () {
      expect(
          isServiceNotRouted(_answer(404, contentType: 'application/problem+json')), isFalse);
      expect(isServiceNotRouted(_answer(404, contentType: 'application/json')), isFalse);
    });

    test('nothing else is it: a refusal, a fault and a stutter all prove the route exists', () {
      for (final int status in <int>[401, 403, 409, 422, 500, 502, 503]) {
        expect(isServiceNotRouted(_answer(status, contentType: 'text/plain')), isFalse,
            reason: '$status came from something');
      }
      expect(
          isServiceNotRouted(DioException(
            requestOptions: RequestOptions(path: '/api/pos'),
            type: DioExceptionType.connectionTimeout,
          )),
          isFalse);
      expect(isServiceNotRouted(StateError('not a Dio failure at all')), isFalse);
    });
  });

  group('probeServiceReach', () {
    test('a read that answers means present, whatever it answered', () async {
      expect(await probeServiceReach(() async {}), ServiceReach.present);
      expect(
          await probeServiceReach(
              () async => throw _answer(500, contentType: 'application/problem+json')),
          ServiceReach.present);
    });

    test('only the edge\'s 404 means absent', () async {
      expect(await probeServiceReach(() async => throw _answer(404, contentType: 'text/plain')),
          ServiceReach.absent);
      expect(ServiceReach.absent.isAbsent, isTrue);
      expect(ServiceReach.unknown.isAbsent, isFalse);
      expect(ServiceReach.present.isAbsent, isFalse);
    });
  });

  test('PosApi passes the edge\'s 404 on, and still reads its own as "no shift"', () async {
    Future<PosShift?> shiftWhen(int status, String contentType) {
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))
        ..httpClientAdapter = _Fixed(status, contentType);
      return PosApi(dio).currentShift('s1');
    }

    // pos-service, answering: nobody has opened a drawer.
    expect(await shiftWhen(404, 'application/problem+json'), isNull);
    // The edge, answering for a pos-service that is not there.
    await expectLater(shiftWhen(404, 'text/plain; charset=utf-8'),
        throwsA(isA<DioException>().having(isServiceNotRouted, 'is not routed', isTrue)));
  });
}

class _Fixed implements HttpClientAdapter {
  _Fixed(this.status, this.contentType);

  final int status;
  final String contentType;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
          Future<void>? cancelFuture) async =>
      ResponseBody.fromString(
          contentType.contains('json') ? '{"detail":"no shift"}' : '404 page not found\n', status,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>[contentType],
          });

  @override
  void close({bool force = false}) {}
}
