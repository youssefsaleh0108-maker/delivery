/// Client-side mirrors of the Butler DTOs: the errand with no catalog behind it.
library;

/// What the rider is being asked to do.
enum ButlerMode {
  /// A shopper buys it and brings it. The price is unknown until they have paid it.
  buy('BUY'),

  /// The customer already owns it; a rider moves it. Fee only, no goods price at all.
  send('SEND');

  const ButlerMode(this.wireValue);

  final String wireValue;

  static ButlerMode fromWire(String? value) =>
      ButlerMode.values.firstWhere((ButlerMode m) => m.wireValue == value,
          orElse: () => ButlerMode.buy);
}

/// Where a request has got to.
///
/// Mirrors the server's machine exactly. The client never decides what may happen next — it asks
/// what state the request is in and offers the actions that go with it.
enum ButlerStatus {
  requested('REQUESTED'),
  claimed('CLAIMED'),
  quoted('QUOTED'),
  approved('APPROVED'),
  declined('DECLINED'),
  cancelled('CANCELLED'),
  expired('EXPIRED');

  const ButlerStatus(this.wireValue);

  final String wireValue;

  static ButlerStatus fromWire(String? value) =>
      ButlerStatus.values.firstWhere((ButlerStatus s) => s.wireValue == value,
          orElse: () => ButlerStatus.requested);

  bool get isTerminal =>
      this == approved || this == declined || this == cancelled || this == expired;

  /// Waiting on the customer to say yes or no to a price.
  bool get needsCustomerAnswer => this == quoted;
}

class ButlerRequest {
  const ButlerRequest({
    required this.id,
    required this.mode,
    required this.status,
    required this.what,
    required this.dropoffAddress,
    required this.deliveryFee,
    required this.payableTotal,
    required this.overBudget,
    required this.createdAt,
    this.sourceHint,
    this.budgetCap,
    this.pickupAddress,
    this.recipient,
    this.contactPhone,
    this.riderId,
    this.goodsCost,
    this.receiptRef,
    this.orderId,
    this.declineReason,
    this.claimedAt,
    this.quotedAt,
    this.resolvedAt,
  });

  final String id;
  final ButlerMode mode;
  final ButlerStatus status;
  final String what;
  final String? sourceHint;
  final double? budgetCap;
  final String? pickupAddress;
  final String? recipient;
  final String dropoffAddress;
  final String? contactPhone;
  final String? riderId;

  /// What the shopper actually paid. Null until quoted, and always null for a pickup.
  final double? goodsCost;
  final double deliveryFee;

  /// Goods plus fee — what the customer pays if they approve.
  final double payableTotal;

  /// The shopper's number came in above the ceiling the customer named.
  final bool overBudget;
  final String? receiptRef;

  /// Set once approved; the order carries the money from then on.
  final String? orderId;
  final String? declineReason;
  final DateTime createdAt;
  final DateTime? claimedAt;
  final DateTime? quotedAt;
  final DateTime? resolvedAt;

  /// Whether the customer still has a decision to make on this one.
  bool get awaitingApproval => status.needsCustomerAnswer;

  factory ButlerRequest.fromJson(Map<String, dynamic> json) => ButlerRequest(
        id: json['id'] as String,
        mode: ButlerMode.fromWire(json['mode'] as String?),
        status: ButlerStatus.fromWire(json['status'] as String?),
        what: json['what'] as String,
        sourceHint: json['sourceHint'] as String?,
        budgetCap: (json['budgetCap'] as num?)?.toDouble(),
        pickupAddress: json['pickupAddress'] as String?,
        recipient: json['recipient'] as String?,
        dropoffAddress: json['dropoffAddress'] as String,
        contactPhone: json['contactPhone'] as String?,
        riderId: json['riderId'] as String?,
        goodsCost: (json['goodsCost'] as num?)?.toDouble(),
        deliveryFee: (json['deliveryFee'] as num?)?.toDouble() ?? 0,
        payableTotal: (json['payableTotal'] as num?)?.toDouble() ?? 0,
        overBudget: json['overBudget'] as bool? ?? false,
        receiptRef: json['receiptRef'] as String?,
        orderId: json['orderId'] as String?,
        declineReason: json['declineReason'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        claimedAt: _maybeDate(json['claimedAt']),
        quotedAt: _maybeDate(json['quotedAt']),
        resolvedAt: _maybeDate(json['resolvedAt']),
      );

  static DateTime? _maybeDate(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}

/// What an errand costs to run, fetched before the form is shown so the fee is never a surprise.
class ButlerTerms {
  const ButlerTerms({required this.errandFee});

  final double errandFee;

  factory ButlerTerms.fromJson(Map<String, dynamic> json) =>
      ButlerTerms(errandFee: (json['errandFee'] as num).toDouble());
}
