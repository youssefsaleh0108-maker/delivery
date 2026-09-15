import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import '../order_detail_screen.dart';
import 'service_offer_form_screen.dart';
import 'service_shop.dart';
import 'service_words.dart';

/// A services shop's offers — the Offers tab of the provider's shell: every offer the shop sells,
/// pauses or is still drafting, each a tap from its form.
///
/// The provider dashboard (126:51) draws the same rows as "Current offers"; this is that list whole,
/// with Add offer. An offer its provider archived is gone for good and is not listed; one YouDrop took
/// down stays, saying so and why ([svcListsOffer]).
class ServiceOffersScreen extends StatefulWidget {
  const ServiceOffersScreen({
    super.key,
    required this.api,
    required this.storeApi,
    this.zoneApi,
    this.storeId,
    this.pendingApproval = false,
    this.onBack,
  });

  final CatalogApi api;

  /// The shop itself — its category and pin — and each offer's option groups.
  final StoreApi storeApi;

  /// The shop's delivery areas, which decide whether an offer may be delivered. Null leaves that to
  /// the pin alone, and to the server.
  final DeliveryZoneApi? zoneApi;

  /// The services shop the shell resolved. Null reads the owner's services shop.
  final String? storeId;

  /// True while the application is still being decided: offers can be drafted, not published.
  final bool pendingApproval;

  /// Draws a back button that calls this, for a host that pushes the offers as a page. Null draws none,
  /// which is what a tab wants.
  final VoidCallback? onBack;

  @override
  State<ServiceOffersScreen> createState() => _ServiceOffersScreenState();
}

