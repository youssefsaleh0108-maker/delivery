import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'cart.dart';
import 'product_detail_screen.dart' show CustomerPhoto;
import 'store_page_screen.dart';
import 'store_power_chip.dart';
import 'store_state_mapping.dart';

/// The category's own listing (Figma `customer-shops` 58:105): the vertical's name in the header,
/// the switch-chips under it, "Showing N shops" beside Sort / Filter, and then the shops as tall
/// photo cards — cover on top, name and rating, the line of facts, delivery time against the
/// minimum order.
///
/// Reached from the home screen's category cards. Same paged read the home grid uses, one page at
/// a time as the customer scrolls; switching chips resets to page zero of the new vertical.
class ShopsListingScreen extends StatefulWidget {
  const ShopsListingScreen({
    super.key,
    required this.storeApi,
    required this.orderApi,
    required this.cart,
    this.initialVertical,
    this.chips = const <CategoryChip>[],
  });

  final StoreApi storeApi;
  final OrderApi orderApi;
  final Cart cart;

  /// The category tapped on home. Null lists everything.
  final StoreVertical? initialVertical;

  /// The curated strip, passed through from home so this screen does not refetch it.
  final List<CategoryChip> chips;

  @override
  State<ShopsListingScreen> createState() => _ShopsListingScreenState();
}

class _ShopsListingScreenState extends State<ShopsListingScreen> {
  late StoreFilters _filters = StoreFilters(vertical: widget.initialVertical);
  bool _filtersOpen = false;

  late final PagedList<StoreCard> _stores = PagedList<StoreCard>(
    pageSize: 20,
    fetch: (int page, int size) =>
        widget.storeApi.browseWith(_filters, page: page, size: size),
  );

  @override
  void initState() {
    super.initState();
    _stores.addListener(_changed);
    _stores.refresh();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _stores.removeListener(_changed);
    _stores.dispose();
    super.dispose();
  }

  void _selectVertical(StoreVertical? vertical) {
    setState(() => _filters = vertical == null
        ? _filters.copyWith(clearVertical: true)
        : _filters.copyWith(vertical: vertical));
    _stores.refresh();
  }

