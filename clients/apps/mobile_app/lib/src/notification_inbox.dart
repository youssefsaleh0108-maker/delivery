import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:flutter/foundation.dart';

/// Holds the in-app inbox and keeps the unread badge current.
///
/// Owned by the shell rather than by the notifications screen, because the badge has to be right
/// on tabs the user is not looking at — a count that only refreshes when you open the inbox is a
/// count nobody trusts.
///
/// **Polling, not WebSocket, in this client.** App Notification Service pushes over STOMP and the
/// endpoint is live; the app uses the REST fallback the brief pairs with it (Section 9). The
/// trade-off is honest: a message can be up to [_pollInterval] late here, against adding a STOMP
/// dependency and a reconnect/backoff state machine to the mobile client. The durable record is the
/// row in Postgres either way, so nothing is ever lost by polling — only delayed. Moving to the
/// socket later changes this class and nothing else.
class NotificationInbox extends ChangeNotifier {
  NotificationInbox(this._api);

  /// Frequent enough that an order update feels immediate, infrequent enough not to drain a phone
  /// battery on a request that answers with one integer.
  static const Duration _pollInterval = Duration(seconds: 15);

  final NotificationApi _api;

  Timer? _timer;
  List<InAppNotification> _messages = const <InAppNotification>[];
  int _unread = 0;
  bool _loading = false;
  Object? _error;

  List<InAppNotification> get messages => _messages;
  int get unread => _unread;
  bool get loading => _loading;
  Object? get error => _error;

  void start() {
    if (_timer != null) return;
    unawaited(refreshCount());
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(refreshCount()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  /// The cheap poll: one integer, no message bodies.
  Future<void> refreshCount() async {
    try {
      final int count = await _api.unreadCount();
      if (count != _unread) {
        _unread = count;
        notifyListeners();
      }
    } catch (_) {
      // Silent. A failed background poll is a stale badge, not something to interrupt the user
      // over — and it will be right again on the next tick.
    }
  }

  /// The full load, on opening the inbox.
  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _messages = await _api.inbox();
      _unread = _messages.where((InAppNotification m) => !m.read).length;
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Marks one read, updating the badge before the server confirms.
  ///
  /// Optimistic because the alternative is a tap that appears to do nothing for a round trip. If
  /// the call fails the state is reverted — read state that silently disagrees with the server
  /// comes back on the next refresh anyway, so it must not be left wrong here.
  Future<void> markRead(InAppNotification message) async {
    if (message.read) return;

    final List<InAppNotification> previous = _messages;
    final int previousUnread = _unread;

    _messages = _messages
        .map((InAppNotification m) =>
            m.id == message.id ? m.copyWith(read: true, readAt: DateTime.now()) : m)
        .toList();
    _unread = (_unread - 1).clamp(0, 1 << 30);
    notifyListeners();

    try {
      await _api.markRead(message.id);
    } catch (_) {
      _messages = previous;
      _unread = previousUnread;
      notifyListeners();
    }
  }

  Future<void> markAllRead() async {
    try {
      await _api.markAllRead();
      _messages = _messages
          .map((InAppNotification m) =>
              m.read ? m : m.copyWith(read: true, readAt: DateTime.now()))
          .toList();
      _unread = 0;
      notifyListeners();
    } catch (_) {
      // Left as-is; the next refresh reconciles.
    }
  }
}
