import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'notification_inbox.dart';

/// The in-app inbox (Section 7), in the redesign's customer language.
///
/// The design has no notifications frame of its own, so this is built from the parts it does draw:
/// the 56px white header, a 24px list of white radius-16 rows with a 32px icon tile, and the brand
/// tint reserved for the ones still unread.
///
/// These are the same notifications that went out as email, SMS and push — the IN_APP channel is
/// one more row in the notification log, not a separate feature. That is why a message here can be
/// trusted to exist even if the push never arrived: the platform recorded it before it tried to
/// send anything.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.inbox});

  final NotificationInbox inbox;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    widget.inbox.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.inbox,
      builder: (BuildContext context, _) {
        final DeliveryStrings t = DeliveryStrings.of(context);
        final List<InAppNotification> messages = widget.inbox.messages;

        return Scaffold(
          backgroundColor: DeliveryColors.background,
          appBar: YdScreenHeader(
            title: t.notifications,
            onBack: () => Navigator.of(context).maybePop(),
            backSemanticLabel: t.back,
            trailing: widget.inbox.unread == 0
                ? null
                : Semantics(
                    button: true,
                    label: t.markAllRead,
                    child: Tooltip(
                      message: t.markAllRead,
                      child: Material(
                        color: DeliveryColors.brandSoft,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: widget.inbox.markAllRead,
                          child: const SizedBox.square(
                            dimension: 32,
                            child: Icon(Icons.done_all_rounded,
                                size: 16, color: DeliveryColors.brand),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          body: RefreshIndicator(
            color: DeliveryColors.brand,
            onRefresh: widget.inbox.refresh,
            child: _body(context, t, messages),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, DeliveryStrings t, List<InAppNotification> messages) {
    if (widget.inbox.loading && messages.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
    }
    if (widget.inbox.error != null && messages.isEmpty) {
      return _scrollable(YdEmptyState(
        icon: Icons.cloud_off_rounded,
        title: t.couldNotLoadNotifications,
        message: t.pullDownToTryAgain,
      ));
    }
    if (messages.isEmpty) {
      return _scrollable(YdEmptyState(
        icon: Icons.notifications_none_rounded,
        title: t.nothingYet,
        message: t.orderUpdatesHere,
      ));
    }

    return ListView.separated(
      // AlwaysScrollable so pull-to-refresh still works on a list too short to scroll.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(DeliverySpacing.lg),
      itemCount: messages.length,
      separatorBuilder: (_, __) =>
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
      itemBuilder: (BuildContext context, int i) => _row(t, messages[i]),
    );
  }

  /// Keeps pull-to-refresh working over a state with nothing to scroll.
  Widget _scrollable(Widget child) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: <Widget>[
        const SizedBox(height: 80),
        child,
      ],
    );
  }

  Widget _row(DeliveryStrings t, InAppNotification m) {
    // Unread is the state worth seeing at a glance from across the list: the tile fills with the
    // brand tint rather than the page grey, and the title carries the weight.
    final Color tile = m.read ? DeliveryColors.background : DeliveryColors.brandSoft;
    final Color glyph = m.read ? DeliveryColors.muted : DeliveryColors.brand;

    return YdCard(
      onTap: () => widget.inbox.markRead(m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tile,
              borderRadius: BorderRadius.circular(DeliveryRadius.sm),
            ),
            child: Icon(_iconFor(m.eventType), size: 16, color: glyph),
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  m.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: m.read ? FontWeight.w500 : FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  m.body,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DeliveryColors.muted,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: DeliverySpacing.sm),
                Text(
                  _ago(t, m.createdAt),
                  style: const TextStyle(
                    fontSize: 12,
                    color: DeliveryColors.faint,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          if (!m.read) ...<Widget>[
            const SizedBox(width: DeliverySpacing.sm),
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: DeliverySpacing.sm),
              decoration: const BoxDecoration(
                color: DeliveryColors.brand,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Icons come from the event type, which is why the manager sends it as metadata rather than
  /// leaving the client to parse the message text.
  static IconData _iconFor(String eventType) {
    if (eventType.startsWith('order.cancelled')) return Icons.cancel_outlined;
    if (eventType.startsWith('order.delivered')) return Icons.check_circle_outline;
    if (eventType.startsWith('order.rider_assigned')) return Icons.two_wheeler;
    if (eventType.startsWith('order.placed')) return Icons.receipt_long_outlined;
    return Icons.notifications_outlined;
  }
}

/// Takes the strings rather than a BuildContext: this is a top-level function with no element to
/// look them up from, and threading a context through it only to reach the string table would make
/// a pure function pretend to be a widget.
String _ago(DeliveryStrings t, DateTime time) {
  final Duration d = DateTime.now().difference(time);
  if (d.inSeconds < 60) return t.justNow;
  if (d.inMinutes < 60) return t.minutesAgo(d.inMinutes);
  if (d.inHours < 24) return t.hoursAgo(d.inHours);
  return t.daysAgo(d.inDays);
}
