import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

import 'console_chrome.dart';

/// The console's notification bell — the real one.
///
/// Every console frame draws a bell in the page header (Figma `header` 3:2529 / 3:3462) and every
/// screen used to render it greyed with a "coming soon" chip beside it. The App Notification
/// service has carried the inbox all along, so this is that control wired to it: a badge with the
/// unread count, and a panel listing what is actually there.
///
/// **The endpoint is `GET /api/notifications`, not `/api/notifications/mine`.**
/// `InAppNotificationController` (app-notification) mounts the inbox on the bare collection path and
/// the badge on `/unread-count`; there is no `/mine` segment anywhere in it. Every one of those
/// endpoints is scoped server-side to the caller's own token subject — there is no path or query
/// parameter naming a user — which is why this widget takes no id and cannot be pointed at somebody
/// else's inbox.
///
/// Geometry is [ConsoleIconAction]'s to the pixel (36px box, [ConsoleSurface.control], a 16px
/// glyph), because it replaces one in the same slot on five screens. What it adds is the count
/// badge, which the design draws as a dot and which is worth a number here: an operator deciding
/// whether to stop what they are doing wants "3", not "some".
///
/// A null [api] renders the same box greyed, exactly as the dead control did. That is the path the
/// widget tests take, and it is also what a portal build that never wired the API would show —
/// a control that plainly does nothing, rather than one that silently swallows a poll.
class ConsoleBell extends StatefulWidget {
  const ConsoleBell({
    super.key,
    required this.api,
    this.pollInterval = const Duration(seconds: 45),
    this.pageSize = 20,
  });

  /// Null when the portal was built without a notification client — see the class note.
  final NotificationApi? api;

  /// Slower than any table's poll on purpose: this is one small request whose answer changes on
  /// human timescales, and it runs on every console screen at once.
  final Duration pollInterval;

  /// How much of the inbox the panel loads. The service caps `limit` at 100; twenty is the panel,
  /// not the archive.
  final int pageSize;

  @override
  State<ConsoleBell> createState() => _ConsoleBellState();
}

class _ConsoleBellState extends State<ConsoleBell> {
  final MenuController _menu = MenuController();

  Timer? _poll;

  /// The badge number. Only drawn while [_countKnown] — a bell that cannot reach the service shows
  /// no badge rather than a stale or invented one.
  int _unread = 0;
  bool _countKnown = false;

  List<InAppNotification>? _items;
  bool _loading = false;
  Object? _listError;

  /// Which of the loaded messages were unread when the panel opened.
  ///
  /// Kept separately from [InAppNotification.read] because opening the panel marks them read
  /// immediately: without this the dots would vanish under the reader's eyes in the same frame that
  /// showed them, which is precisely the information they came for.
  Set<String> _wasUnread = <String>{};

  /// A one-line failure from an action inside the panel — marking read, mostly. Distinct from
  /// [_listError], which replaces the whole list.
  String? _notice;

  @override
  void initState() {
    super.initState();
    if (widget.api == null) return;
    _refreshCount();
    _poll = Timer.periodic(widget.pollInterval, (_) => _refreshCount());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------ the badge

  Future<void> _refreshCount() async {
    final NotificationApi? api = widget.api;
    if (api == null) return;
    try {
      final int unread = await api.unreadCount();
      if (!mounted) return;
      setState(() {
        _unread = unread;
        _countKnown = true;
      });
    } catch (_) {
      // The service did not answer. Drop the badge rather than keep showing the last number it
      // gave — a count that stopped being true is worse than no count.
      if (!mounted) return;
      setState(() => _countKnown = false);
    }
  }

  // ------------------------------------------------------------------- the panel

  Future<void> _load() async {
    final NotificationApi? api = widget.api;
    if (api == null) return;

    setState(() {
      _loading = true;
      _listError = null;
      _notice = null;
    });

    final List<InAppNotification> items;
    try {
      items = await api.inbox(limit: widget.pageSize);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _listError = e;
        _loading = false;
      });
      return;
    }
    if (!mounted) return;

