/// The Backoffice activity feed mirroring `GET /api/orders/activity`.
library;

import 'order_models.dart';

/// What happened, mirroring the feed's `event` strings.
///
/// A coarser vocabulary than [OrderStatus] on purpose: the feed calls out the three moments worth a
/// row of their own and folds every other transition into [statusChanged]. The raw status behind
/// the event travels alongside on [ActivityEntry.status].
enum ActivityEvent {
  placed('placed', 'Placed'),
  delivered('delivered', 'Delivered'),
  cancelled('cancelled', 'Cancelled'),
  statusChanged('status-changed', 'Status changed'),

  /// An event this client does not know yet. Rendered by its wire string, never dropped — a feed
  /// with silently missing rows is worse than one with an unfamiliar label.
  unknown('unknown', 'Activity');

  const ActivityEvent(this.wire, this.label);

  final String wire;
  final String label;

  static ActivityEvent fromWire(String? value) => ActivityEvent.values.firstWhere(
        (ActivityEvent e) => e.wire == value,
        orElse: () => ActivityEvent.unknown,
      );
}

/// One row of the feed.
///
/// Entries are immutable and newest-first; the feed is a poll, not a push — re-request page zero on
/// an interval and new rows only ever prepend.
class ActivityEntry {
  const ActivityEntry({
    required this.occurredAt,
    required this.event,
    required this.eventWire,
    required this.status,
    required this.orderId,
    required this.amount,
    this.storeName,
  });

  final DateTime? occurredAt;

  final ActivityEvent event;

  /// The event exactly as the server spelled it, for rendering [ActivityEvent.unknown].
  final String eventWire;

  /// The raw order status behind the event.
  final OrderStatus status;

  final String orderId;

  /// Null on Butler errands — there is no shop. Render the errand for what it is rather than
  /// leaving a blank where a name should be.
  final String? storeName;

  /// The order's CURRENT total, not the total at the entry's moment — an order discounted after
  /// placement shows its discounted total on its placement row too.
  final double amount;

  factory ActivityEntry.fromJson(Map<String, dynamic> json) => ActivityEntry(
        occurredAt: _time(json['occurredAt']),
        event: ActivityEvent.fromWire(json['event'] as String?),
        eventWire: json['event'] as String? ?? '',
        status: OrderStatus.fromWire(json['status'] as String? ?? 'PLACED'),
        orderId: json['orderId'] as String? ?? '',
        storeName: json['storeName'] as String?,
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
      );

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}
