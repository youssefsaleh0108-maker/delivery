import 'dart:async';

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
///
/// The promo row is live when a [PromoApi] is provided: the code is quoted against the basket as
/// the customer types (debounced — the server answers sub-three-character queries with nothing
/// anyway), the Discounts line shows what the server says the code is worth, and the code itself
/// travels with the order at placement, where the discount is recomputed against the basket the
/// server priced. Nothing here trusts the quote; it only decides what the summary shows.
class CartScreen extends StatefulWidget {
  const CartScreen({
    super.key,
    required this.cart,
    required this.addresses,
    required this.orderApi,
    required this.offerApi,
    required this.onOrderPlaced,
    this.zoneApi,
    this.promoApi,
    this.geocodingApi,
  });

  final Cart cart;
  final DeliveryAddressStore addresses;
  final OrderApi orderApi;

  /// Handed to checkout so a new address added there can still pick its area.
  final DeliveryZoneApi? zoneApi;

  /// Used to re-ask what the basket qualifies for when its contents change on this screen.
  final OfferApi offerApi;

  /// Validates promo codes. Optional so the screen still builds where the shell has not been
  /// handed one; the promo row then stays the drawn-and-inert affordance it was.
  final PromoApi? promoApi;

  /// Handed through to checkout's address sheet for the place search. Optional for the same
  /// reason as [promoApi].
  final GeocodingApi? geocodingApi;

  final VoidCallback onOrderPlaced;

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  static const double _gutter = DeliverySpacing.lg;

  /// Long enough that a customer typing a code does not fire a request per keystroke, short
  /// enough that the answer appears as soon as they pause.
  static const Duration _debounce = Duration(milliseconds: 450);

  final TextEditingController _promo = TextEditingController();
  Timer? _promoDebounce;

  /// The server's last answer about the code in the field, or null while the field is empty or a
  /// quote is still owed. Never trusted for money — only for what the summary shows.
  PromoQuote? _quote;
  bool _checking = false;

  /// True when the last quote attempt could not reach the server at all — a different sentence
  /// from a code the server looked at and refused.
  bool _quoteFailed = false;

  /// What the last quote was measured against, so a basket edit re-asks and a rebuild does not.
  String? _quotedSignature;

  @override
  void initState() {
    super.initState();
    // A basket edit changes what a code is worth — crossing a minimum is exactly the moment the
    // Discounts line must change.
    widget.cart.addListener(_onCartChanged);
  }

  @override
  void dispose() {
    widget.cart.removeListener(_onCartChanged);
    _promoDebounce?.cancel();
    _promo.dispose();
    super.dispose();
  }

  void _onCartChanged() {
    if (!mounted || widget.promoApi == null) return;
    if (_promo.text.trim().isEmpty) return;
    final String signature =
        '${_promo.text.trim()}|${widget.cart.subtotal.toStringAsFixed(2)}';
    if (signature == _quotedSignature) return;
    _scheduleQuote();
  }

  void _onPromoTyped(String _) {
    setState(() {
      _quote = null;
      _quoteFailed = false;
    });
    _scheduleQuote();
  }

  void _scheduleQuote() {
    _promoDebounce?.cancel();
    if (_promo.text.trim().isEmpty) {
      setState(() {
        _quote = null;
        _checking = false;
        _quoteFailed = false;
        _quotedSignature = null;
      });
      return;
    }
    _promoDebounce = Timer(_debounce, _requestQuote);
  }

  Future<void> _requestQuote() async {
    final PromoApi? api = widget.promoApi;
    final String code = _promo.text.trim();
    if (api == null || code.isEmpty || !mounted) return;

    final String signature = '$code|${widget.cart.subtotal.toStringAsFixed(2)}';
    setState(() {
      _checking = true;
      _quoteFailed = false;
    });
    try {
      final PromoQuote quote = await api.quote(
        code,
        subtotal: widget.cart.subtotal,
        deliveryFee: widget.cart.deliveryFeeCharged,
      );
      if (!mounted) return;
      // Answers can cross when typing continues past the debounce; only the answer to the code
      // still in the field may land.
      if (_promo.text.trim() != code) return;
      setState(() {
        _quote = quote;
        _checking = false;
        _quotedSignature = signature;
      });
    } catch (_) {
      if (!mounted || _promo.text.trim() != code) return;
      setState(() {
        _checking = false;
        _quoteFailed = true;
        _quote = null;
        _quotedSignature = signature;
      });
    }
  }

