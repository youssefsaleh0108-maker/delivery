import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'cart.dart';
import 'checkout_screen.dart';
import 'delivery_address.dart';
import 'product_detail_screen.dart' show CustomerPhoto, QuantityStepper;
import 'product_options_sheet.dart';

/// The basket (Figma `customer-basket`, node 3:389).
///
/// A white header, the lines as cards with a stepper each, the promo row, and then the money —
/// itemised on a white plinth with the checkout button under it.
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

  static const double _gutter = DeliverySpacing.lg;

  Future<void> _checkout(BuildContext context) async {
    final DeliveryOrder? order = await Navigator.of(context).push<DeliveryOrder>(
      MaterialPageRoute<DeliveryOrder>(
        builder: (_) => CheckoutScreen(
            api: orderApi, cart: cart, addresses: addresses, zoneApi: zoneApi),
      ),
    );
    if (order == null || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(DeliveryStrings.of(context).orderPlacedToastShort(
          order.shortId, order.totalAmount.toStringAsFixed(2)))),
    );
    // Jump to Orders so the customer immediately sees the thing they just created.
    onOrderPlaced();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<CartLine> lines = cart.lines;

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(title: t.custMyBasket),
      body: lines.isEmpty
          ? YdEmptyState(
              icon: Icons.shopping_bag_outlined,
              title: t.basketEmpty,
              padding: const EdgeInsets.all(DeliverySpacing.xl),
            )
          : ListView(
              padding: EdgeInsets.zero,
              children: <Widget>[
                _storeStrip(context),
                Padding(
                  padding: const EdgeInsetsDirectional.all(_gutter),
                  child: Column(
                    children: <Widget>[
                      for (int i = 0; i < lines.length; i++) ...<Widget>[
                        if (i > 0) const SizedBox(height: DeliverySpacing.md - 4),
                        _basketRow(context, lines[i]),
                      ],
                    ],
                  ),
                ),
                _promoSection(context),
                const SizedBox(height: DeliverySpacing.lg),
                _summary(context),
              ],
            ),
    );
  }

  /// Names the shop the basket is locked to, so the one-store rule is visible rather than only
  /// discovered when adding something from somewhere else is refused. The frame has no such row —
  /// it is kept because the rule it explains is real.
  Widget _storeStrip(BuildContext context) {
    final StoreCard? store = cart.store;
    if (store == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: DeliveryColors.brandSoft,
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: _gutter, vertical: DeliverySpacing.md - 4),
      child: Row(
        children: <Widget>[
          const Icon(Icons.storefront, size: 16, color: DeliveryColors.brand),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              store.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: DeliveryColors.ink,
              ),
            ),
          ),
          Text(store.etaLabel,
              style: const TextStyle(fontSize: 12, color: DeliveryColors.muted)),
        ],
      ),
    );
  }

  static const double _thumb = 64;

  /// `basket-row`: a 64px thumbnail, the name over the line price, and the stepper.
  Widget _basketRow(BuildContext context, CartLine line) {
    return Container(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
      decoration: BoxDecoration(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
      ),
      child: Row(
        children: <Widget>[
          CustomerPhoto(
            url: line.product.imageUrls.isEmpty ? null : line.product.imageUrls.first,
            width: _thumb,
            height: _thumb,
            radius: 10,
            icon: Icons.fastfood_outlined,
          ),
          const SizedBox(width: DeliverySpacing.md - 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  line.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
                // The configuration, so two lines of the same product are tellable apart at a
                // glance. Not on the frame, which draws only products without options.
                if (line.optionsSummary.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    line.optionsSummary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: DeliveryColors.faint, height: 1.3),
                  ),
                ],
                const SizedBox(height: DeliverySpacing.xs),
                Text(
                  line.unitPrice.toStringAsFixed(2),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.brand,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          QuantityStepper(
            quantity: line.qty,
            // At one, decrementing removes the line — so the glyph says so. The frame draws no
            // delete affordance at all and a basket you cannot empty is not shippable.
            decreaseIcon: line.qty > 1 ? Icons.remove : Icons.delete_outline,
            onDecrease: () => cart.remove(line.key),
            onIncrease: () => cart.addConfigured(ConfiguredProduct(
              product: line.product,
              optionIds: line.optionIds,
              unitPrice: line.unitPrice,
              summary: line.optionsSummary,
            )),
          ),
        ],
      ),
    );
  }

  /// The promo row, drawn as designed and inert.
  ///
  /// There is no voucher service: nothing on the platform can validate a code, and a field that
  /// silently accepts anything is worse than one that says it is not ready.
  Widget _promoSection(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: _gutter),
      child: YdComingSoon.wrap(
        label: t.custSoon,
        icon: Icons.schedule,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Container(
                padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
                decoration: BoxDecoration(
                  color: DeliveryColors.white,
                  borderRadius: BorderRadius.circular(DeliveryRadius.md),
                  border: Border.all(color: DeliveryColors.border),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.sell_outlined, size: 18, color: DeliveryColors.faint),
                    const SizedBox(width: DeliverySpacing.sm),
                    Expanded(
                      child: Text(
                        t.custPromoCode,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, color: DeliveryColors.faint),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: DeliverySpacing.md - 4),
            Container(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: DeliverySpacing.lg - DeliverySpacing.xs,
                  vertical: DeliverySpacing.md - DeliverySpacing.xs),
              decoration: BoxDecoration(
                color: DeliveryColors.brandSoft,
                borderRadius: BorderRadius.circular(DeliveryRadius.md),
                border: Border.all(color: DeliveryColors.brand),
              ),
              child: Text(
                t.custApply,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: DeliveryColors.brand,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The money, itemised.
  ///
  /// The delivery fee is shown as its own line rather than folded into one number, because a
  /// customer comparing shops is comparing exactly that split — and because a total that silently
  /// grew between the shelf and the basket is the classic reason a basket gets abandoned.
  Widget _summary(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final StoreCard? store = cart.store;
    final bool blocked = !cart.meetsMinimum;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(top: BorderSide(color: DeliveryColors.border)),
      ),
      padding: const EdgeInsetsDirectional.all(_gutter),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              t.custOrderSummary,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: DeliveryColors.ink,
              ),
            ),
            const SizedBox(height: DeliverySpacing.md),
            _summaryRow(t.subtotal, cart.subtotal.toStringAsFixed(2)),
            if (store != null) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              _summaryRow(
                t.delivery,
                // What will be CHARGED. Adding the shop's fee to the subtotal here, when the
                // platform is absorbing it, quoted the customer a total the server would not bill.
                // "Free" is the thing worth reading; 0.00 makes the eye do arithmetic.
                cart.deliveryFeeCharged == 0
                    ? t.free
                    : cart.deliveryFeeCharged.toStringAsFixed(2),
              ),
              // The discounts line, and only when there is a real discount to put on it. Names the
              // promotion underneath: a customer who is not told why their delivery was free has
              // been given something that changes nothing about what they do next.
              if (cart.deliveryIsFree) ...<Widget>[
                const SizedBox(height: DeliverySpacing.sm),
                _summaryRow(
                  t.custDiscounts,
                  '-${cart.deliveryFee.toStringAsFixed(2)}',
                  valueColor: DeliveryAccent.positive.color,
                ),
                const SizedBox(height: DeliverySpacing.xs),
                Row(
                  children: <Widget>[
                    const Icon(Icons.redeem_outlined, size: 14, color: DeliveryColors.brand),
                    const SizedBox(width: DeliverySpacing.xs),
                    Expanded(
                      child: Text(
                        cart.waiver?.offerTitle ?? t.freeDelivery,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: DeliveryColors.brand,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
            const Padding(
              padding: EdgeInsetsDirectional.symmetric(vertical: DeliverySpacing.sm),
              child: Divider(height: 1, thickness: 1, color: DeliveryColors.border),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  t.custTotalAmount,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                  ),
                ),
                Text(
                  cart.total.toStringAsFixed(2),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.brand,
                  ),
                ),
              ],
            ),
            if (blocked) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.info_outline, size: 16, color: DeliveryColors.brand),
                  const SizedBox(width: DeliverySpacing.sm),
                  Expanded(
                    child: Text(
                      t.minimumExplanationFull(
                        (store?.minOrder ?? 0).toStringAsFixed(2),
                        cart.amountBelowMinimum.toStringAsFixed(2),
                      ),
                      style: const TextStyle(
                          fontSize: 12, color: DeliveryColors.brand, height: 1.35),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: DeliverySpacing.md),
            YdPillButton(
              // Disabled rather than hidden: a customer needs to see that checkout exists and why
              // it is not available yet.
              label: blocked ? t.minimumNotReached : t.custProceedToCheckout,
              onPressed: blocked ? null : () => _checkout(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(label,
            style: const TextStyle(fontSize: 13, color: DeliveryColors.muted)),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: valueColor ?? DeliveryColors.ink,
          ),
        ),
      ],
    );
  }
}
