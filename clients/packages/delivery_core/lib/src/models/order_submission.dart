import 'dart:math';

import 'gift_models.dart';
import 'order_models.dart';
import 'service_order_models.dart';

/// One basket line as Order Manager takes it: ids and a quantity, never a price.
typedef OrderLineSubmission = ({String productId, int qty, List<String> optionIds});

/// A fresh Idempotency-Key: a random UUID v4 from the platform's secure generator.
///
/// Secure rather than `Random()` because the key is the whole identity of a checkout attempt: two
/// devices that happened to draw the same sequence would each be told the other's order was theirs
/// if the server did not also scope keys to the customer — which it does, and this is the second
/// wall, not the only one.
String newIdempotencyKey() {
  final Random random = Random.secure();
  final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  final String hex = bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// One checkout attempt: exactly what is being ordered, and the key that identifies it.
///
/// **The key is minted once per attempt and sent on every retry of it** — a second tap after a
/// timeout, the same checkout re-sent by the offline outbox an hour later, the same checkout after
/// an app restart. Order Manager remembers the key on the order it places and answers every later
/// copy with that order, so a request whose answer was lost can always be sent again without
/// placing a second order. A NEW key is a new order: never mint one to "retry".
///
/// Immutable, and the body is rebuilt from the same fields every time, so a retry sends the same
/// request the first attempt sent — which matters, because the server refuses a used key that
/// arrives with a different basket (see [OrderAlreadyPlaced]).
///
/// Persistable ([toJson]/[fromJson]) so the offline outbox can keep an attempt across an app
/// restart. **The payment instrument token is never persisted**: it is not written by [toJson],
/// so an attempt restored from disk carries none. That is one reason only cash checkouts can be
/// queued; the other is that a card hold cannot be decided while the phone is offline.
///
/// For successors building other kinds of checkout on this (gifting, the multi-shop basket): make
/// the new flow produce an [OrderSubmission] per order and send it through [OrderApi.place]; the
/// key, the retry rules and the price guard come with it.
///
/// A service order is one of these as well: one line whose quantity counts packs of the offer's unit,
/// the [fulfilment] the customer chose, the [attachmentFileIds] of the files they uploaded and their
/// [serviceInstructions]. Every one of them is in the body, so every one is part of what a retry
/// repeats and what the server compares a reused key against.
class OrderSubmission {
  OrderSubmission({
    required List<OrderLineSubmission> items,
    required this.deliveryAddress,
    this.deliveryZoneId,
    this.contactPhone,
    this.notes,
    this.paymentMethod = PaymentMethod.cash,
    this.promoCode,
    this.paymentInstrumentToken,
    this.deliveryTier = DeliveryTier.standard,
    this.deliveryLatitude,
    this.deliveryLongitude,
    this.gift,
    this.fulfilment,
    List<String> attachmentFileIds = const <String>[],
    this.serviceInstructions,
    String? idempotencyKey,
  })  : items = List<OrderLineSubmission>.unmodifiable(items),
        attachmentFileIds = List<String>.unmodifiable(attachmentFileIds),
        idempotencyKey = idempotencyKey ?? newIdempotencyKey() {
    if (fulfilment == Fulfilment.unknown) {
      throw ArgumentError.value(
          fulfilment, 'fulfilment', 'An order is either delivered or collected at the shop');
    }
  }

  /// Sent as the `Idempotency-Key` header. See the class comment for its one rule.
  final String idempotencyKey;

  final List<OrderLineSubmission> items;

  /// Where to deliver. Not sent for a [Fulfilment.pickup] order, which goes nowhere: the server takes
  /// a pickup without an address, and refuses a delivery without one.
  final String deliveryAddress;

  /// The area the address is in, when the customer picked one. Absent on an address saved before
  /// areas existed; the server prices those at the shop's flat fee.
  final String? deliveryZoneId;
  final String? contactPhone;
  final String? notes;

  /// Sent explicitly even when it is the server's default, so the order records a choice the
  /// customer actually made.
  final PaymentMethod paymentMethod;

  /// The canonical code the server quoted — never raw field text. What it is worth is decided
  /// again at placement.
  final String? promoCode;

  /// The processor's opaque handle for a card or wallet. Null on cash; never a card number; never
  /// persisted.
  final String? paymentInstrumentToken;

  /// The tier and nothing else — the EXPRESS premium is priced server-side.
  final DeliveryTier deliveryTier;

  /// The address's map pin. Both or neither.
  final double? deliveryLatitude;
  final double? deliveryLongitude;

  /// Who receives it and what goes with it, when this checkout is a gift; null otherwise.
  ///
  /// Sent in the body and so fingerprinted with everything else: a retry that changes the
  /// recipient, the card or the wrap is a different order, refused rather than answered with the
  /// first. A gift is never cash, so it is never queued by the offline outbox — which is also why
  /// the recipient's phone never reaches the phone's own storage through [toJson].
  final GiftDetails? gift;

  /// How the customer gets a service order: [Fulfilment.pickup] at the shop, or
  /// [Fulfilment.delivery].
  ///
  /// Null on everything but a service order, and then not sent: the server reads no fulfilment as a
  /// delivery, which every basket is. A service order names it even when it is a delivery, so the
  /// order records the choice the customer made. Never [Fulfilment.unknown], which is refused here.
  final Fulfilment? fulfilment;

  /// The files the customer uploaded for a service order, by the ids their upload confirmed: three at
  /// most, and only for an offer that takes files. Ids and nothing else — whether each is the
  /// customer's own, confirmed and on no other order is the server's to check. Empty on a basket, and
  /// then not sent.
  final List<String> attachmentFileIds;

  /// What the customer tells the provider about the work ("leave a white border"), up to 1,000
  /// characters. Its own field rather than [notes], which stays the note a rider reads at the door.
  /// Null or blank on a basket, and then not sent.
  final String? serviceInstructions;

  /// The request body.
  ///
  /// [expectedTotal] is the total the customer agreed to, when the caller wants the server to
  /// refuse anything else (409 PRICE_CHANGED rather than an order at a price nobody saw). It is
  /// rounded to cents here: a total added up in doubles (10.40 + 2.00 = 12.399999999999999) would
  /// otherwise reach the server as a number it neither accepts (two decimals at most) nor equals.
  Map<String, dynamic> toBody({double? expectedTotal}) => <String, dynamic>{
        'items': items
            .map((OrderLineSubmission i) => <String, dynamic>{
                  'productId': i.productId,
                  'qty': i.qty,
                  if (i.optionIds.isNotEmpty) 'optionIds': i.optionIds,
                })
            .toList(),
        if (fulfilment != Fulfilment.pickup) 'deliveryAddress': deliveryAddress,
        if (deliveryZoneId != null) 'deliveryZoneId': deliveryZoneId,
        if (contactPhone != null && contactPhone!.isNotEmpty) 'contactPhone': contactPhone,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        'paymentMethod': paymentMethod.wire,
        'deliveryTier': deliveryTier.wire,
        if (promoCode != null && promoCode!.isNotEmpty) 'promoCode': promoCode,
        if (paymentInstrumentToken != null && paymentInstrumentToken!.isNotEmpty)
          'paymentInstrumentToken': paymentInstrumentToken,
        if (deliveryLatitude != null && deliveryLongitude != null) ...<String, dynamic>{
          'deliveryLatitude': deliveryLatitude,
          'deliveryLongitude': deliveryLongitude,
        },
        if (gift != null) 'gift': gift!.toJson(),
        // A basket sends none of these, so its body is exactly what it was before service orders.
        if (fulfilment != null) 'fulfilment': fulfilment!.wire,
        if (attachmentFileIds.isNotEmpty) 'attachmentFileIds': attachmentFileIds,
        if (serviceInstructions != null && serviceInstructions!.trim().isNotEmpty)
          'serviceInstructions': serviceInstructions,
        if (expectedTotal != null) 'expectedTotal': num.parse(expectedTotal.toStringAsFixed(2)),
      };

  /// For local persistence only. Omits [paymentInstrumentToken] — see the class comment.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'idempotencyKey': idempotencyKey,
        'items': items
            .map((OrderLineSubmission i) => <String, dynamic>{
                  'productId': i.productId,
                  'qty': i.qty,
                  'optionIds': i.optionIds,
                })
            .toList(),
        'deliveryAddress': deliveryAddress,
        'deliveryZoneId': deliveryZoneId,
        'contactPhone': contactPhone,
        'notes': notes,
        'paymentMethod': paymentMethod.wire,
        'promoCode': promoCode,
        'deliveryTier': deliveryTier.wire,
        'deliveryLatitude': deliveryLatitude,
        'deliveryLongitude': deliveryLongitude,
        'gift': gift?.toJson(),
        'fulfilment': fulfilment?.wire,
        'attachmentFileIds': attachmentFileIds,
        'serviceInstructions': serviceInstructions,
      };

  factory OrderSubmission.fromJson(Map<String, dynamic> json) => OrderSubmission(
        idempotencyKey: json['idempotencyKey'] as String,
        items: (json['items'] as List<dynamic>)
            .map((dynamic e) {
              final Map<String, dynamic> line = e as Map<String, dynamic>;
              return (
                productId: line['productId'] as String,
                qty: (line['qty'] as num).toInt(),
                optionIds:
                    (line['optionIds'] as List<dynamic>? ?? <dynamic>[]).cast<String>().toList(),
              );
            })
            .toList(),
        deliveryAddress: json['deliveryAddress'] as String,
        deliveryZoneId: json['deliveryZoneId'] as String?,
        contactPhone: json['contactPhone'] as String?,
        notes: json['notes'] as String?,
        paymentMethod: PaymentMethod.fromWire(json['paymentMethod'] as String?),
        promoCode: json['promoCode'] as String?,
        deliveryTier: DeliveryTier.fromWire(json['deliveryTier'] as String?),
        deliveryLatitude: (json['deliveryLatitude'] as num?)?.toDouble(),
        deliveryLongitude: (json['deliveryLongitude'] as num?)?.toDouble(),
        gift: json['gift'] is Map<String, dynamic>
            ? GiftDetails.fromJson(json['gift'] as Map<String, dynamic>)
            : null,
        // Absent from every attempt stored before service orders, which were all baskets.
        fulfilment: json['fulfilment'] == null ? null : Fulfilment.fromWire(json['fulfilment']),
        attachmentFileIds: (json['attachmentFileIds'] as List<dynamic>? ?? <dynamic>[])
            .whereType<String>()
            .toList(),
        serviceInstructions: json['serviceInstructions'] as String?,
      );
}

