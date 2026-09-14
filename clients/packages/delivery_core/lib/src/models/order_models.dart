/// Order models mirroring the Order Manager API (Phase 2).
library;

import 'gift_models.dart';
import 'service_order_models.dart';
import 'store_models.dart' show ServiceCategory;

/// The lifecycle, mirroring `com.delivery.order.domain.OrderStatus`.
enum OrderStatus {
  placed('PLACED', 'Placed'),
  accepted('ACCEPTED', 'Accepted'),
  preparing('PREPARING', 'Preparing'),
  ready('READY', 'Ready for pickup'),
  pickedUp('PICKED_UP', 'On the way'),
  delivered('DELIVERED', 'Delivered'),
  cancelled('CANCELLED', 'Cancelled');

  const OrderStatus(this.wire, this.label);

  final String wire;
  final String label;

  static OrderStatus fromWire(String value) => OrderStatus.values.firstWhere(
        (OrderStatus s) => s.wire == value,
        orElse: () => OrderStatus.placed,
      );

  bool get isTerminal => this == delivered || this == cancelled;
}

/// What the calling user may do to an order right now.
///
/// Computed server-side and sent with every order, so a button is only rendered when the action
/// would actually succeed. Deliberately NOT re-derived on the client: three Flutter apps each
/// reimplementing the rules would drift from the service, and from each other.
enum OrderAction {
  accept('ACCEPT', 'Accept'),
  prepare('PREPARE', 'Start preparing'),
  ready('READY', 'Mark ready'),

  /// The customer collected their pickup at the counter: READY to DELIVERED. Offered only to the
  /// shop, and only on a pickup waiting there — a delivery is delivered by the rider who carried it.
  collected('COLLECTED', 'Customer collected'),
  claim('CLAIM', 'Claim'),
  pickUp('PICK_UP', 'Picked up'),
  deliver('DELIVER', 'Delivered'),
  cancel('CANCEL', 'Cancel');

  const OrderAction(this.wire, this.label);

  final String wire;
  final String label;

  /// Null for anything this build does not know — an action a newer server offers, or an entry that
  /// is not a string at all — so its button is simply not drawn.
  static OrderAction? fromWire(Object? value) {
    for (final OrderAction a in OrderAction.values) {
      if (a.wire == value) return a;
    }
    return null;
  }

  /// The endpoint suffix this action maps to on Order Manager.
  String get path => switch (this) {
        OrderAction.accept => 'accept',
        OrderAction.prepare => 'prepare',
        OrderAction.ready => 'ready',
        OrderAction.collected => 'collected',
        OrderAction.claim => 'claim',
        OrderAction.pickUp => 'pick-up',
        OrderAction.deliver => 'deliver',
        OrderAction.cancel => 'cancel',
      };
}

/// How fast the customer asked for it, mirroring `com.delivery.order.domain.DeliveryTier`.
///
/// Chosen at placement and never changed afterwards. There is no surcharge in the request and never
/// will be: the EXPRESS premium is priced server-side from configuration and snapshotted onto the
/// order, which is where [DeliveryOrder.expressSurcharge] comes from.
enum DeliveryTier {
  /// The default. An order that says nothing about tier is a standard order, which is exactly what
  /// the server assumes.
  standard('STANDARD', 'Standard'),

  /// Jumped the queue for a fixed premium. The premium is platform revenue: it is charged even
  /// when the base delivery fee is waived, because the waiver covers the delivery, not the hurry.
  express('EXPRESS', 'Express');

  const DeliveryTier(this.wire, this.label);

  final String wire;
  final String label;

  static DeliveryTier fromWire(String? value) => DeliveryTier.values.firstWhere(
        (DeliveryTier t) => t.wire == value,
        orElse: () => DeliveryTier.standard,
      );
}

