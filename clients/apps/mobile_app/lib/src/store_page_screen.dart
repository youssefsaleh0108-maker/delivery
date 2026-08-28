import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'cart.dart';
import 'product_detail_screen.dart';
import 'product_options_sheet.dart';
import 'store_state_mapping.dart';

/// A store's landing page: Shop, Aisles, Offers, Buy Again.
///
/// The four tabs are four different questions — what does this place sell, how is it organised,
/// what is cheap right now, and what did I get last time. A single scrolling menu answers only the
/// first, which is fine for a restaurant with twelve dishes and useless for a supermarket.
///
/// Drawn to `customer-shop` (Figma 3:224): a 200px cover with three glass controls floating on it,
/// the three-stat strip under it, the underlined tab bar, and then the menu as full-width rows.
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
  late final TabController _tabs = TabController(length: 4, vsync: this)
    ..addListener(_rebuild);

  Store? _store;
  List<Aisle> _aisles = <Aisle>[];
  List<Offer> _offers = <Offer>[];

  /// The in-shop search the hero's magnifier opens. Null when the field is closed; the shelf query
  /// carries it, so this searches the whole catalogue of the shop rather than the loaded pages.
  String? _search;
  final TextEditingController _searchController = TextEditingController();
  bool _searchOpen = false;
  Timer? _searchDebounce;

  /// The shelf, a page at a time. A supermarket has thousands of lines; fetching them all to render
  /// the first dozen rows is the single biggest avoidable payload in the app.
  late final PagedList<Product> _products = PagedList<Product>(
    pageSize: 20,
    fetch: (int page, int size) => widget.storeApi.products(
      widget.storeId,
      categoryId: _selectedAisle,
      search: _search,
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
    _searchDebounce?.cancel();
    _searchController.dispose();
    _tabs.removeListener(_rebuild);
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

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _search = value.trim().isEmpty ? null : value.trim());
      _products.refresh();
    });
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen && _search != null) {
        _search = null;
        _searchController.clear();
        _products.refresh();
      }
    });
    // Searching is a question about the shelf, so it takes the reader there.
    if (_searchOpen) _tabs.animateTo(0);
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
    await _openDetail(product, groups);
  }

  /// The full product screen the redesign promotes the options sheet into.
  Future<void> _openDetail(Product product, List<OptionGroup> groups) async {
    final ConfiguredProduct? configured = await showProductDetail(
      context,
      api: widget.storeApi,
      product: product,
      groups: groups,
    );
    if (configured != null) {
      widget.cart.addConfigured(configured, from: _card);
    }
  }

  /// Opening a row rather than its add button: the detail screen is the frame's own destination
  /// for a product, options or not.
  Future<void> _openProduct(Product product) async {
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
        _optionGroups[product.id] = const <OptionGroup>[];
        groups = const <OptionGroup>[];
      }
    }
    if (!mounted) return;
    await _openDetail(product, groups);
  }

  /// The one-store rule, explained at the moment of the tap rather than as a 422 at checkout.
  Future<void> _askToSwitchStore(Product product) async {
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: DeliveryColors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
        title: Text(DeliveryStrings.of(context).startNewBasket,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: DeliveryColors.ink)),
        content: Text(
          '${DeliveryStrings.of(context).basketFromShopReplace(widget.cart.store?.name ?? '')} '
          '${DeliveryStrings.of(context).basketFromAnotherShopSingle}',
          style: const TextStyle(fontSize: 14, color: DeliveryColors.muted, height: 1.4),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(foregroundColor: DeliveryColors.muted),
              child: Text(DeliveryStrings.of(context).keepIt)),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: DeliveryColors.brand,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(DeliveryRadius.md)),
            ),
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

  // ------------------------------------------------------------------------------------- layout

  static const double _gutter = DeliverySpacing.lg;
  static const double _heroHeight = 200;

  @override
  Widget build(BuildContext context) {
    if (_loading && widget.preview == null) {
      return const Scaffold(
        backgroundColor: DeliveryColors.background,
        body: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
      );
    }
    if (_error != null && _store == null) {
      final DeliveryStrings t = DeliveryStrings.of(context);
      return Scaffold(
        backgroundColor: DeliveryColors.background,
        appBar: YdScreenHeader(
          title: t.couldNotLoadShop,
          onBack: () => Navigator.of(context).maybePop(),
          backSemanticLabel: t.back,
        ),
        body: YdEmptyState(
          icon: Icons.cloud_off,
          title: t.couldNotLoadShop,
          action: YdPillButton(
            label: t.tryAgain,
            onPressed: _load,
            size: YdPillButtonSize.compact,
            expand: false,
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
            _hero(),
            SliverToBoxAdapter(child: _statStrip()),
            if (_searchOpen) SliverToBoxAdapter(child: _searchBar()),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabsHeader(child: _categoryTabs(), height: _tabsHeight),
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
                label: DeliveryStrings.of(context).viewBasket,
                blockedReason: widget.cart.meetsMinimum
                    ? null
                    : DeliveryStrings.of(context).addToReachMinimumShort(
                        widget.cart.amountBelowMinimum.toStringAsFixed(2)),
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
    );
  }

  /// The 200px cover: the photo, a 40% scrim so white type survives it, three glass controls, and
  /// the shop's name pinned to the bottom.
  Widget _hero() {
    final StoreCard card = _card;
    final Store? store = _store;
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool favorite = store?.favorite ?? false;
    final bool rtl = Directionality.of(context) == TextDirection.rtl;

    return SliverAppBar(
      expandedHeight: _heroHeight,
      pinned: true,
      backgroundColor: DeliveryColors.brand,
      foregroundColor: DeliveryColors.white,
      elevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: _gutter),
        child: Row(
          children: <Widget>[
            GlassCircleButton(
              icon: rtl ? Icons.chevron_right : Icons.chevron_left,
              semanticLabel: t.back,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const Spacer(),
            GlassCircleButton(
              icon: _searchOpen ? Icons.close : Icons.search,
              semanticLabel: t.custSearchInShop,
              onPressed: _toggleSearch,
            ),
            const SizedBox(width: DeliverySpacing.sm),
            GlassCircleButton(
              icon: favorite ? Icons.favorite : Icons.favorite_border,
              semanticLabel: favorite ? t.removeFromFavourites : t.addToFavourites,
              onPressed: _toggleFavorite,
            ),
          ],
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            CustomerPhoto(
              // The full-size cover, deliberately. This is a hero — full-bleed behind the header —
              // and the one place on the shop page where the whole photo is worth its bytes.
              url: card.coverUrl,
              height: _heroHeight,
              icon: iconForVertical(card.vertical),
            ),
            // Keeps the white title legible over whatever the cover happens to be.
            DecoratedBox(
              decoration: BoxDecoration(color: DeliveryColors.ink.withValues(alpha: 0.4)),
            ),
            PositionedDirectional(
              start: _gutter,
              end: _gutter,
              bottom: _gutter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    card.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: DeliveryColors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: DeliverySpacing.xs),
                  Text(
                    _tagLine(card, store),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: DeliveryColors.white.withValues(alpha: 0.82),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Italian • Gourmet Burgers • Pizza" — the shop's own tags, with its closing time appended
  /// when it has one, because that is the fact a customer needs before they start filling a basket.
  String _tagLine(StoreCard card, Store? store) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return <String>[
      if (card.tags.isNotEmpty) card.tags.join(' • '),
      if (card.tags.isEmpty && card.tagline != null) card.tagline!,
      if (store?.closesAtLabel != null) t.closesAtLabel(store!.closesAtLabel!),
    ].join(' • ');
  }

  /// The three-stat strip: rating, delivery time, minimum order, hairline-separated.
  Widget _statStrip() {
    final StoreCard card = _card;
    final DeliveryStrings t = DeliveryStrings.of(context);
    final DeliveryStoreState state = storeStateOf(card.availability);

    return Container(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.lg - DeliverySpacing.xs),
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Expanded(
                child: _stat(
                  value: card.rating?.toStringAsFixed(1) ?? t.ratingNew,
                  caption: t.custRatingsCount(card.ratingCount),
                  leading: card.rating == null
                      ? null
                      : Icon(Icons.star_rounded,
                          size: 14, color: DeliveryAccent.caution.color),
                ),
              ),
              const _StatDivider(),
              Expanded(child: _stat(value: card.etaLabel, caption: t.custDeliveryTime)),
              const _StatDivider(),
              Expanded(
                child: _stat(
                  value: card.minOrder > 0 ? card.minOrder.toStringAsFixed(2) : t.free,
                  caption: t.custMinOrderStat,
                ),
              ),
            ],
          ),
          // A shop that is not open is the one thing on this strip that changes what happens next.
          if (state != DeliveryStoreState.open) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            StoreStatePill(state: state),
          ],
        ],
      ),
    );
  }

  Widget _stat({required String value, required String caption, Widget? leading}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (leading != null) ...<Widget>[
              leading,
              const SizedBox(width: DeliverySpacing.xs),
            ],
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.ink,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: DeliveryColors.faint, height: 1.2),
        ),
      ],
    );
  }

  Widget _searchBar() {
    return Container(
      color: DeliveryColors.white,
      padding: const EdgeInsetsDirectional.fromSTEB(
          _gutter, DeliverySpacing.md - 4, _gutter, DeliverySpacing.md - 4),
      child: YdSearchField(
        controller: _searchController,
        autofocus: true,
        hintText: DeliveryStrings.of(context).custShopSearchHint,
        onChanged: _onSearchChanged,
        searchSemanticLabel: DeliveryStrings.of(context).custSearchInShop,
      ),
    );
  }

  /// 12px padding, a 14px label, the 8px gap and the 3px bar — the frame's `category-tabs`.
  static const double _tabsHeight = 52;

  /// The design's underlined text tabs. Built by hand rather than through [TabBar] so the
  /// indicator is the drawn 24x3 bar rather than a full-width label underline.
  Widget _categoryTabs() {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<String> labels = <String>[
      t.tabShop,
      t.tabAislesCount(_aisles.length),
      t.tabOffersCount(_offers.length),
      t.tabBuyAgain,
    ];

    return Container(
      height: _tabsHeight,
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.fromSTEB(_gutter, 0, DeliverySpacing.md, 0),
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: DeliverySpacing.lg - DeliverySpacing.xs),
        itemBuilder: (BuildContext context, int i) {
          final bool active = _tabs.index == i;
          return Semantics(
            button: true,
            selected: active,
            child: InkWell(
              onTap: () => _tabs.animateTo(i),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: active ? DeliveryColors.brand : DeliveryColors.muted,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: DeliverySpacing.sm),
                  Container(
                    width: 24,
                    height: 3,
                    decoration: BoxDecoration(
                      color: active ? DeliveryColors.brand : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _shopTab() {
    if (_products.isEmpty && _search == null && _selectedAisle == null) {
      return _empty(Icons.inventory_2_outlined, DeliveryStrings.of(context).nothingOnShelves);
    }
    return Column(
      children: <Widget>[
        if (_aisles.isNotEmpty)
          Container(
            color: DeliveryColors.white,
            child: SizedBox(
              height: YdChip.minHeight + DeliverySpacing.lg,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsetsDirectional.fromSTEB(
                    _gutter, DeliverySpacing.md - 4, DeliverySpacing.md, DeliverySpacing.md - 4),
                children: <Widget>[
                  YdChip(
                    label: DeliveryStrings.of(context).everything,
                    selected: _selectedAisle == null,
                    onTap: () => _selectAisle(null),
                  ),
                  for (final Aisle aisle in _aisles) ...<Widget>[
                    const SizedBox(width: DeliverySpacing.sm),
                    YdChip(
                      label: aisle.name,
                      selected: _selectedAisle == aisle.categoryId,
                      onTap: () => _selectAisle(aisle.categoryId),
                    ),
                  ],
                ],
              ),
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
        padding: const EdgeInsetsDirectional.fromSTEB(
            _gutter, _gutter, _gutter, DeliverySpacing.xxl),
        // One extra row for the footer: a spinner, a retry, or nothing.
        itemCount: products.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: DeliverySpacing.md),
        itemBuilder: (BuildContext context, int i) {
          if (i == products.length) {
            return _listFooter(list);
          }
          return _productRow(products[i]);
        },
      ),
    );
  }

  static const double _thumb = 80;

  /// `product-row`: an 80px square thumbnail, the name, the truncated description, and the price
  /// paired with the round add button.
  Widget _productRow(Product product) {
    final int inBasket = widget.cart.qtyOf(product.id);
    final String? description = product.description;

    return YdCard(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
      onTap: () => _openProduct(product),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          CustomerPhoto(
            // The 320px derivative, not the merchant's original. This row is the screen that was
            // measured: three photos at 631 KB, 575 KB and 410 KB, 2.0-2.9s each, all of them
            // arriving to fill an 80dp square. Falls back to the full-size URL by itself when a
            // product has no derivative.
            url: product.listImageUrl,
            width: _thumb,
            height: _thumb,
            radius: DeliveryRadius.md,
            icon: Icons.fastfood_outlined,
          ),
          const SizedBox(width: DeliverySpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
                if (description != null && description.isNotEmpty) ...<Widget>[
                  const SizedBox(height: DeliverySpacing.xs),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DeliveryColors.muted,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: DeliverySpacing.xs),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        product.price.toStringAsFixed(2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: DeliveryColors.brand,
                        ),
                      ),
                    ),
                    // How many are already in the basket, and the way back out again. The frame
                    // draws a bare add button; a shelf you can only add to is a shelf you have to
                    // leave to correct.
                    if (inBasket > 0) ...<Widget>[
                      Semantics(
                        button: true,
                        label: DeliveryStrings.of(context).remove,
                        child: InkResponse(
                          onTap: () => widget.cart.removeProduct(product.id),
                          radius: 18,
                          child: const Padding(
                            padding: EdgeInsetsDirectional.all(DeliverySpacing.xs),
                            child: Icon(Icons.remove_circle_outline,
                                size: 18, color: DeliveryColors.muted),
                          ),
                        ),
                      ),
                      const SizedBox(width: DeliverySpacing.xs),
                      Text(
                        '$inBasket',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: DeliveryColors.ink,
                        ),
                      ),
                      const SizedBox(width: DeliverySpacing.sm),
                    ],
                    AddButton(
                      onPressed: _acceptsOrders ? () => _add(product) : null,
                      semanticLabel: DeliveryStrings.of(context).add,
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
      padding: const EdgeInsetsDirectional.all(_gutter),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: DeliverySpacing.md - 4,
        crossAxisSpacing: DeliverySpacing.md - 4,
        mainAxisExtent: 92,
      ),
      itemCount: _aisles.length,
      itemBuilder: (BuildContext context, int i) {
        final Aisle aisle = _aisles[i];
        return YdCard.bordered(
          onTap: () {
            _selectAisle(aisle.categoryId);
            _tabs.animateTo(0);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                aisle.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    height: 1.25,
                    color: DeliveryColors.ink),
              ),
              Text(DeliveryStrings.of(context).itemCount(aisle.productCount),
                  style: const TextStyle(color: DeliveryColors.faint, fontSize: 11)),
            ],
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
      padding: const EdgeInsetsDirectional.all(_gutter),
      itemCount: _offers.length,
      separatorBuilder: (_, __) => const SizedBox(height: DeliverySpacing.md - 4),
      itemBuilder: (BuildContext context, int i) {
        final Offer offer = _offers[i];
        return YdCard(
          child: Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                    color: DeliveryColors.brandSoft, shape: BoxShape.circle),
                child: const Icon(Icons.local_offer_outlined,
                    color: DeliveryColors.brand, size: 18),
              ),
              const SizedBox(width: DeliverySpacing.md - 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(offer.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: DeliveryColors.ink)),
                    if (offer.subtitle != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(offer.subtitle!,
                          style: const TextStyle(
                              color: DeliveryColors.muted, fontSize: 12, height: 1.35)),
                    ],
                    if (offer.isPlatformWide) ...<Widget>[
                      const SizedBox(height: DeliverySpacing.xs),
                      Text(DeliveryStrings.of(context).appliesEverywhere,
                          style: const TextStyle(
                              color: DeliveryColors.brand,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              YdBadge.brand(label: offer.badgeLabel, uppercase: false, fontSize: 12),
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

  Widget _empty(IconData icon, String message) =>
      YdEmptyState(icon: icon, title: message, padding: const EdgeInsets.all(DeliverySpacing.xl));
}

/// The 32px hairline the design puts between the shop's three stats.
class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32, color: DeliveryColors.border);
  }
}

/// Keeps the tab bar pinned under the collapsing header.
class _TabsHeader extends SliverPersistentHeaderDelegate {
  _TabsHeader({required this.child, required this.height});

  final Widget child;
  final double height;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;

  @override
  bool shouldRebuild(_TabsHeader oldDelegate) =>
      oldDelegate.child != child || oldDelegate.height != height;
}
