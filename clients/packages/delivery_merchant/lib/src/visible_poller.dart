import 'dart:async';

import 'package:flutter/widgets.dart';

/// Runs [onTick] every [every] while the app is on screen, and not at all while it is hidden.
///
/// A merchant's customer messages have no live feed on the web — the portal holds no socket — so
/// the inbox, an open conversation and the unread count there stay current by asking again. Three
/// places ask, and the rule that makes asking acceptable belongs in one: no requests from a browser
/// tab nobody is looking at, or from a phone in somebody's pocket. Coming back to the app asks once
/// straight away, so what arrived meanwhile shows at once rather than a whole interval later.
///
/// A tick still running when the next falls due is not doubled up. A failing [onTick] is the
/// caller's to report; the poller only keeps asking.
class VisiblePoller {
  VisiblePoller({required this.every, required this.onTick});

  final Duration every;
  final Future<void> Function() onTick;

  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  bool _hidden = false;
  bool _paused = false;
  bool _ticking = false;
  bool _disposed = false;

  /// Starts the interval. The caller makes its own first load, so no tick is made here.
  void start() {
    if (_lifecycle != null || _disposed) return;
    _hidden = !_showing(WidgetsBinding.instance.lifecycleState);
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    _schedule();
  }

  bool get paused => _paused;

  /// Stops asking while something covers the page — a conversation pushed over the inbox — and asks
  /// once when it is uncovered.
  set paused(bool value) {
    if (_paused == value) return;
    _paused = value;
    _changed();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  /// Inactive still counts as showing: a desktop browser window that lost focus to another is on
  /// screen all the same, and a shop may well keep the portal open on a second monitor.
  static bool _showing(AppLifecycleState? state) =>
      state == null || state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;

  bool get _active => !_hidden && !_paused && !_disposed;

  void _onLifecycle(AppLifecycleState state) {
    final bool hidden = !_showing(state);
    if (hidden == _hidden) return;
    _hidden = hidden;
    _changed();
  }

  /// Hidden or covered: stop. Showing again: ask now, then keep to the interval.
  void _changed() {
    if (_active) unawaited(_tick());
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!_active) return;
    _timer = Timer.periodic(every, (_) => unawaited(_tick()));
  }

  Future<void> _tick() async {
    if (_ticking || !_active) return;
    _ticking = true;
    try {
      await onTick();
    } catch (_) {
      // The caller says what a failure means; the poller only keeps asking.
    } finally {
      _ticking = false;
    }
  }
}
