import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'cart.dart';
import 'offline_catalog.dart';
import 'order_outbox.dart';
import 'outbox_card.dart';

/// "Cached Catalog" (Figma 121:279): what the customer can still do with no connection.
///
/// Laid out as the frame draws it: the 56px header with its back chip, the title over the shop's
/// name, and the brand "Offline Mode" pill on the end; then "Your Last Cached Purchases" as a
/// horizontal track of 160px cards, each with its photo, name, price and a "Quick Add"; then the
/// queued checkouts. Opened by the offline strip's "Saved items" from any tab, and shown where the
/// frame draws it: in the Orders tab, under the strip and above the nav bar, with its back chip
/// returning to the order list ([onBack]).
///
/// The prices are the ones saved with the shelf, and a line under the heading says when that was.
/// The design's "Offline Mode" pill appears only while offline — once the connection is back this
/// is simply a list of recent purchases, and a pill claiming otherwise would be untrue.
///
/// Quick Add puts the saved product in the basket at its saved price, exactly as a shop page add
/// does; the customer then checks out as usual, and offline checkout offers to queue it. A product
/// with options has no Quick Add — choosing a size needs the live catalog to price it — and says
/// so where the button would be, rather than drawing a button that cannot work.
class CachedCatalogScreen extends StatelessWidget {
  const CachedCatalogScreen({
    super.key,
    required this.catalog,
    required this.cart,
    required this.connectivity,
    required this.onOpenBasket,
    this.outbox,
    this.onBack,
  });

  final OfflineCatalog catalog;
  final Cart cart;
  final ValueListenable<bool> connectivity;
  final OrderOutbox? outbox;

  /// The shell's way to its Basket tab, offered on the "added" message.
  final VoidCallback onOpenBasket;

  /// What the back chip does. The shell closes the catalog back to the order list; null — the
  /// screen on a route of its own, as in a test — pops the route.
  final VoidCallback? onBack;

  void _quickAdd(BuildContext context, CachedProduct item) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    // The basket's one-shop rule, told at the tap. Replacing somebody's basket from a screen they
    // may have opened only to look is not this screen's call; the shop page offers that.
    if (cart.conflictsWith(item.product)) {
      messenger.showSnackBar(
          SnackBar(content: Text(t.basketFromAnotherShop(cart.store?.name ?? ''))));
      return;
    }
    cart.add(item.product, from: catalog.store);
    messenger.showSnackBar(SnackBar(
      content: Text(t.addedToBasket(1)),
      action: SnackBarAction(label: t.viewBasket, onPressed: onOpenBasket),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable?>[catalog, connectivity, outbox]),
      builder: (BuildContext context, _) {
        final bool offline = !connectivity.value;
        final DateTime? savedAt = catalog.savedAt;
        return Scaffold(
          backgroundColor: DeliveryColors.background,
          appBar: YdScreenHeader(
            title: t.offlineCachedCatalogTitle,
            subtitle: catalog.store?.name,
            onBack: onBack ?? () => Navigator.of(context).maybePop(),
            backSemanticLabel: t.back,
            trailing: offline ? YdBadge.brand(label: t.offlineModeBadge, uppercase: false) : null,
          ),
          body: ListView(
            padding: const EdgeInsets.all(DeliverySpacing.md),
            children: <Widget>[
              Text(
                t.offlineLastPurchases,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.ink,
                  height: 1.25,
                ),
              ),
              if (savedAt != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  t.offlinePricesAsOf(_when(context, savedAt)),
                  style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.35),
                ),
              ],
              const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
              if (catalog.isEmpty)
                YdEmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: t.offlineNothingSaved,
                  message: t.offlineNothingSavedHint,
                )
              else
                // A scrolling row rather than a lazy list with a fixed track height: there are at
                // most [OfflineCatalog.maxProducts] cards, and a row that sizes itself to them grows
                // with a larger text setting instead of clipping the cards. The cards share the
                // tallest one's height, so every Quick Add sits on the same line.
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (int i = 0; i < catalog.products.length; i++) ...<Widget>[
                          if (i > 0) const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
                          _CachedCard(
                            item: catalog.products[i],
                            onQuickAdd: catalog.products[i].canQuickAdd
                                ? () => _quickAdd(context, catalog.products[i])
                                : null,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              if (outbox != null && !outbox!.isEmpty) ...<Widget>[
                const SizedBox(height: DeliverySpacing.md),
                OutboxSection(outbox: outbox!),
              ],
            ],
          ),
        );
      },
    );
  }

  static String _when(BuildContext context, DateTime at) {
    final MaterialLocalizations dates = MaterialLocalizations.of(context);
    final DateTime local = at.toLocal();
    return '${dates.formatShortDate(local)} ${dates.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }
}

/// One saved product: the frame's 160px card — 12px padding, a 70px photo at radius 8, the name
/// and brand price 2px apart, and the brand-soft "Quick Add" 8px below.
class _CachedCard extends StatelessWidget {
  const _CachedCard({required this.item, required this.onQuickAdd});

  final CachedProduct item;

  /// Null for a product with options, which draws the explanation instead of a button.
  final VoidCallback? onQuickAdd;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final Product product = item.product;
    return SizedBox(
      width: 160,
      child: YdCard.bordered(
        radius: DeliveryRadius.md,
        padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            DeliveryProductImage(
              url: product.listImageUrl,
              height: 70,
              borderRadius: BorderRadius.circular(DeliveryRadius.sm),
            ),
            const SizedBox(height: DeliverySpacing.sm),
            Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: DeliveryColors.ink,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '\$${product.price.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.brand,
                height: 1.3,
              ),
            ),
            const SizedBox(height: DeliverySpacing.sm),
            // Takes up whatever a taller neighbour adds, so the buttons line up across the track.
            const Spacer(),
            if (onQuickAdd != null)
              Semantics(
                button: true,
                child: Material(
                  color: DeliveryColors.brandSoft,
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    onTap: onQuickAdd,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 6),
                      child: Text(
                        t.offlineQuickAdd,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: DeliveryColors.brand,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(vertical: 1),
                child: Text(
                  t.offlineNeedsOptions,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, color: DeliveryColors.muted, height: 1.2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
