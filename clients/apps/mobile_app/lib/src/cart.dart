import 'package:delivery_core/delivery_core.dart';
import 'package:flutter/foundation.dart';

import 'product_options_sheet.dart';

/// The customer's basket, held in memory only.
///
/// Deliberately not persisted: prices are re-read from the catalog when the order is placed, so a
/// basket restored from disk days later could show a total that no longer matches what the server
/// would charge. Losing the basket on restart is the lesser problem.
///
/// Offline mode did not change that. What must survive a restart is a checkout the customer asked
/// to send later, and that is kept by [OrderOutbox] — as the exact request, with the total the
/// customer agreed to, which the server refuses to exceed. The basket that produced it is cleared
/// the moment it is safely queued.
///
/// **One basket, several shops** (Figma 121:358). The lines are grouped by the shop they come from,
/// in the order the shops were first added, and checkout places one order per shop — all of them or
/// none, under one key (`OrderApi.placeCheckout`). Each shop's part is still measured against that
/// shop's own fee and minimum, because each becomes that shop's own order; what one basket changes
/// is only that the customer no longer has to finish one shop's order before starting the next.
/// That used to be refused on purpose ("one basket, one store, one order"), and the owner decided
/// to build it: a dinner, a dekkane run and a pharmacy errand in one go.
///
/// At most [maxShops] shops at once. Grouped by **store**, not merchant: a merchant may run several
/// shops, each with its own fee, minimum and pickup point, and Order Manager groups by store too —
/// from the catalog, never from what the phone says, so the two cannot disagree on what goes where.
class Cart extends ChangeNotifier {
  /// How many shops one basket may hold. Order Manager's `delivery.checkout.max-shops` defaults to
  /// the same number, and its refusal is the one that binds should the two ever differ. Checked here
  /// so a customer hears it at the tap, not at checkout.
  static const int maxShops = 3;

  /// Keyed by product *and* selection — see [_keyFor].
  final Map<String, _Line> _lines = <String, _Line>{};

  /// The shops in the basket, first added first, each with the card it was added from when the
  /// adding screen had one. The card carries the fee and minimum the phone can show before the
  /// server has priced the basket.
  final Map<String, StoreCard?> _stores = <String, StoreCard?>{};

  /// Every shop with something in the basket, first added first.
  List<String> get storeIds => List<String>.unmodifiable(_stores.keys);

  /// How many shops the basket spans.
  int get storeCount => _stores.length;

  /// Whether the basket spans several shops, and so checks out as several orders.
  bool get isMultiShop => _stores.length > 1;

  /// The card [storeId] was added from, when the adding screen had one.
  StoreCard? storeFor(String storeId) => _stores[storeId];

  /// The basket's one shop when it holds exactly one; null when it is empty or spans several.
  ///
  /// For what only a one-shop basket has — a gift, a split with friends, a checkout queued for when
  /// the connection returns — each of which reads "the shop" and must never read one of several as
  /// though it were the only one.
  String? get storeId => _stores.length == 1 ? _stores.keys.first : null;

  /// The card of [storeId]'s shop. Null in exactly the same cases, or when no card was known.
  StoreCard? get store => _stores.length == 1 ? _stores.values.first : null;

  bool get isEmpty => _lines.isEmpty;

  bool get isNotEmpty => _lines.isNotEmpty;

  int get itemCount => _lines.values.fold(0, (int a, _Line l) => a + l.qty);

  /// Goods only, from every shop. The delivery fee is not part of this — see [total].
  ///
  /// Priced from each line's own unit price, which already includes its option deltas, rather than
  /// from the product's base price.
  double get subtotal =>
      _lines.values.fold(0, (double a, _Line l) => a + l.unitPrice * l.qty);

  /// Goods from one shop — what that shop's minimum is measured against.
  double subtotalAt(String storeId) => _lines.values
      .where((_Line l) => l.storeId == storeId)
      .fold(0, (double a, _Line l) => a + l.unitPrice * l.qty);

