import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'cart.dart';
import 'product_options_sheet.dart';
import 'store_state_mapping.dart';

/// A store's landing page: Shop, Aisles, Offers, Buy Again.
///
/// The four tabs are four different questions — what does this place sell, how is it organised,
/// what is cheap right now, and what did I get last time. A single scrolling menu answers only the
/// first, which is fine for a restaurant with twelve dishes and useless for a supermarket.
class StorePageScreen extends StatefulWidget {
  const StorePageScreen({
    super.key,
    required this.storeApi,
    required this.cart,
    required this.storeId,
    this.preview,
    this.orderApi,
  });

  final StoreApi storeApi;
  final Cart cart;
  final String storeId;

  /// The card the customer tapped. Lets the header render immediately instead of showing a spinner
  /// over information the previous screen already had.
  final StoreCard? preview;

  /// Optional: without it the Buy Again tab explains it has no history rather than failing.
  final OrderApi? orderApi;

  @override
  State<StorePageScreen> createState() => _StorePageScreenState();
}

class _StorePageScreenState extends State<StorePageScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  Store? _store;
  List<Aisle> _aisles = <Aisle>[];
  List<Offer> _offers = <Offer>[];

  /// The shelf, a page at a time. A supermarket has thousands of lines; fetching them all to render
  /// the first dozen rows is the single biggest avoidable payload in the app.
  late final PagedList<Product> _products = PagedList<Product>(
    pageSize: 20,
    fetch: (int page, int size) => widget.storeApi.products(
      widget.storeId,
      categoryId: _selectedAisle,
      page: page,
      size: size,
    ),
  );

  /// Buy Again is its own paged list rather than a filter over the shelf — it is driven by the
  /// customer's order history, which has nothing to do with which shelf pages happen to be loaded.
  PagedList<Product>? _buyAgain;

  String? _selectedAisle;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _products.addListener(_rebuild);
    _load();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.dispose();
    _products.removeListener(_rebuild);
    _products.dispose();
    _buyAgain?.removeListener(_rebuild);
    _buyAgain?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<Object?> results = await Future.wait(<Future<Object?>>[
        widget.storeApi.read(widget.storeId),
        _products.refresh(),
        widget.storeApi.aisles(widget.storeId),
        widget.storeApi.offers(widget.storeId, size: 20),
      ]);
      if (!mounted) return;
      setState(() {
        _store = results[0]! as Store;
        _aisles = results[2]! as List<Aisle>;
        _offers = (results[3]! as Paged<Offer>).content;
        _loading = false;
      });
      _loadBuyAgain();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Buy Again, derived from the customer's own order history.
  ///
  /// Nothing stores a "previously bought" list; it is reconstructed from past orders and then
  /// intersected with what this store currently sells. The intersection matters — offering a
  /// customer something the shop has since delisted is worse than not offering it at all.
  Future<void> _loadBuyAgain() async {
    final OrderApi? orders = widget.orderApi;
    if (orders == null) return;

    try {
      // One page of recent history, not all of it. Toters caps this at six months for the same
      // reason: nobody re-orders from three years ago, and reading it costs the same as reading
      // what they will.
      final Paged<DeliveryOrder> history = await orders.mine(size: 20);
      final List<String> boughtBefore = <String>{
        for (final DeliveryOrder order in history.content)
          for (final OrderLine line in order.items) line.productId,
      }.toList();
      if (!mounted) return;

      if (boughtBefore.isEmpty) {
        setState(() => _buyAgain = null);
        return;
      }

      // Re-read from the live catalog, restricted to those ids and this store. Anything since
      // archived simply does not come back, which is the correct outcome.
      final PagedList<Product> list = PagedList<Product>(
        pageSize: 20,
        fetch: (int page, int size) => widget.storeApi.products(
          widget.storeId,
          ids: boughtBefore,
          page: page,
          size: size,
        ),
      )..addListener(_rebuild);

      setState(() => _buyAgain = list);
      await list.refresh();
    } catch (_) {
      // A history that will not load is not a reason to break the store page.
      if (mounted) setState(() => _buyAgain = null);
    }
  }

  StoreCard get _card => _store?.toCard() ?? widget.preview!;

  bool get _acceptsOrders => _card.availability.acceptsOrders;

  /// Selecting an aisle re-queries rather than filtering what happens to be loaded — with paging,
  /// an in-memory filter would only ever search the pages already fetched.
  void _selectAisle(String? categoryId) {
    setState(() => _selectedAisle = categoryId);
    _products.refresh();
  }

  /// Cached per product so re-tapping Add does not re-fetch a menu that cannot have changed
  /// while this screen is open.
  final Map<String, List<OptionGroup>> _optionGroups = <String, List<OptionGroup>>{};

  /// Adds a product, asking its questions first if it has any.
  ///
  /// The options are fetched on demand rather than with the shelf: most products have none, and
  /// loading every product's option tree to render a list would undo the paging.
  Future<void> _add(Product product) async {
    if (widget.cart.conflictsWith(product)) {
      await _askToSwitchStore(product);
      return;
    }

    List<OptionGroup> groups = _optionGroups[product.id] ?? const <OptionGroup>[];
    if (!_optionGroups.containsKey(product.id)) {
      try {
        groups = await widget.storeApi.productOptions(product.id);
        _optionGroups[product.id] = groups;
      } catch (_) {
        // A menu that will not load must not block a product that probably has no options; the
        // server revalidates at checkout either way.
        _optionGroups[product.id] = const <OptionGroup>[];
        groups = const <OptionGroup>[];
      }
    }

    if (groups.isEmpty) {
      widget.cart.add(product, from: _card);
      return;
    }
    if (!mounted) return;
    final ConfiguredProduct? configured = await showProductOptionsSheet(
      context,
      api: widget.storeApi,
      product: product,
      groups: groups,
    );
    if (configured != null) {
      widget.cart.addConfigured(configured, from: _card);
    }
  }

  /// The one-store rule, explained at the moment of the tap rather than as a 422 at checkout.
  Future<void> _askToSwitchStore(Product product) async {
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(DeliveryStrings.of(context).startNewBasket),
        content: Text(
          '${DeliveryStrings.of(context).basketFromShopReplace(widget.cart.store?.name ?? '')} '
          '${DeliveryStrings.of(context).basketFromAnotherShopSingle}',
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(DeliveryStrings.of(context).keepIt)),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: DeliveryColors.brand),
            child: Text(DeliveryStrings.of(context).startHere),
          ),
        ],
      ),
    );
    if (discard == true) {
      widget.cart.switchTo(_card);
      widget.cart.add(product, from: _card);
    }
  }

  Future<void> _toggleFavorite() async {
    final Store? store = _store;
    if (store == null) return;
    final bool nowFavorite = !store.favorite;
    setState(() => _store = store.copyWith(favorite: nowFavorite));
    try {
      if (nowFavorite) {
        await widget.storeApi.star(store.id);
      } else {
        await widget.storeApi.unstar(store.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _store = store.copyWith(favorite: !nowFavorite));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && widget.preview == null) {
      return const Scaffold(
        backgroundColor: DeliveryColors.background,
        body: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
      );
    }
    if (_error != null && _store == null) {
      return Scaffold(
        appBar: AppBar(),
        backgroundColor: DeliveryColors.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(DeliverySpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.cloud_off_rounded, size: 40, color: DeliveryColors.muted),
                const SizedBox(height: DeliverySpacing.md),
                Text(DeliveryStrings.of(context).couldNotLoadShop,
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: DeliverySpacing.md),
                FilledButton(onPressed: _load, child: Text(DeliveryStrings.of(context).tryAgain)),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: AnimatedBuilder(
        animation: widget.cart,
        builder: (BuildContext context, _) => NestedScrollView(
          headerSliverBuilder: (BuildContext context, bool _) => <Widget>[
            _header(),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarHeader(
                TabBar(
                  controller: _tabs,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: DeliveryColors.brand,
                  unselectedLabelColor: DeliveryColors.muted,
                  indicatorColor: DeliveryColors.brand,
                  indicatorWeight: 3,
                  labelStyle:
                      const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  tabs: <Widget>[
                    Tab(text: DeliveryStrings.of(context).tabShop),
                    Tab(text: DeliveryStrings.of(context).tabAislesCount(_aisles.length)),
                    Tab(text: DeliveryStrings.of(context).tabOffersCount(_offers.length)),
                    Tab(text: DeliveryStrings.of(context).tabBuyAgain),
                  ],
                ),
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabs,
            children: <Widget>[
              _shopTab(),
              _aislesTab(),
              _offersTab(),
              _buyAgainTab(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: widget.cart.isEmpty
          ? null
          : AnimatedBuilder(
              animation: widget.cart,
              builder: (BuildContext context, _) => StickyBasketBar(
                itemCount: widget.cart.itemCount,
                total: widget.cart.subtotal.toStringAsFixed(2),
                blockedReason: widget.cart.meetsMinimum
                    ? null
                    : DeliveryStrings.of(context).addToReachMinimumShort(
                        widget.cart.amountBelowMinimum.toStringAsFixed(2)),
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
    );
  }

  Widget _header() {
    final StoreCard card = _card;
    final Store? store = _store;
    return SliverAppBar(
      expandedHeight: 232,
      pinned: true,
      backgroundColor: DeliveryColors.brand,
      foregroundColor: DeliveryColors.white,
      actions: <Widget>[
        IconButton(
          onPressed: _toggleFavorite,
          tooltip: (store?.favorite ?? false) ? DeliveryStrings.of(context).removeFromFavourites : DeliveryStrings.of(context).addToFavourites,
          icon: Icon(
            (store?.favorite ?? false)
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (card.coverUrl == null || card.coverUrl!.isEmpty)
              StoreMonogram(name: card.name, radius: 0)
            else
              Image.network(card.coverUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => StoreMonogram(name: card.name, radius: 0)),
            // Keeps the white title legible over whatever the cover happens to be.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Colors.black54, Colors.transparent, Colors.black87],
                  stops: <double>[0, 0.35, 1],
                ),
              ),
            ),
            Positioned(
              left: DeliverySpacing.md,
              right: DeliverySpacing.md,
              bottom: DeliverySpacing.md,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      StoreAvatar(name: card.name, logoUrl: card.logoUrl, size: 54),
                      const SizedBox(width: DeliverySpacing.sm + 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            StoreStatePill(state: storeStateOf(card.availability)),
                            const SizedBox(height: DeliverySpacing.xs + 2),
                            Text(
                              card.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: DeliveryColors.white,
                                fontSize: 23,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: DeliverySpacing.sm),
                  Text(
                    <String>[
                      if (card.tags.isNotEmpty) card.tags.join(' · '),
                      card.etaLabel,
                      card.feeLabel,
                      if (card.minOrder > 0)
                        DeliveryStrings.of(context)
                            .minOrderLabel(card.minOrder.toStringAsFixed(2)),
                      if (store?.closesAtLabel != null)
                        DeliveryStrings.of(context).closesAtLabel(store!.closesAtLabel!),
                    ].join('  •  '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12.5, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shopTab() {
    if (_products.isEmpty) {
      return _empty(Icons.inventory_2_outlined, DeliveryStrings.of(context).nothingOnShelves);
    }
    return Column(
      children: <Widget>[
        if (_aisles.isNotEmpty)
          Container(
            color: DeliveryColors.white,
            child: ChipStrip<String>(
              values: _aisles.map((Aisle a) => a.categoryId).toList(),
              labelOf: (String id) =>
                  _aisles.firstWhere((Aisle a) => a.categoryId == id).name,
              selected: _selectedAisle,
              allLabel: DeliveryStrings.of(context).everything,
              onSelected: _selectAisle,
            ),
          ),
        Expanded(child: _pagedProductList(_products)),
      ],
    );
  }

  /// A product list that pulls its next page as the customer nears the bottom.
  Widget _pagedProductList(PagedList<Product> list) {
    if (list.isLoadingFirstPage) {
      return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
    }
    if (list.isEmptyAfterLoad) {
      return _empty(Icons.search_off_rounded, DeliveryStrings.of(context).nothingInAisle);
    }
    final List<Product> products = list.items;
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (shouldLoadMore(notification.metrics)) {
          list.loadMore();
        }
        return false;
      },
      child: ListView.separated(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.xxl),
      // One extra row for the footer: a spinner, a retry, or nothing.
      itemCount: products.length + 1,
      separatorBuilder: (_, __) => const Divider(height: 1, color: DeliveryColors.border),
      itemBuilder: (BuildContext context, int i) {
        if (i == products.length) {
          return _listFooter(list);
        }
        final Product product = products[i];
        return ShelfProductTile(
          name: product.name,
          description: product.description,
          price: product.price.toStringAsFixed(2),
          imageUrl: product.imageUrls.isEmpty ? null : product.imageUrls.first,
          quantityInBasket: widget.cart.qtyOf(product.id),
          enabled: _acceptsOrders,
          onAdd: () => _add(product),
          onRemove: () => widget.cart.removeProduct(product.id),
        );
      },
      ),
    );
  }

  Widget _listFooter(PagedList<Product> list) {
    if (list.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(DeliverySpacing.lg),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: DeliveryColors.brand),
          ),
        ),
      );
    }
    // A page that failed after earlier ones loaded: keep what we have and offer another go.
    if (list.error != null && list.items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(DeliverySpacing.md),
        child: Center(
          child: TextButton.icon(
            onPressed: list.loadMore,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(DeliveryStrings.of(context).couldNotLoadMore),
            style: TextButton.styleFrom(foregroundColor: DeliveryColors.brand),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  /// The Aisles tab, as a grid of the categories this store actually stocks.
  Widget _aislesTab() {
    if (_aisles.isEmpty) {
      return _empty(Icons.grid_view_rounded, DeliveryStrings.of(context).noAislesYet);
    }
    return GridView.builder(
      padding: const EdgeInsets.all(DeliverySpacing.md),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: DeliverySpacing.sm + 4,
        crossAxisSpacing: DeliverySpacing.sm + 4,
        mainAxisExtent: 92,
      ),
      itemCount: _aisles.length,
      itemBuilder: (BuildContext context, int i) {
        final Aisle aisle = _aisles[i];
        return Material(
          color: DeliveryColors.white,
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
            onTap: () {
              _selectAisle(aisle.categoryId);
              _tabs.animateTo(0);
            },
            child: Container(
              padding: const EdgeInsets.all(DeliverySpacing.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(DeliveryRadius.md),
                border: Border.all(color: DeliveryColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    aisle.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14, height: 1.2),
                  ),
                  Text(DeliveryStrings.of(context).itemCount(aisle.productCount),
                      style: const TextStyle(
                          color: DeliveryColors.muted, fontSize: 12)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _offersTab() {
    if (_offers.isEmpty) {
      return _empty(Icons.local_offer_outlined, DeliveryStrings.of(context).noOffersHere);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(DeliverySpacing.md),
      itemCount: _offers.length,
      separatorBuilder: (_, __) => const SizedBox(height: DeliverySpacing.sm + 4),
      itemBuilder: (BuildContext context, int i) {
        final Offer offer = _offers[i];
        return Container(
          padding: const EdgeInsets.all(DeliverySpacing.md),
          decoration: BoxDecoration(
            color: DeliveryColors.white,
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
            border: Border.all(color: DeliveryColors.brandLine),
          ),
          child: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(DeliverySpacing.sm + 2),
                decoration: const BoxDecoration(
                    color: DeliveryColors.brandSoft, shape: BoxShape.circle),
                child: const Icon(Icons.local_offer_rounded,
                    color: DeliveryColors.brand, size: 20),
              ),
              const SizedBox(width: DeliverySpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(offer.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14.5)),
                    if (offer.subtitle != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(offer.subtitle!,
                          style: const TextStyle(
                              color: DeliveryColors.muted, fontSize: 12.5)),
                    ],
                    if (offer.isPlatformWide) ...<Widget>[
                      const SizedBox(height: DeliverySpacing.xs + 2),
                      Text(DeliveryStrings.of(context).appliesEverywhere,
                          style: TextStyle(
                              color: DeliveryColors.brand,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
              ),
              OfferBadge(label: offer.badgeLabel),
            ],
          ),
        );
      },
    );
  }

  Widget _buyAgainTab() {
    if (widget.orderApi == null) {
      return _empty(Icons.history_rounded, DeliveryStrings.of(context).signInPrompt);
    }
    final PagedList<Product>? list = _buyAgain;
    if (list == null || list.isEmptyAfterLoad) {
      return _empty(Icons.history_rounded, DeliveryStrings.of(context).noHistoryHere);
    }
    return _pagedProductList(list);
  }

  Widget _empty(IconData icon, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DeliverySpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(DeliverySpacing.md),
              decoration: const BoxDecoration(
                  color: DeliveryColors.brandSoft, shape: BoxShape.circle),
              child: Icon(icon, size: 28, color: DeliveryColors.brand),
            ),
            const SizedBox(height: DeliverySpacing.md),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: DeliveryColors.muted)),
          ],
        ),
      ),
    );
  }
}

/// Keeps the tab bar pinned under the collapsing header.
class _TabBarHeader extends SliverPersistentHeaderDelegate {
  _TabBarHeader(this.tabBar);

  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: DeliveryColors.white, child: tabBar);
  }

  @override
  bool shouldRebuild(_TabBarHeader oldDelegate) => oldDelegate.tabBar != tabBar;
}
