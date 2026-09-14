/// Customer-to-shop threads, mirroring App Notification's `ShopChatController`.
library;

import 'service_order_models.dart';

DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

/// The two sides of a shop thread. The shop side is a role, not a person: a customer is told "the
/// shop" replied, never which account typed it.
enum ShopThreadSide {
  customer('CUSTOMER'),
  shop('SHOP');

  const ShopThreadSide(this.wire);

  final String wire;

  static ShopThreadSide fromWire(String? value) =>
      value == shop.wire ? ShopThreadSide.shop : ShopThreadSide.customer;
}

/// One customer's conversation with one shop, as the caller's side sees it.
class ShopThread {
  const ShopThread({
    required this.id,
    required this.storeId,
    required this.storeName,
    required this.yourSide,
    required this.open,
    required this.lastSequence,
    required this.unread,
    this.customerName,
    this.closesAt,
    this.lastMessageAt,
    this.lastMessagePreview,
    this.lastMessageSide,
    this.orderId,
    this.orderShortId,
    this.orderKind,
  });

  final String id;
  final String storeId;
  final String storeName;

  /// What the shop sees of the customer: a first name and an initial, or null.
  final String? customerName;

  final ShopThreadSide yourSide;

  /// Whether the composer should be enabled. A thread goes quiet two weeks after the customer's
  /// last activity; only the customer can start it again, except that the shop reopening it for an
  /// open or recently ended order keeps it open for that order.
  final bool open;

  final DateTime? closesAt;
  final DateTime? lastMessageAt;
  final int lastSequence;

  /// What the other side said that the caller's side has not read.
  final int unread;

  /// The inbox preview; null outside the inbox.
  final String? lastMessagePreview;
  final ShopThreadSide? lastMessageSide;

  /// The order the thread was last opened from or for, once the server confirmed it — to the
  /// customer as theirs and this shop's, or to the shop's merchant as one of its orders. Null when
  /// the thread was only ever opened from the shop page.
  final String? orderId;

  /// That order's number as its order screens show it (`DeliveryOrder.shortId`); null without one.
  final String? orderShortId;

  /// That order's kind, so a service order can be labelled as one; null without an order.
  final OrderKind? orderKind;

  ShopThread copyWith({bool? open, int? unread}) => ShopThread(
        id: id,
        storeId: storeId,
        storeName: storeName,
        customerName: customerName,
        yourSide: yourSide,
        open: open ?? this.open,
        closesAt: closesAt,
        lastMessageAt: lastMessageAt,
        lastSequence: lastSequence,
        unread: unread ?? this.unread,
        lastMessagePreview: lastMessagePreview,
        lastMessageSide: lastMessageSide,
        orderId: orderId,
        orderShortId: orderShortId,
        orderKind: orderKind,
      );

  factory ShopThread.fromJson(Map<String, dynamic> json) => ShopThread(
        id: json['id'] as String,
        storeId: json['storeId'] as String? ?? '',
        storeName: json['storeName'] as String? ?? '',
        customerName: json['customerName'] as String?,
        yourSide: ShopThreadSide.fromWire(json['yourSide'] as String?),
        open: json['open'] as bool? ?? false,
        closesAt: _date(json['closesAt']),
        lastMessageAt: _date(json['lastMessageAt']),
        lastSequence: (json['lastSequence'] as num?)?.toInt() ?? 0,
        unread: (json['unread'] as num?)?.toInt() ?? 0,
        lastMessagePreview: json['lastMessagePreview'] as String?,
        lastMessageSide: json['lastMessageSide'] == null
            ? null
            : ShopThreadSide.fromWire(json['lastMessageSide'] as String?),
        orderId: json['orderId'] as String?,
        orderShortId: json['orderId'] == null ? null : json['orderShortId'] as String?,
        // Only with an order: [OrderKind.fromWire] reads a missing kind as a basket.
        orderKind: json['orderId'] == null ? null : OrderKind.fromWire(json['orderKind']),
      );
}

/// One message in a shop thread, in history and in a live frame alike.
class ShopMessage {
  const ShopMessage({
    required this.id,
    required this.threadId,
    required this.sequence,
    required this.side,
    required this.mine,
    required this.text,
    this.storeId,
    this.sentAt,
    this.readAt,
  });

  final String id;
  final String threadId;
  final String? storeId;
  final int sequence;
  final ShopThreadSide side;

  /// Whether the viewer sent it, computed by the server against the caller's token.
  final bool mine;

  final String text;
  final DateTime? sentAt;
  final DateTime? readAt;

  factory ShopMessage.fromJson(Map<String, dynamic> json) => ShopMessage(
        id: json['id'] as String,
        threadId: json['threadId'] as String? ?? '',
        storeId: json['storeId'] as String?,
        sequence: (json['sequence'] as num?)?.toInt() ?? 0,
        side: ShopThreadSide.fromWire(json['side'] as String?),
        mine: json['mine'] as bool? ?? false,
        text: json['text'] as String? ?? '',
        sentAt: _date(json['sentAt']),
        readAt: _date(json['readAt']),
      );
}

/// A post refused because the thread went quiet (409): the composer locks and says so. The
/// customer can reopen it; the shop cannot.
class ShopThreadQuietException implements Exception {
  const ShopThreadQuietException(this.closedAt);

  final DateTime? closedAt;

  @override
  String toString() => 'ShopThreadQuietException(closed at $closedAt)';
}

/// A shop's "chat with the customer" refused because the order ended, or was due, longer ago than a
/// shop may open a conversation about it (409) — which can be true of an order still open, once it is
/// long overdue. [closedAt] is when that became so, when the server says. A thread that already
/// exists stays readable from the inbox.
class ShopOrderChatClosedException implements Exception {
  const ShopOrderChatClosedException(this.closedAt);

  final DateTime? closedAt;

  @override
  String toString() => 'ShopOrderChatClosedException(closed at $closedAt)';
}

/// A thread with a page of its messages.
class ShopThreadPage {
  const ShopThreadPage({required this.thread, required this.messages, required this.more});

  final ShopThread thread;
  final List<ShopMessage> messages;
  final bool more;

  factory ShopThreadPage.fromJson(Map<String, dynamic> json) => ShopThreadPage(
        thread: ShopThread.fromJson(json['thread'] as Map<String, dynamic>),
        messages: (json['messages'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic e) => ShopMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
        more: json['more'] as bool? ?? false,
      );
}