  /// What delivery costs by the shops' cards: the one shop's fee, or every shop's added up.
  ///
  /// Not necessarily what the customer will pay — see [waiver] — and not what an address in a priced
  /// area pays. The basket's quote from the server says that; this is what the phone can show while
  /// it cannot ask.
  double get deliveryFee =>
      _stores.values.fold(0, (double a, StoreCard? s) => a + (s?.deliveryFee ?? 0));

  /// What the platform has said it will absorb on a one-shop basket, if anything.
  ///
  /// Asked of the server rather than worked out here. The basket has no way of knowing whether a
  /// promotion is running, whether this shop is in it, or whether the platform can still afford it
  /// — and a total computed locally is how checkout came to quote 18.25 and then bill 15.00.
  OfferPreview? _waiver;

  OfferPreview? get waiver => _waiver;

  bool get deliveryIsFree => _waiver?.deliveryFeeWaived ?? false;

  /// What the customer will actually be charged for delivery, as far as the phone can tell.
  double get deliveryFeeCharged => deliveryIsFree ? 0 : deliveryFee;

  double get total => subtotal + deliveryFeeCharged;

  /// Re-asks the server what a one-shop basket qualifies for.
  ///
  /// Called when the basket changes, because offers have minimums and crossing one is exactly the
  /// moment the customer should see the fee disappear. Failure leaves the previous answer alone
  /// rather than silently reverting to "you pay" — a flicker between free and not free while
  /// somebody is deciding whether to check out is worse than a stale quote by a few seconds.
  ///
  /// A basket from several shops has no one offer to ask about: its quote prices every shop's
  /// waiver itself (`OrderApi.quote`), so here it simply has none.
  Future<void> refreshWaiver(OfferApi api) async {
    final String? only = storeId;
    if (only == null || isEmpty) {
      _waiver = null;
      notifyListeners();
      return;
    }
    try {
      _waiver = await api.preview(
        storeId: only,
        subtotal: subtotal,
        deliveryFee: deliveryFee,
      );
      notifyListeners();
    } catch (_) {
      // Best effort. The server decides at placement regardless of what was shown here.
    }
  }

  /// How much more is needed at [storeId] before that shop's minimum is met, by the shop's card —
  /// or zero when there is no shortfall, or no card to measure against.
  ///
  /// The server's minimum for the address's area can differ from the card's; the basket's quote says
  /// that one. This is what the phone knows without asking.
  double shortfallAt(String storeId) {
    final double minimum = _stores[storeId]?.minOrder ?? 0;
    final double shortfall = minimum - subtotalAt(storeId);
    return shortfall > 0 ? shortfall : 0;
  }

  /// The shortfall of a one-shop basket; zero for an empty basket or one spanning several shops,
  /// whose shortfalls are each shop's own ([shortfallAt]).
  double get amountBelowMinimum {
    final String? only = storeId;
    return only == null ? 0 : shortfallAt(only);
  }

  /// Whether every shop in the basket clears its own minimum, by the cards.
  bool get meetsMinimum => _stores.keys.every((String id) => shortfallAt(id) == 0);

  List<CartLine> get lines => _lines.entries
      .map((MapEntry<String, _Line> e) => CartLine(
            key: e.key,
            product: e.value.product,
            qty: e.value.qty,
            unitPrice: e.value.unitPrice,
            optionIds: e.value.optionIds,
            optionsSummary: e.value.summary,
            storeId: e.value.storeId,
          ))
      .toList(growable: false);

  /// One shop's lines, in the order they were added.
  List<CartLine> linesFor(String storeId) =>
      lines.where((CartLine l) => l.storeId == storeId).toList(growable: false);

  /// Total quantity of a product across every configuration of it.
  ///
  /// The shelf tile shows one badge per product, and a customer with a medium and a large in the
  /// basket has two of that pizza however they are split across lines.
  int qtyOf(String productId) => _lines.values
      .where((_Line l) => l.product.id == productId)
      .fold(0, (int a, _Line l) => a + l.qty);

