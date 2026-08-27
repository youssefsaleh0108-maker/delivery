import 'package:flutter/material.dart';

import 'tokens.dart';

/// The welcome screen's translucent role card (Figma `role-card-customer` 22:34 and its rider /
/// merchant twins).
///
/// It only ever sits on a [DeliveryColors.brand] background, which is why every colour here is an
/// on-brand token: a white-at-15% fill ([DeliveryColors.onBrandSurface]) inside a white-at-20%
/// hairline ([DeliveryColors.onBrandBorder]), a matching 44px icon tile, a white Bold 16 title
/// and an [DeliveryColors.onBrandSoft] 13 subtitle.
///
/// The 20px corner is the design's own — it is neither [DeliveryRadius.lg] (16) nor
/// [DeliveryRadius.sheet] (24), and rounding it to either is visible against the 44px tile's 14.
class YdRoleCard extends StatelessWidget {
  const YdRoleCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  /// 22px line glyph inside the tile.
  final IconData icon;

  /// Already localised by the caller.
  final String title;

  /// Already localised by the caller.
  final String subtitle;

  final VoidCallback onTap;

  /// Replaces the default end chevron — for a role that is not yet open, say.
  final Widget? trailing;

  /// The design's card corner. See the class doc: deliberately not a radius token.
  static const double radius = 20;

  /// The icon tile's corner, likewise measured rather than rounded to a token.
  static const double tileRadius = 14;

  @override
  Widget build(BuildContext context) {
    final BorderRadius corners = BorderRadius.circular(radius);

    return Semantics(
      button: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: corners,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: DeliveryColors.onBrandSurface,
          shape: RoundedRectangleBorder(
            borderRadius: corners,
            side: const BorderSide(color: DeliveryColors.onBrandBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(DeliverySpacing.md),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: DeliveryColors.onBrandSurface,
                      borderRadius: BorderRadius.circular(tileRadius),
                    ),
                    child: Icon(icon, size: 22, color: DeliveryColors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: DeliveryColors.white,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: DeliverySpacing.xs),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            // The design's 90% opacity on the rose tint.
                            color: DeliveryColors.onBrandSoft
                                .withValues(alpha: 0.9),
                            height: 18 / 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: DeliverySpacing.sm),
                  trailing ??
                      Icon(
                        Directionality.of(context) == TextDirection.rtl
                            ? Icons.chevron_left
                            : Icons.chevron_right,
                        size: 20,
                        color: DeliveryColors.white,
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
