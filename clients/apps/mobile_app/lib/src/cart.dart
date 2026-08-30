import 'package:delivery_core/delivery_core.dart';
import 'package:flutter/foundation.dart';

import 'product_options_sheet.dart';

/// The customer's basket, held in memory only.
///
/// Deliberately not persisted: prices are re-read from the catalog when the order is placed, so a
/// basket restored from disk days later could show a total that no longer matches what the server
/// would charge. Losing the basket on restart is the lesser problem.
///
/// Scoped to one **store**, not one merchant. That is stricter than Order Manager's rule and
/// deliberately so — a merchant may run several shops, and a basket mixing a pharmacy and a pizzeria
/// is one delivery nobody can make. Anything this accepts still satisfies the server's
/// one-merchant check, so the two cannot disagree.
class Cart extends ChangeNotifier {
  /// Keyed by product *and* selection — see [_keyFor].
  final Map<String, _Line> _lines = <String, _Line>{};

  String? _storeId;
  StoreCard? _store;

  /// The store every line belongs to, or null when the basket is empty.
  String? get storeId => _storeId;

  /// The store itself, when it was known at the time of the first add. Carries the delivery fee and
  /// minimum order the basket has to be measured against.
  StoreCard? get store => _store;

  bool get isEmpty => _lines.isEmpty;

  bool get isNotEmpty => _lines.isNotEmpty;

  int get itemCount => _lines.values.fold(0, (int a, _Line l) => a + l.qty);

  /// Goods only. The delivery fee is not part of this — see [total].
  ///
  /// Priced from each line's own unit price, which already includes its option deltas, rather than
  /// from the product's base price.
  double get subtotal =>
      _lines.values.fold(0, (double a, _Line l) => a + l.unitPrice * l.qty);

  /// What delivery costs at this shop. Not necessarily what the customer will pay — see [waiver].
  double get deliveryFee => _store?.deliveryFee ?? 0;

  /// What the platform has said it will absorb on this basket, if anything.
  ///
  /// Asked of the server rather than worked out here. The basket has no way of knowing whether a
  /// promotion is running, whether this shop is in it, or whether the platform can still afford it
  /// — and a total computed locally is how checkout came to quote 18.25 and then bill 15.00.
  OfferPreview? _waiver;

  OfferPreview? get waiver => _waiver;

  bool get deliveryIsFree => _waiver?.deliveryFeeWaived ?? false;

  /// What the customer will actually be charged for delivery.
  double get deliveryFeeCharged => deliveryIsFree ? 0 : deliveryFee;

  double get total => subtotal + deliveryFeeCharged;

  /// Re-asks the server what this basket qualifies for.
  ///
  /// Called when the basket changes, because offers have minimums and crossing one is exactly the
  /// moment the customer should see the fee disappear. Failure leaves the previous answer alone
  /// rather than silently reverting to "you pay" — a flicker between free and not free while
  /// somebody is deciding whether to check out is worse than a stale quote by a few seconds.
  Future<void> refreshWaiver(OfferApi api) async {
    if (_storeId == null || isEmpty) {
      _waiver = null;
      notifyListeners();
      return;
    }
    try {
      _waiver = await api.preview(
        storeId: _storeId!,
        subtotal: subtotal,
        deliveryFee: deliveryFee,
      );
      notifyListeners();
    } catch (_) {
      // Best effort. The server decides at placement regardless of what was shown here.
    }
  }

  /// How much more is needed before checkout unlocks, or zero when there is no shortfall.
  double get amountBelowMinimum {
    final double minimum = _store?.minOrder ?? 0;
    final double shortfall = minimum - subtotal;
    return shortfall > 0 ? shortfall : 0;
  }

  bool get meetsMinimum => amountBelowMinimum == 0;

  List<CartLine> get lines => _lines.entries
      .map((MapEntry<String, _Line> e) => CartLine(
            key: e.key,
            product: e.value.product,
            qty: e.value.qty,
            unitPrice: e.value.unitPrice,
            optionIds: e.value.optionIds,
            optionsSummary: e.value.summary,
          ))
      .toList(growable: false);

  /// Total quantity of a product across every configuration of it.
  ///
  /// The shelf tile shows one badge per product, and a customer with a medium and a large in the
  /// basket has two of that pizza however they are split across lines.
  int qtyOf(String productId) => _lines.values
      .where((_Line l) => l.product.id == productId)
      .fold(0, (int a, _Line l) => a + l.qty);

  /// True when this product cannot be added because the basket already belongs to another store.
  bool conflictsWith(Product product) =>
      _storeId != null && product.storeId != null && _storeId != product.storeId;