  /// Whether adding [product] would take the basket past [maxShops]: it comes from a shop the basket
  /// does not have yet, and the basket already holds as many shops as it may.
  ///
  /// The only reason an add is refused. A product from a shop already in the basket is always
  /// addable, and so is one from a new shop while there is room.
  bool exceedsShopLimit(Product product, {StoreCard? from}) =>
      !_stores.containsKey(_shopOf(product, from)) && _stores.length >= maxShops;

  /// The shop a product belongs to: its own store id, else the card it is being added from. A
  /// product that names neither — one predating the store model — gets a group of its own.
  static String _shopOf(Product product, StoreCard? from) => product.storeId ?? from?.id ?? '';

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
    if (exceedsShopLimit(product, from: from)) {
      throw StateError('A basket holds items from at most $maxShops shops.');
    }
    final String shop = _shopOf(product, from);
    // The first card anyone knew is kept: an add from a screen that has no card must not forget the
    // fee and minimum an earlier add from the shop's own page brought with it.
    _stores[shop] = _stores[shop] ?? from;

    final String key = _keyFor(product.id, optionIds);
    _lines.update(
      key,
      (_Line l) => l..qty += qty,
      ifAbsent: () => _Line(product, qty, optionIds, unitPrice, summary, shop),
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
    _forgetEmptyShops();
    notifyListeners();
  }

  /// Removes one product entirely, whatever configurations of it are in the basket.
  void removeProduct(String productId) {
    _lines.removeWhere((String _, _Line l) => l.product.id == productId);
    _forgetEmptyShops();
    notifyListeners();
  }

  void removeLine(String lineKey) {
    if (_lines.remove(lineKey) == null) return;
    _forgetEmptyShops();
    notifyListeners();
  }

  /// Takes one shop's items out of the basket and leaves the rest — "Remove {shop}" beside a shop
  /// that is closed, does not deliver to the address, or that the customer changed their mind about.
  void removeStore(String storeId) {
    _lines.removeWhere((String _, _Line l) => l.storeId == storeId);
    _forgetEmptyShops();
    notifyListeners();
  }

  /// Drops every shop with nothing left in the basket. A shop whose last line goes stops counting
  /// towards [maxShops] at once, so the customer never has to find a "clear basket" button to make
  /// room.
  void _forgetEmptyShops() {
    final Set<String> stocked = _lines.values.map((_Line l) => l.storeId).toSet();
    _stores.removeWhere((String id, StoreCard? _) => !stocked.contains(id));
    if (_lines.isEmpty) _releaseStores();
  }

  /// The card for a gift, as typed at the gift checkout and kept while the customer goes back to the
  /// basket and returns. On the CART rather than an address: the note belongs to THIS order, and
  /// writing it onto a saved address is exactly the leak checkout once had to fix. It is sent as
  /// the gift's own message ([GiftDetails.message]), never folded into the door notes.
  String? giftNote;

  /// Whether this basket is a gift for somebody else. Started from the gift hub ([startGift]);
  /// ended by placing it, emptying it ([clear]) or the customer saying it is not one ([stopGift]).
  ///
  /// It is what sends Proceed to Checkout to the gift checkout, so the basket says so while it is
  /// on. Adding from another shop keeps it — a gift is about who receives it — but a gift is sent
  /// from one shop at a time, so the basket holds its checkout until only one shop is left in it.
  bool get isGift => _isGift;
  bool _isGift = false;

  /// Whether the gift checkout's wrap switch is on, kept for the same round trip as [giftNote].
  /// What wrapping costs is the server's to price.
  bool giftWrap = false;

  /// Marks this basket as a gift. Harmless when it already is one.
  void startGift() {
    if (_isGift) return;
    _isGift = true;
    notifyListeners();
  }

  /// Checks this basket out as an ordinary order after all, forgetting the card and the wrap only
  /// a gift carries.
  void stopGift() {
    _isGift = false;
    giftNote = null;
    giftWrap = false;
    notifyListeners();
  }

