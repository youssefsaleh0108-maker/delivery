import 'package:dio/dio.dart';

import '../models/neighbourhood_chat_models.dart';

/// The Backoffice moderation queue for neighbourhood rooms.
///
/// BACKOFFICE-only on the server. Every action takes a reason, which the server records with the
/// actor in its audit trail before the action takes effect; staff always act through a reported
/// message and never name an account.
class ChatModerationApi {
  ChatModerationApi(this._dio);

  static const String _base = '/api/chat/backoffice/moderation';

  final Dio _dio;

  /// Reported messages still waiting for a decision, oldest wait first.
  Future<List<ReportedRoomMessage>> queue() async {
    final Response<dynamic> response = await _dio.get<dynamic>('$_base/reports');
    return (response.data as List<dynamic>)
        .map((dynamic e) => ReportedRoomMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Removes the message for every neighbour and closes its reports.
  Future<void> hide(String messageId, {required String reason}) async {
    await _dio.post<dynamic>('$_base/messages/$messageId/hide',
        data: <String, dynamic>{'reason': reason});
  }

  /// Closes the reports and leaves the message.
  Future<void> dismiss(String messageId, {required String reason}) async {
    await _dio.post<dynamic>('$_base/messages/$messageId/dismiss',
        data: <String, dynamic>{'reason': reason});
  }

  /// Mutes the message's author in its room for [hours] (1 to 8760). Returns when it ends.
  Future<DateTime?> muteAuthor(String messageId, {required int hours, required String reason}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '$_base/messages/$messageId/mute-author',
      data: <String, dynamic>{'hours': hours, 'reason': reason},
    );
    final Object? until = (response.data as Map<String, dynamic>?)?['mutedUntil'];
    return until is String ? DateTime.tryParse(until)?.toLocal() : null;
  }

  Future<void> unmuteAuthor(String messageId, {required String reason}) async {
    await _dio.post<dynamic>('$_base/messages/$messageId/unmute-author',
        data: <String, dynamic>{'reason': reason});
  }
}
