import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

import 'store_state_mapping.dart';

/// The row of category cards under the customer home's search field.
///
/// Its own widget because its height has to be derived from what a card is made of, and that
/// derivation is the whole point of the file. It lived inside the home screen as a hand-written
/// `SizedBox(height: 96)` next to a card that occupies 80.1 — four pixels of RenderFlex overflow,
/// on the first screen of the app, at the default font size, with every category label clipped
/// through the middle. It reached a device and stayed there because nothing could mount just this
/// row: the only way to see it was to build the entire home screen against a live backend.
///
/// So the numbers are named, the height is computed from them, and [CategoryStripMetrics] is
/// public so a test can assert the box is big enough for its contents without standing up an API.
class CategoryStrip extends StatelessWidget {
  const CategoryStrip({
    super.key,
    required this.verticals,
    required this.labelOf,
    required this.onSelected,
    required this.gutter,
  });

  final List<StoreVertical> verticals;
  final String Function(StoreVertical) labelOf;
  final ValueChanged<StoreVertical> onSelected;

  /// The page gutter the rest of the home screen sits on, so this row lines up with it.
  final double gutter;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: CategoryStripMetrics.stripHeight(context),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsetsDirectional.fromSTEB(
            gutter,
            CategoryStripMetrics.listPaddingTop,
            DeliverySpacing.md,
            CategoryStripMetrics.listPaddingBottom),
        children: <Widget>[
          for (final StoreVertical vertical in verticals) ...<Widget>[
            CategoryCard(
              label: labelOf(vertical),
              icon: iconForVertical(vertical),
              onTap: () => onSelected(vertical),
            ),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

/// Every number the strip's height is made of, in one place.
///
/// Separated from the widgets so the card and the box around it cannot drift apart again. They
/// did: the card was built from literals and the strip reserved a number typed beside it, and the
/// two disagreed by four pixels.
class CategoryStripMetrics {
  const CategoryStripMetrics._();

  /// The brand-soft square holding the glyph.
  static const double tile = 44;

  /// Between the tile and its label.
  static const double tileGap = 6;

  static const double labelSize = 10.5;
  static const double labelHeight = 1.15;

  /// The card's own vertical padding, top and bottom, and its hairline border.
  static const double cardPadding = DeliverySpacing.sm;
  static const double cardBorder = 1;

  static const double listPaddingTop = DeliverySpacing.md;
  static const double listPaddingBottom = DeliverySpacing.xs;

  /// What one card occupies, at this context's text scale.
  ///
  /// The label goes through the text scaler rather than being taken at its nominal size: a reader
  /// running a larger system font is the same bug further along the accessibility slider, and a
  /// height that ignores the scaler clips them instead of growing.
  static double cardHeight(BuildContext context) {
    // Rounded UP, and that is not defensive padding. A line of text is laid out and painted on
    // whole logical pixels, so its real height is the ceiling of the nominal one — computing the
    // box from the nominal figure produced a fit that was exact on paper and 0.114px short in the
    // renderer, which Flutter reports as an overflow just as loudly as four pixels.
    final double label =
        (MediaQuery.textScalerOf(context).scale(labelSize) * labelHeight)
            .ceilToDouble();
    return tile + tileGap + label + cardPadding * 2 + cardBorder * 2;
  }

  /// What the strip must reserve: a card, plus the list's own padding around it.
  static double stripHeight(BuildContext context) =>
      cardHeight(context) + listPaddingTop + listPaddingBottom;
}

/// One category: the glyph in a brand-soft square, the name beneath it.
class CategoryCard extends StatelessWidget {
  const CategoryCard({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          onTap: onTap,
          child: Container(
            width: 82,
            padding: const EdgeInsets.symmetric(
                vertical: CategoryStripMetrics.cardPadding),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
              border: Border.all(
                  color: DeliveryColors.borderFaint,
                  width: CategoryStripMetrics.cardBorder),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Container(
                  width: CategoryStripMetrics.tile,
                  height: CategoryStripMetrics.tile,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: DeliveryColors.brandSoft,
                    borderRadius: BorderRadius.circular(DeliveryRadius.sm + 2),
                  ),
                  child: Icon(icon, size: 20, color: DeliveryColors.brand),
                ),
                const SizedBox(height: CategoryStripMetrics.tileGap),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    // Smaller and a touch tighter than the shop-name scale — the tile is 82px
                    // wide and the longer vertical names (Restaurants, Pharmacies) were riding
                    // the ellipsis at 11.5. This fits them whole.
                    fontSize: CategoryStripMetrics.labelSize,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    letterSpacing: -0.1,
                    height: CategoryStripMetrics.labelHeight,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
