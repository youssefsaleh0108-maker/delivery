import 'package:dio/dio.dart';

import '../models/shop_chat_models.dart';
import '../network/user_queue_socket.dart';
import 'neighbourhood_chat_api.dart';

/// Client for conversations between customers and shops on App Notification Service.
///
/// A customer opens a thread with a shop ([openWithStore]); the shop's merchant answers it from
/// [inbox]. Which side the caller is on is decided by the server from the token — the customer who
/// opened the thread, or a merchant Product Service confirms owns the shop — so nothing here names a
/// side, a merchant or a customer.
class ShopChatApi {
  ShopChatApi(this._dio);

  /// Where the other side's messages arrive, for customers and merchants alike.
  static const String liveDestination = '/user/queue/chat.shops';

  final Dio _dio;

  static Stream<ShopMessage> live(UserQueueSocket socket) =>
      socket.subscribe(liveDestination).map(ShopMessage.fromJson);

  /// The caller's conversation with a shop, opened if it is not already. Safe to call on every tap:
  /// the same shop gives the same thread, and opening restarts its quiet-period clock.
  Future<ShopThread> openWithStore(String storeId) async {
    final Response<dynamic> response = await _dio.post<dynamic>('/api/chat/stores/$storeId/thread');
    return ShopThread.fromJson(response.data as Map<String, dynamic>);
  }

  /// The calling merchant's conversations, for the shops they own, newest first.
  Future<List<ShopThread>> inbox() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/chat/shop-threads/inbox');
    return (response.data as List<dynamic>)
        .map((dynamic e) => ShopThread.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ShopThreadPage> messages(String threadId, {int afterSequence = 0}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/chat/shop-threads/$threadId/messages',
      queryParameters: <String, dynamic>{'afterSequence': afterSequence},
    );
    return ShopThreadPage.fromJson(response.data as Map<String, dynamic>);
  }

  /// Says something. A quiet thread arrives as [ShopThreadQuietException], a rate limit as
  /// [ChatRateLimitedException].
  Future<ShopMessage> send(String threadId, String text, {String? clientMessageId}) async {
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        '/api/chat/shop-threads/$threadId/messages',
        data: <String, dynamic>{
          'text': text,
          if (clientMessageId != null) 'clientMessageId': clientMessageId,
        },
      );
      return ShopMessage.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      final Object? body = e.response?.data;
      if (e.response?.statusCode == 409) {
        final Object? closedAt = body is Map ? body['closedAt'] : null;
        throw ShopThreadQuietException(
            closedAt is String ? DateTime.tryParse(closedAt)?.toLocal() : null);
      }
      final Exception? refusal = NeighbourhoodChatApi.refusalOf(e);
      if (refusal != null) throw refusal;
      rethrow;
    }
  }

  /// "Our side has read what the other side said, up to here."
  Future<int> markRead(String threadId, {required int upToSequence}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/chat/shop-threads/$threadId/read',
      data: <String, dynamic>{'upToSequence': upToSequence},
    );
    return (response.data as Map<String, dynamic>)['updated'] as int? ?? 0;
  }
}
