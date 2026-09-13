import 'package:dio/dio.dart';

import '../models/neighbourhood_chat_models.dart';
import '../network/user_queue_socket.dart';

/// Client for neighbourhood rooms on App Notification Service.
///
/// Like [ChatApi], no method takes a user id or a room to join. The only thing the app says about
/// where it belongs is the delivery area of its address ([myRoom]); the server places the caller and
/// checks that membership on every read, post, report and live subscription.
///
/// Refusals the screen acts on arrive as typed exceptions — [NoNeighbourhoodException] (choose an
/// area), [RoomMutedException] (explain the pause), [ChatRateLimitedException] (slow down) — rather
/// than as status codes each screen would have to decode the same way.
class NeighbourhoodChatApi {
  NeighbourhoodChatApi(this._dio);

  /// A room's live feed is `/user/queue/chat.rooms.{roomId}`. Under `/user/`, so the broker resolves
  /// it per session, and the socket's interceptor refuses it to anyone not in the room.
  static const String liveDestinationPrefix = '/user/queue/chat.rooms.';

  final Dio _dio;

  /// Messages and removals in [roomId], live. A removal arrives as the same message with
  /// [RoomMessage.isHidden] set, so a screen replaces by id. Blocked authors never arrive: the server
  /// leaves the blocker's socket out.
  static Stream<RoomMessage> live(UserQueueSocket socket, String roomId) =>
      socket.subscribe('$liveDestinationPrefix$roomId').map(RoomMessage.fromJson);

  /// The caller's room, from the area of their selected delivery address.
  ///
  /// Throws [NoNeighbourhoodException] when the address names no area (and the caller is in no room
  /// yet) or names one the platform does not offer.
  Future<NeighbourhoodRoom> myRoom({String? zoneId}) async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        '/api/chat/rooms/mine',
        queryParameters: <String, dynamic>{if (zoneId != null && zoneId.isNotEmpty) 'zoneId': zoneId},
      );
      return NeighbourhoodRoom.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      final Object? body = e.response?.data;
      if (e.response?.statusCode == 404 && body is Map) {
        switch (body['reason']) {
          case 'NO_ZONE':
            throw const NoNeighbourhoodException(NoNeighbourhoodReason.noZone);
          case 'UNKNOWN_ZONE':
            throw const NoNeighbourhoodException(NoNeighbourhoodReason.unknownZone);
        }
      }
      rethrow;
    }
  }

  /// History, oldest first within the page. With no cursor: the newest page. [beforeSequence]: the
  /// page before it, for scrolling up. [afterSequence]: what was missed, for a reconnect.
  Future<RoomHistoryPage> messages(String roomId, {int? beforeSequence, int? afterSequence}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/chat/rooms/$roomId/messages',
      queryParameters: <String, dynamic>{
        if (beforeSequence != null) 'beforeSequence': beforeSequence,
        if (afterSequence != null) 'afterSequence': afterSequence,
      },
    );
    return RoomHistoryPage.fromJson(response.data as Map<String, dynamic>);
  }

  /// Says something. [clientMessageId] makes a retry after a lost response post once.
  Future<RoomMessage> send(String roomId, String text, {String? clientMessageId}) async {
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        '/api/chat/rooms/$roomId/messages',
        data: <String, dynamic>{
          'text': text,
          if (clientMessageId != null) 'clientMessageId': clientMessageId,
        },
      );
      return RoomMessage.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      final Exception? refusal = refusalOf(e);
      if (refusal != null) throw refusal;
      rethrow;
    }
  }

  /// Flags a message for a moderator. Reporting twice is one report.
  Future<void> report(String messageId, RoomReportReason reason) async {
    await _dio.post<dynamic>(
      '/api/chat/rooms/messages/$messageId/report',
      data: <String, dynamic>{'reason': reason.wire},
    );
  }

  /// Stops the caller seeing the author of [messageId], in every room.
  Future<BlockedNeighbour> blockAuthor(String messageId) async {
    final Response<dynamic> response =
        await _dio.post<dynamic>('/api/chat/rooms/messages/$messageId/block-author');
    return BlockedNeighbour.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<BlockedNeighbour>> blocks() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/chat/rooms/blocks');
    return (response.data as List<dynamic>)
        .map((dynamic e) => BlockedNeighbour.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> unblock(String blockId) async {
    await _dio.delete<dynamic>('/api/chat/rooms/blocks/$blockId');
  }

  /// The refusals a chat post can meet that deserve a sentence rather than a generic failure: a
  /// mute (403 carrying `mutedUntil`) and a rate limit (429 with Retry-After). Anything else is left
  /// to the caller as the original [DioException].
  static Exception? refusalOf(DioException e) {
    final Response<dynamic>? response = e.response;
    if (response == null) return null;
    final Object? body = response.data;

    if (response.statusCode == 429) {
      final int? fromHeader = int.tryParse(response.headers.value('retry-after') ?? '');
      final int? fromBody = body is Map ? (body['retryAfterSeconds'] as num?)?.toInt() : null;
      return ChatRateLimitedException(Duration(seconds: fromHeader ?? fromBody ?? 60));
    }
    if (response.statusCode == 403 && body is Map && body.containsKey('mutedUntil')) {
      return RoomMutedException(_date(body['mutedUntil']));
    }
    return null;
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}
