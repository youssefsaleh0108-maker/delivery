import 'dart:async';
import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:flutter/foundation.dart';

import 'offline_store.dart';

/// A product saved for offline, and whether it can be added without choosing anything.
@immutable
class CachedProduct {
  const CachedProduct(this.product, {required this.hasOptions});

  /// As the live catalog described it when the snapshot was taken — price included.
  final Product product;

  /// Whether the product asks questions (size, extras) before it can be added. Null when its
  /// option list could not be read while saving.
  final bool? hasOptions;

  /// Only a product known to have no options can be added offline.
  ///
  /// Options are priced by a live catalog call, and a product that needs a choice cannot be ordered
  /// without one — the server would refuse it. Unknown counts as "has options": a disabled button
  /// is a smaller failure than an order that bounces when the connection returns.
  bool get canQuickAdd => hasOptions == false;
}

/// The "Your Last Cached Purchases" shelf: what the customer last bought from the shop they last
/// ordered from, saved while online so it can be read — and re-ordered — while not.
///
/// Built the same way the shop page's Buy Again is: the customer's own recent orders, re-read
/// against the live catalog and restricted to that shop, so something delisted since is not
/// offered. Then the shop's own card, and whether each product has options. Replaced only when the
/// whole refresh succeeds; a failed refresh keeps the snapshot it had, because an older shelf is
/// still the best thing a phone with no connection can show.
///
/// **Prices are the prices at [savedAt]** and the screen says so. What a queued checkout finally
/// costs is the server's to decide when it is sent, and if that differs from the total the
/// customer saw, they are asked again (see [OrderOutbox]).
///
/// One shop, not a mixed shelf: the basket takes one shop at a time, so a shelf mixing three would
/// offer adds that conflict with each other. Scoped to the signed-in person like the address book.
class OfflineCatalog extends ChangeNotifier {
  OfflineCatalog({
    required OfflineStore store,
    required String? ownerId,
    this.refreshEvery = const Duration(minutes: 10),
    DateTime Function()? now,
  })  : _store = store,
        _ownerId = ownerId,
        _now = now ?? DateTime.now;

  /// How many products are kept. Enough for a shelf, small enough to keep the snapshot a few
  /// kilobytes and the refresh to a handful of requests.
  static const int maxProducts = 8;
  static const int _historySize = 20;
  static const String _keyPrefix = 'delivery.offlineCatalog.';

  final OfflineStore _store;
  final String? _ownerId;
  final DateTime Function() _now;

  /// The least time between two unforced refreshes, so a connection that flaps does not refetch
  /// the same shelf every few seconds.
  final Duration refreshEvery;

  StoreCard? _shop;
  List<CachedProduct> _products = <CachedProduct>[];
  DateTime? _savedAt;
  DateTime? _lastAttempt;
  bool _refreshing = false;

  String? get _storageKey => _ownerId == null ? null : '$_keyPrefix$_ownerId';

  /// The shop the shelf is from, as its card was when saved.
  StoreCard? get store => _shop;

  /// Most recently bought first.
  List<CachedProduct> get products => List<CachedProduct>.unmodifiable(_products);

  /// When the snapshot — and every price on it — was taken.
  DateTime? get savedAt => _savedAt;

  bool get isEmpty => _products.isEmpty;

  Future<void> load() async {
    final String? key = _storageKey;
    if (key == null) return;
    try {
      final String? raw = await _store.read(key);
      if (raw == null) return;
      final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
      _shop = StoreCard.fromJson(json['store'] as Map<String, dynamic>);
      _products = (json['products'] as List<dynamic>).map((dynamic e) {
        final Map<String, dynamic> row = e as Map<String, dynamic>;
        return CachedProduct(Product.fromJson(row['product'] as Map<String, dynamic>),
            hasOptions: row['hasOptions'] as bool?);
      }).toList();
      _savedAt = DateTime.parse(json['savedAt'] as String);
      notifyListeners();
    } catch (_) {
      // Unreadable: no shelf, which is what a first launch shows too.
    }
  }

