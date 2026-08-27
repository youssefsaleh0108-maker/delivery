import 'package:flutter/material.dart';

import 'tokens.dart';

/// The redesign's section title row (Figma `title-row` 3:61, `recent-header` 20:43).
///
/// A Bold title on one side and, when the section has more behind it, a SemiBold 14
/// [DeliveryColors.brand] text action on the other. The design uses 16 for a title inside a card
/// and 18 for a title that heads a whole page section, so [fontSize] is a parameter and defaults
/// to the in-card 16.
///
/// Both strings arrive already localised.
class YdSectionHeader extends StatelessWidget {
  const YdSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.fontSize = 16,
    this.trailing,
  });

  /// Already localised by the caller.
  final String title;

  /// Optional second line, 12 in [DeliveryColors.muted].
  final String? subtitle;

  /// The "See All" affordance. Rendered only when both this and [onAction] are given.
  final String? actionLabel;
  final VoidCallback? onAction;

  final double fontSize;

  /// Replaces the text action entirely — for a section that ends in a chip or an icon button.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final bool hasTextAction = actionLabel != null && onAction != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.ink,
                  height: 1.25,
                ),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DeliveryColors.muted,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null)
          trailing!
        else if (hasTextAction) ...<Widget>[
          const SizedBox(width: DeliverySpacing.sm),
          // Flexible, and the label ellipsises. At the default text size "See All" is nowhere near
          // the width it is given, so nothing about the design changes; at Android's largest text
          // setting the unbounded version pushed the row past the card and painted a stripe.
          Flexible(
            child: Semantics(
              button: true,
              child: InkWell(
                onTap: onAction,
                borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: DeliverySpacing.xs,
                    vertical: DeliverySpacing.xs,
                  ),
                  child: Text(
                    actionLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: DeliveryColors.brand,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
