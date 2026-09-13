import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what was asked and answers with one canned body.
class _Recorder implements HttpClientAdapter {
  _Recorder(this.body);

  final Object body;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(body), 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, int> _stars(Map<int, int> counts) =>
    <String, int>{for (int s = 1; s <= 5; s++) '$s': counts[s] ?? 0};

/// The reads and the one write the carrier's Riders HR pages make about a whole fleet: every
/// rider's rating in one response, each application carrying its standing, and a release that sends
/// its reason in the body.
void main() {
  DeliveryProviderApi providerApi(_Recorder adapter) =>
      DeliveryProviderApi(Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter);

  group('a delivery company\'s fleet', () {
    test('has every rider\'s rating in one response, an unrated rider included', () async {
      final _Recorder adapter = _Recorder(<Map<String, dynamic>>[
        <String, dynamic>{
          'riderId': 'rider-a',
          'average': 4.5,
          'ratings': 4,
          'stars': _stars(const <int, int>{3: 1, 5: 3}),
        },
        <String, dynamic>{
          'riderId': 'rider-b',
          'average': null,
          'ratings': 0,
          'stars': _stars(const <int, int>{}),
        },
      ]);

      final List<RiderStanding> standings = await providerApi(adapter).myRiderRatings();

      expect(adapter.requests.single.method, 'GET');
      expect(adapter.requests.single.path, '/api/delivery-providers/my-company/riders/ratings');
      expect(standings.map((RiderStanding s) => s.riderId), <String>['rider-a', 'rider-b']);
      expect(standings.first.average, 4.5);
      // Unrated is new, never zero.
      expect(standings.last.isRated, isFalse);
    });

    test('ends a contract with the reason in the body, never in the address', () async {
      final _Recorder adapter = _Recorder(<String, dynamic>{});

      await providerApi(adapter).releaseMyRider('rider-a', reason: 'Missed agreed shifts');

      final RequestOptions request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/api/delivery-providers/my-company/riders/rider-a/release');
      expect(request.data, <String, dynamic>{'reason': 'Missed agreed shifts'});
      expect(request.uri.toString(), isNot(contains('Missed')));
    });
  });

  group('an application\'s standing', () {
    Map<String, dynamic> application({Object? suspended, bool carried = true}) =>
        <String, dynamic>{
          'id': 'app-1',
          'reference': 'REF-1',
          'kind': 'RIDER',
          'status': 'PROVISIONED',
          if (carried) 'suspended': suspended,
        };

    test('is read where the listing carries it', () {
      expect(OnboardingApplication.fromJson(application(suspended: true)).suspended, isTrue);
      expect(OnboardingApplication.fromJson(application(suspended: false)).suspended, isFalse);
    });

    test('is unknown — never "not suspended" — where the listing does not say', () {
      expect(OnboardingApplication.fromJson(application()).suspended, isNull);
      expect(OnboardingApplication.fromJson(application(carried: false)).suspended, isNull);
    });
  });
}
