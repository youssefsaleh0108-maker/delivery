import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// The merchant Demand Radar's read, and the delivery-area centres that let it draw anything.
///
/// Two things are protected. The request: it names one shop and one window and nothing else — no
/// coordinates, no customer, nothing a log line or a proxy could turn into somebody's whereabouts.
/// And the parsing: a level this build does not know must not take the whole map down, and half a
/// centre must never be drawn as a point on the equator.
class _Recorder implements HttpClientAdapter {
  _Recorder(this.body);

  final Object body;
  final List<RequestOptions> calls = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add(options);
    return ResponseBody.fromString(jsonEncode(body), 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

const Map<String, dynamic> _density = <String, dynamic>{
  'storeId': 'store-1',
  'region': 'Beirut',
  'windowMinutes': 60,
  'generatedAt': '2026-09-13T10:00:00Z',
  'minimumCustomers': 5,
  'areasAround': 3,
  'zones': <dynamic>[
    <String, dynamic>{
      'zoneId': 'z-hamra',
      'name': 'Hamra',
      'region': 'Beirut',
      'centerLat': 33.8959,
      'centerLng': 35.4787,
      'level': 'HIGH',
    },
    <String, dynamic>{
      'zoneId': 'z-verdun',
      'name': 'Verdun',
      'region': 'Beirut',
      'centerLat': null,
      'centerLng': null,
      'level': 'LOW',
    },
  ],
};

(DemandApi, _Recorder) _api(Object body) {
  final _Recorder adapter = _Recorder(body);
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;
  return (DemandApi(dio), adapter);
}

void main() {
  group('DemandApi.density', () {
    test('asks Order Manager about one shop over one window, and nothing else', () async {
      final (DemandApi api, _Recorder adapter) = _api(_density);

      await api.density(storeId: 'store-1', windowMinutes: DemandApi.lastDay);

      final RequestOptions sent = adapter.calls.single;
      expect(sent.method, 'GET');
      expect(sent.path, '/api/orders/demand/density');
      expect(sent.queryParameters, <String, dynamic>{'storeId': 'store-1', 'windowMinutes': 1440});
    });

    test('the last hour is the window unless another is asked for', () async {
      final (DemandApi api, _Recorder adapter) = _api(_density);

      await api.density(storeId: 'store-1');

      expect(adapter.calls.single.queryParameters['windowMinutes'], 60);
      expect(DemandApi.lastWeek, 10080);
    });

    test('reads levels, centres, the city label and the privacy floor', () async {
      final (DemandApi api, _) = _api(_density);

      final DemandDensity density = await api.density(storeId: 'store-1');

      expect(density.region, 'Beirut');
      expect(density.minimumCustomers, 5);
      expect(density.areasAround, 3);
      expect(density.hasNeighbourhood, isTrue);
      expect(density.zones.map((DemandZone z) => z.level),
          <DemandLevel>[DemandLevel.high, DemandLevel.low]);
      expect(density.zones.first.isPlaced, isTrue);
      expect(density.zones.first.centerLat, 33.8959);
      // Listed, but there is nowhere to draw it.
      expect(density.zones.last.isPlaced, isFalse);
      expect(density.placed.map((DemandZone z) => z.name), <String>['Hamra']);
    });

    test('an unknown level is kept as unknown rather than failing the map', () {
      final DemandZone zone = DemandZone.fromJson(<String, dynamic>{
        'zoneId': 'z-1',
        'name': 'Badaro',
        'level': 'SCORCHING',
      });

      expect(zone.level, DemandLevel.unknown);
    });

    test('half a centre is no centre', () {
      final DemandZone zone = DemandZone.fromJson(<String, dynamic>{
        'zoneId': 'z-1',
        'name': 'Badaro',
        'centerLat': 33.87,
        'level': 'MEDIUM',
      });

      expect(zone.isPlaced, isFalse);
      expect(zone.centerLat, isNull);
    });

    test('a shop the platform cannot place yet parses to an honest empty answer', () {
      final DemandDensity density = DemandDensity.fromJson(<String, dynamic>{
        'storeId': 'store-1',
        'region': null,
        'windowMinutes': 60,
        'minimumCustomers': 5,
        'areasAround': 0,
        'zones': <dynamic>[],
      });

      expect(density.hasNeighbourhood, isFalse);
      expect(density.zones, isEmpty);
      expect(density.region, isNull);
    });
  });

  group('DemandApi.unmet', () {
    test('asks for one shop by id, with no query at all', () async {
      final _Recorder adapter = _Recorder(<String, dynamic>{
        'storeId': 'store-1',
        'region': 'Beirut',
        'areasAround': 2,
        'minimumSearches': 5,
        'farMetres': 2000,
        'thisWeek': <String, dynamic>{
          'weekStart': '2026-09-14T21:00:00Z',
          'terms': <dynamic>[
            <String, dynamic>{
              'areaId': 'z-hamra',
              'areaName': 'Hamra',
              'region': 'Beirut',
              'kind': 'NONE',
              'term': 'حفاضات',
              'about': 10,
              'rank': 1,
              'alreadySold': false,
            },
          ],
        },
        'lastWeek': <String, dynamic>{'weekStart': '2026-09-07T21:00:00Z', 'terms': <dynamic>[]},
      });
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;

      final UnmetDemand unmet = await DemandApi(dio).unmet(storeId: 'store-1');

      // The whole request: a store id in the path. No coordinates, no window, no customer —
      // nothing a proxy or an access log could turn into somebody's whereabouts.
      expect(adapter.calls.single.path, '/api/products/demand/unmet/store-1');
      expect(adapter.calls.single.queryParameters, isEmpty);

      expect(unmet.hasNeighbourhood, isTrue);
      expect(unmet.minimumSearches, 5);
      expect(unmet.thisWeek.terms.single.term, 'حفاضات');
      expect(unmet.thisWeek.terms.single.kind, UnmetKind.none);
      expect(unmet.thisWeek.terms.single.about, 10);
      expect(unmet.lastWeek.isEmpty, isTrue);
    });

    test('a reason this build does not know is kept, never guessed at', () async {
      final _Recorder adapter = _Recorder(<String, dynamic>{
        'storeId': 'store-1',
        'areasAround': 1,
        'thisWeek': <String, dynamic>{
          'terms': <dynamic>[
            <String, dynamic>{'term': 'rice', 'kind': 'SOMETHING_NEW', 'about': 5},
          ],
        },
      });
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;

      final UnmetDemand unmet = await DemandApi(dio).unmet(storeId: 'store-1');

      final UnmetTerm term = unmet.thisWeek.terms.single;
      expect(term.kind, UnmetKind.unknown);
      expect(term.term, 'rice');
      // The floor and the distance fall back to what the server would have said, so a screen
      // built on an older response never explains the rule wrongly.
      expect(unmet.minimumSearches, 5);
      expect(unmet.farMetres, 2000);
      expect(unmet.lastWeek.isEmpty, isTrue);
    });
  });

  group('delivery area centres', () {
    test('an area reads its centre when it has one, and none otherwise', () {
      final DeliveryZone placed = DeliveryZone.fromJson(<String, dynamic>{
        'id': 'z-1',
        'name': 'Hamra',
        'sortOrder': 10,
        'active': true,
        'centerLat': 33.8959,
        'centerLng': 35.4787,
      });
      final DeliveryZone unplaced = DeliveryZone.fromJson(<String, dynamic>{
        'id': 'z-2',
        'name': 'Verdun',
        'sortOrder': 20,
        'active': true,
      });

      expect(placed.isPlaced, isTrue);
      expect(placed.centerLng, 35.4787);
      expect(unplaced.isPlaced, isFalse);
    });

    (DeliveryZoneApi, _Recorder) zoneApi() {
      final _Recorder adapter = _Recorder(<String, dynamic>{
        'id': 'z-1',
        'name': 'Hamra',
        'sortOrder': 10,
        'active': true,
      });
      return (
        DeliveryZoneApi(Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter),
        adapter,
      );
    }

    test('creating an area sends its centre, and an unplaced one sends none', () async {
      final (DeliveryZoneApi api, _Recorder adapter) = zoneApi();

      await api.create(name: 'Hamra', region: 'Beirut', centerLat: 33.8959, centerLng: 35.4787);
      await api.create(name: 'Verdun', region: 'Beirut');

      final Map<String, dynamic> placed = adapter.calls.first.data as Map<String, dynamic>;
      expect(placed['centerLat'], 33.8959);
      expect(placed['centerLng'], 35.4787);
      final Map<String, dynamic> unplaced = adapter.calls.last.data as Map<String, dynamic>;
      expect(unplaced.containsKey('centerLat'), isFalse);
      expect(unplaced.containsKey('centerLng'), isFalse);
    });

    test('an edit that says nothing about the centre sends nothing about it, so it is kept',
        () async {
      final (DeliveryZoneApi api, _Recorder adapter) = zoneApi();

      await api.rename('z-1', name: 'Hamra', region: 'Beirut', sortOrder: 5);

      // Exactly the body every build older than centres sends, which the server reads as "keep".
      final Map<String, dynamic> edited = adapter.calls.single.data as Map<String, dynamic>;
      expect(edited.keys, unorderedEquals(<String>['name', 'region', 'sortOrder']));
    });

    test('a new centre is sent whole, and taking one off is said out loud', () async {
      final (DeliveryZoneApi api, _Recorder adapter) = zoneApi();

      await api.rename('z-1', name: 'Hamra', centerLat: 33.897, centerLng: 35.48);
      await api.rename('z-1', name: 'Hamra', clearCentre: true);

      final Map<String, dynamic> moved = adapter.calls.first.data as Map<String, dynamic>;
      expect(moved['centerLat'], 33.897);
      expect(moved['centerLng'], 35.48);
      expect(moved.containsKey('clearCentre'), isFalse);
      final Map<String, dynamic> cleared = adapter.calls.last.data as Map<String, dynamic>;
      expect(cleared['clearCentre'], isTrue);
      expect(cleared.containsKey('centerLat'), isFalse);
      expect(cleared.containsKey('centerLng'), isFalse);
    });
  });
}
