import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'notification_inbox.dart';

/// The in-app inbox (Section 7).
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
        final List<InAppNotification> messages = widget.inbox.messages;

        return Scaffold(
          appBar: AppBar(
            title: Text(DeliveryStrings.of(context).notifications),
            actions: <Widget>[
              if (widget.inbox.unread > 0)
                TextButton(
                  onPressed: widget.inbox.markAllRead,
                  child: Text(DeliveryStrings.of(context).markAllRead),
                ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: widget.inbox.refresh,
            child: _body(context, messages),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, List<InAppNotification> messages) {
    if (widget.inbox.loading && messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.inbox.error != null && messages.isEmpty) {
      return _Empty(
        icon: Icons.cloud_off,
        title: DeliveryStrings.of(context).couldNotLoadNotifications,
        subtitle: DeliveryStrings.of(context).pullDownToTryAgain,
      );
    }
    if (messages.isEmpty) {
      return _Empty(
        icon: Icons.notifications_none,
        title: DeliveryStrings.of(context).nothingYet,
        subtitle: DeliveryStrings.of(context).orderUpdatesHere,
      );
    }

    return ListView.separated(
      // AlwaysScrollable so pull-to-refresh still works on a list too short to scroll.
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: messages.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int i) {
        final InAppNotification m = messages[i];
        return ListTile(
          // A tinted row rather than a bold dot: unread is the state worth seeing at a glance from
          // across the list, not a detail to hunt for.
          tileColor: m.read ? null : DeliveryColors.brandSoft,
          leading: CircleAvatar(
            backgroundColor: m.read ? DeliveryColors.background : DeliveryColors.brand,
            foregroundColor: m.read ? DeliveryColors.muted : DeliveryColors.white,
            child: Icon(_iconFor(m.eventType), size: 20),
          ),
          title: Text(
            m.title,
            style: TextStyle(fontWeight: m.read ? FontWeight.w400 : FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(m.body),
              const SizedBox(height: DeliverySpacing.xs),
              Text(
                _ago(DeliveryStrings.of(context), m.createdAt),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: DeliveryColors.muted),
              ),
            ],
          ),
          isThreeLine: true,
          onTap: () => widget.inbox.markRead(m),
        );
      },
    );
  }

  /// Icons come from the event type, which is why the manager sends it as metadata rather than
  /// leaving the client to parse the message text.
  static IconData _iconFor(String eventType) {
    if (eventType.startsWith('order.cancelled')) return Icons.cancel_outlined;
    if (eventType.startsWith('order.delivered')) return Icons.check_circle_outline;
    if (eventType.startsWith('order.rider_assigned')) return Icons.pedal_bike;
    if (eventType.startsWith('order.placed')) return Icons.receipt_long_outlined;
    return Icons.notifications_outlined;
  }
}

class _Empty extends StatelessWidget {
  // Still a const constructor even though the call sites can no longer be const: the strings they
  // pass are looked up at runtime, but that is the caller's constraint, not this widget's.
  const _Empty({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    // A ListView so pull-to-refresh still works when there is nothing to scroll.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: <Widget>[
        const SizedBox(height: 120),
        Icon(icon, size: 48, color: DeliveryColors.muted),
        const SizedBox(height: DeliverySpacing.md),
        Center(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        const SizedBox(height: DeliverySpacing.xs),
        Center(
          child: Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: DeliveryColors.muted),
          ),
        ),
      ],
    );
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
