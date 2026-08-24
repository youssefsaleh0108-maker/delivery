import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the customer wants their order delivered.
///
/// Held here rather than typed fresh at checkout every time. The home screen shows it, checkout
/// pre-fills from it, and the last few are remembered so a customer switching between home and
/// work picks rather than retypes.
///
/// Device-local for now. A server-side address book is the right eventual home — it would follow
/// the customer between devices and let the rider app read it — but this keeps the address out of
/// a free-text box without waiting on that.
class DeliveryAddress {
  const DeliveryAddress({
    required this.line,
    this.label,
    this.notes,
    this.zoneId,
    this.zoneName,
  });

  /// The address itself, as the customer typed it.
  final String line;

  /// Optional "Home", "Work". Purely for recognising it in a list.
  final String? label;

  /// Buzzer codes, floor, "leave at the door" — sent to the rider as order notes.
  final String? notes;

  /// The area this address is in, as picked from a list.
  ///
  /// Nullable, and stays that way: addresses saved before areas existed have none, and a shop that
  /// prices a flat fee everywhere does not care. An order with no area is priced exactly as it
  /// always was rather than refused.
  final String? zoneId;

  /// Kept alongside the id so the address reads correctly without a lookup, including offline and
  /// including after the area has been retired.
  final String? zoneName;

  String get display => label == null || label!.isEmpty ? line : '$label · $line';

  DeliveryAddress withZone(String? id, String? name) =>
      DeliveryAddress(line: line, label: label, notes: notes, zoneId: id, zoneName: name);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'line': line,
        'label': label,
        'notes': notes,
        'zoneId': zoneId,
        'zoneName': zoneName,
      };

  factory DeliveryAddress.fromJson(Map<String, dynamic> json) => DeliveryAddress(
        line: json['line'] as String,
        label: json['label'] as String?,
        notes: json['notes'] as String?,
        zoneId: json['zoneId'] as String?,
        zoneName: json['zoneName'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is DeliveryAddress && other.line.trim().toLowerCase() == line.trim().toLowerCase();

  @override
  int get hashCode => line.trim().toLowerCase().hashCode;
}

/// Owns the chosen address and the recent ones, and persists both, PER SIGNED-IN PERSON.
///
/// The key is scoped by the Keycloak `sub`. It used to be one fixed key for the whole device, so
/// every account that signed in on a phone inherited whatever addresses the last one had saved —
/// which is what a tester sees immediately, signing in as a customer, then a rider, then a
/// merchant, and finding the same delivery locations under all three. On a shared or handed-over
/// phone it also shows one person where another one lives.
class DeliveryAddressStore extends ChangeNotifier {
  DeliveryAddressStore({FlutterSecureStorage? storage, required this.ownerId})
      : _storage = storage ?? const FlutterSecureStorage();

  /// The Keycloak `sub` of whoever is signed in. Null only before a session exists, in which case
  /// nothing is written at all rather than written somewhere a later account would read it.
  final String? ownerId;

  /// The device-wide key this used to write to. Read once, only to delete it — see [load].
  static const String _legacyKey = 'delivery.addresses';
  static const String _keyPrefix = 'delivery.addresses.';
  static const int _maxRecents = 5;

  String? get _key => ownerId == null ? null : '$_keyPrefix$ownerId';

  final FlutterSecureStorage _storage;

  DeliveryAddress? _selected;
  List<DeliveryAddress> _recents = <DeliveryAddress>[];
  bool _loaded = false;

  DeliveryAddress? get selected => _selected;

  List<DeliveryAddress> get recents => List<DeliveryAddress>.unmodifiable(_recents);

  bool get isSet => _selected != null;

  bool get loaded => _loaded;

  /// What the home screen header shows.
  ///
  /// The prompt is passed in rather than held here: this is a store with no BuildContext, and the
  /// only part of the answer that needs translating is the case where there is no address yet.
  String headerLabelOr(String prompt) => _selected?.display ?? prompt;

  Future<void> load() async {
    // Delete the old device-wide blob rather than adopt it. Nothing records whose addresses those
    // were, so handing them to whoever signs in next is exactly the bug being fixed here — and
    // attributing somebody's home address to the wrong account is worse than asking for it again.
    try {
      await _storage.delete(key: _legacyKey);
    } catch (_) {
      // Nothing to do: it is a cleanup, and a failure leaves an unread key behind.
    }

    final String? key = _key;
    if (key == null) {
      _loaded = true;
      notifyListeners();
      return;
    }

    try {
      final String? raw = await _storage.read(key: key);
      if (raw != null) {
        final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
        _recents = (json['recents'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => DeliveryAddress.fromJson(e as Map<String, dynamic>))
            .toList();
        final Map<String, dynamic>? sel = json['selected'] as Map<String, dynamic>?;
        _selected = sel == null ? null : DeliveryAddress.fromJson(sel);
      }
    } catch (_) {
      // A corrupt or unreadable blob must not stop the app booting — the customer simply has no
      // saved address and is asked for one.
      _recents = <DeliveryAddress>[];
      _selected = null;
    }
    _loaded = true;
    notifyListeners();
  }

  /// Selects an address and promotes it to the top of the recents.
  Future<void> select(DeliveryAddress address) async {
    _selected = address;
    // Equality is on the address line, so re-selecting an existing one moves it rather than
    // duplicating it.
    _recents = <DeliveryAddress>[
      address,
      ..._recents.where((DeliveryAddress a) => a != address),
    ].take(_maxRecents).toList();
    notifyListeners();
    await _persist();
  }

  Future<void> forget(DeliveryAddress address) async {
    _recents = _recents.where((DeliveryAddress a) => a != address).toList();
    if (_selected == address) {
      _selected = _recents.isEmpty ? null : _recents.first;
    }
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final String? key = _key;
    if (key == null) {
      // No session, so there is no one to attribute this to. Held in memory for the session and
      // written nowhere — a guest's address must not become the next account's address.
      return;
    }
    try {
      await _storage.write(
        key: key,
        value: jsonEncode(<String, dynamic>{
          'selected': _selected?.toJson(),
          'recents': _recents.map((DeliveryAddress a) => a.toJson()).toList(),
        }),
      );
    } catch (_) {
      // Persistence is a convenience. Failing to write must not lose the address the customer
      // just chose for this session.
    }
  }
}
