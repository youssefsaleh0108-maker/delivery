import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'cart.dart';
import 'product_options_sheet.dart';
import 'delivery_address.dart';
import 'checkout_screen.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({
    super.key,
    required this.cart,
    required this.addresses,
    required this.orderApi,
    required this.offerApi,
    required this.onOrderPlaced,
    this.zoneApi,
  });

  final Cart cart;
  final DeliveryAddressStore addresses;
  final OrderApi orderApi;

  /// Handed to checkout so a new address added there can still pick its area.
  final DeliveryZoneApi? zoneApi;

  /// Used to re-ask what the basket qualifies for when its contents change on this screen.
  final OfferApi offerApi;
  final VoidCallback onOrderPlaced;

  Future<void> _checkout(BuildContext context) async {
    final DeliveryOrder? order = await Navigator.of(context).push<DeliveryOrder>(
      MaterialPageRoute<DeliveryOrder>(
        builder: (_) => CheckoutScreen(
            api: orderApi, cart: cart, addresses: addresses, zoneApi: zoneApi),
      ),
    );
    if (order == null || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(DeliveryStrings.of(context).orderPlacedToastShort(order.shortId, order.totalAmount.toStringAsFixed(2)))),
    );
    // Jump to Orders so the customer immediately sees the thing they just created.
    onOrderPlaced();
  }

  @override
  Widget build(BuildContext context) {
    final List<CartLine> lines = cart.lines;

    final StoreCard? store = cart.store;

    return Scaffold(
      appBar: AppBar(
        title: Text(DeliveryStrings.of(context).basket),
        // Names the shop the basket is locked to, so the one-store rule is visible rather than
        // only discovered when adding something from somewhere else is refused.
        bottom: store == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(44),
                child: Container(
                  width: double.infinity,
                  color: DeliveryColors.brandSoft,
                  padding: const EdgeInsets.symmetric(
                      horizontal: DeliverySpacing.md, vertical: DeliverySpacing.sm),
                  child: Row(
                    children: <Widget>[
                      StoreAvatar(name: store.name, logoUrl: store.logoUrl, size: 26),
                      const SizedBox(width: DeliverySpacing.sm),
                      Expanded(
                        child: Text(
                          store.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: DeliveryColors.ink),
                        ),
                      ),
                      Text(store.etaLabel,
                          style: const TextStyle(
                              fontSize: 12, color: DeliveryColors.muted)),
                    ],
                  ),
                ),
              ),
      ),
      body: lines.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.shopping_bag_outlined,
                      size: 44, color: DeliveryColors.muted),
                  const SizedBox(height: DeliverySpacing.sm),
                  Text(DeliveryStrings.of(context).basketEmpty,
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(DeliverySpacing.md),
              itemCount: lines.length,
              separatorBuilder: (_, __) => const SizedBox(height: DeliverySpacing.sm),
              itemBuilder: (BuildContext context, int i) {
                final CartLine line = lines[i];
                return SoftCard(
                  padding: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(DeliverySpacing.sm),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(line.product.name,
                                  style: Theme.of(context).textTheme.titleMedium,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              // The configuration, so two lines of the same product are tellable
                              // apart at a glance.
                              if (line.optionsSummary.isNotEmpty)
                                Text(line.optionsSummary,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: DeliveryColors.muted,
                                        height: 1.3)),
                              Text(line.unitPrice.toStringAsFixed(2),
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => cart.remove(line.key),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text('${line.qty}',
                            style: Theme.of(context).textTheme.titleMedium),
                        IconButton(
                          // Re-adds this exact configuration, not a bare product.
                          onPressed: () => cart.addConfigured(ConfiguredProduct(
                            product: line.product,
                            optionIds: line.optionIds,
                            unitPrice: line.unitPrice,
                            summary: line.optionsSummary,
                          )),
                          icon: const Icon(Icons.add_circle, color: DeliveryColors.brand),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: lines.isEmpty ? null : _summary(context),
    );
  }

  /// The money, itemised.
  ///
  /// The delivery fee is shown as its own line rather than folded into one number, because a
  /// customer comparing shops is comparing exactly that split — and because a total that silently
  /// grew between the shelf and the basket is the classic reason a basket gets abandoned.
  Widget _summary(BuildContext context) {
    final StoreCard? store = cart.store;
    final bool blocked = !cart.meetsMinimum;

    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: DeliveryColors.white,
          border: Border(top: BorderSide(color: DeliveryColors.border)),
        ),
        padding: const EdgeInsets.fromLTRB(DeliverySpacing.md, DeliverySpacing.md,
            DeliverySpacing.md, DeliverySpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _summaryRow(DeliveryStrings.of(context).subtotal, cart.subtotal),
            if (store != null) ...<Widget>[
              const SizedBox(height: DeliverySpacing.xs),
              _summaryRow(
                DeliveryStrings.of(context).delivery,
                // What will be CHARGED. Adding the shop's fee to the subtotal here, when the
                // platform is absorbing it, quoted the customer a total the server would not bill.
                cart.deliveryFeeCharged,
                // "Free" is the thing worth reading; 0.00 makes the eye do arithmetic.
                override: cart.deliveryFeeCharged == 0
                    ? DeliveryStrings.of(context).free
                    : null,
              ),
              if (cart.deliveryIsFree)
                Padding(
                  padding: const EdgeInsets.only(top: DeliverySpacing.xs),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.redeem_rounded, size: 15, color: DeliveryColors.brand),
                      const SizedBox(width: DeliverySpacing.xs),
                      Expanded(
                        // Names the promotion. A customer who is not told why their delivery was
                        // free has been given something that changes nothing about what they do
                        // next — which is the whole point of running an offer.
                        child: Text(
                          cart.waiver?.offerTitle ?? DeliveryStrings.of(context).freeDelivery,
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: DeliveryColors.brand),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const Padding(
              padding: EdgeInsets.symmetric(vertical: DeliverySpacing.sm),
              child: Divider(height: 1, color: DeliveryColors.border),
            ),
            _summaryRow(DeliveryStrings.of(context).total, cart.total, emphasised: true),
            if (blocked)
              Padding(
                padding: const EdgeInsets.only(top: DeliverySpacing.sm),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.info_outline_rounded,
                        size: 16, color: DeliveryColors.brand),
                    const SizedBox(width: DeliverySpacing.xs + 2),
                    Expanded(
                      child: Text(
                        DeliveryStrings.of(context).minimumExplanationFull((store?.minOrder ?? 0).toStringAsFixed(2),
                        cart.amountBelowMinimum.toStringAsFixed(2)),
                        style: const TextStyle(fontSize: 12.5, color: DeliveryColors.brand),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: DeliverySpacing.sm),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                // Disabled rather than hidden: a customer needs to see that checkout exists and
                // why it is not available yet.
                onPressed: blocked ? null : () => _checkout(context),
                child: Text(blocked
                    ? DeliveryStrings.of(context).minimumNotReached
                    : DeliveryStrings.of(context).checkoutWithTotal(cart.total.toStringAsFixed(2))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, double amount,
      {bool emphasised = false, String? override}) {
    final TextStyle style = TextStyle(
      fontSize: emphasised ? 16 : 14,
      fontWeight: emphasised ? FontWeight.w800 : FontWeight.w500,
      color: emphasised ? DeliveryColors.ink : DeliveryColors.muted,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(label, style: style),
        Text(override ?? amount.toStringAsFixed(2),
            style: style.copyWith(color: DeliveryColors.ink)),
      ],
    );
  }
}