/// How an order is paid for, mirroring `com.delivery.order.domain.Payment.Method`.
///
/// [cash] is the only method that moves real money today. [card] and [wallet] are fully wired —
/// authorised at checkout, refused if declined, captured on delivery — but against the DEV payment
/// provider, because no real processor credential is configured. A screen offering them in a dev
/// build must label them as test payments; presenting one as a live card charge would be a lie.
enum PaymentMethod {
  /// Collected by the rider at the door. Nothing is owed until the order arrives.
  cash('CASH', 'Cash on delivery'),

  /// Authorised at checkout via an opaque instrument token, captured on delivery. The platform
  /// never sees a card number.
  card('CARD', 'Card'),

  /// A stored balance, on the same authorise-then-capture lifecycle as a card.
  wallet('WALLET', 'Wallet');

  const PaymentMethod(this.wire, this.label);

  final String wire;
  final String label;

  /// Cash on the way in as well as the way out: an order that says nothing about payment is a cash
  /// order, which is exactly what the server assumes.
  static PaymentMethod fromWire(String? value) => PaymentMethod.values.firstWhere(
        (PaymentMethod m) => m.wire == value,
        orElse: () => PaymentMethod.cash,
      );

  /// Whether the money passes through a payment provider — the methods that need an instrument
  /// token at placement, and the ones to label as test payments while the provider is the dev one.
  bool get needsProvider => this != cash;

  /// What every build can offer without qualification. [card] and [wallet] are additionally
  /// offerable where the build has decided to show dev-provider test payments, labelled as such.
  static const List<PaymentMethod> offered = <PaymentMethod>[PaymentMethod.cash];
}

/// Where the money has got to, mirroring `com.delivery.order.domain.Payment.Status`.
enum PaymentStatus {
  due('DUE', 'Due on delivery'),
  authorizationPending('AUTHORIZATION_PENDING', 'Awaiting authorisation'),
  authorized('AUTHORIZED', 'Authorised'),
  collected('COLLECTED', 'Paid'),
  captured('CAPTURED', 'Paid'),
  refunded('REFUNDED', 'Refunded'),
  failed('FAILED', 'Failed');

  const PaymentStatus(this.wire, this.label);

  final String wire;
  final String label;

  static PaymentStatus fromWire(String? value) => PaymentStatus.values.firstWhere(
        (PaymentStatus s) => s.wire == value,
        orElse: () => PaymentStatus.due,
      );

  /// Whether the money has actually moved.
  bool get isSettled => this == collected || this == captured;
}

class OrderLine {
  const OrderLine({
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.qty,
    required this.lineTotal,
    this.optionsSummary,
    this.service,
  });

  final String productId;
  final String productName;
  final double unitPrice;
  final int qty;
  final double lineTotal;

  /// The options as chosen, joined by the server ("Choose Size: Medium (30 Cm)") so every client
  /// renders them alike — for a service line, the finish or paper the provider has to make. Null for
  /// a line without options, and from a server that predates the field.
  final String? optionsSummary;

  /// The terms a service line was ordered on; null on a goods line. Its [ServiceOrderLine.packs] is
  /// this line's [qty].
  final ServiceOrderLine? service;

  factory OrderLine.fromJson(Map<String, dynamic> json) {
    final int qty = (json['qty'] as num).toInt();
    return OrderLine(
      productId: json['productId'] as String,
      productName: json['productName'] as String,
      unitPrice: (json['unitPrice'] as num).toDouble(),
      qty: qty,
      lineTotal: (json['lineTotal'] as num).toDouble(),
      optionsSummary: _textOrNull(json['optionsSummary']),
      service: ServiceOrderLine.maybeFromJson(json['service'], packs: qty),
    );
  }
}