  /// The group split plan behind this basket, set once the host's payment requests went out.
  /// Checkout attaches the placed order to it; same order-scoped lifetime as [giftNote]. Only ever
  /// on a one-shop basket: a plan closes over exactly one order.
  String? splitPlanId;

  /// Empties the basket and its order-scoped state.
  ///
  /// Not the end of a checkout attempt that may have placed an order ([checkoutUnconfirmed]) — its
  /// key stays. Checkout ends an attempt with [settleCheckout].
  void clear() {
    _lines.clear();
    _releaseStores();
    giftNote = null;
    giftWrap = false;
    _isGift = false;
    splitPlanId = null;
    notifyListeners();
  }

  void _releaseStores() {
    _stores.clear();
    // An attempt whose outcome is unknown outlives the basket it came from; see
    // [checkoutUnconfirmed].
    if (!_checkoutUnconfirmed) _checkoutKey = null;
  }

  String? _checkoutKey;
  bool _checkoutUnconfirmed = false;

  /// The idempotency key of this basket's checkout attempt — minted on first use, kept for as long
  /// as the basket has anything in it.
  ///
  /// On the basket rather than on the checkout screen, because the attempt outlives the screen. A
  /// placement whose answer was lost may have gone through; the customer backing out to the basket
  /// and checking out again must be recognised as the same attempt, or it places a second order.
  /// Editing the basket in between keeps the key too — adding or removing a whole shop included —
  /// and the server then answers with what the first try placed rather than placing the edited
  /// basket as well (see [OrderAlreadyPlaced] and [CheckoutAlreadyPlaced]). One key covers a
  /// basket from several shops: Order Manager places all of their orders under it or none.
  ///
  /// A fresh key when the attempt ends: when checkout settles it ([settleCheckout]: placed, found
  /// already placed, or queued), or when the customer empties the basket — except while
  /// [checkoutUnconfirmed], when only [settleCheckout] ends it.
  String get checkoutKey => _checkoutKey ??= newIdempotencyKey();

  /// True from the moment a send of this basket's checkout may have placed an order with its answer
  /// lost ([OrderApi.mayHavePlaced]) until checkout learns the outcome ([settleCheckout]).
  ///
  /// While true, [checkoutKey] survives the basket being emptied, refilled, or filled from other
  /// shops. That is what stops the second order: whatever the customer checks out next goes under
  /// the same key, and the server answers it with the first order if that one landed — the same
  /// basket as a replay, a different one as already placed — or places it normally if it did not. A
  /// fresh key would place the refilled basket beside an order that may already exist.
  ///
  /// A later refusal does not clear it. A request turned away before Order Manager reads its key
  /// says nothing about the one that went unanswered, and keeping the key is always safe.
  bool get checkoutUnconfirmed => _checkoutUnconfirmed;

  /// Records that the send carrying [key] went unanswered and may have placed an order.
  ///
  /// Takes the key of the send itself, so an attempt still in flight when the customer emptied the
  /// basket is held onto all the same.
  void markCheckoutUnconfirmed(String key) {
    _checkoutKey = key;
    _checkoutUnconfirmed = true;
  }

  /// Ends the checkout attempt because its outcome is known — the order was placed, turned out to
  /// be placed already, or the attempt was handed to the offline outbox, which carries its key on
  /// from here — and empties the basket. The next basket is a new attempt under a new key.
  void settleCheckout() {
    _checkoutUnconfirmed = false;
    _checkoutKey = null;
    clear();
  }

  /// The payload Order Manager expects: ids and quantities only, never prices — and never which shop
  /// a line is from, which the server reads from its own catalog.
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
    this.storeId = '',
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

  /// The shop this line is grouped under — see [Cart.storeIds].
  final String storeId;

  double get lineTotal => unitPrice * qty;
}

class _Line {
  _Line(this.product, this.qty, this.optionIds, this.unitPrice, this.summary, this.storeId);

  final Product product;
  int qty;
  final List<String> optionIds;
  final double unitPrice;
  final String summary;
  final String storeId;
}
