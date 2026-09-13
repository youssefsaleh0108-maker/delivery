import 'catalog_models.dart';
import 'order_models.dart';
import 'store_models.dart';

/// One featured care bundle on the customer gift hub — `GET /api/gift-bundles`.
///
/// An ordinary product a shop already sells, picked by the back office: priced, stocked and ordered
/// like any other, from one shop, through the one-shop basket. [product] is that product as the
/// basket holds it, so a bundle goes into the basket exactly the way a shelf item does — and the
/// price on the hub is the price checkout charges.
class GiftBundle {
  const GiftBundle({
    required this.productId,
    required this.merchantId,
    required this.storeId,
    required this.storeName,
    required this.name,
    required this.price,
    required this.availability,
    required this.sameDayDeliverable,
    this.storeSlug,
    this.description,
    this.imageUrls = const <String>[],
    this.imageThumbUrls = const <String>[],
  });

  factory GiftBundle.fromJson(Map<String, dynamic> json) => GiftBundle(
        productId: json['productId'] as String,
        merchantId: json['merchantId'] as String? ?? '',
        storeId: json['storeId'] as String,
        storeSlug: json['storeSlug'] as String?,
        storeName: json['storeName'] as String? ?? '',
        name: json['name'] as String,
        description: json['description'] as String?,
        price: (json['price'] as num).toDouble(),
        imageUrls: (json['imageUrls'] as List<dynamic>? ?? <dynamic>[]).cast<String>(),
        imageThumbUrls: (json['imageThumbUrls'] as List<dynamic>? ?? <dynamic>[]).cast<String>(),
        availability: StoreAvailability.fromWire(json['availability'] as String?),
        sameDayDeliverable: json['sameDayDeliverable'] as bool? ?? false,
      );

  final String productId;
  final String merchantId;
  final String storeId;
  final String? storeSlug;
  final String storeName;
  final String name;
  final String? description;

  /// The catalogue price: exactly what checkout charges for the product.
  final double price;
  final List<String> imageUrls;
  final List<String> imageThumbUrls;

  /// The shop's card state when the hub was loaded.
  final StoreAvailability availability;

  /// The shop is taking orders and the slow end of its delivery estimate fits before it closes —
  /// decided by the server from the shop's own clock. False promises nothing, and the card then says
  /// nothing about today rather than "not today".
  final bool sameDayDeliverable;

  /// The small image for a list row, falling back to the full-size one.
  String? get thumbUrl => imageThumbUrls.isNotEmpty
      ? imageThumbUrls.first
      : (imageUrls.isEmpty ? null : imageUrls.first);

  /// The bundle as the basket holds it: a live product of its shop.
  Product get product => Product(
        id: productId,
        merchantId: merchantId,
        storeId: storeId,
        name: name,
        description: description,
        price: price,
        status: ProductStatus.active,
        imageUrls: imageUrls,
        imageThumbUrls: imageThumbUrls,
      );
}

/// What a gift checkout needs before an order exists — `GET /api/orders/gift-terms`.
class GiftTerms {
  const GiftTerms({required this.wrapFee, required this.paymentMethods});

  factory GiftTerms.fromJson(Map<String, dynamic> json) => GiftTerms(
        wrapFee: (json['wrapFee'] as num).toDouble(),
        // Compared on the wire first: PaymentMethod.fromWire reads anything it does not know as
        // cash, and a method this build has never heard of must be dropped, not offered as cash.
        paymentMethods: (json['paymentMethods'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => '$e')
            .where((String wire) => PaymentMethod.values
                .any((PaymentMethod m) => m.wire == wire && m != PaymentMethod.cash))
            .map(PaymentMethod.fromWire)
            .toList(growable: false),
      );

  /// What wrapping costs right now, from the platform's configuration. The order snapshots whatever
  /// it is at placement, and the receipt shows that.
  final double wrapFee;

  /// The methods a gift can be paid with here. Never cash — the rider would be collecting from the
  /// person receiving it — and possibly none, in which case no gift can be sent yet.
  final List<PaymentMethod> paymentMethods;

  bool get canPay => paymentMethods.isNotEmpty;
}

/// The gift half of an [OrderSubmission]: who receives it and what goes with it.
///
/// Never an amount. What wrapping costs is the server's to price, for the same reason a basket
/// line carries a product id and never a price.
class GiftDetails {
  const GiftDetails({
    required this.recipientName,
    required this.recipientPhone,
    this.message,
    this.wrap = false,
  });

  factory GiftDetails.fromJson(Map<String, dynamic> json) => GiftDetails(
        recipientName: json['recipientName'] as String,
        recipientPhone: json['recipientPhone'] as String,
        message: json['message'] as String?,
        wrap: json['wrap'] as bool? ?? false,
      );

  /// Who the rider asks for at the door, and the name on the card.
  final String recipientName;

  /// International form, `+96171234567` — the only form the server accepts.
  final String recipientPhone;

  /// The card, up to 240 characters; null for none.
  final String? message;
  final bool wrap;

  /// Part of the placement body, and so part of what the server fingerprints: a retry that changes
  /// any of this is a different order and is refused, never answered with the old one.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'recipientName': recipientName,
        'recipientPhone': recipientPhone,
        if (message != null && message!.isNotEmpty) 'message': message,
        'wrap': wrap,
      };
}

/// The gift on a placed order, as the signed-in person may see it — [DeliveryOrder.gift].
class OrderGift {
  const OrderGift({
    required this.recipientName,
    this.recipientPhone,
    this.message,
    this.wrap = false,
    this.wrapFee = 0,
  });

  factory OrderGift.fromJson(Map<String, dynamic> json) => OrderGift(
        recipientName: json['recipientName'] as String? ?? '',
        recipientPhone: json['recipientPhone'] as String?,
        message: json['message'] as String?,
        wrap: json['wrap'] as bool? ?? false,
        wrapFee: (json['wrapFee'] as num?)?.toDouble() ?? 0,
      );

  final String recipientName;

  /// Null unless this viewer needs it: the rider carrying the order, the customer who typed it, or
  /// support. The shop, the job board and the delivery company's staff never receive it — render
  /// null as nothing at all.
  final String? recipientPhone;

  /// The card; null when the customer wrote none.
  final String? message;
  final bool wrap;

  /// What wrapping added to the total — inside `totalAmount`, outside the delivery fee. Zero when
  /// not wrapped.
  final double wrapFee;
}