class _ServiceOffersScreenState extends State<ServiceOffersScreen> {
  Store? _shop;
  bool _noShop = false;
  List<Product> _offers = const <Product>[];
  bool? _reach;
  bool _loading = true;
  Object? _error;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ServiceOffersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storeId != widget.storeId) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Store? shop = await svcFindShop(widget.storeApi, widget.storeId);
      if (shop == null) {
        if (!mounted) return;
        setState(() {
          _shop = null;
          _noShop = true;
          _offers = const <Product>[];
          _loading = false;
        });
        return;
      }
      final Future<bool?> reach = svcDeliveryReach(shop, widget.zoneApi);
      final Paged<Product> page = await widget.api.myProducts(storeId: shop.id, size: 100);
      final bool? reaches = await reach;
      if (!mounted) return;
      setState(() {
        _shop = shop;
        _noShop = false;
        _offers = page.content.where(svcListsOffer).toList(growable: false);
        _reach = reaches;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _openForm([Product? existing]) async {
    final Store? shop = _shop;
    if (shop == null) return;
    await Navigator.of(context).push<Object?>(MaterialPageRoute<Object?>(
      builder: (_) => ServiceOfferFormScreen(
        api: widget.api,
        shop: shop,
        storeApi: widget.storeApi,
        deliveryReach: _reach,
        existing: existing,
        pendingApproval: widget.pendingApproval,
      ),
    ));
    // Whatever happened in the form — saved, published, paused, archived — the list reads it again.
    if (mounted) await _load();
  }

  Future<void> _toggle(Product offer) async {
    setState(() => _busyId = offer.id);
    final Product? moved = await svcToggleOffer(context, widget.api, offer, deliveryReach: _reach);
    if (!mounted) return;
    setState(() {
      _busyId = null;
      if (moved != null) {
        _offers = <Product>[
          for (final Product p in _offers)
            if (p.id != moved.id) p else if (svcListsOffer(moved)) moved,
        ];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return ColoredBox(
      color: DeliveryColors.background,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double side = constraints.maxWidth > merchantMaxContentWidth
              ? (constraints.maxWidth - merchantMaxContentWidth) / 2
              : 0;
          final EdgeInsets pad = EdgeInsets.fromLTRB(
            DeliverySpacing.md + side,
            DeliverySpacing.md,
            DeliverySpacing.md + side,
            DeliverySpacing.xl,
          );
          return RefreshIndicator(
            onRefresh: _load,
            color: DeliveryColors.brand,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: <Widget>[
                SliverToBoxAdapter(
                  child: MerchantScreenHeader(
                    title: t.svcOffersTitle,
                    subtitle: t.svcOffersSubtitle,
                    onBack: widget.onBack,
                    backSemanticLabel: widget.onBack == null ? null : t.back,
                    trailing: _shop == null
                        ? null
                        : YdPillButton(
                            label: t.svcAddOffer,
                            icon: Icons.add_rounded,
                            size: YdPillButtonSize.compact,
                            expand: false,
                            onPressed: () => _openForm(),
                          ),
                  ),
                ),
                if (widget.pendingApproval && _shop != null)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(pad.left, DeliverySpacing.md, pad.right, 0),
                    sliver: SliverToBoxAdapter(
                      child: SvcNotice(text: t.svcPublishAfterApproval),
                    ),
                  ),
                ..._body(t, pad),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _body(DeliveryStrings t, EdgeInsets pad) {
    final Widget? standIn = _standIn(t);
    if (standIn != null) {
      return <Widget>[SliverPadding(padding: pad, sliver: SliverToBoxAdapter(child: standIn))];
    }
    return <Widget>[
      SliverPadding(
        padding: pad,
        sliver: SliverList.separated(
          itemCount: _offers.length,
          separatorBuilder: (_, __) => const SizedBox(height: DeliverySpacing.sm),
          itemBuilder: (BuildContext context, int i) {
            final Product offer = _offers[i];
            return SvcOfferRow(
              offer: offer,
              busy: _busyId == offer.id,
              onTap: () => _openForm(offer),
              onToggle: _busyId == null ? () => _toggle(offer) : null,
            );
          },
        ),
      ),
    ];
  }

  Widget? _standIn(DeliveryStrings t) {
    if (_error != null) {
      return YdEmptyState(
        icon: Icons.cloud_off_rounded,
        title: t.svcOffersLoadFailed,
        message: t.thatDidNotGoThrough,
        action: YdPillButton.secondary(
          label: t.tryAgain,
          onPressed: _load,
          size: YdPillButtonSize.compact,
          expand: false,
        ),
      );
    }
    if (_loading && _offers.isEmpty && !_noShop) {
      return const Padding(
        padding: EdgeInsets.all(DeliverySpacing.xl),
        child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
      );
    }
    if (_noShop) {
      return YdEmptyState(
        icon: Icons.storefront_outlined,
        title: t.svcNoShopYet,
        message: t.svcNoShopYetBody,
      );
    }
    if (_offers.isEmpty) {
      return YdEmptyState(
        icon: Icons.design_services_outlined,
        title: t.svcNoOffersYet,
        message: t.svcNoOffersYetBody,
        action: YdPillButton(
          label: t.svcAddOffer,
          icon: Icons.add_rounded,
          size: YdPillButtonSize.compact,
          expand: false,
          onPressed: () => _openForm(),
        ),
      );
    }
    return null;
  }
}

/// One offer as the dashboard and the offers list draw it (126:51 "Current offers"): its name, how it
/// is sold, its price with the LBP beside it, its state, and Pause or Resume.
///
/// The frame's rows print no LBP, unlike every other price in the batch; the platform's rule is that
/// a dollar price carries its conversion, so these do too.
class SvcOfferRow extends StatelessWidget {
  const SvcOfferRow({
    super.key,
    required this.offer,
    this.onTap,
    this.onToggle,
    this.busy = false,
  });

  final Product offer;
  final VoidCallback? onTap;

  /// Pauses a live offer or resumes a paused one. Null draws no such control. A draft never has one,
  /// because a draft is published from its form, and nor does an offer YouDrop holds, which the server
  /// will neither pause nor resume.
  final VoidCallback? onToggle;

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String? pack = svcPackLine(offer.service, t);
    // A held offer's status reads archived, which its provider never chose: its chip names the hold.
    final bool held = offer.isTakenDown;
    final Widget? chip = held ? svcOfferTakenDownChip(t) : svcOfferStatusChip(offer.status, t);
    final String? heldBecause = held ? offer.moderation?.reason : null;
    final String? lbp = svcLbp(svcOfferAmount(offer), t);
    final bool toggles =
        !held && (offer.status == ProductStatus.active || offer.status == ProductStatus.paused);

    return YdCard.bordered(
      onTap: onTap,
      padding: const EdgeInsets.all(DeliverySpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  offer.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
                if (pack != null)
                  Text(pack, style: const TextStyle(fontSize: 11, color: DeliveryColors.muted)),
                const SizedBox(height: DeliverySpacing.xs + 2),
                Wrap(
                  spacing: DeliverySpacing.xs + 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(
                      svcOfferPrice(offer, t),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.brand,
                      ),
                    ),
                    if (lbp != null)
                      Text(lbp, style: const TextStyle(fontSize: 11, color: DeliveryColors.faint)),
                  ],
                ),
                if (heldBecause != null) ...<Widget>[
                  const SizedBox(height: DeliverySpacing.xs),
                  Text(
                    t.svcOfferTakenDownReason(heldBecause),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: DeliveryAccent.critical.onTint,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (chip != null) chip,
              if (toggles && (onToggle != null || busy))
                busy
                    ? const Padding(
                        padding: EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
                        child: SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: DeliveryColors.brand),
                        ),
                      )
                    : TextButton(
                        onPressed: onToggle,
                        child: Text(
                          offer.status == ProductStatus.active
                              ? t.svcPauseOffer
                              : t.svcResumeOffer,
                        ),
                      ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Taken down by YouDrop": the chip of an offer back office holds off sale, in the critical colours,
/// because until back office restores it nobody can order it.
Widget svcOfferTakenDownChip(DeliveryStrings t) => YdBadge(
      label: t.svcOfferTakenDown,
      color: DeliveryAccent.critical.onTint,
      background: DeliveryAccent.critical.tint,
      uppercase: false,
      fontSize: 10,
    );

/// A caution note across the page — the pending-approval banner's look.
class SvcNotice extends StatelessWidget {
  const SvcNotice({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
      decoration: BoxDecoration(
        color: DeliveryAccent.caution.tint,
        border: Border.all(color: DeliveryAccent.caution.color),
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 16, color: DeliveryAccent.caution.onTint),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: DeliveryAccent.caution.onTint,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
