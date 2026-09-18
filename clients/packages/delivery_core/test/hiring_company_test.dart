import 'package:delivery_core/delivery_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reading a delivery company off the public list of who is hiring.
///
/// The region is what a rider applying to the company is shown instead of an area to choose, so the
/// parse has to be forgiving in one direction only: anything that is not a list of names reads as no
/// region — a server older than the field included — and never as a crash or an invented place.
void main() {
  test('reads the names of the regions the company delivers to', () {
    final HiringCompany company = HiringCompany.fromJson(<String, dynamic>{
      'id': 'swift-id',
      'name': 'Swift Couriers',
      'regions': <dynamic>['Achrafieh', ' Hamra '],
    });

    expect(company.id, 'swift-id');
    expect(company.name, 'Swift Couriers');
    expect(company.regions, <String>['Achrafieh', 'Hamra']);
  });

  test('a company with no zones has no region', () {
    final HiringCompany company = HiringCompany.fromJson(<String, dynamic>{
      'id': 'fresh-id',
      'name': 'Fresh Fleet',
      'regions': <dynamic>[],
    });

    expect(company.regions, isEmpty);
  });

  test('a server older than the field sends none, and that reads as no region', () {
    final HiringCompany company =
        HiringCompany.fromJson(<String, dynamic>{'id': 'old-id', 'name': 'Old Fleet'});

    expect(company.regions, isEmpty);
  });

  test('anything but a list of names is no region, and entries that are not names are skipped', () {
    expect(
        HiringCompany.fromJson(<String, dynamic>{'id': 'a', 'name': 'A', 'regions': 'Beirut'})
            .regions,
        isEmpty);
    expect(
        HiringCompany.fromJson(<String, dynamic>{'id': 'b', 'name': 'B', 'regions': null}).regions,
        isEmpty);
    expect(
        HiringCompany.fromJson(<String, dynamic>{
          'id': 'c',
          'name': 'C',
          'regions': <dynamic>[7, null, '', '   ', 'Verdun', <String>['Hamra']],
        }).regions,
        <String>['Verdun']);
  });

  test('the regions cannot be changed by whoever holds the company', () {
    final HiringCompany company = HiringCompany.fromJson(<String, dynamic>{
      'id': 'swift-id',
      'name': 'Swift Couriers',
      'regions': <dynamic>['Hamra'],
    });

    expect(() => company.regions.add('Jounieh'), throwsUnsupportedError);
  });
}
