import 'order_models.dart';
import 'order_submission.dart';
import 'promo_models.dart';
import 'service_order_models.dart';

/// Why one shop's part of a basket cannot be checked out as it stands — Order Manager's
/// `ShopRefusal`, reported on that shop's line of a [BasketQuote] and on a checkout's 422.
enum ShopRefusal {
  /// The shop is not taking orders right now.
  closed('CLOSED'),

  /// The shop does not deliver to the address's area.
  notServed('NOT_SERVED'),

  /// The shop's goods in the basket do not reach its minimum order for that area.
  belowMinimum('BELOW_MINIMUM'),

  /// A reason this build does not know yet. Still a refusal — the shop's part cannot be checked
  /// out — and the server's own sentence ([ShopQuote.refusalMessage]) says why.
  unknown('UNKNOWN');

  const ShopRefusal(this.wire);

  final String wire;

  /// Null for no refusal; [unknown] for one this client cannot name.
  static ShopRefusal? fromWire(String? value) => value == null
      ? null
      : ShopRefusal.values.firstWhere((ShopRefusal r) => r.wire == value,
          orElse: () => ShopRefusal.unknown);
}

double? _money(Object? value) => (value as num?)?.toDouble();

/// What a basket would cost if it were checked out now — asked with a [BasketQuestion], answered by
/// `POST /api/orders/quote`.
///
/// **The server's figures, not the phone's arithmetic.** Each shop's line is priced by the path
/// placement itself takes: the fee for the address's area rather than a shop card's flat one, the
/// Express premium, any waiver, the shop's minimum for that area, and each shop's share of a promo
/// code judged once on the whole basket. So [totalAmount] is what checkout will charge at this
/// moment — which a total added up on the phone was not: it once quoted 18.25 and billed 15.00.
///
/// **Unknown is null, never zero.** A shop that cannot be priced at all (closed, or not delivering
/// to the area) has no figures, and then neither does the basket: every sum is null, and a screen
/// shows a dash rather than a total that leaves that shop out.
class BasketQuote {
  const BasketQuote({
    required this.shops,
    required this.placeable,
    required this.maxShops,
    this.subtotal,
    this.deliveryFeeCharged,
    this.expressSurcharge,
    this.discountAmount,
    this.totalAmount,
    this.promo,
  });

  /// One line per shop, in the order the server would place them.
  final List<ShopQuote> shops;

  /// Whether checking out now would be accepted: every shop open, delivering to the area and above
  /// its minimum. A promo code that does not apply does not count against it — checkout simply goes
  /// without the code, as it always has.
  final bool placeable;

  /// The goods of every shop. Null, like every sum here, when a shop could not be priced.
  final double? subtotal;

  /// The delivery charged across every shop, after waivers.
  final double? deliveryFeeCharged;

  /// The Express premium across every shop — one per shop's order.
  final double? expressSurcharge;

  /// The promo code's discount: every shop's share, added up.
  final double? discountAmount;

  /// What the whole basket would be charged.
  final double? totalAmount;

  /// What the code in the question is worth on this basket. Null when the question named none, or
  /// when a shop could not be priced and so the code was not judged.
  final PromoQuote? promo;

  /// How many shops one checkout may hold, as Order Manager is configured.
  final int maxShops;

  /// The line for [storeId], or null when the quote has none for it.
  ShopQuote? shop(String? storeId) =>
      shops.where((ShopQuote s) => s.storeId == storeId).firstOrNull;

  factory BasketQuote.fromJson(Map<String, dynamic> json) => BasketQuote(
        shops: (json['shops'] as List<dynamic>)
            .map((dynamic e) => ShopQuote.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        placeable: json['placeable'] as bool? ?? false,
        subtotal: _money(json['subtotal']),
        deliveryFeeCharged: _money(json['deliveryFeeCharged']),
        expressSurcharge: _money(json['expressSurcharge']),
        discountAmount: _money(json['discountAmount']),
        totalAmount: _money(json['totalAmount']),
        promo: json['promo'] is Map<String, dynamic>
            ? PromoQuote.fromJson(json['promo'] as Map<String, dynamic>)
            : null,
        maxShops: (json['maxShops'] as num?)?.toInt() ?? 0,
      );
}

/// One shop's line in a [BasketQuote].
class ShopQuote {
  const ShopQuote({
    required this.storeId,
    required this.storeName,
    this.refusal,
    this.refusalMessage,
    this.subtotal,
    this.minimumOrder,
    this.shortfall,
    this.deliveryFee,
    this.deliveryFeeCharged,
    this.deliveryFeeWaived = false,
    this.offerTitle,
    this.expressSurcharge,
    this.discountAmount,
    this.totalAmount,
  });

