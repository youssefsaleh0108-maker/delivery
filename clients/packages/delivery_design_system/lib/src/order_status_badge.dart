import 'package:flutter/material.dart';

import 'status_badge.dart';
import 'tokens.dart';

/// Maps an order status to the platform's semantic colour, in one place.
///
/// Appendix A requires the status→colour mapping to be identical across the Backoffice tables, the
/// Merchant Portal and in-app tracking. All three call this rather than choosing a colour locally,
/// which is what stops "preparing" being amber in one app and grey in another.
class OrderStatusBadge extends StatelessWidget {
  const OrderStatusBadge({super.key, required this.statusWire, required this.label});

  /// The wire value, e.g. `PREPARING`. Taking the raw string keeps this widget usable from any app
  /// without the design system depending on the API models.
  final String statusWire;

  /// Already localised by the caller — `OrderStatus.labelIn(DeliveryStrings)` in `delivery_core`.
  /// This widget used to fall back to an English word per wire value, which is a fallback that only
  /// ever fires in the app that forgot to translate.
  final String label;

  @override
  Widget build(BuildContext context) {
    return DeliveryStatusBadge(status: _map(statusWire), label: label);
  }

  static DeliveryStatusColor _map(String wire) => switch (wire) {
        // Appendix A: placed = blue-gray, preparing = amber, in-transit = brand red,
        // delivered = green, inactive = neutral gray.
        'PLACED' || 'ACCEPTED' => DeliveryStatusColor.placed,
        'PREPARING' || 'READY' => DeliveryStatusColor.preparing,
        'PICKED_UP' => DeliveryStatusColor.inTransit,
        'DELIVERED' => DeliveryStatusColor.delivered,
        // Cancelled is neutral rather than red: red is the brand colour and reads as "active" in
        // this palette, which is the opposite of what a cancelled order means.
        'CANCELLED' => DeliveryStatusColor.offline,
        _ => DeliveryStatusColor.offline,
      };

  /// The accent colour for this status, for callers that need it outside a badge.
  static Color colorFor(String wire) => _map(wire).color;
}
