import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the offline pieces keep what has to outlive the app process: the queued checkouts and
/// the snapshot of recent purchases.
///
/// An interface so the outbox and the catalog can be tested against an in-memory store — and so
/// that moving to files later, if the snapshot ever grows, is one class rather than two rewrites.
///
/// Unlike [DeliveryAddressStore]'s private writer, [write] **throws** when it cannot write. The
/// outbox depends on that: a checkout the customer was told is saved must actually be saved, and
/// the only honest reaction to a failed write is to say so while the basket is still there.
abstract interface class OfflineStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// The device's encrypted key-value store (Keystore on Android, Keychain on iOS).
///
/// Chosen over a new file-storage dependency for two reasons. A queued checkout carries the
/// customer's delivery address, pin and phone number — the same data the address book already
/// keeps here, and data that should not sit in a plain file. And both things stored are small and
/// bounded: a handful of queued orders, and at most [OfflineCatalog.maxProducts] products stored as
/// names, prices and image URLs rather than image bytes — a few kilobytes, well within what this
/// store is for.
class SecureOfflineStore implements OfflineStore {
  const SecureOfflineStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