  final String? storeId;
  final String? storeName;

  /// Why this shop's part cannot be checked out as it stands; null when it can.
  final ShopRefusal? refusal;

  /// The server's sentence for [refusal], for a refusal this build has no wording of its own for.
  final String? refusalMessage;

  final double? subtotal;

  /// The shop's minimum order for the address's area.
  final double? minimumOrder;

  /// How much more in goods this shop needs; zero when it clears its minimum.
  final double? shortfall;

  /// What delivery from this shop costs, before any waiver.
  final double? deliveryFee;

  /// What the customer is charged for it: zero when [deliveryFeeWaived].
  final double? deliveryFeeCharged;
  final bool deliveryFeeWaived;

  /// The offer behind a waived fee, when there is one.
  final String? offerTitle;

  final double? expressSurcharge;
  final double? discountAmount;

  /// What this shop's order would be charged. Null — like every figure here — when the shop could
  /// not be priced at all.
  final double? totalAmount;

  /// Whether the shop could be priced. A closed shop, or one not delivering to the area, cannot.
  bool get priced => totalAmount != null;

  factory ShopQuote.fromJson(Map<String, dynamic> json) => ShopQuote(
        storeId: json['storeId'] as String?,
        storeName: json['storeName'] as String?,
        refusal: ShopRefusal.fromWire(json['refusal'] as String?),
        refusalMessage: json['refusalMessage'] as String?,
        subtotal: _money(json['subtotal']),
        minimumOrder: _money(json['minimumOrder']),
        shortfall: _money(json['shortfall']),
        deliveryFee: _money(json['deliveryFee']),
        deliveryFeeCharged: _money(json['deliveryFeeCharged']),
        deliveryFeeWaived: json['deliveryFeeWaived'] as bool? ?? false,
        offerTitle: json['offerTitle'] as String?,
        expressSurcharge: _money(json['expressSurcharge']),
        discountAmount: _money(json['discountAmount']),
        totalAmount: _money(json['totalAmount']),
      );
}

/// What came of asking what one service would cost — `OrderApi.quoteService`.
///
/// Anything but these three — a 400, a network failure — is thrown as the `DioException` it is.
sealed class ServiceQuoteResult {
  const ServiceQuoteResult();
}

/// The server's figures for the service as asked: the total the service order screen shows.
final class ServiceQuoted extends ServiceQuoteResult {
  const ServiceQuoted(this.quote);

  final BasketQuote quote;

  /// The shop's line — what the fee, waiver, discount and total are read from. Null only when the
  /// server sent no line at all.
  ShopQuote? get shop => quote.shops.firstOrNull;
}

/// The service cannot be ordered as asked — Express, a way of getting the work the offer is not sold
/// with, a closed category — and so has no price. [refusal] says why, in placement's own codes.
final class ServiceQuoteRefused extends ServiceQuoteResult implements ServiceRefusalOutcome {
  const ServiceQuoteRefused({required this.refusal, required this.code, this.detail});

  @override
  final ServiceOrderRefusal refusal;

  @override
  final String code;

  @override
  final String? detail;
}

/// The server could not read which service categories are open, so it priced nothing: the 503
/// `SERVICES_DIRECTORY_UNAVAILABLE`. Nothing is wrong with the question; ask again shortly.
final class ServiceQuoteUnavailable extends ServiceQuoteResult {
  const ServiceQuoteUnavailable();
}

/// The question a [BasketQuote] answers: the lines, the address's area, the tier and the code — and,
/// for a service, how the customer gets it. Nothing else changes a price, so nothing else is asked.
class BasketQuestion {
  BasketQuestion({
    required List<OrderLineSubmission> items,
    this.deliveryZoneId,
    this.deliveryTier = DeliveryTier.standard,
    String? promoCode,
    this.fulfilment,
  })  : items = List<OrderLineSubmission>.unmodifiable(items),
        promoCode = promoCode == null || promoCode.trim().isEmpty ? null : promoCode.trim() {
    if (fulfilment == Fulfilment.unknown) {
      throw ArgumentError.value(
          fulfilment, 'fulfilment', 'An order is either delivered or collected at the shop');
    }
  }