  void _removePromo() {
    _promoDebounce?.cancel();
    setState(() {
      _promo.clear();
      _quote = null;
      _checking = false;
      _quoteFailed = false;
      _quotedSignature = null;
    });
  }

  /// The advisory discount the summary shows. Zero unless the server said the code applies.
  double get _promoDiscount {
    final PromoQuote? quote = _quote;
    if (quote == null || !quote.valid) return 0;
    // Clamped against the payable total as a belt over the server's own clamp — the summary must
    // never show a negative amount to pay.
    final double payable = widget.cart.total;
    return quote.discount > payable ? payable : quote.discount;
  }

  Future<void> _checkout(BuildContext context) async {
    final PromoQuote? quote = _quote;
    final DeliveryOrder? order = await Navigator.of(context).push<DeliveryOrder>(
      MaterialPageRoute<DeliveryOrder>(
        builder: (_) => CheckoutScreen(
          api: widget.orderApi,
          cart: widget.cart,
          addresses: widget.addresses,
          zoneApi: widget.zoneApi,
          geocodingApi: widget.geocodingApi,
          // The canonical stored code, never the raw field text — and only when the server said
          // it applies, because placing with a refused code fails the whole order.
          promo: quote != null && quote.valid ? quote : null,
        ),
      ),
    );
    if (order == null || !context.mounted) return;

    // The code was consumed by the order; a stale "applied" chip over an empty basket would
    // claim a discount on nothing.
    _removePromo();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(DeliveryStrings.of(context).orderPlacedToastShort(
          order.shortId, order.totalAmount.toStringAsFixed(2)))),
    );
    // Jump to Orders so the customer immediately sees the thing they just created.
    widget.onOrderPlaced();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<CartLine> lines = widget.cart.lines;

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
    final StoreCard? store = widget.cart.store;
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
            onDecrease: () => widget.cart.remove(line.key),
            onIncrease: () => widget.cart.addConfigured(ConfiguredProduct(
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

  /// The promo row — live against the promotions API when one was provided, and the drawn-inert
  /// affordance it always was when not, because a field that accepts anything and validates
  /// nothing is worse than one that says it is not ready.
  Widget _promoSection(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    if (widget.promoApi == null) {
      return Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: _gutter),
        child: YdComingSoon.wrap(
          label: t.custSoon,
          icon: Icons.schedule,
          child: _promoRowShell(
            t,
            field: Text(
              t.custPromoCode,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: DeliveryColors.faint),
            ),
            onApply: null,
          ),
        ),
      );
    }

    final PromoQuote? quote = _quote;
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: _gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _promoRowShell(
            t,
            field: TextField(
              controller: _promo,
              onChanged: _onPromoTyped,
              onSubmitted: (_) => _requestQuote(),
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                  fontSize: 14, color: DeliveryColors.ink, height: 1.2),
              decoration: InputDecoration(
                isDense: true,
                isCollapsed: true,
                border: InputBorder.none,
                hintText: t.custPromoCode,
                hintStyle:
                    const TextStyle(fontSize: 14, color: DeliveryColors.faint),
              ),
            ),
            onApply: () {
              _promoDebounce?.cancel();
              _requestQuote();
            },
          ),
          if (_checking) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Row(
              children: <Widget>[
                const SizedBox.square(
                  dimension: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: DeliveryColors.brand),
                ),
                const SizedBox(width: DeliverySpacing.sm),
                Text(
                  t.custPromoChecking,
                  style: const TextStyle(
                      fontSize: 12, color: DeliveryColors.muted, height: 1.3),
                ),
              ],
            ),
          ] else if (quote != null && quote.valid) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Row(
              children: <Widget>[
                Icon(Icons.check_circle_rounded,
                    size: 14, color: DeliveryAccent.positive.color),
                const SizedBox(width: DeliverySpacing.xs),
                Expanded(
                  child: Text(
                    '${quote.code ?? _promo.text.trim()} · -${_promoDiscount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DeliveryAccent.positive.color,
                      height: 1.3,
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: t.custPromoRemove,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                    onTap: _removePromo,
                    child: const Padding(
                      padding: EdgeInsetsDirectional.all(DeliverySpacing.xs),
                      child: Icon(Icons.close_rounded,
                          size: 14, color: DeliveryColors.faint),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (quote != null && !quote.valid) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Text(
              custPromoReasonLabel(t, quote.reason),
              style: TextStyle(
                fontSize: 12,
                color: DeliveryAccent.critical.color,
                height: 1.35,
              ),
            ),
          ] else if (_quoteFailed) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Text(
              // The server was not reached — a different fact from a refused code, and the Apply
              // button is the retry.
              t.promoCouldNotCheck,
              style: TextStyle(
                fontSize: 12,
                color: DeliveryAccent.critical.color,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The geometry the frame draws for the promo row: the bordered white field with the tag glyph,
  /// then the tinted Apply button.
  Widget _promoRowShell(DeliveryStrings t,
      {required Widget field, required VoidCallback? onApply}) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Container(
            padding:
                const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
            decoration: BoxDecoration(
              color: DeliveryColors.white,
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
              border: Border.all(color: DeliveryColors.border),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.sell_outlined, size: 18, color: DeliveryColors.faint),
                const SizedBox(width: DeliverySpacing.sm),
                Expanded(child: field),
              ],
            ),
          ),
        ),
        const SizedBox(width: DeliverySpacing.md - 4),
        Semantics(
          button: onApply != null,
          child: InkWell(
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
            onTap: onApply,
            child: Container(
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
          ),
        ),
      ],
    );
  }

  /// The money, itemised.
  ///
  /// The delivery fee is shown as its own line rather than folded into one number, because a
  /// customer comparing shops is comparing exactly that split — and because a total that silently
  /// grew between the shelf and the basket is the classic reason a basket gets abandoned.
  Widget _summary(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final StoreCard? store = widget.cart.store;
    final bool blocked = !widget.cart.meetsMinimum;
    final double promoDiscount = _promoDiscount;
    final double payable =
        (widget.cart.total - promoDiscount).clamp(0, double.infinity).toDouble();

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
            _summaryRow(t.subtotal, widget.cart.subtotal.toStringAsFixed(2)),
            if (store != null) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              _summaryRow(
                t.delivery,
                // What will be CHARGED. Adding the shop's fee to the subtotal here, when the
                // platform is absorbing it, quoted the customer a total the server would not bill.
                // "Free" is the thing worth reading; 0.00 makes the eye do arithmetic.
                widget.cart.deliveryFeeCharged == 0
                    ? t.free
                    : widget.cart.deliveryFeeCharged.toStringAsFixed(2),
              ),
              // The discounts line, and only when there is a real discount to put on it. Names the
              // promotion underneath: a customer who is not told why their delivery was free has
              // been given something that changes nothing about what they do next.
              if (widget.cart.deliveryIsFree) ...<Widget>[
                const SizedBox(height: DeliverySpacing.sm),
                _summaryRow(
                  t.custDiscounts,
                  '-${widget.cart.deliveryFee.toStringAsFixed(2)}',
                  valueColor: DeliveryAccent.positive.color,
                ),
                const SizedBox(height: DeliverySpacing.xs),
                Row(
                  children: <Widget>[
                    const Icon(Icons.redeem_outlined, size: 14, color: DeliveryColors.brand),
                    const SizedBox(width: DeliverySpacing.xs),
                    Expanded(
                      child: Text(
                        widget.cart.waiver?.offerTitle ?? t.freeDelivery,
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
            // The promo code's own line, under the code the server recognised. Advisory: what is
            // billed is recomputed at placement, and the confirmation shows the server's total.
            if (promoDiscount > 0) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              _summaryRow(
                _quote?.code ?? t.custPromoCode,
                '-${promoDiscount.toStringAsFixed(2)}',
                valueColor: DeliveryAccent.positive.color,
              ),
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
                  payable.toStringAsFixed(2),
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
                        widget.cart.amountBelowMinimum.toStringAsFixed(2),
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
