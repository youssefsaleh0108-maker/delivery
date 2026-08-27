import 'package:delivery_core/delivery_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatMessage states', () {
    Map<String, dynamic> message({String? deliveredAt, String? readAt}) => <String, dynamic>{
          'id': 'm-1',
          'sequence': 7,
          'senderRole': 'CUSTOMER',
          'mine': true,
          'text': 'On my way down',
          'sentAt': '2026-08-27T10:00:00Z',
          'deliveredAt': deliveredAt,
          'readAt': readAt,
        };

    test('no timestamps is sent', () {
      expect(ChatMessage.fromJson(message()).state, ChatMessageState.sent);
    });

    test('a delivery timestamp is delivered', () {
      expect(
        ChatMessage.fromJson(message(deliveredAt: '2026-08-27T10:00:01Z')).state,
        ChatMessageState.delivered,
      );
    });

    test('a read timestamp is read, even without a delivery one', () {
      // markRead is a cursor: a message can be read past without its delivery flag having caught
      // up. Read wins — it is the stronger fact.
      expect(
        ChatMessage.fromJson(message(readAt: '2026-08-27T10:00:05Z')).state,
        ChatMessageState.read,
      );
    });

    test('an unknown sender role survives parsing', () {
      final ChatMessage parsed = ChatMessage.fromJson(<String, dynamic>{
        'id': 'm-2',
        'sequence': 8,
        'senderRole': 'MEDIATOR',
        'mine': false,
        'text': 'hello',
      });
      expect(parsed.senderRole, ChatRole.unknown);
    });
  });

  group('ChatFrame', () {
    test('round-trips into a thread row that is never mine', () {
      final ChatFrame frame = ChatFrame.fromJson(<String, dynamic>{
        'id': 'm-3',
        'conversationId': 'c-1',
        'orderId': 'o-1',
        'sequence': 12,
        'senderRole': 'RIDER',
        'text': 'At the door',
        'sentAt': '2026-08-27T10:01:00Z',
      });

      final ChatMessage row = frame.asMessage();
      expect(row.mine, isFalse);
      expect(row.sequence, 12);
      expect(row.senderRole, ChatRole.rider);
      expect(row.text, 'At the door');
      // Delivery timestamps describe the other party's device; a frame knows nothing about them.
      expect(row.deliveredAt, isNull);
      expect(row.readAt, isNull);
      expect(row.state, ChatMessageState.sent);
    });
  });

  group('ChatConversation', () {
    test('parses the composer state and the cursor', () {
      final ChatConversation conversation = ChatConversation.fromJson(<String, dynamic>{
        'id': 'c-1',
        'orderId': 'o-1',
        'yourRole': 'CUSTOMER',
        'open': true,
        'openedAt': '2026-08-27T09:00:00Z',
        'closesAt': null,
        'lastMessageAt': '2026-08-27T10:01:00Z',
        'lastSequence': 12,
        'unread': 3,
      });

      expect(conversation.yourRole, ChatRole.customer);
      expect(conversation.open, isTrue);
      expect(conversation.lastSequence, 12);
      expect(conversation.unread, 3);
      expect(conversation.closesAt, isNull);
    });
  });

  group('ChatUnreadSummary', () {
    test('conversations with nothing unread are absent, not zero', () {
      final ChatUnreadSummary summary = ChatUnreadSummary.fromJson(<String, dynamic>{
        'total': 4,
        'byConversation': <String, dynamic>{'c-1': 3, 'c-2': 1},
      });

      expect(summary.total, 4);
      expect(summary.byConversation['c-1'], 3);
      expect(summary.byConversation.containsKey('c-3'), isFalse);
    });
  });
}
