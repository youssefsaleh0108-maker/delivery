import 'package:dio/dio.dart';

import '../models/notification_models.dart';

/// Client for the Notifications Manager preference API — the settings screen's grid.
///
/// The caller's own settings are addressed as `mine` with no id anywhere, ownership coming from
/// the token. The one method that names somebody is read-only support tooling, BACKOFFICE-gated
/// server-side: an operator can see why a customer got no SMS, and cannot quietly re-enable
/// marketing for somebody who turned it off.
class NotificationPrefsApi {
  NotificationPrefsApi(this._dio);

  final Dio _dio;

  /// The caller's complete grid, defaults filled in — every category on every channel, so the
  /// screen renders rows it never has to invent.
  Future<List<NotificationPreference>> mine() async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/notification-preferences/mine');
    return _grid(response);
  }

  /// Saves only what the user touched, and returns the whole saved grid.
  ///
  /// Partial on purpose: a whole-grid PUT from a second device would silently revert what the
  /// first one changed. Render from the response rather than the optimistic state — a locked
  /// category comes back still on, and that is the truth to show.
  ///
  /// A 400 carries the server's reason when a change is refused — turning off an
  /// account-critical category is refused with words, not accepted and ignored.
  Future<List<NotificationPreference>> update(
      List<NotificationPreferenceChange> changes) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/notification-preferences/mine',
      data: <String, dynamic>{
        'changes': changes.map((NotificationPreferenceChange c) => c.toJson()).toList(),
      },
    );
    return _grid(response);
  }

  /// One user's settings, read-only, for support. BACKOFFICE only.
  Future<List<NotificationPreference>> forRecipient(String recipientId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/notification-preferences/$recipientId');
    return _grid(response);
  }

  static List<NotificationPreference> _grid(Response<dynamic> response) =>
      (response.data as List<dynamic>)
          .map((dynamic e) => NotificationPreference.fromJson(e as Map<String, dynamic>))
          .toList();
}