class DeliveryOrder {
  const DeliveryOrder({
    required this.id,
    required this.customerId,
    required this.merchantId,
    required this.riderId,
    required this.status,
    required this.totalAmount,
    required this.deliveryAddress,
    this.subtotal,
    this.deliveryFee = 0,
    this.deliveryFeeCharged = 0,
    this.deliveryTier = DeliveryTier.standard,
    this.expressSurcharge = 0,
    this.deliveryFeeWaived = false,
    this.merchantFeeWaived = false,
    this.carrierFeeWaived = false,
    this.discountAmount,
    this.promoCode,
    this.storeId,
    this.storeName,
    this.paymentMethod = PaymentMethod.cash,
    this.paymentStatus = PaymentStatus.due,
    this.paidAt,
    required this.contactPhone,
    required this.notes,
    this.gift,
    this.checkoutId,
    this.checkoutSize,
    required this.items,
    required this.availableActions,
    required this.placedAt,
    required this.deliveredAt,
    required this.cancelReason,
    this.kind = OrderKind.catalog,
    this.fulfilment = Fulfilment.delivery,
    this.serviceCategory,
    this.customerDisplayName,
    this.readyAt,
    this.estimatedReadyAt,
    this.uncollectedCancellableAt,
  });

  final String id;
  final String customerId;
  final String merchantId;
  final String? riderId;
  final OrderStatus status;
  final double totalAmount;

  /// The breakdown behind [totalAmount], as the server computed it.
  ///
  /// Null on orders placed before the delivery fee existed — for those, the whole total was goods,
  /// which is what [goodsSubtotal] falls back to.
  final double? subtotal;

  /// What delivery *cost* — not necessarily what the customer paid. See [deliveryFeeCharged].
  final double deliveryFee;

  /// What the customer was actually charged for delivery: zero when the platform waived it.
  ///
  /// Separate from [deliveryFee] because a receipt that adds up the cost against the total does
  /// not balance on a waived order. Rendering the cost as though it were charged was a real bug.
  final double deliveryFeeCharged;

  /// How fast the customer asked for it. Standard on every order placed before tiers existed.
  final DeliveryTier deliveryTier;

  /// What the hurry cost: zero on a STANDARD order, the snapshotted premium on EXPRESS.
  ///
  /// Inside [totalAmount] but NOT inside [deliveryFee] — a receipt itemises it as its own line
  /// ("Express +2.00"), and it stays payable even when the base fee is waived, because the waiver
  /// covers the delivery rather than the premium. Never add it to a merchant or carrier payout
  /// figure: it is platform revenue.
  final double expressSurcharge;

  /// The platform absorbed the delivery fee. Worth saying on screen — a customer who is not told
  /// they were given something has not been given anything that changes their behaviour.
  final bool deliveryFeeWaived;

  /// No commission was taken from the merchant on this order.
  final bool merchantFeeWaived;

  /// No platform cut was taken from the delivery company's fee.
  final bool carrierFeeWaived;

  /// The Discounts line: what a promo code took off. Null when no code applied — distinct from
  /// zero, which the server never sends for an order without a code.
  final double? discountAmount;

  /// The canonical stored code behind [discountAmount], never the string the customer typed. Null
  /// when no code applied.
  final String? promoCode;

  final String? storeId;
  final String? storeName;

  /// How this order is being paid for. Cash for everything the app can currently place.
  final PaymentMethod paymentMethod;

  /// Where that payment has got to. What the rider needs is the pair: a CASH order still DUE is
  /// money to collect at the door, and one already COLLECTED is not.
  final PaymentStatus paymentStatus;

  /// When the money actually moved. Null until it has.
  final DateTime? paidAt;

  final String deliveryAddress;
  final String? contactPhone;
  final String? notes;

  /// Who receives it and what goes with it, when the order is a gift; null on an ordinary order.
  /// Its recipient phone is present only for the viewers the server allows — see [OrderGift].
  final OrderGift? gift;

  /// The checkout this order was placed in with other shops' orders; null when it was placed alone.
  /// Every order of one checkout carries the same id, which is how the Orders list shows them as one
  /// purchase.
  final String? checkoutId;

