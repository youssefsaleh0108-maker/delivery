import 'package:dio/dio.dart';

import '../models/chat_models.dart';
import '../network/user_queue_socket.dart';

/// Client for the order chat on App Notification Service.
///
/// Reads and writes go over REST; delivery of the *other* party's messages is live over the same
/// STOMP socket the in-app notifications ride — see [live]. The server refuses client SEND frames
/// on that socket by design, which is why [send] is HTTP: the resource server, the length
/// validation and the membership check all apply there for free.
///
/// No method here takes a user id. Membership is a property of the conversation row and the caller
/// is whoever the token says, so reading or posting to somebody else's thread is unexpressible.
class ChatApi {
  ChatApi(this._dio);

  /// Where chat frames arrive on the shared socket. Clients subscribe under `/user/`; the broker
  /// resolves it per principal, so this names the caller's own queue and nobody else's.
  static const String liveDestination = '/user/queue/chat';

  final Dio _dio;

  /// The other party's messages, live, as typed frames.
  ///
  /// One subscription on the app's single [UserQueueSocket] — the mechanism the notification
  /// socket already uses, extended to chat rather than a second socket stack. The stream goes
  /// quiet while the socket is down and the socket reconnects itself; on every
  /// [UserQueueSocket.connected] false→true edge the screen refetches with [messages] and
  /// `afterSequence`, which is exactly what makes a reconnect cheap and correct.
  static Stream<ChatFrame> live(UserQueueSocket socket) =>
      socket.subscribe(liveDestination).map(ChatFrame.fromJson);

  // ---------------------------------------------------------------- conversations

  /// Every conversation the caller is in, most recently active first, each with its badge.
  Future<List<ChatConversation>> conversations() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/chat/conversations');
    return (response.data as List<dynamic>)
        .map((dynamic e) => ChatConversation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The conversation attached to an order — the id the chat button on the order screen actually
  /// holds. 404 when the caller is not in it, indistinguishable from an order that does not exist.
  ///
  /// There is deliberately no call that *creates* a conversation: one opens when a rider is
  /// assigned, server-side.
  Future<ChatConversation> conversationForOrder(String orderId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/chat/orders/$orderId/conversation');
    return ChatConversation.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- messages

  /// The thread, from a cursor.
  ///
  /// [afterSequence] 0 — the default — fetches from the beginning, which is what a fresh open
  /// does. A client that held 41 messages asks for everything after 41 and gets exactly what it
  /// missed while its socket was down.
  Future<List<ChatMessage>> messages(String conversationId, {int afterSequence = 0}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/chat/conversations/$conversationId/messages',
      queryParameters: <String, dynamic>{'afterSequence': afterSequence},
    );
    return (response.data as List<dynamic>)
        .map((dynamic e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Says something. Returns the stored message, whose sequence is the client's next cursor.
  ///
  /// [clientMessageId] is the sender's own idempotency key: a retry after a lost response does
  /// not post twice. Omitting it opts out of that guarantee.
  ///
  /// 422 when the text is refused, 409 when the conversation has closed, 404 when it is not the
  /// caller's.
  Future<ChatMessage> send(String conversationId, String text, {String? clientMessageId}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/chat/conversations/$conversationId/messages',
      data: <String, dynamic>{
        'text': text,
        if (clientMessageId != null) 'clientMessageId': clientMessageId,
      },
    );
    return ChatMessage.fromJson(response.data as Map<String, dynamic>);
  }

  /// "I have read up to here." A cursor rather than message ids, because it stays correct even
  /// for a frame that arrived which the client never told the server about. Returns how many
  /// messages the receipt covered.
  Future<int> markRead(String conversationId, {required int upToSequence}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/chat/conversations/$conversationId/read',
      data: <String, dynamic>{'upToSequence': upToSequence},
    );
    return (response.data as Map<String, dynamic>)['updated'] as int? ?? 0;
  }

  /// The badge, alone. Polled on every app foreground — whole threads are not.
  Future<ChatUnreadSummary> unreadCount() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/chat/unread-count');
    return ChatUnreadSummary.fromJson(response.data as Map<String, dynamic>);
  }
}