  /// Identifies a line: a product plus the exact set of options chosen for it.
  ///
  /// Sorted so that ticking the same two extras in a different order is recognised as the same
  /// line. Mirrors `OrderService.LineKey` on the server, which must agree or a basket showing two
  /// lines would place an order with one.
  static String _keyFor(String productId, List<String> optionIds) {
    final List<String> sorted = <String>{...optionIds}.toList()..sort();
    return sorted.isEmpty ? productId : '$productId|${sorted.join(',')}';
  }

  /// Adds a product with no options, at its base price.
  void add(Product product, {StoreCard? from}) {
    _addLine(product, const <String>[], product.price, '', 1, from);
  }

  /// Adds a product configured through the options sheet.
  ///
  /// The unit price comes from the catalog's own pricing call, never from adding up deltas here.
  void addConfigured(ConfiguredProduct configured, {StoreCard? from}) {
    _addLine(configured.product, configured.optionIds, configured.unitPrice,
        configured.summary, configured.qty, from);
  }

  void _addLine(Product product, List<String> optionIds, double unitPrice, String summary,
      int qty, StoreCard? from) {
    if (conflictsWith(product)) {
      throw StateError('This basket already has items from another shop.');
    }
    _storeId ??= product.storeId ?? from?.id;
    _store ??= from;

    final String key = _keyFor(product.id, optionIds);
    _lines.update(
      key,
      (_Line l) => l..qty += qty,
      ifAbsent: () => _Line(product, qty, optionIds, unitPrice, summary),
    );
    notifyListeners();
  }

  /// Decrements a line by its key. Falls back to the product id for optionless lines.
  void remove(String lineKey) {
    final _Line? line = _lines[lineKey];
    if (line == null) return;

    if (line.qty > 1) {
      line.qty -= 1;
    } else {
      _lines.remove(lineKey);
    }
    // Releasing the store lock when the last line goes lets the customer switch shops without
    // having to find a "clear basket" button.
    if (_lines.isEmpty) _releaseStore();
    notifyListeners();
  }

  /// Removes one product entirely, whatever configurations of it are in the basket.
  void removeProduct(String productId) {
    _lines.removeWhere((String _, _Line l) => l.product.id == productId);
    if (_lines.isEmpty) _releaseStore();
    notifyListeners();
  }

  void removeLine(String lineKey) {
    if (_lines.remove(lineKey) == null) return;
    if (_lines.isEmpty) _releaseStore();
    notifyListeners();
  }

  /// The diaspora gift note, set by the Send-to-Lebanon flow and carried until checkout folds it
  /// into the order's notes. On the CART rather than an address: the note belongs to THIS order,
  /// and writing it onto a saved address is exactly the leak checkout once had to fix.
  String? giftNote;

  /// The group split plan behind this basket, set once the host's payment requests went out.
  /// Checkout attaches the placed order to it; same order-scoped lifetime as [giftNote].
  String? splitPlanId;

  void clear() {
    _lines.clear();
    _releaseStore();
    giftNote = null;
    splitPlanId = null;
    notifyListeners();
  }

  /// Empties the basket and immediately re-locks it to a new store, for "discard and start here".
  void switchTo(StoreCard store) {
    _lines.clear();
    _storeId = store.id;
    _store = store;
    notifyListeners();
  }

  void _releaseStore() {
    _storeId = null;
    _store = null;
  }

  /// The payload Order Manager expects: ids and quantities only, never prices.
  List<({String productId, int qty, List<String> optionIds})> toOrderLines() => _lines.values
      .map((_Line l) => (productId: l.product.id, qty: l.qty, optionIds: l.optionIds))
      .toList(growable: false);
}

/// A basket line as the UI sees it.
class CartLine {
  const CartLine({
    required this.key,
    required this.product,
    required this.qty,
    required this.unitPrice,
    required this.optionIds,
    required this.optionsSummary,
  });

  /// Identifies this exact configuration; pass it back to [Cart.remove].
  final String key;
  final Product product;
  final int qty;

  /// Includes the option deltas.
  final double unitPrice;
  final List<String> optionIds;

  /// "Choose Size: Large (36 Cm)" — empty when the product has no options.
  final String optionsSummary;

  double get lineTotal => unitPrice * qty;
}

class _Line {
  _Line(this.product, this.qty, this.optionIds, this.unitPrice, this.summary);

  final Product product;
  int qty;
  final List<String> optionIds;
  final double unitPrice;
  final String summary;
}
