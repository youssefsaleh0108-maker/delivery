import 'dart:async';
import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';

import 'offline_store.dart';

/// What each shop charges to deliver to each area, as the platform last said — kept on the phone
/// so a checkout with no connection can still state the total Order Manager will charge.
///
/// **Why checkout needs it.** A queued checkout asserts its total (`expectedTotal`) and the server
/// refuses any other. The delivery fee inside that total is not the shop card's flat fee: once a
/// shop prices by area, Order Manager charges what Product Service quotes for the shop AND the
/// address's area — `GET /api/delivery-zones/terms/{storeId}?zoneId=`, the same call it makes at
/// placement. Adding the flat fee instead sent every such checkout back as PRICE_CHANGED although
/// no price had changed. Asking that endpoint and remembering the answer is how the app states the
/// server's own figure.
///
/// **Remembered, never guessed.** An entry is exactly what the platform answered. Offline, checkout
/// uses the last answer — the bargain the offline shelf already makes with its prices: if the shop
/// has changed its fee since, the queued checkout comes back PRICE_CHANGED and the customer is
/// asked, which is the guard doing its job rather than a mismatch built in. With no answer at all,
/// checkout does not queue.
///
/// **An address with no area needs no entry:** Order Manager prices it at the shop's flat fee.
///
/// Scoped to the signed-in person like the rest of the phone's order state (which areas a phone
/// orders to says where somebody lives), and bounded to [maxEntries], oldest learned dropped first.
///
/// For the multi-shop basket: every shop in it has its own entry for the same area, and each
/// order's asserted total takes its own shop's fee.
class DeliveryTermsBook {
  DeliveryTermsBook({
    required DeliveryZoneApi? api,
    required OfflineStore store,
    required String? ownerId,
    this.freshFor = const Duration(minutes: 10),
    DateTime Function()? now,
  })  : _api = api,
        _store = store,
        _ownerId = ownerId,
        _now = now ?? DateTime.now;

  /// Enough for every shop a customer orders from, times their saved areas.
  static const int maxEntries = 40;
  static const String _keyPrefix = 'delivery.deliveryTerms.';

  final DeliveryZoneApi? _api;
  final OfflineStore _store;
  final String? _ownerId;
  final DateTime Function() _now;

  /// How long an answer received in this session is used before [learn] asks again.
  final Duration freshFor;

  /// Keyed `storeId|zoneId`, in the order learned — the first is the next to go.
  final Map<String, ZoneTerms> _entries = <String, ZoneTerms>{};
  final Map<String, DateTime> _answeredAt = <String, DateTime>{};
  final Map<String, Future<ZoneTerms?>> _asking = <String, Future<ZoneTerms?>>{};
  Future<void> _ready = Future<void>.value();

  String? get _storageKey => _ownerId == null ? null : '$_keyPrefix$_ownerId';

  static String _pair(String storeId, String zoneId) => '$storeId|$zoneId';

  /// Restores what was learned before the app last stopped.
  Future<void> load() => _ready = _load();

  Future<void> _load() async {
    final String? key = _storageKey;
    if (key == null) return;
    try {
      final String? raw = await _store.read(key);
      if (raw == null) return;
      for (final dynamic row in jsonDecode(raw) as List<dynamic>) {
        final Map<String, dynamic> json = row as Map<String, dynamic>;
        _entries[_pair(json['storeId'] as String, json['zoneId'] as String)] =
            ZoneTerms.fromJson(json);
      }
    } catch (_) {
      // Unreadable: nothing is known, as on a first launch — and checkout declines to queue what
      // it cannot price rather than guess.
    }
  }

  /// The platform's last answer for this shop and area, or null when this phone never had one.
  ZoneTerms? known(String storeId, String zoneId) => _entries[_pair(storeId, zoneId)];

  /// Asks the platform what this shop charges to reach this area, remembers the answer and returns
  /// it — or, when the platform cannot be asked, returns the last answer this phone had (or null).
  ///
  /// One request per pair at a time, and none while this session's answer is younger than
  /// [freshFor], however many screens ask.
  Future<ZoneTerms?> learn(String storeId, String zoneId) async {
    await _ready;
    final String pair = _pair(storeId, zoneId);
    final DateTime? answered = _answeredAt[pair];
    if (answered != null && _now().difference(answered) < freshFor) return _entries[pair];
    // A block body, not an arrow: `remove` returns the very future this callback belongs to, and
    // whenComplete waits for a future its callback returns — which would never finish.
    return _asking[pair] ??= _ask(storeId, zoneId, pair).whenComplete(() {
      _asking.remove(pair);
    });
  }

  Future<ZoneTerms?> _ask(String storeId, String zoneId, String pair) async {
    final DeliveryZoneApi? api = _api;
    if (api == null) return _entries[pair];
    final ZoneTerms terms;
    try {
      terms = await api.terms(storeId, zoneId: zoneId);
    } catch (_) {
      // Unreachable or refused: the last answer stands, and the next caller asks again.
      return _entries[pair];
    }
    _answeredAt[pair] = _now();
    _entries
      ..remove(pair)
      ..[pair] = terms;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    await _persist();
    return terms;
  }

  Future<void> _persist() async {
    final String? key = _storageKey;
    if (key == null) return;
    try {
      await _store.write(
        key,
        jsonEncode(<Map<String, dynamic>>[
          for (final MapEntry<String, ZoneTerms> entry in _entries.entries)
            <String, dynamic>{
              // The pair as it was asked, not as echoed back, so the entry is found again under it.
              'storeId': entry.key.substring(0, entry.key.indexOf('|')),
              'zoneId': entry.key.substring(entry.key.indexOf('|') + 1),
              'served': entry.value.served,
              'deliveryFee': entry.value.deliveryFee,
              'minOrder': entry.value.minOrder,
              'etaMinMinutes': entry.value.etaMinMinutes,
              'etaMaxMinutes': entry.value.etaMaxMinutes,
            },
        ]),
      );
    } catch (_) {
      // Known for this session; it simply will not survive a restart.
    }
  }
}
