import 'package:flutter/material.dart';

import 'tokens.dart';
import 'yd_card.dart';

/// The redesign's category / filter pill (Figma `cat-chip` 3:32, the address label chips on
/// `customer-set-address` 22:204).
///
/// Selected is a solid [DeliveryColors.brand] with a white label; unselected is white with an
/// [DeliveryColors.ink] label. The design separates the unselected chip from the page in two
/// different ways depending on where it sits, so both are offered:
///
/// * [elevated] `false` (default) — a 1px [DeliveryColors.borderFaint] hairline, as the label
///   chips on the address sheet are drawn.
/// * [elevated] `true` — no border, lifted instead by [YdCard.softShadow], as the horizontally
///   scrolling category strip on `customer-home` is drawn.
///
/// Geometry: 16px horizontal padding, 10px vertical, fully rounded, minimum height 36 so a strip
/// of chips stays on one rhythm whether or not the individual chips carry icons.
class YdChip extends StatelessWidget {
  const YdChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
    this.elevated = false,
    this.trailing,
  });

  /// Already localised by the caller.
  final String label;

  /// Optional 16px leading glyph, tinted with the label.
  final IconData? icon;

  final bool selected;
  final VoidCallback? onTap;

  /// Swaps the hairline border for the card shadow — the category-strip treatment.
  final bool elevated;

  /// Optional end-slot widget (a count, a [YdComingSoon] chip, a clear affordance).
  final Widget? trailing;

  static const double minHeight = 36;

  @override
  Widget build(BuildContext context) {
    final Color background =
        selected ? DeliveryColors.brand : DeliveryColors.white;
    final Color foreground =
        selected ? DeliveryColors.white : DeliveryColors.ink;

    final BorderRadius corners = BorderRadius.circular(DeliveryRadius.pill);

    return Semantics(
      button: onTap != null,
      selected: selected,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: corners,
          boxShadow: elevated && !selected ? YdCard.softShadow : null,
        ),
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: corners,
            side: selected || elevated
                ? BorderSide.none
                : const BorderSide(color: DeliveryColors.borderFaint),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: minHeight),
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: DeliverySpacing.md,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (icon != null) ...<Widget>[
                      Icon(icon, size: 16, color: foreground),
                      const SizedBox(width: DeliverySpacing.sm),
                    ],
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                        height: 1.2,
                      ),
                    ),
                    if (trailing != null) ...<Widget>[
                      const SizedBox(width: DeliverySpacing.sm),
                      trailing!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
