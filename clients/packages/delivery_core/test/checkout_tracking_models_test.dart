import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// The checkout map's wire format, read defensively: a missing pin stays missing, a status or a
/// line kind this build does not know degrades to something the screen can say honestly, and a road
/// that cannot be decoded is drawn as nothing rather than as straight lines.
void main() {
  Map<String, dynamic> eta(String orderId, {bool available = false, String? reason = 'NO_FIX'}) =>
      <String, dynamic>{
        'orderId': orderId,
        'available': available,
        'reason': available ? null : reason,
        'leg': available ? 'TO_PICKUP' : null,
        'remainingMetres': available ? 2400.0 : null,
        'remainingSeconds': available ? 480 : null,
        'estimatedArrival': available ? '2026-09-19T12:08:00Z' : null,
        'provider': 'HAVERSINE_DEV',
        'fixRecordedAt': null,
        'computedAt': '2026-09-19T12:00:00Z',
      };

  Map<String, dynamic> view({String geometry = 'STRAIGHT', String? polyline}) =>
      <String, dynamic>{
        'checkoutId': 'c-1',
        'provider': geometry == 'ROAD' ? 'OSRM' : 'HAVERSINE_DEV',
        'geometry': geometry,
        'door': <String, dynamic>{'lat': 33.8981, 'lng': 35.5214},
        'orders': <dynamic>[
          <String, dynamic>{
            'orderId': 'o-a',
            'storeName': 'Hamra Bakery',
            'status': 'PICKED_UP',
            'shop': <String, dynamic>{'lat': 33.8938, 'lng': 35.5018},
            'riderAssigned': true,
            'stop': 1,
            'expected': false,
            'pickedUpAt': '2026-09-19T11:50:00Z',
            'completedAt': null,
            'eta': eta('o-a', available: true),
          },
          <String, dynamic>{
            'orderId': 'o-b',
            'storeName': null,
            'status': 'READY',
            'shop': null,
            'riderAssigned': true,
            'stop': 2,
            'expected': true,
            'pickedUpAt': null,
            'completedAt': null,
            'eta': eta('o-b', available: true),
          },
        ],
        'riders': <dynamic>[
          <String, dynamic>{
            'orderIds': <dynamic>['o-a', 'o-b'],
            'run': true,
            'position': <String, dynamic>{
              'lat': 33.8950,
              'lng': 35.5050,
              'recordedAt': '2026-09-19T11:59:40Z',
              'stale': false,
            },
            'hasOtherDeliveries': true,
          },
        ],
        'paths': <dynamic>[
          <String, dynamic>{
            'orderIds': <dynamic>['o-a', 'o-b'],
            'kind': 'RIDER_LEG',
            'points': <dynamic>[
              <String, dynamic>{'lat': 33.8950, 'lng': 35.5050},
              <String, dynamic>{'lat': 33.8981, 'lng': 35.5214},
            ],
            'polyline6': polyline,
            'metres': 1600.5,
            'provider': geometry == 'ROAD' ? 'OSRM' : 'HAVERSINE_DEV',
          },
        ],
        'computedAt': '2026-09-19T12:00:00Z',
      };

  group('CheckoutTracking', () {
    test('a straight-line view: pins, a run, its numbers, and a leg drawn through its stops', () {
      final CheckoutTracking tracking = CheckoutTracking.fromJson(view());

      expect(tracking.checkoutId, 'c-1');
      expect(tracking.geometry, RouteGeometry.straight);
      expect(tracking.isStraightLine, isTrue);
      expect(tracking.door, const GeoPin(33.8981, 35.5214));
      expect(tracking.orders, hasLength(2));

      final CheckoutTrackedOrder a = tracking.orders.first;
      expect(a.storeName, 'Hamra Bakery');
      expect(a.status, OrderStatus.pickedUp);
      expect(a.shop, const GeoPin(33.8938, 35.5018));
      expect(a.stop, 1);
      expect(a.expected, isFalse);
      expect(a.pickedUpAt, isNotNull);
      expect(a.eta?.available, isTrue);
      expect(a.eta?.leg, EtaLeg.toPickup);

      final CheckoutTrackedOrder b = tracking.orders.last;
      expect(b.storeName, isNull);
      expect(b.shop, isNull);
      expect(b.expected, isTrue);

      final CheckoutRider rider = tracking.riders.single;
      expect(rider.run, isTrue);
      expect(rider.hasOtherDeliveries, isTrue);
      expect(rider.position?.stale, isFalse);
      expect(rider.position?.pin, const GeoPin(33.8950, 35.5050));
      expect(tracking.riderFor('o-b'), same(rider));
      expect(tracking.riderFor('o-z'), isNull);

      final CheckoutRoutePath path = tracking.paths.single;
      expect(path.kind, CheckoutPathKind.riderLeg);
      expect(path.polyline6, isNull);
      // No road: the line is the stops themselves, straight.
      expect(path.line, path.points);
      expect(path.line, hasLength(2));
    });

    test('a road view draws the decoded polyline, not the stops', () {
      final CheckoutTracking tracking =
          CheckoutTracking.fromJson(view(geometry: 'ROAD', polyline: 'oyus_AomzubAfnLgaU_{TweO'));

      expect(tracking.geometry, RouteGeometry.road);
      expect(tracking.isStraightLine, isFalse);
      expect(tracking.paths.single.line, const <GeoPin>[
        GeoPin(33.8938, 35.5018),
        GeoPin(33.8869, 35.5131),
        GeoPin(33.8981, 35.5214),
      ]);
    });

    // A road the app cannot decode is a road it must not draw, and straight segments in its
    // place would sit under a label that says roads.
    test('a road that cannot be decoded is drawn as nothing, never as straight lines', () {
      final CheckoutTracking tracking =
          CheckoutTracking.fromJson(view(geometry: 'ROAD', polyline: 'oyus_A~'));

      expect(tracking.paths.single.line, isEmpty);
    });

    test('nulls stay nulls: no door, no pins, no riders, no paths', () {
      final CheckoutTracking tracking = CheckoutTracking.fromJson(<String, dynamic>{
        'checkoutId': 'c-2',
        'provider': 'HAVERSINE_DEV',
        'geometry': 'STRAIGHT',
        'door': null,
        'orders': <dynamic>[
          <String, dynamic>{
            'orderId': 'o-1',
            'status': 'PREPARING',
            'shop': <String, dynamic>{'lat': 33.9, 'lng': null},
            'riderAssigned': false,
            'stop': null,
            'expected': true,
            'eta': null,
          },
        ],
        'riders': null,
        'paths': null,
      });

      expect(tracking.door, isNull);
      // Half a coordinate is not a place.
      expect(tracking.orders.single.shop, isNull);
      // "Expected" means nothing without a number.
      expect(tracking.orders.single.expected, isFalse);
      expect(tracking.orders.single.eta, isNull);
      expect(tracking.riders, isEmpty);
      expect(tracking.paths, isEmpty);
      expect(tracking.computedAt, isNull);
    });

    test('a status this build does not know is kept verbatim and is not finished', () {
      final CheckoutTrackedOrder order = CheckoutTrackedOrder.fromJson(<String, dynamic>{
        'orderId': 'o-9',
        'status': 'AWAITING_DRONE',
      });

      expect(order.statusWire, 'AWAITING_DRONE');
      expect(order.status, isNull);
      expect(order.isFinished, isFalse);
    });

    test('an unknown geometry is labelled approximate, and an unknown line kind is not drawn', () {
      expect(RouteGeometry.fromWire('ROAD_WITH_TRAFFIC'), RouteGeometry.straight);
      expect(RouteGeometry.fromWire(null), RouteGeometry.straight);
      expect(CheckoutPathKind.fromWire('ALTERNATIVE'), CheckoutPathKind.unknown);
      expect(CheckoutPathKind.fromWire('PLANNED'), CheckoutPathKind.planned);
    });

    test('an out-of-range pin is no pin', () {
      expect(GeoPin.fromJson(<String, dynamic>{'lat': 95, 'lng': 35.5}), isNull);
      expect(GeoPin.fromJson(<String, dynamic>{'lat': 33.9, 'lng': 181}), isNull);
      expect(GeoPin.fromJson('33.9,35.5'), isNull);
    });

    test('every order delivered or cancelled makes it a finished summary', () {
      CheckoutTracking withStatuses(List<String> statuses) =>
          CheckoutTracking.fromJson(<String, dynamic>{
            'checkoutId': 'c-3',
            'provider': 'HAVERSINE_DEV',
            'geometry': 'STRAIGHT',
            'orders': <dynamic>[
              for (int i = 0; i < statuses.length; i++)
                <String, dynamic>{'orderId': 'o-$i', 'status': statuses[i]},
            ],
          });

      expect(withStatuses(<String>['DELIVERED', 'CANCELLED']).allFinished, isTrue);
      expect(withStatuses(<String>['DELIVERED', 'PICKED_UP']).allFinished, isFalse);
      expect(withStatuses(<String>[]).allFinished, isFalse);
    });
  });

  group('decodePolyline6', () {
    test('decodes OSRM and Mapbox road geometry at 1e6 precision', () {
      expect(decodePolyline6('oyus_AomzubAfnLgaU_{TweO'), const <GeoPin>[
        GeoPin(33.8938, 35.5018),
        GeoPin(33.8869, 35.5131),
        GeoPin(33.8981, 35.5214),
      ]);
      expect(decodePolyline6('fqru_Agqocb@gnLwoJ'), const <GeoPin>[
        GeoPin(-33.9249, 18.4241),
        GeoPin(-33.918, 18.43),
      ]);
    });

    test('is the classic algorithm: Google\'s own precision-5 example decodes', () {
      expect(decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@', precision: 5), const <GeoPin>[
        GeoPin(38.5, -120.2),
        GeoPin(40.7, -120.95),
        GeoPin(43.252, -126.453),
      ]);
    });

    test('an empty string is an empty line', () {
      expect(decodePolyline6(''), isEmpty);
    });

    test('a truncated or foreign string is no line at all, never part of one', () {
      // Cut mid-number.
      expect(decodePolyline6('oyus_AomzubAfnLgaU_{Tw'), isNull);
      // A latitude with no longitude.
      expect(decodePolyline6('oyus_A'), isNull);
      // A character below the format's range.
      expect(decodePolyline6('oyus_A omzubA'), isNull);
      // A value too large to be a coordinate.
      expect(decodePolyline6('~~~~~~~~~~~~'), isNull);
    });
  });

  group('CheckoutTrackingApi', () {
    test('reads the checkout from Order Tracking by its id', () async {
      final List<String> asked = <String>[];
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (RequestOptions o, RequestInterceptorHandler h) {
          asked.add('${o.method} ${o.path}');
          h.resolve(Response<dynamic>(requestOptions: o, statusCode: 200, data: view()));
        },
      ));

      final CheckoutTracking tracking = await CheckoutTrackingApi(dio).view('c-1');

      expect(asked, <String>['GET /api/tracking/checkouts/c-1']);
      expect(tracking.orders, hasLength(2));
    });

    test('a checkout that is not the caller\'s surfaces as the 404 it is', () async {
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (RequestOptions o, RequestInterceptorHandler h) {
          h.reject(DioException(
            requestOptions: o,
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(requestOptions: o, statusCode: 404),
          ));
        },
      ));

      await expectLater(
        CheckoutTrackingApi(dio).view('c-other'),
        throwsA(isA<DioException>()
            .having((DioException e) => e.response?.statusCode, 'status', 404)),
      );
    });
  });
}