  /// How many shops' orders that checkout placed; null when the order was placed alone.
  final int? checkoutSize;

  /// Whether this order was one of several shops' orders placed together.
  bool get isPartOfCheckout => checkoutId != null && (checkoutSize ?? 0) > 1;
  final List<OrderLine> items;
  final List<OrderAction> availableActions;
  final DateTime? placedAt;
  final DateTime? deliveredAt;
  final String? cancelReason;

  /// What kind of order this is. A basket on every order from a server that does not say.
  final OrderKind kind;

  /// How the customer gets it: a delivery on every order but a service order collected at the shop.
  final Fulfilment fulfilment;

  /// What a service order's shop does; null on every other order, and for a category this build does
  /// not know.
  final ServiceCategory? serviceCategory;

  /// The customer as a provider's card names them ("Jean-Pierre D."). **Null unless the caller may
  /// see it** — the shop, the customer, the rider carrying it and support — and on other orders.
  final String? customerDisplayName;

  /// When the order became READY, for a card's "waiting since"; null until then.
  final DateTime? readyAt;

  /// When a service order's work is promised: acceptance plus the offer's longest turnaround. Null
  /// until accepted, and on every other order. When the work is ready — not when it arrives.
  final DateTime? estimatedReadyAt;

  /// When a pickup waiting at the counter may be cancelled by its shop as not collected. Null on every
  /// other order, and on a pickup not yet ready or already collected. See [canCancelAsNotCollected].
  final DateTime? uncollectedCancellableAt;

  /// Short form for display. Keycloak subs and order ids are full UUIDs, which are unreadable in a
  /// list; the first segment is enough to tell rows apart.
  String get shortId => id.length <= 8 ? id : id.substring(0, 8);

  /// Goods only, safe to call on any order however old.
  double get goodsSubtotal => subtotal ?? (totalAmount - deliveryFeeCharged);

  /// Whether delivery was worth anything at all — true even when the customer did not pay it, so a
  /// receipt can show "3.25, free" rather than pretending the delivery was worthless.
  bool get hasDeliveryFee => deliveryFee > 0;

  /// Whether the rider has to come away from this door with money.
  ///
  /// Both halves matter. Cash that has already been collected is not collectable twice, and a card
  /// order is never cash however unpaid it is — a rider asked for money on either would be asking
  /// for money the platform is not owed.
  bool get collectsCashOnDelivery =>
      paymentMethod == PaymentMethod.cash && !paymentStatus.isSettled;

  /// Whether this is a service order: one line of work a services shop makes to order.
  bool get isService => kind == OrderKind.service;

  /// Whether the customer collects it at the shop — so no rider, no fee, no address and no tracking.
  bool get isPickup => fulfilment == Fulfilment.pickup;

  /// The terms a service order's one line was ordered on; null on any other order.
  ServiceOrderLine? get serviceLine =>
      items.map((OrderLine line) => line.service).whereType<ServiceOrderLine>().firstOrNull;

  /// Why the shop declined this order, or null when it did not. See [DeclineReason.fromCancelReason].
  DeclineReason? get declineReason => DeclineReason.fromCancelReason(cancelReason);

  /// What Order Manager stores as the cancel reason of a pickup its customer never collected — alone,
  /// or with the shop's own words after a colon.
  static const String notCollectedCancelReason = 'NOT_COLLECTED';

  /// Whether the shop cancelled this pickup because its customer never came for it. Like a decline,
  /// a reason only Order Manager can write.
  bool get wasCancelledAsNotCollected {
    final String reason = cancelReason?.trim() ?? '';
    if (!reason.toUpperCase().startsWith(notCollectedCancelReason)) {
      return false;
    }
    final String rest = reason.substring(notCollectedCancelReason.length).trim();
    return rest.isEmpty || rest.startsWith(':');
  }

