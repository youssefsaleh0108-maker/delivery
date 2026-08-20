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

/// Owns the chosen address and the recent ones, and persists both.
class DeliveryAddressStore extends ChangeNotifier {
  DeliveryAddressStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'delivery.addresses';
  static const int _maxRecents = 5;

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
    try {
      final String? raw = await _storage.read(key: _key);
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
    try {
      await _storage.write(
        key: _key,
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
