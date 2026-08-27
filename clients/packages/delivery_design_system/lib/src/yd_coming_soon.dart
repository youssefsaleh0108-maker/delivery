import 'package:flutter/material.dart';

import 'tokens.dart';

/// The marker for an affordance the design draws but no backend serves yet — Apple Pay, promo
/// codes, in-app chat, social sign-in.
///
/// It is written in the design's existing chip language (the `Edit` and `Upload` badges:
/// [DeliveryColors.brandSoft] fill, brand label, small radius) at the smallest size that stays
/// legible — Bold 10, uppercased — so it reads as a note *about* a control rather than as another
/// control competing with it.
///
/// [label] is required and has no default: the package ships no user-facing text, so the screen
/// passes its own localised "Soon".
///
/// Wrap the control with [YdComingSoon.wrap] to get the design's dimmed-and-inert treatment;
/// use the bare chip when the control keeps its full appearance and the chip sits beside it.
class YdComingSoon extends StatelessWidget {
  const YdComingSoon({
    super.key,
    required this.label,
    this.icon,
  });

  /// Already localised by the caller.
  final String label;

  /// Optional 10px leading glyph — [Icons.schedule] reads well here.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: DeliverySpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: DeliveryColors.brandSoft,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm - 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 10, color: DeliveryColors.brand),
            const SizedBox(width: 3),
          ],
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.brand,
              height: 1.2,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  /// Renders [child] as the design draws it, dimmed to 55% and refusing every gesture, with the
  /// chip pinned to its top end corner.
  ///
  /// Never fake the data behind such a control: this is for affordances that are drawn but do
  /// nothing yet.
  static Widget wrap({
    required Widget child,
    required String label,
    IconData? icon,
    double opacity = 0.55,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        IgnorePointer(
          child: Opacity(opacity: opacity, child: child),
        ),
        PositionedDirectional(
          top: -6,
          end: -6,
          child: YdComingSoon(label: label, icon: icon),
        ),
      ],
    );
  }
}
