import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/delivery_address.dart';

/// Storage that keeps values in a map, so a test can see exactly which keys were written.
///
/// `noSuchMethod` covers the rest of the interface: only three of its methods are used here, and
/// stubbing the platform options overloads would say nothing about the behaviour under test.
class _FakeStorage implements FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions,
          dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async =>
      values[key];

  @override
  Future<void> write({required String key, required String? value, dynamic iOptions,
      dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions,
      dynamic wOptions}) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({required String key, dynamic iOptions, dynamic aOptions,
      dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async {
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const DeliveryAddress home =
      DeliveryAddress(line: '12 Nile Street, Flat 4', label: 'Home');

  group('addresses belong to one account', () {
    test('what one account saves, another does not see', () async {
      final _FakeStorage storage = _FakeStorage();

      final DeliveryAddressStore first =
          DeliveryAddressStore(storage: storage, ownerId: 'user-a');
      await first.load();
      await first.select(home);

      // The bug this guards: the key used to be one fixed string for the whole device, so the
      // second account inherited the first one's addresses — which is what a tester sees signing
      // in as a customer and then as a rider on the same phone.
      final DeliveryAddressStore second =
          DeliveryAddressStore(storage: storage, ownerId: 'user-b');
      await second.load();

      expect(second.selected, isNull);
      expect(second.recents, isEmpty);
      expect(first.selected, home);
    });

    test('the same account gets its own addresses back', () async {
      final _FakeStorage storage = _FakeStorage();

      final DeliveryAddressStore before =
          DeliveryAddressStore(storage: storage, ownerId: 'user-a');
      await before.load();
      await before.select(home);

      final DeliveryAddressStore after =
          DeliveryAddressStore(storage: storage, ownerId: 'user-a');
      await after.load();

      expect(after.selected, home);
    });

    test('a guest writes nothing that a later account could read', () async {
      final _FakeStorage storage = _FakeStorage();

      final DeliveryAddressStore guest =
          DeliveryAddressStore(storage: storage, ownerId: null);
      await guest.load();
      await guest.select(home);

      // Usable for the session, and persisted nowhere: there is no one to attribute it to.
      expect(guest.selected, home);
      expect(storage.values, isEmpty);
    });

    test('the old device-wide blob is deleted rather than adopted', () async {
      final _FakeStorage storage = _FakeStorage();
      // Written by a build from before the key was scoped. Nothing records whose it was.
      storage.values['delivery.addresses'] =
          '{"selected":{"line":"9 Old Road"},"recents":[{"line":"9 Old Road"}]}';

      final DeliveryAddressStore store =
          DeliveryAddressStore(storage: storage, ownerId: 'user-a');
      await store.load();

      expect(store.selected, isNull,
          reason: 'adopting it would hand one person another\'s address');
      expect(storage.values.containsKey('delivery.addresses'), isFalse);
    });
  });
}
