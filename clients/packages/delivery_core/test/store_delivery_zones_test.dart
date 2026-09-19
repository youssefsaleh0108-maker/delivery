import 'package:delivery_core/delivery_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// The areas a shop delivers to, as the store read carries them (`deliveryZones`) for the shop
/// page's "Delivery area" map.
///
/// Pinned: each area parses with the picker's own model — placed or not, retired or not — in the
/// order the server sent; an empty list means the areas do not limit the shop; and a store read
/// with no such key (a server from before the field) is null, never an empty list, because "the
/// areas do not limit this shop" is a fact only the server can state.
void main() {
  Map<String, dynamic> shop([Object? zones = _absent]) => <String, dynamic>{
        'id': 's1',
        'slug': 's1',
        'name': 'Hamra Corner Grocer',
        'vertical': 'GROCERY',
        'availability': 'OPEN',
        'latitude': 33.8977,
        'longitude': 35.4829,
        'deliveryRadiusMetres': 3000,
        if (!identical(zones, _absent)) 'deliveryZones': zones,
      };

  test('reads each area with its centre only where it was placed, in the order sent', () {
    final Store store = Store.fromJson(shop(<Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'z-hamra',
        'name': 'Hamra',
        'region': 'Beirut',
        'sortOrder': 10,
        'active': true,
        'centerLat': 33.896,
        'centerLng': 35.48,
      },
      <String, dynamic>{
        'id': 'z-verdun',
        'name': 'Verdun',
        'region': 'Beirut',
        'sortOrder': 20,
        'active': false,
        'centerLat': null,
        'centerLng': null,
      },
    ]));

    final List<DeliveryZone> zones = store.deliveryZones!;
    expect(zones.map((DeliveryZone z) => z.name), <String>['Hamra', 'Verdun']);
    expect(zones.first.id, 'z-hamra');
    expect(zones.first.isPlaced, isTrue);
    expect(zones.first.centerLat, 33.896);
    expect(zones.first.centerLng, 35.48);
    // Retired from the picker and still served: kept, and read as retired rather than defaulted.
    expect(zones.last.active, isFalse);
    expect(zones.last.isPlaced, isFalse);
    // The circle is untouched beside them.
    expect(store.deliveryRadiusMetres, 3000);
  });

  test('an empty list is a shop its areas do not limit', () {
    expect(Store.fromJson(shop(<dynamic>[])).deliveryZones, isEmpty);
  });

  test('no key at all is unknown, not "no areas"', () {
    expect(Store.fromJson(shop()).deliveryZones, isNull);
    expect(Store.fromJson(shop(null)).deliveryZones, isNull);
  });

  test('copyWith keeps the areas', () {
    final Store store = Store.fromJson(shop(<Map<String, dynamic>>[
      <String, dynamic>{'id': 'z-hamra', 'name': 'Hamra', 'sortOrder': 10, 'active': true},
    ]));

    expect(store.copyWith(favorite: true).deliveryZones!.single.id, 'z-hamra');
  });
}

const Object _absent = Object();
