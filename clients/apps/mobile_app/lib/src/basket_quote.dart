import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/foundation.dart';

import 'cart.dart';

/// The question to ask Order Manager about [cart] as it stands: its lines, the address's area, the
/// tier and the promo field's text. Null for an empty basket, which has no price to ask about.
BasketQuestion? questionFor(
  Cart cart, {
  String? zoneId,
  DeliveryTier tier = DeliveryTier.standard,
  String? promoCode,
}) =>
    cart.isEmpty
        ? null
        : BasketQuestion(
            items: cart.toOrderLines(),
            deliveryZoneId: zoneId,
            deliveryTier: tier,
            promoCode: promoCode,
          );

/// Why [shop]'s part of a basket cannot be checked out as the server priced it, calling the shop
/// [name] — or null when it can.
///
/// One sentence for both places that say it: the Basket tab, on that shop's own card, and checkout,
/// which has no shop cards and says it over the button the refusal holds back.
String? shopRefusalSentence(DeliveryStrings t, ShopQuote shop, String name) {
  final ShopRefusal? refusal = shop.refusal;
  if (refusal == null) return null;
  return switch (refusal) {
    ShopRefusal.belowMinimum =>
      t.multiCartBelowMinimum('\$${(shop.shortfall ?? 0).toStringAsFixed(2)}', name),
    ShopRefusal.closed => t.multiCartShopClosed(name),
    ShopRefusal.notServed => t.multiCartShopNotServing(name),
    ShopRefusal.unknown => shop.refusalMessage ?? t.multiCartShopUnavailable(name),
  };
}

/// Keeps the server's price for a basket current as the basket changes (`POST /api/orders/quote`).
///
/// **Why the phone asks rather than adds up.** What checkout charges depends on things only the
/// platform knows: each shop's fee for the address's area (not the flat fee on its card), each
/// shop's minimum for that area, the Express premium, whether an offer waives a fee and can still
/// be afforded, and what a promo code is worth at the right fee — shared across every shop's order.
/// The basket used to add up its own total from the cards, and that is how it showed a flat fee at
/// a zone-priced address and a promo total the server would not charge. A quote is the placement
/// path itself, stopped before anything is saved.
///
/// **Only the answer to the question on screen.** Asks are debounced, so a customer tapping + five
/// times asks once, and every answer is matched to the question it answers: one that comes back
/// after the basket changed again is dropped. [quote] is the answer for [question] and nothing else.
/// While a new answer is on its way [shown] keeps the last one on screen — so figures do not flicker
/// to dashes on every tap — and [asking] says they are being updated, which is what a screen uses to
/// hold its checkout button until the figures are the basket's own. A failed ask shows nothing: a
/// figure for a basket that is no longer the one on screen is not the platform's figure.
class BasketQuoter extends ChangeNotifier {
  BasketQuoter(this._api, {this.debounce = const Duration(milliseconds: 350)});

  final OrderApi _api;

  /// How long the basket must stay still before it is asked about.
  final Duration debounce;

  BasketQuestion? _question;
  BasketQuote? _quote;
  BasketQuote? _previous;
  bool _asking = false;
  bool _failed = false;
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;

  /// The question last asked, answered or not.
  BasketQuestion? get question => _question;

  /// The server's answer to [question]; null until it has answered this question.
  BasketQuote? get quote => _quote;

  /// What a screen should show: [quote], or — while it is on its way — the previous answer. Null
  /// after a failure, and for an empty basket.
  BasketQuote? get shown => _quote ?? (_asking ? _previous : null);

  /// True while an answer for [question] is owed.
  bool get asking => _asking;

  /// True when the last ask could not be answered: unreachable, or refused.
  bool get failed => _failed;

  /// Asks about [next] — unless it is the question already answered or on its way. Null (an empty
  /// basket) forgets everything.
  void ask(BasketQuestion? next, {bool immediately = false}) {
    if (_disposed) return;
    if (next == null) {
      _timer?.cancel();
      _generation++;
      final bool changed = _question != null || _quote != null || _asking || _failed;
      _question = null;
      _quote = null;
      _previous = null;
      _asking = false;
      _failed = false;
      if (changed) notifyListeners();
      return;
    }
    final bool same = _question?.signature == next.signature;
    if (same && (_quote != null || _asking)) return;
    _question = next;
    if (_quote != null) _previous = _quote;
    _quote = null;
    _failed = false;
    _asking = true;
    _timer?.cancel();
    final int generation = ++_generation;
    notifyListeners();
    _timer = Timer(immediately ? Duration.zero : debounce, () => _send(next, generation));
  }

  /// Asks the same question again — after a failure, say.
  void retry() {
    final BasketQuestion? question = _question;
    if (question == null || _asking) return;
    _question = null;
    ask(question, immediately: true);
  }

  Future<void> _send(BasketQuestion question, int generation) async {
    try {
      final BasketQuote answer = await _api.quote(question);
      if (_disposed || generation != _generation) return;
      _quote = answer;
      _previous = answer;
      _asking = false;
      _failed = false;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _asking = false;
      _failed = true;
      _previous = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
