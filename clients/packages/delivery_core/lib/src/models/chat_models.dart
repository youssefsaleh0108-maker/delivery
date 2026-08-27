/// Order chat models mirroring the App Notification `ChatController` and its STOMP frames.
library;

/// Which side of the conversation somebody is on, mirroring `ChatParticipantRole`.
///
/// The socket and the REST thread never carry the other party's user id — only their role. Two
/// people are in the conversation, so the role says everything a bubble needs.
enum ChatRole {
  customer('CUSTOMER', 'Customer'),
  rider('RIDER', 'Rider'),

  /// A role this client does not know. Rendered as the other party, never dropped.
  unknown('UNKNOWN', 'Participant');

  const ChatRole(this.wire, this.label);

  final String wire;
  final String label;

  static ChatRole fromWire(String? value) => ChatRole.values.firstWhere(
        (ChatRole r) => r.wire == value,
        orElse: () => ChatRole.unknown,
      );
}

/// How far one of the caller's own messages has travelled.
///
/// Derived from the timestamps rather than sent as a field, exactly as the wire has it: a message
/// with a `readAt` was necessarily delivered, so the states are strictly ordered.
enum ChatMessageState {
  /// Stored on the server; the recipient's device has not confirmed it yet.
  sent,

  /// The recipient's device received it — live over the socket, or on their next fetch.
  delivered,

  /// The recipient's client marked the thread read past this message.
  read,
}

/// One message as a participant sees it, mirroring `ChatController.MessageView`.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sequence,
    required this.senderRole,
    required this.mine,
    required this.text,
    this.sentAt,
    this.deliveredAt,
    this.readAt,
  });

  final String id;

  /// The conversation's own strictly increasing counter. The cursor for "everything after" on a
  /// reconnect, and the value to send as a read receipt.
  final int sequence;

  /// Which side sent it. With [mine], enough to lay out the thread — there is no sender id.
  final ChatRole senderRole;

  /// Whether the viewer sent it. Computed server-side against the caller's token, so the same
  /// message serialises differently for each participant.
  final bool mine;

  final String text;

  final DateTime? sentAt;

  /// When the recipient's device got it. Null until then — and null on messages the viewer
  /// received, where the server has nothing to report about the viewer's own device.
  final DateTime? deliveredAt;

  /// When the recipient read past it. Null until then.
  final DateTime? readAt;

  /// The tick to draw on the viewer's own bubbles. Meaningless on [mine] == false.
  ChatMessageState get state => readAt != null
      ? ChatMessageState.read
      : deliveredAt != null
          ? ChatMessageState.delivered
          : ChatMessageState.sent;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        sequence: (json['sequence'] as num?)?.toInt() ?? 0,
        senderRole: ChatRole.fromWire(json['senderRole'] as String?),
        mine: json['mine'] as bool? ?? false,
        text: json['text'] as String? ?? '',
        sentAt: _date(json['sentAt']),
        deliveredAt: _date(json['deliveredAt']),
        readAt: _date(json['readAt']),
      );

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

/// One conversation as a participant sees it, mirroring `ChatService.ConversationView`.
class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.orderId,
    required this.yourRole,
    required this.open,
    required this.lastSequence,
    required this.unread,
    this.openedAt,
    this.closesAt,
    this.lastMessageAt,
  });

  final String id;

  /// The order this chat is about. The app holds this long before it holds a conversation id —
  /// the chat button lives on the order screen.
  final String orderId;

  /// Which side the caller is on. The thread is drawn from this.
  final ChatRole yourRole;

  /// Whether the composer should be enabled. A conversation closes a while after delivery.
  final bool open;

  final DateTime? openedAt;

  /// When the composer will lock. Null when the server has not scheduled it yet.
  final DateTime? closesAt;

  /// Null while nobody has said anything.
  final DateTime? lastMessageAt;

  /// The highest sequence stored — the cursor a fresh client fetches after.
  final int lastSequence;

  /// The badge.
  final int unread;

  factory ChatConversation.fromJson(Map<String, dynamic> json) => ChatConversation(
        id: json['id'] as String,
        orderId: json['orderId'] as String? ?? '',
        yourRole: ChatRole.fromWire(json['yourRole'] as String?),
        open: json['open'] as bool? ?? false,
        openedAt: ChatMessage._date(json['openedAt']),
        closesAt: ChatMessage._date(json['closesAt']),
        lastMessageAt: ChatMessage._date(json['lastMessageAt']),
        lastSequence: (json['lastSequence'] as num?)?.toInt() ?? 0,
        unread: (json['unread'] as num?)?.toInt() ?? 0,
      );
}

/// The badge across every conversation, mirroring `ChatService.UnreadSummary`.
class ChatUnreadSummary {
  const ChatUnreadSummary({required this.total, required this.byConversation});

  final int total;

  /// Conversation id to unread count. Conversations with nothing unread are absent, not zero.
  final Map<String, int> byConversation;

  factory ChatUnreadSummary.fromJson(Map<String, dynamic> json) => ChatUnreadSummary(
        total: (json['total'] as num?)?.toInt() ?? 0,
        byConversation: (json['byConversation'] as Map<String, dynamic>? ?? <String, dynamic>{})
            .map((String k, dynamic v) => MapEntry<String, int>(k, (v as num?)?.toInt() ?? 0)),
      );
}

/// One live message as it arrives on the socket, mirroring `ChatDelivery.ChatFrame`.
///
/// The frame is what the *recipient* gets, so it carries no `mine` flag — a frame is by
/// construction somebody else talking. [asMessage] fixes that reading into a [ChatMessage].
class ChatFrame {
  const ChatFrame({
    required this.id,
    required this.conversationId,
    required this.orderId,
    required this.sequence,
    required this.senderRole,
    required this.text,
    this.sentAt,
  });

  final String id;
  final String conversationId;
  final String orderId;
  final int sequence;
  final ChatRole senderRole;
  final String text;
  final DateTime? sentAt;

  /// The frame as a thread row. Never [ChatMessage.mine] — see the class note — and with no
  /// delivery timestamps, because those describe the *other* party's device, not this one.
  ChatMessage asMessage() => ChatMessage(
        id: id,
        sequence: sequence,
        senderRole: senderRole,
        mine: false,
        text: text,
        sentAt: sentAt,
      );

  factory ChatFrame.fromJson(Map<String, dynamic> json) => ChatFrame(
        id: json['id'] as String,
        conversationId: json['conversationId'] as String? ?? '',
        orderId: json['orderId'] as String? ?? '',
        sequence: (json['sequence'] as num?)?.toInt() ?? 0,
        senderRole: ChatRole.fromWire(json['senderRole'] as String?),
        text: json['text'] as String? ?? '',
        sentAt: ChatMessage._date(json['sentAt']),
      );
}
