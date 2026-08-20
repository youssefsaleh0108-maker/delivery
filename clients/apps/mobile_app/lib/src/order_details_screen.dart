import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'cart.dart';
import 'order_tracking_panel.dart';
import 'store_page_screen.dart';

/// One order, in full.
///
/// Laid out as three stacked cards, following the reference design: who it came from and what you
/// can do about it, what was in it, and what it cost. Each card answers one question, which is why
/// they are separated rather than run together as one long list.
///
/// Product thumbnails are resolved by re-reading the ordered products from the live catalog — the
/// order lines snapshot name and price at purchase time (correctly, those must not drift) but carry
/// no image reference. Anything since delisted simply renders without a picture.
class OrderDetailsScreen extends StatefulWidget {
  const OrderDetailsScreen({
    super.key,
    required this.orderApi,
    required this.storeApi,
    required this.cart,
    required this.orderId,
    this.preview,
  });

  final OrderApi orderApi;
  final StoreApi storeApi;
  final Cart cart;
  final String orderId;

  /// The row that was tapped, so the page renders immediately instead of flashing a spinner over
  /// information the list already had.
  final DeliveryOrder? preview;

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  DeliveryOrder? _order;
  Store? _store;

  /// productId -> first image URL, for the line thumbnails.
  Map<String, String> _thumbnails = <String, String>{};

  bool _loading = true;
  bool _reordering = false;