  void _open(StoreCard store) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StorePageScreen(
        storeApi: widget.storeApi,
        orderApi: widget.orderApi,
        cart: widget.cart,
        storeId: store.id,
        preview: store,
      ),
    ));
  }

  List<StoreVertical> get _verticals => widget.chips.isEmpty
      ? StoreVertical.values
      : widget.chips.map((CategoryChip c) => c.vertical).toList();

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String title =
        _filters.vertical?.labelIn(t) ?? t.allStores;

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(
        title: title,
        onBack: () => Navigator.of(context).maybePop(),
        backSemanticLabel: t.back,
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          // depth 0 only — the chip rail below satisfies the near-the-end check at position
          // zero otherwise, exactly the home-screen bug this guard exists for.
          if (notification.depth == 0 &&
              shouldLoadMore(notification.metrics)) {
            _stores.loadMore();
          }
          return false;
        },
        child: RefreshIndicator(
          color: DeliveryColors.brand,
          onRefresh: _stores.refresh,
          child: CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(child: _chipRow(t)),
              SliverToBoxAdapter(child: _countRow(t)),
              if (_filtersOpen) SliverToBoxAdapter(child: _filterRow(t)),
              if (_stores.isLoadingFirstPage)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                      child:
                          CircularProgressIndicator(color: DeliveryColors.brand)),
                )
              else if (_stores.isEmptyAfterLoad)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: YdEmptyState(
                    icon: Icons.storefront_outlined,
                    title: t.noShopsMatch,
                    message: t.tryClearingAFilter,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                      DeliverySpacing.md, 0, DeliverySpacing.md, 0),
                  sliver: SliverList.separated(
                    itemCount: _stores.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: DeliverySpacing.md),
                    itemBuilder: (BuildContext context, int i) =>
                        _shopCard(t, _stores.items[i]),
                  ),
                ),
              SliverToBoxAdapter(child: _footer()),
              const SliverToBoxAdapter(
                  child: SizedBox(height: DeliverySpacing.lg)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipRow(DeliveryStrings t) {
    return SizedBox(
      height: YdChip.minHeight + DeliverySpacing.md,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.fromSTEB(
            DeliverySpacing.md, DeliverySpacing.sm, DeliverySpacing.md, 0),
        children: <Widget>[
          YdChip(
            label: t.allStores,
            selected: _filters.vertical == null,
            onTap: () => _selectVertical(null),
          ),
          for (final StoreVertical vertical in _verticals) ...<Widget>[
            const SizedBox(width: DeliverySpacing.sm),
            YdChip(
              label: vertical.labelIn(t),
              selected: _filters.vertical == vertical,
              onTap: () => _selectVertical(vertical),
            ),
          ],
        ],
      ),
    );
  }

  Widget _countRow(DeliveryStrings t) {
    final int count = _stores.totalElements ?? _stores.length;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
          DeliverySpacing.md, DeliverySpacing.sm, DeliverySpacing.md, DeliverySpacing.md),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              t.custShowingShops(count),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.muted,
                height: 1.3,
              ),
            ),
          ),
          Semantics(
            button: true,
            child: InkWell(
              onTap: () => setState(() => _filtersOpen = !_filtersOpen),
              borderRadius: BorderRadius.circular(DeliveryRadius.sm),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.tune,
                        size: 15, color: DeliveryColors.brand),
                    const SizedBox(width: 4),
                    Text(
                      t.custSortFilter,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.brand,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The same refine chips the home screen offers, behind the Sort / Filter control.
  Widget _filterRow(DeliveryStrings t) {
    return SizedBox(
      height: YdChip.minHeight + DeliverySpacing.md,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.fromSTEB(
            DeliverySpacing.md, 0, DeliverySpacing.md, DeliverySpacing.md),
        children: <Widget>[
          YdChip(
            label: t.filterUnder30,
            icon: Icons.bolt_outlined,
            selected: _filters.maxEtaMinutes != null,
            onTap: () {
              setState(() => _filters = _filters.maxEtaMinutes == null
                  ? _filters.copyWith(maxEtaMinutes: 30)
                  : _filters.copyWith(clearEta: true));
              _stores.refresh();
            },
          ),
          const SizedBox(width: DeliverySpacing.sm),
          YdChip(
            label: t.filterFreeDelivery,
            icon: Icons.two_wheeler_outlined,
            selected: _filters.maxDeliveryFee != null,
            onTap: () {
              setState(() => _filters = _filters.maxDeliveryFee == null
                  ? _filters.copyWith(maxDeliveryFee: 0)
                  : _filters.copyWith(clearFee: true));
              _stores.refresh();
            },
          ),
          const SizedBox(width: DeliverySpacing.sm),
          YdChip(
            label: t.filterHighlyRated,
            icon: Icons.star_outline_rounded,
            selected: _filters.minRating != null,
            onTap: () {
              setState(() => _filters = _filters.minRating == null
                  ? _filters.copyWith(minRating: 4.5)
                  : _filters.copyWith(clearRating: true));
              _stores.refresh();
            },
          ),
        ],
      ),
    );
  }

  /// One shop as the frame's tall card: the cover, then name against the rating, the vertical's
  /// own line, and the delivery time in positive green against the minimum order. A shop that
  /// declared itself DARK dims — visible, honest, and not pretending to cook.
  Widget _shopCard(DeliveryStrings t, StoreCard store) {
    final Widget card = _shopCardBody(t, store);
    return store.powerStatus == StorePowerStatus.dark
        ? Opacity(opacity: 0.55, child: card)
        : card;
  }

  Widget _shopCardBody(DeliveryStrings t, StoreCard store) {
    return YdCard(
      onTap: () => _open(store),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(DeliveryRadius.lg)),
            child: CustomerPhoto(
              url: store.listCoverUrl,
              height: 150,
              icon: iconForVertical(store.vertical),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        store.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: DeliveryColors.ink,
                          height: 1.25,
                        ),
                      ),
                    ),
                    if (store.powerStatus != StorePowerStatus.unknown) ...<Widget>[
                      const SizedBox(width: DeliverySpacing.sm),
                      StorePowerChip(status: store.powerStatus, compact: true),
                    ],
                    if (store.rating != null) ...<Widget>[
                      const SizedBox(width: DeliverySpacing.sm),
                      const Icon(Icons.star_rounded,
                          size: 16, color: DeliveryColors.brand),
                      const SizedBox(width: 2),
                      Text(
                        store.rating!.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: DeliveryColors.brand,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  store.tagline?.isNotEmpty == true
                      ? store.tagline!
                      : store.vertical.labelIn(t),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: DeliveryColors.muted,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: DeliverySpacing.sm),
                const Divider(height: 1, color: DeliveryColors.borderFaint),
                const SizedBox(height: DeliverySpacing.sm),
                Row(
                  children: <Widget>[
                    const Icon(Icons.schedule,
                        size: 14, color: DeliveryColors.faint),
                    const SizedBox(width: 4),
                    Text(
                      store.etaLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: DeliveryAccent.positive.color,
                        height: 1.2,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      t.custMinOrderLine(store.minOrder > 0
                          ? '\$${store.minOrder.toStringAsFixed(2)}'
                          : t.free),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DeliveryColors.muted,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    if (_stores.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(DeliverySpacing.md),
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: DeliveryColors.brand),
          ),
        ),
      );
    }
    if (_stores.error != null && _stores.length > 0) {
      final DeliveryStrings t = DeliveryStrings.of(context);
      return Padding(
        padding: const EdgeInsets.all(DeliverySpacing.md),
        child: Center(
          child: YdPillButton.secondary(
            label: t.tryAgain,
            expand: false,
            size: YdPillButtonSize.compact,
            onPressed: _stores.loadMore,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
