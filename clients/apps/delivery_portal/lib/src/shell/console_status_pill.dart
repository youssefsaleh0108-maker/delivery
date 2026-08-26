import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

/// The console's status badge: a tinted rounded rectangle with the status word in its own colour.
///
/// Figma `status-badge` (3:2750 and siblings): radius 12, 10 across and 4 down, Rubik SemiBold 12.
/// Flatter than the mobile [DeliveryStatusBadge] — no leading dot and no border — because a table
/// of forty rows wants the badge to read as a label, not as forty small buttons.
///
/// The colour is never chosen here. It comes from [DeliveryAccent] or, for anything on an order's
/// lifecycle, from [DeliveryStatusColor] via [ConsoleStatusPill.status] — which is the whole point
/// of those enums: "delivered" has to be the same green in the Backoffice table, the Carrier job
/// board and the customer's tracking screen.
class ConsoleStatusPill extends StatelessWidget {
  const ConsoleStatusPill({
    super.key,
    required this.label,
    this.accent = DeliveryAccent.neutral,
  })  : _color = null;

  /// The variant for anything on the order lifecycle.
  ConsoleStatusPill.status(DeliveryStatusColor status, {super.key, String? label})
      : label = label ?? status.label,
        accent = DeliveryAccent.neutral,
        _color = status.color;

  final String label;
  final DeliveryAccent accent;

  final Color? _color;

  Color get _base => _color ?? accent.color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: DeliverySpacing.xs),
      decoration: BoxDecoration(
        // The design paints Tailwind's 50-step (`#ecfdf5` behind an emerald label). A 12% wash of
        // the accent itself lands within a shade of it and stays derived from the token, so a
        // repaint of the palette carries the badges with it instead of leaving them behind.
        color: _base.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _base,
        ),
      ),
    );
  }
}