    final Set<String> unread = items
        .where((InAppNotification n) => !n.read)
        .map((InAppNotification n) => n.id)
        .toSet();

    setState(() {
      _items = items;
      _wasUnread = unread;
      _loading = false;
    });

    if (unread.isNotEmpty) await _markShownRead(unread);
  }

  /// Marks read exactly the messages the panel just put on screen.
  ///
  /// One `POST /{id}/read` each rather than the single `read-all`: the inbox loads twenty and the
  /// badge may count more than that, and clearing messages the operator was never shown would be
  /// this widget deciding they had been read. The badge drops by what actually succeeded, so a
  /// partial failure leaves a true remainder rather than a zero.
  Future<void> _markShownRead(Set<String> ids) async {
    final NotificationApi api = widget.api!;
    int done = 0;
    await Future.wait(ids.map((String id) async {
      try {
        await api.markRead(id);
        done++;
      } catch (_) {
        // Swallowed per message: one 404 (already read elsewhere, or gone) must not stop the rest.
      }
    }));
    if (!mounted) return;
    setState(() {
      _unread = _unread - done < 0 ? 0 : _unread - done;
      _items = _items
          ?.map((InAppNotification n) => ids.contains(n.id) ? n.copyWith(read: true) : n)
          .toList();
      if (done < ids.length) _notice = 'Some messages could not be marked read.';
    });
  }

  Future<void> _markAllRead() async {
    final NotificationApi? api = widget.api;
    if (api == null) return;
    try {
      await api.markAllRead();
    } catch (_) {
      if (!mounted) return;
      setState(() => _notice = 'That did not go through. Try again.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _unread = 0;
      _countKnown = true;
      _wasUnread = <String>{};
      _items = _items
          ?.map((InAppNotification n) => n.read ? n : n.copyWith(read: true))
          .toList();
      _notice = null;
    });
  }

  // -------------------------------------------------------------------- building

  @override
  Widget build(BuildContext context) {
    final bool live = widget.api != null;
    final bool showBadge = live && _countKnown && _unread > 0;

    final String tooltip = !live
        ? 'Notifications unavailable'
        : showBadge
            ? '$_unread unread notification${_unread == 1 ? '' : 's'}'
            : 'Notifications';

    return MenuAnchor(
      controller: _menu,
      // Under the bell, with the design's 4px breath — the same offset [ConsoleSelect] opens on.
      alignmentOffset: const Offset(0, DeliverySpacing.xs),
      onOpen: _load,
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll<Color>(DeliveryColors.white),
        surfaceTintColor: const WidgetStatePropertyAll<Color>(DeliveryColors.white),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(EdgeInsets.zero),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DeliveryRadius.lg),
            side: const BorderSide(color: DeliveryColors.border),
          ),
        ),
      ),
      menuChildren: <Widget>[
        SizedBox(width: _panelWidth, child: _panel()),
      ],
      builder: (BuildContext context, MenuController controller, Widget? _) {
        return Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: live
                ? () => controller.isOpen ? controller.close() : controller.open()
                : null,
            borderRadius: BorderRadius.circular(DeliveryRadius.sm),
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Container(
                  width: ConsoleMetrics.iconActionSize,
                  height: ConsoleMetrics.iconActionSize,
                  alignment: Alignment.center,
                  decoration: ConsoleSurface.control,
                  child: Icon(
                    Icons.notifications_none,
                    size: 16,
                    color: live ? DeliveryColors.muted : DeliveryColors.faint,
                  ),
                ),
                if (showBadge)
                  PositionedDirectional(
                    top: -4,
                    end: -4,
                    child: _CountBadge(count: _unread),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 360, not the activity card's 380: this hangs off a control at the right edge of the header and
  /// has to stay inside a 1024 window with the rail already taking 260 of it.
  static const double _panelWidth = 360;

  Widget _panel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ConsoleMetrics.cellPaddingX - DeliverySpacing.sm,
            DeliverySpacing.md - 2,
            ConsoleMetrics.cellPaddingX - DeliverySpacing.sm,
            DeliverySpacing.md - 2,
          ),
          child: Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Notifications',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                  ),
                ),
              ),
              if (_countKnown && _unread > 0)
                _PanelAction(label: 'Mark all as read', onPressed: _markAllRead),
            ],
          ),
        ),
        const Divider(height: 1, color: DeliveryColors.border),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ConsoleMetrics.cellPaddingX - DeliverySpacing.sm,
            vertical: DeliverySpacing.md - 2,
          ),
          child: _body(),
        ),
        if (_notice != null) ...<Widget>[
          const Divider(height: 1, color: DeliveryColors.border),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ConsoleMetrics.cellPaddingX - DeliverySpacing.sm,
              vertical: DeliverySpacing.sm,
            ),
            child: Text(_notice!, style: ConsoleText.meta),
          ),
        ],
      ],
    );
  }

  Widget _body() {
    if (_loading && _items == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: DeliverySpacing.lg),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.brand),
          ),
        ),
      );
    }

    if (_listError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('Could not load notifications.', style: ConsoleText.body),
          const SizedBox(height: DeliverySpacing.xs),
          Text('$_listError', style: ConsoleText.meta),
          const SizedBox(height: DeliverySpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _PanelAction(label: 'Try again', onPressed: _load),
          ),
        ],
      );
    }

    final List<InAppNotification> items = _items ?? const <InAppNotification>[];
    if (items.isEmpty) {
      return const Text(
        'Nothing has come in yet.',
        style: ConsoleText.body,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          _BellRow(
            message: items[i],
            wasUnread: _wasUnread.contains(items[i].id),
          ),
        ],
      ],
    );
  }
}

