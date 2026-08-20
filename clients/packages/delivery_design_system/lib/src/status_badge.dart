import 'package:flutter/material.dart';

import 'tokens.dart';

/// The one place an order status is turned into a colour.
///
/// Appendix A requires the status→colour mapping to stay consistent across Backoffice tables, the
/// Merchant Portal and in-app order tracking. Three separately-built clients will drift if each
/// draws its own badge, so all three use this widget and none of them reach for
/// [DeliveryStatusColor] directly.
class DeliveryStatusBadge extends StatelessWidget {
  const DeliveryStatusBadge({super.key, required this.status, this.label});

  final DeliveryStatusColor status;

  /// Overrides the default label. The colour is not overridable — that is the point.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final Color base = status.color;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DeliverySpacing.sm + DeliverySpacing.xs,
        vertical: DeliverySpacing.xs,
      ),
      decoration: BoxDecoration(
        // A tint of the status colour rather than a solid fill, so a table of badges does not
        // compete with the primary action on the same screen.
        color: base.withValues(alpha: 0.12),
        border: Border.all(color: base.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: base, shape: BoxShape.circle),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Text(
            label ?? status.label,
            style: TextStyle(
              color: base,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
