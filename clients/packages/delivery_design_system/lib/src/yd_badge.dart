import 'package:flutter/material.dart';

import 'tokens.dart';

/// The small tinted status pill the redesign uses everywhere a state needs naming —
/// `PICKING UP` / `ON THE WAY` on the rider offer cards, `Uploaded` on the document rows,
/// the order-state chips in the merchant and backoffice tables.
///
/// Geometry read off the frames: radius [DeliveryRadius.sm], 8px horizontal / 4px vertical
/// padding, label SemiBold 11 in the accent colour, uppercased, on that accent's 12% tint.
///
/// The label is supplied already localised. [uppercase] is on by default because that is how the
/// design draws it, but Arabic has no case, so the transform is a no-op there rather than a
/// mistake — `String.toUpperCase` leaves Arabic script untouched.
class YdBadge extends StatelessWidget {
  const YdBadge({
    super.key,
    required this.label,
    required this.color,
    this.background,
    this.icon,
    this.uppercase = true,
    this.fontSize = 11,
  });

  /// The semantic accents: `positive`, `caution`, `critical`, `neutral`, `info`.
  YdBadge.accent({
    super.key,
    required this.label,
    required DeliveryAccent accent,
    this.icon,
    this.uppercase = true,
    this.fontSize = 11,
  })  : color = accent.color,
        background = accent.tint;

  /// The brand-tinted variant: the `Edit` chip on the profile card, the `Upload` chip on the
  /// document rows.
  const YdBadge.brand({
    super.key,
    required this.label,
    this.icon,
    this.uppercase = true,
    this.fontSize = 11,
  })  : color = DeliveryColors.brand,
        background = DeliveryColors.brandSoft;

  /// Already localised by the caller.
  final String label;

  /// Glyph and text colour.
  final Color color;

  /// Fill. Defaults to [color] at 12%, matching [DeliveryAccent.tint].
  final Color? background;

  /// Optional 12px leading glyph.
  final IconData? icon;

  final bool uppercase;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: DeliverySpacing.sm,
        vertical: DeliverySpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: DeliverySpacing.xs),
          ],
          Text(
            uppercase ? label.toUpperCase() : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: color,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// A [YdBadge] driven by the shared order-status palette.
///
/// The colour is not overridable, and that is the point: Appendix A requires a status to mean the
/// same colour in the backoffice tables, the merchant portal and in-app tracking. Only the label
/// is passed in, so the caller can localise it.
class YdStatusPill extends StatelessWidget {
  const YdStatusPill({
    super.key,
    required this.status,
    required this.label,
    this.icon,
    this.uppercase = true,
  });

  final DeliveryStatusColor status;

  /// Already localised by the caller. [DeliveryStatusColor.label] is the English fallback and is
  /// deliberately not used here.
  final String label;

  final IconData? icon;
  final bool uppercase;

  @override
  Widget build(BuildContext context) {
    return YdBadge(
      label: label,
      color: status.color,
      background: status.color.withValues(alpha: 0.12),
      icon: icon,
      uppercase: uppercase,
    );
  }
}
