import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what was asked and answers with one canned body.
class _Recorder implements HttpClientAdapter {
  _Recorder(this.body);

  final Object? body;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    if (body == null) return ResponseBody.fromString('', 204);
    return ResponseBody.fromString(jsonEncode(body), 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _output({List<Map<String, dynamic>>? days}) => <String, dynamic>{
      'riderId': 'rider-1',
      'zone': 'Asia/Beirut',
      'from': '2026-09-05',
      'to': '2026-09-11',
      'days': days ??
          <Map<String, dynamic>>[
            <String, dynamic>{'date': '2026-09-06', 'delivered': 4},
            <String, dynamic>{'date': '2026-09-09', 'delivered': 2},
          ],
    };

void main() {
  group('RiderDailyOutput', () {
    test('keeps the server\'s calendar dates rather than shifting them by the viewer\'s zone', () {
      final RiderDailyOutput out = RiderDailyOutput.fromJson(_output());

      expect(out.zone, 'Asia/Beirut');
      expect(out.from, DateTime(2026, 9, 5));
      expect(out.to, DateTime(2026, 9, 11));
      expect(out.days.first.date, DateTime(2026, 9, 6));
    });

    test('draws every day of the window, a quiet day as zero', () {
      final List<RiderDeliveredDay> filled = RiderDailyOutput.fromJson(_output()).zeroFilled;

      // Seven days, 5 to 11 inclusive — the server sent only the two with work on them.
      expect(filled, hasLength(7));
      expect(filled.map((RiderDeliveredDay d) => d.delivered), <int>[0, 4, 0, 0, 2, 0, 0]);
      expect(filled.first.date, DateTime(2026, 9, 5));
      expect(filled.last.date, DateTime(2026, 9, 11));
    });

    test('an empty window is all zeros and a zero total, never a missing chart', () {
      final RiderDailyOutput out =
          RiderDailyOutput.fromJson(_output(days: const <Map<String, dynamic>>[]));

      expect(out.total, 0);
      expect(out.zeroFilled, hasLength(7));
      expect(out.zeroFilled.every((RiderDeliveredDay d) => d.delivered == 0), isTrue);
    });

    test('totals what was delivered', () {
      expect(RiderDailyOutput.fromJson(_output()).total, 6);
    });
  });

  group('the carrier rider routes', () {
    test('the daily series asks the rider\'s own route with the window it wants', () async {
      final _Recorder recorder = _Recorder(_output());
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = recorder;

      final RiderDailyOutput out = await RiderPerformanceApi(dio).dailyForRider('rider-1', days: 7);

      expect(recorder.requests.single.method, 'GET');
      expect(recorder.requests.single.path, '/api/orders/riders/rider-1/performance/daily');
      expect(recorder.requests.single.queryParameters, <String, dynamic>{'days': 7});
      expect(out.total, 6);
    });

    test('ending a contract is a DELETE on the caller\'s own company, naming no company', () async {
      final _Recorder recorder = _Recorder(null);
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = recorder;

      await DeliveryProviderApi(dio).releaseMyRider('rider-1');

      expect(recorder.requests.single.method, 'DELETE');
      expect(recorder.requests.single.path,
          '/api/delivery-providers/my-company/riders/rider-1');
    });
  });
}
