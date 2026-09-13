import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:flutter/foundation.dart';

import 'visible_poller.dart';

/// How many of their customers' messages the signed-in merchant has not read, across every shop they
/// own — the number on the ways into [ShopInboxScreen]: the Settings row on the phone, the rail on
/// the web.
///
/// The sum of the inbox's own unread counts, so the badge and the inbox cannot disagree about what
/// "unread" means. Null until the first answer; a failed read keeps the last number rather than
/// showing a zero the platform does not have.
///
/// There is no push for these messages, so the number is kept current three ways: a live frame on
/// [socket] when the host has one, [refresh] when the host knows it just changed (the inbox was
/// closed), and a gentle poll while the app is on screen. The poll does a second job: each inbox read
/// renews the platform's short-lived record that this merchant owns the shop, and that record is what
/// lets a customer's next message reach them live at all.
class ShopUnreadCount extends ValueNotifier<int?> {
  ShopUnreadCount({required this.api, this.socket, Duration every = defaultInterval}) : super(null) {
    _poller = VisiblePoller(every: every, onTick: refresh);
  }

  /// Once a minute: a number on a menu row, not a conversation anybody is waiting on — and well
  /// inside the ten minutes the server trusts a shop's owner before it stops pushing to them.
  static const Duration defaultInterval = Duration(minutes: 1);

  final ShopChatApi api;
  final UserQueueSocket? socket;

  late final VisiblePoller _poller;
  StreamSubscription<ShopMessage>? _live;
  bool _disposed = false;

  /// Asks now, then keeps the number current until [dispose].
  void start() {
    unawaited(refresh());
    _poller.start();
    final UserQueueSocket? socket = this.socket;
    if (socket != null) {
      _live = ShopChatApi.live(socket).listen((_) => unawaited(refresh()));
    }
  }

  Future<void> refresh() async {
    try {
      final List<ShopThread> threads = await api.inbox();
      if (_disposed) return;
      value = threads.fold<int>(0, (int sum, ShopThread thread) => sum + thread.unread);
    } catch (_) {
      // Keep the last number: a failed read is not "nothing unread".
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _poller.dispose();
    unawaited(_live?.cancel());
    super.dispose();
  }
}