  /// The question a service order screen asks: [packs] of one offer with the options chosen, got the
  /// way the customer chose.
  ///
  /// Always the standard tier, the only one a service order is delivered on. [deliveryZoneId] prices
  /// a delivery at the area's fee; a pickup has no fee whatever area is named.
  factory BasketQuestion.service({
    required String productId,
    required int packs,
    List<String> optionIds = const <String>[],
    required Fulfilment fulfilment,
    String? deliveryZoneId,
    String? promoCode,
  }) =>
      BasketQuestion(
        items: <OrderLineSubmission>[(productId: productId, qty: packs, optionIds: optionIds)],
        deliveryZoneId: deliveryZoneId,
        promoCode: promoCode,
        fulfilment: fulfilment,
      );

  final List<OrderLineSubmission> items;

  /// The area of the address the basket would go to; null prices each shop at its flat fee, which
  /// is what Order Manager charges an address with no area.
  final String? deliveryZoneId;
  final DeliveryTier deliveryTier;

  /// Whatever is in the promo field, trimmed. The server reports anything that is not a live code
  /// as not recognised rather than refusing the question, so a half-typed code costs nothing.
  final String? promoCode;

  /// How a service would reach its customer: the difference between the area's fee and none. Null
  /// for a basket, and then not sent — the server reads no fulfilment as a delivery. Never
  /// [Fulfilment.unknown], which is refused here.
  final Fulfilment? fulfilment;

  Map<String, dynamic> toBody() => <String, dynamic>{
        'items': items
            .map((OrderLineSubmission i) => <String, dynamic>{
                  'productId': i.productId,
                  'qty': i.qty,
                  if (i.optionIds.isNotEmpty) 'optionIds': i.optionIds,
                })
            .toList(),
        if (deliveryZoneId != null) 'deliveryZoneId': deliveryZoneId,
        'deliveryTier': deliveryTier.wire,
        if (promoCode != null) 'promoCode': promoCode,
        if (fulfilment != null) 'fulfilment': fulfilment!.wire,
      };

  /// The same text for the same question however its lines happen to be ordered — so an answer is
  /// matched to the basket it priced, and a basket that did not change is not asked about again.
  String get signature {
    final List<String> lines = items
        .map((OrderLineSubmission i) =>
            '${i.productId}|${(<String>[...i.optionIds]..sort()).join(',')}x${i.qty}')
        .toList()
      ..sort();
    return <String>[
      lines.join(';'),
      deliveryZoneId ?? '',
      deliveryTier.wire,
      promoCode ?? '',
      // Only when asked, so a basket's signature is the one it always had.
      if (fulfilment != null) fulfilment!.wire!,
    ]
        .join('');
  }
}

/// What came of sending a checkout of a basket from several shops — `POST /api/orders/checkout`.
///
/// Anything else — a shop that refused (422, naming it), a declined payment (402), a network
/// failure — is thrown as the `DioException` it is, exactly as a single placement's is.
sealed class PlaceCheckoutResult {
  const PlaceCheckoutResult();
}

/// Every order exists: one per shop, linked by [checkoutId].
final class CheckoutPlaced extends PlaceCheckoutResult {
  const CheckoutPlaced({
    required this.orders,
    required this.totalAmount,
    this.checkoutId,
    this.replayed = false,
  });

  /// Null when the basket turned out to hold one shop's items, placed as an ordinary order.
  final String? checkoutId;

  /// One per shop, in the order the server placed them.
  final List<DeliveryOrder> orders;

  /// What the whole checkout is charged: every order's total, added up by the server.
  final double totalAmount;

  /// True when this attempt had already placed them and the server answered a retry with them —
  /// nothing was placed twice.
  final bool replayed;
}

/// The server priced the checkout at [total], not the [expectedTotal] the customer agreed to, and
/// placed nothing. Show [total] and ask again; never re-send on the customer's behalf.
final class CheckoutPriceChanged extends PlaceCheckoutResult {
  const CheckoutPriceChanged({required this.total, required this.expectedTotal});

  final double total;
  final double expectedTotal;
}

/// This attempt's key had already placed [orderId] for a different basket — an earlier try that went
/// through with its answer lost. That order is the one that exists: read it and show it.
final class CheckoutAlreadyPlaced extends PlaceCheckoutResult {
  const CheckoutAlreadyPlaced(this.orderId);

  final String orderId;
}