  /// Re-reads the shelf from the platform. Best effort and silent: nothing here is worth an error
  /// message, and the caller is never waiting on it.
  Future<void> refresh({
    required OrderApi orders,
    required StoreApi stores,
    bool force = false,
  }) async {
    final DateTime now = _now();
    if (_refreshing) return;
    if (!force) {
      // Throttled twice over: against the last try in this session, so a flapping connection does
      // not refetch the shelf every few seconds, and against the snapshot's own age, so a cold
      // start does not spend a dozen requests re-reading a shelf saved a minute ago.
      final DateTime? last = _lastAttempt;
      final DateTime? saved = _savedAt;
      if (last != null && now.difference(last) < refreshEvery) return;
      if (saved != null && now.difference(saved) < refreshEvery) return;
    }
    _refreshing = true;
    _lastAttempt = now;
    try {
      final Paged<DeliveryOrder> history = await orders.mine(size: _historySize);
      final String? storeId =
          history.content.map((DeliveryOrder o) => o.storeId).whereType<String>().firstOrNull;
      if (storeId == null) return;

      // Most recent first, each product once.
      final List<String> ids = <String>{
        for (final DeliveryOrder order in history.content)
          if (order.storeId == storeId)
            for (final OrderLine line in order.items) line.productId,
      }.toList();
      if (ids.isEmpty) return;

      final Paged<Product> live = await stores.products(storeId, ids: ids, size: _historySize);
      final Map<String, Product> byId = <String, Product>{
        for (final Product p in live.content) p.id: p,
      };
      final List<Product> picked =
          ids.map((String id) => byId[id]).whereType<Product>().take(maxProducts).toList();

      final StoreCard shop = (await stores.read(storeId)).toCard();
      final List<bool?> options = await Future.wait(picked.map((Product p) => stores
          .productOptions(p.id)
          .then<bool?>((List<OptionGroup> groups) => groups.isNotEmpty)
          .catchError((Object _) => null)));

      _shop = shop;
      _products = <CachedProduct>[
        for (int i = 0; i < picked.length; i++) CachedProduct(picked[i], hasOptions: options[i]),
      ];
      _savedAt = now;
      notifyListeners();
      await _persist();
    } catch (_) {
      // The snapshot it had stays.
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _persist() async {
    final String? key = _storageKey;
    final StoreCard? shop = _shop;
    final DateTime? savedAt = _savedAt;
    if (key == null || shop == null || savedAt == null) return;
    try {
      await _store.write(
        key,
        jsonEncode(<String, dynamic>{
          'store': _storeJson(shop),
          'products': <Map<String, dynamic>>[
            for (final CachedProduct p in _products)
              <String, dynamic>{'product': _productJson(p.product), 'hasOptions': p.hasOptions},
          ],
          'savedAt': savedAt.toUtc().toIso8601String(),
        }),
      );
    } catch (_) {
      // The shelf still shows for this session; it simply will not survive a restart.
    }
  }

  /// The card in the shape [StoreCard.fromJson] reads — only what the shelf, the basket and
  /// checkout use. No offer: a promotion saved offline would be a promise nobody re-checked.
  static Map<String, dynamic> _storeJson(StoreCard s) => <String, dynamic>{
        'id': s.id,
        'slug': s.slug,
        'name': s.name,
        'vertical': s.vertical.wireValue,
        'availability': s.availability.wireValue,
        'deliveryFee': s.deliveryFee,
        'minOrder': s.minOrder,
        'etaMinMinutes': s.etaMinMinutes,
        'etaMaxMinutes': s.etaMaxMinutes,
        'logoUrl': s.logoUrl,
        'logoThumbUrl': s.logoThumbUrl,
        'neighborhood': s.neighborhood,
        'verifiedLocal': s.verifiedLocal,
        'latitude': s.latitude,
        'longitude': s.longitude,
        'deliveryRadiusMetres': s.deliveryRadiusMetres,
      };

  /// The product in the shape [Product.fromJson] reads. Image URLs rather than image bytes: a
  /// signed URL may have expired by the time it is shown, and the product image falls back to its
  /// placeholder when it has.
  static Map<String, dynamic> _productJson(Product p) => <String, dynamic>{
        'id': p.id,
        'merchantId': p.merchantId,
        'storeId': p.storeId,
        'name': p.name,
        'description': p.description,
        'price': p.price,
        'categoryId': p.categoryId,
        'imageUrls': p.imageUrls,
        'imageThumbUrls': p.imageThumbUrls,
        'status': p.status.wireValue,
        'inStock': p.inStock,
      };
}