/// The unread count over the bell's corner.
///
/// Capped at "99+" so a neglected inbox cannot widen the header. A count of zero never reaches
/// here — the badge is not drawn at all, rather than drawn as a zero.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final String label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DeliveryColors.brand,
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
        border: Border.all(color: DeliveryColors.white, width: 1.5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          height: 1,
          fontWeight: FontWeight.w700,
          color: DeliveryColors.white,
        ),
      ),
    );
  }
}

/// One message: the unread mark, the title, the body, and when it arrived.
class _BellRow extends StatelessWidget {
  const _BellRow({required this.message, required this.wasUnread});

  final InAppNotification message;
  final bool wasUnread;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Always occupies its 8px, read or unread, so a mixed list keeps one text margin.
        Container(
          margin: const EdgeInsets.only(top: 5),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: wasUnread ? DeliveryColors.brand : Colors.transparent,
            borderRadius: BorderRadius.circular(DeliverySpacing.xs),
          ),
        ),
        const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                message.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: wasUnread ? FontWeight.w600 : FontWeight.w500,
                  color: DeliveryColors.ink,
                ),
              ),
              if (message.body.isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  message.body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.4),
                ),
              ],
              const SizedBox(height: 2),
              Text(consoleAgo(message.createdAt), style: ConsoleText.meta),
            ],
          ),
        ),
      ],
    );
  }
}

/// The panel's small text button. Not [ConsoleButton]: this sits on a 36px header row and the
/// console button's padding would make that row 44.
class _PanelAction extends StatelessWidget {
  const _PanelAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.xs, vertical: 2),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: DeliveryColors.brand,
          ),
        ),
      ),
    );
  }
}

/// Relative time in the console's words — "Just now", "4 mins ago", "Yesterday".
///
/// Lives here rather than in each screen because the bell, the activity feed and the roster all
/// spell it the same way and three copies had already started to drift.
String consoleAgo(DateTime at) {
  final Duration d = DateTime.now().difference(at);
  if (d.isNegative) return 'Just now';
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min${d.inMinutes == 1 ? '' : 's'} ago';
  if (d.inHours < 24) return '${d.inHours} hour${d.inHours == 1 ? '' : 's'} ago';
  if (d.inDays == 1) return 'Yesterday';
  return '${d.inDays} days ago';
}
