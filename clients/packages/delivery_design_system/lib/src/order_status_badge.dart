import 'package:flutter/material.dart';

import 'status_badge.dart';
import 'tokens.dart';

/// Maps an order status to the platform's semantic colour, in one place.
///
/// Appendix A requires the status→colour mapping to be identical across the Backoffice tables, the
/// Merchant Portal and in-app tracking. All three call this rather than choosing a colour locally,
/// which is what stops "preparing" being amber in one app and grey in another.
class OrderStatusBadge extends StatelessWidget {
  const OrderStatusBadge({super.key, required this.statusWire, this.label});

  /// The wire value, e.g. `PREPARING`. Taking the raw string keeps this widget usable from any app
  /// without the design system depending on the API models.
  final String statusWire;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final (DeliveryStatusColor color, String text) = _map(statusWire);
    return DeliveryStatusBadge(status: color, label: label ?? text);
  }

  static (DeliveryStatusColor, String) _map(String wire) => switch (wire) {
        // Appendix A: placed = blue-gray, preparing = amber, in-transit = brand red,
        // delivered = green, inactive = neutral gray.
        'PLACED' => (DeliveryStatusColor.placed, 'Placed'),
        'ACCEPTED' => (DeliveryStatusColor.placed, 'Accepted'),
        'PREPARING' => (DeliveryStatusColor.preparing, 'Preparing'),
        'READY' => (DeliveryStatusColor.preparing, 'Ready'),
        'PICKED_UP' => (DeliveryStatusColor.inTransit, 'On the way'),
        'DELIVERED' => (DeliveryStatusColor.delivered, 'Delivered'),
        // Cancelled is neutral rather than red: red is the brand colour and reads as "active" in
        // this palette, which is the opposite of what a cancelled order means.
        'CANCELLED' => (DeliveryStatusColor.offline, 'Cancelled'),
        _ => (DeliveryStatusColor.offline, wire),
      };

  /// The accent colour for this status, for callers that need it outside a badge.
  static Color colorFor(String wire) => _map(wire).$1.color;
}
