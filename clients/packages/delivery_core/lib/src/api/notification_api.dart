import 'package:dio/dio.dart';

import '../models/notification_models.dart';

/// Client for the App Notification Service (Phase 3).
///
/// Every call is scoped server-side to the caller's token subject, so nothing here takes a user id.
class NotificationApi {
  NotificationApi(this._dio);

  final Dio _dio;

  Future<List<InAppNotification>> inbox({int limit = 50}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/notifications',
      queryParameters: <String, dynamic>{'limit': limit},
    );
    return (response.data as List<dynamic>)
        .map((dynamic e) => InAppNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Just the badge number.
  ///
  /// Separate from [inbox] because it is polled far more often — on every app foreground and on a
  /// timer — and pulling fifty message bodies to render a number would be most of the traffic
  /// between the app and this service.
  Future<int> unreadCount() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/notifications/unread-count');
    return (response.data as Map<String, dynamic>)['unread'] as int? ?? 0;
  }

  Future<void> markRead(String id) => _dio.post<dynamic>('/api/notifications/$id/read');

  Future<int> markAllRead() async {
    final Response<dynamic> response = await _dio.post<dynamic>('/api/notifications/read-all');
    return (response.data as Map<String, dynamic>)['updated'] as int? ?? 0;
  }
}
