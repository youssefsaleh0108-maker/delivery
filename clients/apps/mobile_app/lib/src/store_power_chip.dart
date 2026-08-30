import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// The power chip (Figma `shop-power-status`): a dot and a word saying what the lights are doing —
/// mains in green, generator in amber, dark in grey.
///
/// Returns nothing at all for [StorePowerStatus.unknown]: a shop that never declared should not
/// wear a badge it did not earn, and most shops start there.
class StorePowerChip extends StatelessWidget {
  const StorePowerChip({super.key, required this.status, this.compact = false});

  final StorePowerStatus status;

  /// Dot + word only at a smaller size, for dense rows.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final (String label, Color color, Color bg) = switch (status) {
      StorePowerStatus.mains => (
          t.custPowerMains,
          DeliveryAccent.positive.color,
          DeliveryAccent.positive.color.withValues(alpha: 0.12),
        ),
      StorePowerStatus.generator => (
          t.custPowerGenerator,
          const Color(0xFFB8860B),
          const Color(0xFFFDF3D7),
        ),
      StorePowerStatus.dark => (
          t.custPowerDark,
          DeliveryColors.muted,
          DeliveryColors.border,
        ),
      StorePowerStatus.unknown => ('', Colors.transparent, Colors.transparent),
    };
    if (status == StorePowerStatus.unknown) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsetsDirectional.symmetric(
          horizontal: compact ? 7 : 9, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: compact ? 4 : 5),
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w700,
              color: color,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// The dekkane trust badge — Backoffice-granted, drawn in the positive green.
class VerifiedLocalBadge extends StatelessWidget {
  const VerifiedLocalBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: DeliveryAccent.positive.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
      ),
      child: Text(
        t.custVerifiedLocal,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: DeliveryAccent.positive.color,
          height: 1.2,
        ),
      ),
    );
  }
}
