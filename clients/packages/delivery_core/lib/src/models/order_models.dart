/// Order models mirroring the Order Manager API (Phase 2).
library;

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
  claim('CLAIM', 'Claim'),
  pickUp('PICK_UP', 'Picked up'),
  deliver('DELIVER', 'Delivered'),
  cancel('CANCEL', 'Cancel');

  const OrderAction(this.wire, this.label);

  final String wire;
  final String label;

  static OrderAction? fromWire(String value) {
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
        OrderAction.claim => 'claim',
        OrderAction.pickUp => 'pick-up',
        OrderAction.deliver => 'deliver',
        OrderAction.cancel => 'cancel',
      };
}

/// How an order is paid for, mirroring `com.delivery.order.domain.Payment.Method`.
///
/// Only [cash] is offered at checkout. The server knows about CARD too, but no payment provider is
/// integrated — a CARD order parks at AUTHORIZATION_PENDING and never becomes money — so putting it
/// in front of a customer would be selling a way to pay that does not work. It stays in this enum
/// because the server can still return it (an order placed through another channel), and an app
/// that could not parse its own order list would be the worse failure.
enum PaymentMethod {
  /// Collected by the rider at the door. Nothing is owed until the order arrives.
  cash('CASH', 'Cash on delivery'),

  /// Authorised at checkout, captured on delivery. Not offered — see the class note.
  card('CARD', 'Card');

  const PaymentMethod(this.wire, this.label);

  final String wire;
  final String label;

  /// Cash on the way in as well as the way out: an order that says nothing about payment is a cash
  /// order, which is exactly what the server assumes.
  static PaymentMethod fromWire(String? value) => PaymentMethod.values.firstWhere(
        (PaymentMethod m) => m.wire == value,
        orElse: () => PaymentMethod.cash,
      );

  /// What the customer can pick at checkout today.
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
  });

  final String productId;
  final String productName;
  final double unitPrice;
  final int qty;
  final double lineTotal;

  factory OrderLine.fromJson(Map<String, dynamic> json) => OrderLine(
        productId: json['productId'] as String,
        productName: json['productName'] as String,
        unitPrice: (json['unitPrice'] as num).toDouble(),
        qty: (json['qty'] as num).toInt(),
        lineTotal: (json['lineTotal'] as num).toDouble(),
      );
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
    this.deliveryFeeWaived = false,
    this.merchantFeeWaived = false,
    this.carrierFeeWaived = false,
    this.storeId,
    this.storeName,
    this.paymentMethod = PaymentMethod.cash,
    this.paymentStatus = PaymentStatus.due,
    required this.contactPhone,
    required this.notes,
    required this.items,
    required this.availableActions,
    required this.placedAt,
    required this.deliveredAt,
    required this.cancelReason,
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

  /// The platform absorbed the delivery fee. Worth saying on screen — a customer who is not told
  /// they were given something has not been given anything that changes their behaviour.
  final bool deliveryFeeWaived;

  /// No commission was taken from the merchant on this order.
  final bool merchantFeeWaived;

  /// No platform cut was taken from the delivery company's fee.
  final bool carrierFeeWaived;

  final String? storeId;
  final String? storeName;

  /// How this order is being paid for. Cash for everything the app can currently place.
  final PaymentMethod paymentMethod;

  /// Where that payment has got to. What the rider needs is the pair: a CASH order still DUE is
  /// money to collect at the door, and one already COLLECTED is not.
  final PaymentStatus paymentStatus;

  final String deliveryAddress;
  final String? contactPhone;
  final String? notes;
  final List<OrderLine> items;
  final List<OrderAction> availableActions;
  final DateTime? placedAt;
  final DateTime? deliveredAt;
  final String? cancelReason;

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
        deliveryFeeWaived: json['deliveryFeeWaived'] as bool? ?? false,
        merchantFeeWaived: json['merchantFeeWaived'] as bool? ?? false,
        carrierFeeWaived: json['carrierFeeWaived'] as bool? ?? false,
        storeId: json['storeId'] as String?,
        storeName: json['storeName'] as String?,
        paymentMethod: PaymentMethod.fromWire(json['paymentMethod'] as String?),
        paymentStatus: PaymentStatus.fromWire(json['paymentStatus'] as String?),
        deliveryAddress: json['deliveryAddress'] as String? ?? '',
        contactPhone: json['contactPhone'] as String?,
        notes: json['notes'] as String?,
        items: (json['items'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => OrderLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        availableActions: (json['availableActions'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => OrderAction.fromWire(e as String))
            .whereType<OrderAction>()
            .toList(),
        placedAt: _parseTime(json['placedAt']),
        deliveredAt: _parseTime(json['deliveredAt']),
        cancelReason: json['cancelReason'] as String?,
      );

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
