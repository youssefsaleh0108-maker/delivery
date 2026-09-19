import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'cart.dart';
import 'hyperlocal_screen.dart' show dekkaneDistanceLabel;
import 'product_detail_screen.dart' show AddButton, CustomerPhoto;
import 'store_state_mapping.dart';

/// The item search's heading: near the customer's pin, or everywhere when their address has none.
String itemSearchTitle(DeliveryStrings t, {required bool nearby}) =>
    nearby ? t.isrchNearTitle : t.isrchAnywhereTitle;

/// What an item search that found nothing says: no shop near the customer sells it, or none at all
/// without a pin.
String itemSearchEmptyTitle(DeliveryStrings t, String query, {required bool nearby}) =>
    nearby ? t.isrchEmptyNear(query) : t.isrchEmptyAnywhere(query);

/// What a truncated answer adds to that: only the best [ItemSearchPage.candidateLimit] matches were
/// looked at, so "no shop sells it" is not the whole truth. Null when nothing needs adding.
String? itemSearchTruncatedNote(DeliveryStrings t, ItemSearchPage? page) {
  final int? limit = page?.candidateLimit;
  if (page == null || !page.truncated || limit == null) return null;
  return t.isrchEmptyTruncated(limit);
}

/// One shop the item search found, and what it sells that matched: the shop's line, then its best
/// items, each with the server's price and an Add, then "N more in this shop".
///
/// The shop line carries what a customer weighs before ordering: the logo and name, a Busy or
/// Closing-soon chip (a closed shop is never listed), the delivery time and fee, and the distance,
/// only when the search was around the customer's pin. Tapping it opens the shop.
///
/// Each item row is the shop shelf's row made smaller: tapping it opens the product, Add puts it in
/// the basket, and once it is there the row shows how many, with the way back out. What the taps do
/// is the caller's ([BasketAdd]); the card only draws. Add is drawn disabled, never hidden, should a
/// shop not take orders, as the shelf draws it.
class ItemSearchGroupCard extends StatelessWidget {
  const ItemSearchGroupCard({
    super.key,
    required this.group,
    required this.nearby,
    required this.maxItems,
    required this.cart,
    required this.onOpenShop,
    required this.onAdd,
    required this.onOpenProduct,
    this.onMoreInShop,
  });

  final ItemSearchGroup group;

  /// Whether the search was around the customer's pin. Without one no distance is drawn.
  final bool nearby;

  /// How many of the group's items to draw: two on Home, three on the results screen.
  final int maxItems;

  /// Read for how many of each product are in the basket. The caller rebuilds the card when it
  /// changes.
  final Cart cart;

  final VoidCallback onOpenShop;
  final ValueChanged<Product> onAdd;
  final ValueChanged<Product> onOpenProduct;

  /// "N more in this shop": the shop's shelf searched for the same words. Drawn only when given and
  /// when the shop has more matches than the card shows.
  final VoidCallback? onMoreInShop;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<Product> shown = group.items.take(maxItems).toList();
    final int more = group.matchedInStore - shown.length;
    final bool acceptsOrders = group.store.availability.acceptsOrders;

