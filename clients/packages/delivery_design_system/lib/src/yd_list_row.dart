import 'package:flutter/material.dart';

import 'tokens.dart';
import 'yd_card.dart';

/// The settings-style row (Figma `menu-item` 3:713 on `customer-settings`, and the same shape on
/// the rider, merchant and carrier settings screens).
///
/// Measured: each row is its own white card — radius [DeliveryRadius.lg], 16px padding, lifted by
/// [YdCard.softShadow] — holding a 32px icon tile ([DeliveryColors.background], radius
/// [DeliveryRadius.sm], 16px glyph), a 12px gap, a SemiBold 14 title, and an end group of an
/// optional muted value plus a 14px chevron.
///
/// Set [card] to `false` to get the bare row, for the screens that group several rows inside one
/// [YdCard] instead of giving each its own.
class YdListRow extends StatelessWidget {
  const YdListRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.trailing,
    this.card = true,
    this.tileSize = 32,
    this.tileColor = DeliveryColors.background,
    this.iconColor = DeliveryColors.ink,
    this.titleColor = DeliveryColors.ink,
  });

  /// Leading glyph, drawn at half the tile's edge (16px in the designed 32px tile).
  final IconData icon;

  /// Already localised by the caller.
  final String title;

  /// Optional second line, 12 in [DeliveryColors.muted].
  final String? subtitle;

  /// The design's muted right-hand value — "Home & Office", "Apple Pay". Already localised.
  final String? value;

  final VoidCallback? onTap;

  /// Replaces the chevron: a [Switch], a [YdBadge], a [YdComingSoon] chip. When null and [onTap]
  /// is set, the design's 14px chevron is drawn and mirrors in RTL.
  final Widget? trailing;

  final bool card;

  final double tileSize;

  /// Tinted variants exist — a brand-soft tile for a highlighted row, an accent tile for a
  /// destructive one — so both tile and glyph colours are parameters.
  final Color tileColor;
  final Color iconColor;
  final Color titleColor;

  @override
  Widget build(BuildContext context) {
    final bool rtl = Directionality.of(context) == TextDirection.rtl;

    final Widget row = Row(
      children: <Widget>[
        Container(
          width: tileSize,
          height: tileSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tileColor,
            borderRadius: BorderRadius.circular(DeliveryRadius.sm),
          ),
          child: Icon(icon, size: tileSize / 2, color: iconColor),
        ),
        const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: titleColor,
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
        if (value != null) ...<Widget>[
          const SizedBox(width: DeliverySpacing.sm),
          Flexible(
            child: Text(
              value!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 12,
                color: DeliveryColors.faint,
                height: 1.2,
              ),
            ),
          ),
        ],
        if (trailing != null) ...<Widget>[
          const SizedBox(width: DeliverySpacing.sm),
          trailing!,
        ] else if (onTap != null) ...<Widget>[
          const SizedBox(width: DeliverySpacing.sm),
          Icon(
            rtl ? Icons.chevron_left : Icons.chevron_right,
            size: 14,
            color: DeliveryColors.faint,
          ),
        ],
      ],
    );

    if (!card) {
      return onTap == null
          ? row
          : Semantics(
              button: true,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                child: row,
              ),
            );
    }

    return Semantics(
      button: onTap != null,
      child: YdCard(onTap: onTap, child: row),
    );
  }
}
