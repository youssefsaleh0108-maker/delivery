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

/// The dekkane frames' power pill (112:1941 on the card, 112:2041 on the shop's hero): "⚡ Generator
/// active" in the brand, and the grey "Currently dark" for a shop that has declared it has no power.
///
/// Worded as what is happening NOW, because that is all the data says: `power_status` is the
/// merchant's latest declaration of what the lights are doing, not a fact about what the shop owns.
/// Mains and undeclared draw nothing — mains is the normal state and not worth a badge on this
/// frame, and a shop that never said should not wear one it did not earn.
///
/// [solid] is the hero's version, a filled pill that survives a photograph behind it; the card's
/// is the brand-soft one.
class DekkanePowerPill extends StatelessWidget {
  const DekkanePowerPill({super.key, required this.status, this.solid = false});

  final StorePowerStatus status;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final (String label, Color fg, Color bg, IconData? icon) = switch (status) {
      StorePowerStatus.generator => solid
          ? (t.dekkaneGeneratorActive, DeliveryColors.white, DeliveryColors.brand, Icons.bolt_rounded)
          : (t.dekkaneGeneratorActive, DeliveryColors.brand, DeliveryColors.brandSoft,
              Icons.bolt_rounded),
      StorePowerStatus.dark => solid
          ? (t.custPowerDark, DeliveryColors.white, DeliveryColors.muted, null)
          : (t.custPowerDark, DeliveryColors.muted, DeliveryColors.border, null),
      StorePowerStatus.mains || StorePowerStatus.unknown =>
        ('', Colors.transparent, Colors.transparent, null),
    };
    if (label.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsetsDirectional.symmetric(horizontal: solid ? 8 : 6, vertical: solid ? 4 : 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(solid ? DeliveryRadius.sm : 4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 2),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: solid ? FontWeight.w700 : FontWeight.w600,
              color: fg,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// The dekkane frames' "Trusted local" badge — the Backoffice-granted `verified_local`, drawn as
/// the frame draws it: brand on brand-soft, small and square-cornered, beside the shop's name.
class TrustedLocalBadge extends StatelessWidget {
  const TrustedLocalBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: DeliveryColors.brandSoft,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        DeliveryStrings.of(context).dekkaneTrustedLocal,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: DeliveryColors.brand,
          height: 1.2,
        ),
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