/// What came of sending an [OrderSubmission]. Anything else — a refused basket (422), a declined
/// payment (402), a network failure — is thrown as the `DioException` it always was. Only a service
/// order — a submission naming its [OrderSubmission.fulfilment] — has refusals of its own that come
/// back as outcomes ([ServiceOrderRefused], [ServicesDirectoryUnavailable]).
sealed class PlaceOrderResult {
  const PlaceOrderResult();
}

/// The order exists. [replayed] is true when this attempt had already placed it and the server
/// answered a retry with that order — nothing was placed twice.
final class OrderPlaced extends PlaceOrderResult {
  const OrderPlaced(this.order, {this.replayed = false});

  final DeliveryOrder order;
  final bool replayed;
}

/// The server priced the basket at [total], not the [expectedTotal] the customer agreed to, and
/// placed nothing. Show [total] and ask again; never re-send on the customer's behalf.
final class OrderPriceChanged extends PlaceOrderResult {
  const OrderPriceChanged({required this.total, required this.expectedTotal});

  final double total;
  final double expectedTotal;
}

/// This attempt's key had already placed [orderId], and this copy described a different basket —
/// the customer edited their basket after a try whose answer was lost, and that try went through.
///
/// Placing the new basket would be the duplicate the key exists to prevent, so the honest outcome
/// is the order that exists: read it and show it.
final class OrderAlreadyPlaced extends PlaceOrderResult {
  const OrderAlreadyPlaced(this.orderId);