    return YdCard(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _ShopLine(group: group, nearby: nearby, onTap: onOpenShop),
          for (final Product product in shown) ...<Widget>[
            const Divider(height: DeliverySpacing.md, color: DeliveryColors.border),
            _ItemRow(
              product: product,
              inBasket: cart.qtyOf(product.id),
              onTap: () => onOpenProduct(product),
              onAdd: acceptsOrders ? () => onAdd(product) : null,
              onRemove: () => cart.removeProduct(product.id),
            ),
          ],
          if (onMoreInShop != null && more > 0) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: onMoreInShop,
                style: TextButton.styleFrom(
                  foregroundColor: DeliveryColors.brand,
                  minimumSize: const Size(48, 40),
                  padding: const EdgeInsetsDirectional.symmetric(horizontal: DeliverySpacing.sm),
                ),
                // Mirrors itself in Arabic, pointing the way the shop opens.
                icon: const Icon(Icons.chevron_right, size: 18),
                label: Text(
                  t.isrchMoreInStore(more),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The shop's line: logo, name, the state chip when it is worth reading, and the facts under it.
class _ShopLine extends StatelessWidget {
  const _ShopLine({required this.group, required this.nearby, required this.onTap});

  final ItemSearchGroup group;
  final bool nearby;
  final VoidCallback onTap;

  static const double _logo = 40;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final StoreCard store = group.store;
    final String? logo = store.listLogoUrl;
    final int? metres = nearby ? group.distanceMetres : null;
    // Open is the ordinary state and says nothing; Busy and Closing soon are worth a glance.
    final bool flagged = store.availability == StoreAvailability.busy ||
        store.availability == StoreAvailability.closingSoon;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DeliveryRadius.md),
      child: Row(
        children: <Widget>[
          if (logo == null)
            StoreMonogram(name: store.name, size: _logo, radius: DeliveryRadius.md)
          else
            CustomerPhoto(
              url: logo,
              width: _logo,
              height: _logo,
              radius: DeliveryRadius.md,
              icon: Icons.storefront_outlined,
            ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        store.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: DeliveryColors.ink,
                          height: 1.25,
                        ),
                      ),
                    ),
                    if (flagged) ...<Widget>[
                      const SizedBox(width: DeliverySpacing.sm),
                      StoreStatePill(
                        state: storeStateOf(store.availability),
                        label: store.availability.labelIn(t),
                        compact: true,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                // A Wrap, so on a narrow phone or in a longer language the facts move to a second
                // line rather than one of them being cut off.
                Wrap(
                  spacing: DeliverySpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    _fact(t.etaRange(store.etaMinMinutes, store.etaMaxMinutes)),
                    const _Dot(),
                    _fact(
                      store.deliveryFee == 0
                          ? t.freeDelivery
                          : t.deliveryFeeLabel('\$${store.deliveryFee.toStringAsFixed(2)}'),
                      color: store.deliveryFee == 0 ? DeliveryAccent.positive.color : null,
                    ),
                    if (metres != null) ...<Widget>[
                      const _Dot(),
                      _fact(dekkaneDistanceLabel(t, metres)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.xs),
          const Icon(Icons.chevron_right, size: 18, color: DeliveryColors.faint),
        ],
      ),
    );
  }

  static Widget _fact(String text, {Color? color}) => Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: color == null ? FontWeight.w400 : FontWeight.w600,
          color: color ?? DeliveryColors.muted,
          height: 1.3,
        ),
      );
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) =>
      const Text('•', style: TextStyle(fontSize: 12, color: DeliveryColors.faint));
}

/// One matching product: its photo, its name, the server's price, and Add.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.product,
    required this.inBasket,
    required this.onTap,
    required this.onAdd,
    required this.onRemove,
  });

  final Product product;
  final int inBasket;
  final VoidCallback onTap;
  final VoidCallback? onAdd;
  final VoidCallback onRemove;

  static const double _thumb = 48;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String? lbp = MarketRates.instance.lbpParen(product.price);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DeliveryRadius.md),
      child: Row(
        children: <Widget>[
          CustomerPhoto(
            // The list-sized derivative, as the shelf row loads it.
            url: product.listImageUrl,
            width: _thumb,
            height: _thumb,
            radius: DeliveryRadius.md,
            icon: Icons.fastfood_outlined,
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                // The price the server sent for this product, the same the shelf shows, and the
                // platform rate's conversion beside it when there is a rate: not a second price.
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: '\$${product.price.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: DeliveryColors.brand,
                        ),
                      ),
                      if (lbp != null)
                        TextSpan(
                          text: '  $lbp',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: DeliveryColors.faint,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (inBasket > 0) ...<Widget>[
            Semantics(
              button: true,
              label: t.remove,
              child: InkResponse(
                onTap: onRemove,
                radius: 18,
                child: const Padding(
                  padding: EdgeInsetsDirectional.all(DeliverySpacing.xs),
                  child: Icon(Icons.remove_circle_outline, size: 18, color: DeliveryColors.muted),
                ),
              ),
            ),
            Text(
              '$inBasket',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.ink,
              ),
            ),
            const SizedBox(width: DeliverySpacing.sm),
          ] else
            const SizedBox(width: DeliverySpacing.sm),
          AddButton(onPressed: onAdd, semanticLabel: t.add),
        ],
      ),
    );
  }
}
