/// One customer talking to one shop.
///
/// The unit a merchant actually works in. They do not think in messages or in orders — they think
/// "Rana wants two shawarma", and everything about that exchange belongs together.
class WhatsAppConversation {
  const WhatsAppConversation({
    required this.id,
    required this.customerWaId,
    required this.customerName,
    required this.lastMessageAt,
    required this.unreadCount,
    required this.archived,
  });

  final String id;

  /// The customer's WhatsApp id — in practice their phone number.
  final String customerWaId;

  /// What to show. Already falls back to the number server-side, so it is never empty.
  final String customerName;

  final DateTime lastMessageAt;

  /// Unread inbound messages. A merchant's own reply does not add to this.
  final int unreadCount;

  final bool archived;

  factory WhatsAppConversation.fromJson(Map<String, dynamic> json) => WhatsAppConversation(
        id: json['id'] as String,
        customerWaId: json['customerWaId'] as String,
        customerName: json['customerName'] as String? ?? json['customerWaId'] as String,
        lastMessageAt: DateTime.parse(json['lastMessageAt'] as String).toLocal(),
        unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
        archived: json['archived'] as bool? ?? false,
      );
}

/// One thing that was said, in either direction.
class WhatsAppMessage {
  const WhatsAppMessage({
    required this.id,
    required this.inbound,
    required this.messageType,
    required this.sentAt,
    this.body,
  });

  final String id;

  /// True when the customer said it.
  final bool inbound;

  /// What was said, verbatim. Null for a kind the platform cannot render.
  final String? body;

  /// TEXT, IMAGE, AUDIO, DOCUMENT, LOCATION or OTHER.
  ///
  /// Shown when there is no body, so a merchant who received a voice note sees a voice note rather
  /// than an empty bubble they would read as a lost message.
  final String messageType;

  final DateTime sentAt;

  bool get hasBody => body != null && body!.trim().isNotEmpty;

  factory WhatsAppMessage.fromJson(Map<String, dynamic> json) => WhatsAppMessage(
        id: json['id'] as String,
        inbound: (json['direction'] as String? ?? 'INBOUND') == 'INBOUND',
        body: json['body'] as String?,
        messageType: json['messageType'] as String? ?? 'TEXT',
        sentAt: DateTime.parse(json['sentAt'] as String).toLocal(),
      );
}

/// A WhatsApp number a merchant has connected to their shop.
class ConnectedNumber {
  const ConnectedNumber({
    required this.phoneNumberId,
    this.label,
    this.displayNumber,
  });

  /// The provider's id for the number — what arrives on the webhook, and the only field that routes.
  final String phoneNumberId;

  final String? label;
  final String? displayNumber;

  factory ConnectedNumber.fromJson(Map<String, dynamic> json) => ConnectedNumber(
        phoneNumberId: json['phoneNumberId'] as String,
        label: json['label'] as String?,
        displayNumber: json['displayNumber'] as String?,
      );
}

/// One option chosen on a draft line — "Large", "extra cheese".
class DraftChosenOption {
  const DraftChosenOption({
    required this.optionId,
    required this.groupName,
    required this.optionName,
    required this.priceDelta,
  });

  final String optionId;
  final String groupName;
  final String optionName;
  final double priceDelta;

  factory DraftChosenOption.fromJson(Map<String, dynamic> json) => DraftChosenOption(
        optionId: json['optionId'] as String,
        groupName: json['groupName'] as String? ?? '',
        optionName: json['optionName'] as String? ?? '',
        priceDelta: (json['priceDelta'] as num?)?.toDouble() ?? 0,
      );
}

/// One item in a draft.
class DraftLine {
  const DraftLine({
    required this.id,
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.qty,
    required this.lineTotal,
    required this.options,
    required this.optionsSummary,
  });

  /// The line's own id. What removal names — with options a product can be in the basket twice.
  final String id;

  final String productId;
  final String productName;

  /// With the options chosen, as the catalog priced it.
  final double unitPrice;

  final int qty;
  final double lineTotal;
  final List<DraftChosenOption> options;

  /// Pre-joined "Choose Size: Large" so every client renders it the same way.
  final String optionsSummary;

  factory DraftLine.fromJson(Map<String, dynamic> json) => DraftLine(
        id: json['id'] as String,
        productId: json['productId'] as String,
        productName: json['productName'] as String,
        unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
        qty: (json['qty'] as num?)?.toInt() ?? 1,
        lineTotal: (json['lineTotal'] as num?)?.toDouble() ?? 0,
        options: ((json['options'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic j) => DraftChosenOption.fromJson(j as Map<String, dynamic>))
            .toList(),
        optionsSummary: json['optionsSummary'] as String? ?? '',
      );
}

/// What a merchant is building out of a conversation, before it becomes an order.
///
/// A message is a request; this is the merchant's reading of it; an order is a commitment. Nothing
/// here is binding until [place] is called — which is the whole safety argument for the feature.
class DraftOrder {
  const DraftOrder({
    required this.id,
    required this.conversationId,
    required this.lines,
    required this.estimatedSubtotal,
    required this.status,
    required this.placeable,
    this.requestText,
    this.deliveryAddress,
    this.deliveryZoneId,
    this.contactPhone,
    this.notes,
    this.orderId,
  });

  final String id;
  final String conversationId;

  /// What the customer actually wrote, verbatim.
  final String? requestText;

  final List<DraftLine> lines;

  /// What the lines add up to at the prices captured when they were added.
  ///
  /// Explicitly not what will be charged: the catalog prices the real order at the moment it is
  /// placed. Shown as an estimate so a merchant can read a number back to the customer.
  final double estimatedSubtotal;

  final String? deliveryAddress;
  final String? deliveryZoneId;
  final String? contactPhone;
  final String? notes;

  /// OPEN, PLACED or DISCARDED.
  final String status;

  /// Has an item and an address. Everything else is checked when it is placed.
  final bool placeable;

  /// Set once confirmed — the order this became.
  final String? orderId;

  bool get isOpen => status == 'OPEN';

  factory DraftOrder.fromJson(Map<String, dynamic> json) => DraftOrder(
        id: json['id'] as String,
        conversationId: json['conversationId'] as String,
        requestText: json['requestText'] as String?,
        lines: ((json['lines'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic j) => DraftLine.fromJson(j as Map<String, dynamic>))
            .toList(),
        estimatedSubtotal: (json['estimatedSubtotal'] as num?)?.toDouble() ?? 0,
        deliveryAddress: json['deliveryAddress'] as String?,
        deliveryZoneId: json['deliveryZoneId'] as String?,
        contactPhone: json['contactPhone'] as String?,
        notes: json['notes'] as String?,
        status: json['status'] as String? ?? 'OPEN',
        placeable: json['placeable'] as bool? ?? false,
        orderId: json['orderId'] as String?,
      );
}

/// What happened to a reply the merchant sent.
class ReplyResult {
  const ReplyResult({required this.message, required this.sent, this.failureDetail});

  final WhatsAppMessage message;

  /// False when the provider refused it. The message is still in the thread either way — a merchant
  /// who sees no trace of what they typed will type it again.
  final bool sent;

  final String? failureDetail;

  factory ReplyResult.fromJson(Map<String, dynamic> json) => ReplyResult(
        message: WhatsAppMessage.fromJson(json['message'] as Map<String, dynamic>),
        sent: json['sent'] as bool? ?? false,
        failureDetail: json['failureDetail'] as String?,
      );
}