  final String orderId;
}

/// Order Manager refused this service order by one of its rules and placed nothing: the 422 whose
/// `code` [refusal] names — a closed category, a way of getting the work the offer is not sold with,
/// a file the offer needs.
///
/// Decided before anything is saved, so nothing exists under the key. Say it in the customer's words
/// and let them change the order; sending the same submission again can only be refused again.
///
/// Only for a service order, and only the codes a service order is refused with. Every other 422 — a
/// closed shop, an item gone, a multi-shop refusal naming its shop — is thrown as it always was, and
/// so is a basket's whatever its code: a basket holding a service offer is refused with a service
/// code too (ONE_SERVICE_AT_A_TIME, NOT_GIFTABLE on a gift), and the checkouts that send baskets show
/// Order Manager's own sentence from the exception.
final class ServiceOrderRefused extends PlaceOrderResult implements ServiceRefusalOutcome {
  const ServiceOrderRefused({required this.refusal, required this.code, this.detail});

  @override
  final ServiceOrderRefusal refusal;

  @override
  final String code;

  @override
  final String? detail;
}

/// Order Manager could not read which service categories are open, so it neither priced nor placed
/// this service order: the 503 `SERVICES_DIRECTORY_UNAVAILABLE`.
///
/// Unlike an unlabelled 5xx this proves nothing was placed — the key is looked up before pricing, and
/// pricing is where it stopped. Nothing is broken: say "try again", and send the same submission when
/// the customer does.
final class ServicesDirectoryUnavailable extends PlaceOrderResult {
  const ServicesDirectoryUnavailable();
}