  @override
  void initState() {
    super.initState();
    _order = widget.preview;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final DeliveryOrder order = await widget.orderApi.read(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order;
        _loading = false;
      });
      // Both are decoration on top of an already-rendered page, so they load after rather than
      // holding it up, and a failure in either leaves the order itself perfectly readable.
      _loadStore(order);
      _loadThumbnails(order);
    } catch (_) {
      // The error state is the absence of an order, not a stored exception — nothing on this
      // screen distinguishes one failure from another, so keeping the object would be pretence.
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadStore(DeliveryOrder order) async {
    final String? storeId = order.storeId;
    if (storeId == null) return;
    try {
      final Store store = await widget.storeApi.read(storeId);
      if (mounted) setState(() => _store = store);
    } catch (_) {
      // The order carries storeName already; the logo is a nicety.
    }
  }

  Future<void> _loadThumbnails(DeliveryOrder order) async {
    final String? storeId = order.storeId;
    if (storeId == null || order.items.isEmpty) return;
    try {
      final Paged<Product> products = await widget.storeApi.products(
        storeId,
        ids: order.items.map((OrderLine l) => l.productId).toList(),
        size: order.items.length,
      );
      if (!mounted) return;
      setState(() {
        _thumbnails = <String, String>{
          for (final Product p in products.content)
            if (p.imageUrls.isNotEmpty) p.id: p.imageUrls.first,
        };
      });
    } catch (_) {
      // No thumbnails; the lines still render.
    }
  }

  /// Puts the whole order back in the basket.
  ///
  /// Re-read from the live catalog rather than reconstructed from the order lines: prices move, and
  /// a basket built from a months-old snapshot would show a total the server then refuses to match.
  /// Items no longer sold are reported rather than silently dropped.
  Future<void> _reorder() async {
    final DeliveryOrder order = _order!;
    final String? storeId = order.storeId;
    if (storeId == null) return;

    setState(() => _reordering = true);
    try {
      final Paged<Product> live = await widget.storeApi.products(
        storeId,
        ids: order.items.map((OrderLine l) => l.productId).toList(),
        size: order.items.length,
      );
      final Map<String, Product> byId = <String, Product>{
        for (final Product p in live.content) p.id: p,
      };

      // The catalog read is an async gap; everything below reads strings off this context.
      if (!mounted) return;
      if (byId.isEmpty) {
        _say(DeliveryStrings.of(context).nothingStillAvailable);
        return;
      }

      // Starting a fresh basket is the honest behaviour: the one-store rule means we would
      // otherwise have to silently discard whatever was already in it.
      if (widget.cart.isNotEmpty && widget.cart.storeId != storeId) {
        final bool? replace = await _confirmReplaceBasket();
        if (replace != true || !mounted) return;
      }
      widget.cart.switchTo(_store?.toCard() ??
          StoreCard(
            id: storeId,
            slug: '',
            name: order.storeName ?? DeliveryStrings.of(context).tabShop,
            vertical: StoreVertical.restaurant,
            availability: StoreAvailability.open,
          ));

      int added = 0;
      int missing = 0;
      for (final OrderLine line in order.items) {
        final Product? product = byId[line.productId];
        if (product == null) {
          missing++;
          continue;
        }
        for (int i = 0; i < line.qty; i++) {
          widget.cart.add(product);
        }
        added++;
      }

      if (!mounted) return;
      final DeliveryStrings t = DeliveryStrings.of(context);
      // The plural is the string table's job, not an inline ternary: Arabic has six forms and
      // "1 item / n items" cannot express them.
      _say(missing == 0 ? t.addedToBasket(added) : t.addedSomeMissing(added, missing));
    } catch (_) {
      _say(DeliveryStrings.of(context).couldNotReorder);
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  Future<bool?> _confirmReplaceBasket() {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(DeliveryStrings.of(context).replaceYourBasket),
        content: Text(
            '${DeliveryStrings.of(context).basketFromShopReplace(widget.cart.store?.name ?? '')} '
            '${DeliveryStrings.of(context).reorderWillReplace}'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(DeliveryStrings.of(context).keepIt)),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: DeliveryColors.brand),
            child: Text(DeliveryStrings.of(context).replace),
          ),
        ],
      ),
    );
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryOrder? order = _order;

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: AppBar(
        backgroundColor: DeliveryColors.white,
        surfaceTintColor: DeliveryColors.white,
        // Without this the icon and title inherit the theme's default and can come out pale on a
        // white bar.
        foregroundColor: DeliveryColors.ink,
        elevation: 0,
        // A back arrow, not the reference design's X. The X suits a modal that was raised over
        // something; this is pushed from the orders list, and "back" is what it actually does.
        leading: IconButton(
          tooltip: DeliveryStrings.of(context).back,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(DeliveryStrings.of(context).orderDetails,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 21)),
      ),
      body: order == null
          ? Center(
              child: _loading
                  ? const CircularProgressIndicator(color: DeliveryColors.brand)
                  : _errorState())
          : RefreshIndicator(
              color: DeliveryColors.brand,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(DeliverySpacing.md),
                children: <Widget>[
                  _headerCard(order),
                  const SizedBox(height: DeliverySpacing.md),
                  OrderTrackingPanel(api: widget.orderApi, order: order),
                  const SizedBox(height: DeliverySpacing.md),
                  _itemsCard(order),
                  const SizedBox(height: DeliverySpacing.md),
                  _totalsCard(order),
                  const SizedBox(height: DeliverySpacing.xl),
                ],
              ),
            ),
    );
  }

  // ------------------------------------------------------------------ card 1: who and what next

  Widget _headerCard(DeliveryOrder order) {
    return _card(
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(DeliverySpacing.md),
            child: Row(
              children: <Widget>[
                StoreAvatar(
                    name: order.storeName ?? DeliveryStrings.of(context).tabShop, logoUrl: _store?.logoUrl, size: 56),
                const SizedBox(width: DeliverySpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(order.storeName ?? DeliveryStrings.of(context).tabShop,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800, height: 1.25)),
                      const SizedBox(height: 2),
                      Text(_timestampLine(order),
                          style: const TextStyle(
                              fontSize: 13, color: DeliveryColors.muted, height: 1.3)),
                    ],
                  ),
                ),
                // Only offered when there is somewhere to go.
                if (order.storeId != null)
                  IconButton(
                    tooltip: DeliveryStrings.of(context)
                        .openStore(order.storeName ?? DeliveryStrings.of(context).tabShop),
                    icon: const Icon(Icons.chevron_right_rounded,
                        color: DeliveryColors.brand, size: 28),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => StorePageScreen(
                        storeApi: widget.storeApi,
                        orderApi: widget.orderApi,
                        cart: widget.cart,
                        storeId: order.storeId!,
                        preview: _store?.toCard(),
                      ),
                    )),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: DeliveryColors.border, indent: DeliverySpacing.md,
              endIndent: DeliverySpacing.md),
          Padding(
            padding: const EdgeInsets.all(DeliverySpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.place_outlined, color: DeliveryColors.muted, size: 22),
                const SizedBox(width: DeliverySpacing.sm + 2),
                Expanded(
                  child: Text(order.deliveryAddress,
                      style: const TextStyle(
                          fontSize: 14, color: DeliveryColors.ink, height: 1.35)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: DeliveryColors.border, indent: DeliverySpacing.md,
              endIndent: DeliverySpacing.md),
          Padding(
            padding: const EdgeInsets.all(DeliverySpacing.md),
            child: SizedBox(
              height: 48,
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _reordering || order.storeId == null ? null : _reorder,
                style: FilledButton.styleFrom(
                  backgroundColor: DeliveryColors.brand,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(DeliveryRadius.md)),
                ),
                icon: _reordering
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child:
                            CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.refresh_rounded, size: 20),
                label: Text(DeliveryStrings.of(context).reorder,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "Delivered on: Wednesday, 23 April, 09:42 PM", or the equivalent for whatever state it is in.
  String _timestampLine(DeliveryOrder order) {
    final DateTime? when = order.deliveredAt ?? order.placedAt;
    if (when == null) {
      return order.status.labelIn(DeliveryStrings.of(context));
    }
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String when12 = _formatWhen(context, when);
    return order.deliveredAt != null ? t.deliveredOn(when12) : t.placedOn(when12);
  }

  /// Formatted through `intl` against the active locale.
  ///
  /// This used to be hand-rolled from two const lists of English day and month names — one string,
  /// one place, no new dependency, and completely untranslatable. `intl` already ships with Flutter
  /// for the generated strings, so the dependency was never the cost it looked like, and it also
  /// brings the ordering and numerals Arabic actually uses rather than English ones rearranged.
  static String _formatWhen(BuildContext context, DateTime when) {
    final String locale = Localizations.localeOf(context).toLanguageTag();
    return DateFormat.yMMMEd(locale).add_jm().format(when);
  }

  // ------------------------------------------------------------------ card 2: what was in it

  Widget _itemsCard(DeliveryOrder order) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(DeliveryStrings.of(context).yourOrder,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: DeliverySpacing.sm + 4),
          _statusPill(order),
          const SizedBox(height: DeliverySpacing.md),
          for (int i = 0; i < order.items.length; i++) ...<Widget>[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: DeliverySpacing.sm + 4),
                child: Divider(height: 1, color: DeliveryColors.border),
              ),
            _line(order.items[i]),
          ],
        ],
      ),
    );
  }

  Widget _statusPill(DeliveryOrder order) {
    final Color colour = _statusColour(order.status);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: DeliverySpacing.md, vertical: DeliverySpacing.sm),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
      ),
      child: Text(order.status.labelIn(DeliveryStrings.of(context)),
          style: TextStyle(color: colour, fontWeight: FontWeight.w700, fontSize: 13.5)),
    );
  }

  static Color _statusColour(OrderStatus status) => switch (status.wire) {
        'DELIVERED' => const Color(0xFF2E7D32),
        'CANCELLED' => DeliveryColors.muted,
        _ => DeliveryColors.brand,
      };

  Widget _line(OrderLine line) {
    final String? thumbnail = _thumbnails[line.productId];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          child: SizedBox(
            width: 56,
            height: 56,
            child: thumbnail == null
                ? StoreMonogram(name: line.productName, radius: 0)
                : Image.network(thumbnail,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        StoreMonogram(name: line.productName, radius: 0)),
          ),
        ),
        const SizedBox(width: DeliverySpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(line.productName,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, height: 1.3)),
              const SizedBox(height: 2),
              // Quantity in brand red, as its own line — it is the number most often checked
              // against what actually turned up.
              Text('${line.qty}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: DeliveryColors.brand)),
              const SizedBox(height: 4),
              Text(DeliveryStrings.of(context).lineQtyPrice(line.qty, line.unitPrice.toStringAsFixed(2)),
                  style: const TextStyle(fontSize: 13, color: DeliveryColors.muted)),
            ],
          ),
        ),
        const SizedBox(width: DeliverySpacing.sm),
        Text(line.lineTotal.toStringAsFixed(2),
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: DeliveryColors.ink)),
      ],
    );
  }

  // ------------------------------------------------------------------ card 3: what it cost

  Widget _totalsCard(DeliveryOrder order) {
    return _card(
      child: Column(
        children: <Widget>[
          _money(DeliveryStrings.of(context).subtotal, order.goodsSubtotal),
          const SizedBox(height: DeliverySpacing.sm + 2),
          _money(
            DeliveryStrings.of(context).deliveryCharge,
            // What was CHARGED, not what it cost. Rendering the cost here against a total that
            // excludes it produced a receipt that did not add up: subtotal 15.00 + delivery 3.25
            // = total 15.00. The waived fee is still shown, as the word "free", below.
            order.deliveryFeeCharged,
            // The fee is set per shop, and a customer comparing two shops is comparing exactly
            // this line — so it says where it came from rather than appearing as a mystery.
            info: order.deliveryFeeWaived
                // Says why, and what it was worth. A customer who is not told they were given
                // something has not been given anything that changes what they do next.
                ? DeliveryStrings.of(context)
                    .deliveryWasFree(order.deliveryFee.toStringAsFixed(2))
                : DeliveryStrings.of(context).setByStoreCharged(order.storeName ?? ''),
            override: order.deliveryFeeCharged == 0 ? DeliveryStrings.of(context).free : null,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: DeliverySpacing.md),
            child: _DashedDivider(),
          ),
          _money(DeliveryStrings.of(context).total, order.totalAmount, emphasised: true),
          // How it is being paid, on the receipt rather than only at checkout: a customer opening
          // an order that has not arrived yet is often checking exactly whether they need cash
          // ready at the door.
          const SizedBox(height: DeliverySpacing.sm + 2),
          Row(
            children: <Widget>[
              const Icon(Icons.payments_outlined, size: 16, color: DeliveryColors.muted),
              const SizedBox(width: DeliverySpacing.xs + 2),
              Expanded(
                child: Text(
                  order.paymentMethod.labelIn(DeliveryStrings.of(context)),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: DeliveryColors.muted),
                ),
              ),
              Text(
                order.paymentStatus.labelIn(DeliveryStrings.of(context)),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: order.paymentStatus.isSettled
                      ? DeliveryAccent.positive.color
                      : DeliveryColors.muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _money(String label, double amount,
      {bool emphasised = false, String? override, String? info}) {
    final TextStyle style = TextStyle(
      fontSize: emphasised ? 19 : 14.5,
      fontWeight: emphasised ? FontWeight.w800 : FontWeight.w500,
      color: emphasised ? DeliveryColors.ink : DeliveryColors.muted,
    );
    return Row(
      children: <Widget>[
        Text(label, style: style),
        if (info != null) ...<Widget>[
          const SizedBox(width: DeliverySpacing.xs + 2),
          Tooltip(
            message: info,
            triggerMode: TooltipTriggerMode.tap,
            showDuration: const Duration(seconds: 4),
            child: const Icon(Icons.info_outline_rounded,
                size: 17, color: DeliveryColors.muted),
          ),
        ],
        const Spacer(),
        Text(override ?? amount.toStringAsFixed(2),
            style: style.copyWith(color: DeliveryColors.ink)),
      ],
    );
  }

  // ------------------------------------------------------------------ shell

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(DeliverySpacing.md),
      decoration: BoxDecoration(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
        boxShadow: DeliveryShadows.card,
      ),
      child: child,
    );
  }

  Widget _errorState() {
    return Padding(
      padding: const EdgeInsets.all(DeliverySpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.cloud_off_rounded, size: 40, color: DeliveryColors.muted),
          const SizedBox(height: DeliverySpacing.md),
          Text(DeliveryStrings.of(context).couldNotLoadOrder,
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: DeliverySpacing.md),
          FilledButton(onPressed: _load, child: Text(DeliveryStrings.of(context).tryAgain)),
        ],
      ),
    );
  }
}

/// The dashed rule above the total, as in the reference design. Painted rather than assembled from
/// widgets so it adapts to any width without a layout pass per dash.
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(double.infinity, 1), painter: _DashedPainter());
}

class _DashedPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = DeliveryColors.border
      ..strokeWidth = 1;
    const double dash = 5;
    const double gap = 4;
    for (double x = 0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, 0), Offset((x + dash).clamp(0, size.width), 0), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedPainter oldDelegate) => false;
}