  /// Whether the customer's time to collect this pickup is up by [now]: the moment the shop's "Cancel
  /// as not collected" unlocks.
  ///
  /// For a card that counts down to it without reading the order again every minute. It is not
  /// permission: only the order's own shop may send that cancel, and the server decides again when
  /// it arrives — answering UNCOLLECTED_TOO_SOON to a phone whose clock runs ahead. Always false for
  /// anything but a pickup still waiting at the counter.
  bool canCancelAsNotCollected(DateTime now) {
    final DateTime? from = uncollectedCancellableAt;
    return isPickup && status == OrderStatus.ready && from != null && !now.isBefore(from);
  }

  factory DeliveryOrder.fromJson(Map<String, dynamic> json) => DeliveryOrder(
        id: json['id'] as String,
        customerId: json['customerId'] as String,
        merchantId: json['merchantId'] as String,
        riderId: json['riderId'] as String?,
        status: OrderStatus.fromWire(json['status'] as String),
        totalAmount: (json['totalAmount'] as num).toDouble(),
        subtotal: (json['subtotal'] as num?)?.toDouble(),
        deliveryFee: (json['deliveryFee'] as num?)?.toDouble() ?? 0,
        // Falls back to the cost, which is what it was before waivers existed and what every order
        // placed before this field shipped genuinely paid.
        deliveryFeeCharged: (json['deliveryFeeCharged'] as num?)?.toDouble()
            ?? (json['deliveryFee'] as num?)?.toDouble() ?? 0,
        deliveryTier: DeliveryTier.fromWire(json['deliveryTier'] as String?),
        expressSurcharge: (json['expressSurcharge'] as num?)?.toDouble() ?? 0,
        deliveryFeeWaived: json['deliveryFeeWaived'] as bool? ?? false,
        merchantFeeWaived: json['merchantFeeWaived'] as bool? ?? false,
        carrierFeeWaived: json['carrierFeeWaived'] as bool? ?? false,
        discountAmount: (json['discountAmount'] as num?)?.toDouble(),
        promoCode: json['promoCode'] as String?,
        storeId: json['storeId'] as String?,
        storeName: json['storeName'] as String?,
        paymentMethod: PaymentMethod.fromWire(json['paymentMethod'] as String?),
        paymentStatus: PaymentStatus.fromWire(json['paymentStatus'] as String?),
        paidAt: _parseTime(json['paidAt']),
        deliveryAddress: json['deliveryAddress'] as String? ?? '',
        contactPhone: json['contactPhone'] as String?,
        notes: json['notes'] as String?,
        checkoutId: json['checkoutId'] as String?,
        checkoutSize: (json['checkoutSize'] as num?)?.toInt(),
        gift: json['gift'] is Map<String, dynamic>
            ? OrderGift.fromJson(json['gift'] as Map<String, dynamic>)
            : null,
        items: (json['items'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => OrderLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        availableActions: _actions(json['availableActions']),
        placedAt: _parseTime(json['placedAt']),
        deliveredAt: _parseTime(json['deliveredAt']),
        cancelReason: json['cancelReason'] as String?,
        // Every service field is absent from a server that predates service orders, and each reads
        // then as what such an order was: a delivered basket with nothing to wait for.
        kind: OrderKind.fromWire(json['kind']),
        fulfilment: Fulfilment.fromWire(json['fulfilment']),
        serviceCategory: ServiceCategory.maybeFromWire(_textOrNull(json['serviceCategory'])),
        customerDisplayName: _textOrNull(json['customerDisplayName']),
        readyAt: _parseTime(json['readyAt']),
        estimatedReadyAt: _parseTime(json['estimatedReadyAt']),
        uncollectedCancellableAt: _parseTime(json['uncollectedCancellableAt']),
      );

  /// What the caller may do, in the server's order. An action this build does not know, or an entry
  /// that is not one at all, is left out rather than guessed at.
  static List<OrderAction> _actions(Object? value) => value is List
      ? value.map(OrderAction.fromWire).whereType<OrderAction>().toList()
      : <OrderAction>[];

  static DateTime? _parseTime(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

/// A rider's reported position.
class RiderPosition {
  const RiderPosition({
    required this.orderId,
    required this.riderId,
    required this.lat,
    required this.lng,
    required this.recordedAt,
  });

  final String orderId;
  final String riderId;
  final double lat;
  final double lng;
  final DateTime? recordedAt;

  factory RiderPosition.fromJson(Map<String, dynamic> json) => RiderPosition(
        orderId: json['orderId'] as String,
        riderId: json['riderId'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        recordedAt: json['recordedAt'] is String
            ? DateTime.tryParse(json['recordedAt'] as String)?.toLocal()
            : null,
      );
}

/// Backoffice dashboard counters.
class OrderStats {
  const OrderStats({
    required this.countByStatus,
    required this.total,
    required this.active,
  });

  final Map<String, int> countByStatus;
  final int total;
  final int active;

  int countOf(OrderStatus status) => countByStatus[status.wire] ?? 0;

  factory OrderStats.fromJson(Map<String, dynamic> json) => OrderStats(
        countByStatus: (json['countByStatus'] as Map<String, dynamic>? ?? <String, dynamic>{})
            .map((String k, dynamic v) => MapEntry<String, int>(k, (v as num).toInt())),
        total: (json['total'] as num?)?.toInt() ?? 0,
        active: (json['active'] as num?)?.toInt() ?? 0,
      );
}

/// One step of an order's life — a row of `GET /api/orders/{id}/history`, which lists them oldest
/// first. What a timeline is drawn from: accepted, in production, ready, collected or delivered.
class OrderStatusChange {
  const OrderStatusChange({
    required this.status,
    this.changedAt,
    this.changedBy,
    this.note,
  });

  /// The status the order moved into.
  final OrderStatus status;

  final DateTime? changedAt;

  /// Who moved it: an account id, never a name. For support; a customer's screen has no use for it.
  final String? changedBy;

  /// What the step recorded, if anything: a cancel reason (`PROVIDER_DECLINED: TOO_BUSY`), or the
  /// server's own sentence such as "Collected by the customer". The server's words, not a label.
  final String? note;

  /// The step, or null when [json] is not one this build can place on a timeline — no status, or one
  /// it does not know — which is left out rather than drawn as a step the order never took.
  static OrderStatusChange? maybeFromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final Object? wire = json['status'];
    final OrderStatus? status =
        OrderStatus.values.where((OrderStatus s) => s.wire == wire).firstOrNull;
    if (status == null) {
      return null;
    }
    return OrderStatusChange(
      status: status,
      changedAt: DeliveryOrder._parseTime(json['changedAt']),
      changedBy: _textOrNull(json['changedBy']),
      note: _textOrNull(json['note']),
    );
  }
}

/// What came of a provider's step on a service order: `OrderApi.collected`, `OrderApi.decline` or
/// `OrderApi.cancelNotCollected`.
///
/// Anything else — a 422 without a code (the order already cancelled or delivered), a 404 (not this
/// shop's order), any network failure — is thrown as the `DioException` it always was.
sealed class ServiceOrderActionResult {
  const ServiceOrderActionResult();
}

/// The step was taken; [order] is the order as it now stands.
final class ServiceOrderUpdated extends ServiceOrderActionResult {
  const ServiceOrderUpdated(this.order);

  final DeliveryOrder order;
}

/// The server refused the step and nothing changed; [refusal] says why.
final class ServiceOrderActionRefused extends ServiceOrderActionResult
    implements ServiceRefusalOutcome {
  const ServiceOrderActionRefused({required this.refusal, required this.code, this.detail});

  @override
  final ServiceOrderRefusal refusal;

  @override
  final String code;

  @override
  final String? detail;
}

String? _textOrNull(Object? value) => value is String && value.trim().isNotEmpty ? value : null;
