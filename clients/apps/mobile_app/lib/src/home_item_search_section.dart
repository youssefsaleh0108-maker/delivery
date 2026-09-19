import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'basket_add.dart';
import 'cart.dart';
import 'delivery_address.dart';
import 'item_search_screen.dart';
import 'item_search_widgets.dart';

/// Home's "Items in shops near you": what the search box found on shop shelves, above the shop grid
/// that answers the same words with shop names.
///
/// Drawn once the search reaches [ItemSearchQuery.minLength] characters: the first three shops that
/// sell a match, each with its best two items and an Add, then "See all items", which opens
/// [ItemSearchScreen] on the same words. "See all items" is drawn only when there is more than this
/// shows: another shop, or a match this card leaves out.
///
/// Never in the way: while the app knows it is offline, and whenever the search fails, the section is
/// not drawn at all, and the shop grid under it carries on as it always did. It follows the words
/// Home has already debounced, and the pin on the customer's selected address, which travels in the
/// request body.
class HomeItemSearchSection extends StatefulWidget {
  const HomeItemSearchSection({
    super.key,
    required this.query,
    required this.storeApi,
    required this.cart,
    required this.addresses,
    required this.onOpenBasket,
    required this.onOpenShop,
    this.orderApi,
    this.onFavoriteChanged,
    this.connectivity,
  });

  /// What the customer typed, trimmed and debounced by Home; null when the box is empty.
  final String? query;

  final StoreApi storeApi;
  final Cart cart;
  final DeliveryAddressStore addresses;

  /// The shell's way to its Basket tab. See [StorePageScreen.onOpenBasket].
  final VoidCallback onOpenBasket;

  /// Opens a shop the way Home opens one from its grid, so the heart there reaches Home's lists.
  final void Function(StoreCard store) onOpenShop;

  /// For the results screen's shop pages: Buy Again, and the heart. See [ItemSearchScreen].
  final OrderApi? orderApi;
  final void Function(StoreCard store)? onFavoriteChanged;

  /// Whether YouDrop can be reached ([ConnectivityService]). Null is always online.
  final ValueListenable<bool>? connectivity;

  /// Home shows the first three shops, and two items of each.
  static const int shops = 3;
  static const int itemsPerShop = 2;

  @override
  State<HomeItemSearchSection> createState() => _HomeItemSearchSectionState();
}

class _HomeItemSearchSectionState extends State<HomeItemSearchSection> {
  late final BasketAdd _basket = BasketAdd(
      storeApi: widget.storeApi, cart: widget.cart, onOpenBasket: widget.onOpenBasket);

  /// The query the answer below is for; null when there is nothing to search.
  ItemSearchQuery? _asked;
  ItemSearchPage? _page;
  bool _failed = false;

  /// Bumped on every search, so an answer to words the customer has since changed is dropped.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.connectivity?.addListener(_onConnectivity);
    widget.addresses.addListener(_onAddress);
    _search();
  }

  @override
  void didUpdateWidget(HomeItemSearchSection old) {
    super.didUpdateWidget(old);
    if (old.connectivity != widget.connectivity) {
      old.connectivity?.removeListener(_onConnectivity);
      widget.connectivity?.addListener(_onConnectivity);
    }
    if (old.addresses != widget.addresses) {
      old.addresses.removeListener(_onAddress);
      widget.addresses.addListener(_onAddress);
    }
    if (old.query != widget.query) _search();
  }

  @override
  void dispose() {
    widget.connectivity?.removeListener(_onConnectivity);
    widget.addresses.removeListener(_onAddress);
    super.dispose();
  }

  bool get _online => widget.connectivity?.value ?? true;

  /// Back online: a search that could not run, or failed, is asked again.
  void _onConnectivity() {
    if (!mounted) return;
    if (_online && (_page == null || _failed)) {
      _search();
    } else {
      setState(() {});
    }
  }

  /// A different address is a different "near you".
  void _onAddress() {
    if (mounted) _search();
  }

  ItemSearchQuery? get _wanted {
    final String? words = widget.query?.trim();
    if (words == null || words.characters.length < ItemSearchQuery.minLength) return null;
    return ItemSearchQuery.text(words);
  }

  Future<void> _search() async {
    final int generation = ++_generation;
    final ItemSearchQuery? query = _wanted;
    setState(() {
      _asked = query;
      _page = null;
      _failed = false;
    });
    if (query == null || !_online) return;
    final DeliveryAddress? at = widget.addresses.selected;
    final bool pinned = at != null && at.hasPoint;
    try {
      final ItemSearchPage page = await widget.storeApi.searchItems(
        query,
        latitude: pinned ? at.latitude : null,
        longitude: pinned ? at.longitude : null,
        size: HomeItemSearchSection.shops,
      );
      if (!mounted || generation != _generation) return;
      setState(() => _page = page);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      // The section steps aside; the shop grid under it is unaffected.
      setState(() => _failed = true);
    }
  }

  /// Whether the results screen has more than this section shows.
  static bool _hasMore(ItemSearchPage page) =>
      page.totalElements > page.content.length ||
      page.content.length > HomeItemSearchSection.shops ||
      page.content.any((ItemSearchGroup g) => g.matchedInStore > HomeItemSearchSection.itemsPerShop);

  void _seeAll(ItemSearchQuery query) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (BuildContext _) => ItemSearchScreen(
        storeApi: widget.storeApi,
        orderApi: widget.orderApi,
        cart: widget.cart,
        addresses: widget.addresses,
        query: query,
        onOpenBasket: widget.onOpenBasket,
        onFavoriteChanged: widget.onFavoriteChanged,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ItemSearchQuery? query = _asked;
    if (query == null || !_online || _failed) {
      return const SizedBox.shrink();
    }
    final DeliveryStrings t = DeliveryStrings.of(context);
    final ItemSearchPage? page = _page;
    final bool nearby = page?.nearby ?? (widget.addresses.selected?.hasPoint ?? false);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
          DeliverySpacing.lg, DeliverySpacing.sm, DeliverySpacing.lg, DeliverySpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          YdSectionHeader(title: itemSearchTitle(t, nearby: nearby), fontSize: 18),
          const SizedBox(height: DeliverySpacing.md - 4),
          if (page == null)
            Semantics(
              label: t.isrchSearching,
              child: const Padding(
                padding: EdgeInsetsDirectional.symmetric(vertical: DeliverySpacing.sm),
                child: Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.brand),
                  ),
                ),
              ),
            )
          else if (page.content.isEmpty)
            Text(
              itemSearchEmptyTitle(t, query.label, nearby: nearby),
              style: const TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.35),
            )
          else
            AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[widget.cart, MarketRates.instance]),
              builder: (BuildContext context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final (int i, ItemSearchGroup group)
                      in page.content.take(HomeItemSearchSection.shops).indexed) ...<Widget>[
                    if (i > 0) const SizedBox(height: DeliverySpacing.md - 4),
                    ItemSearchGroupCard(
                      group: group,
                      nearby: nearby,
                      maxItems: HomeItemSearchSection.itemsPerShop,
                      cart: widget.cart,
                      onOpenShop: () => widget.onOpenShop(group.store),
                      onAdd: (Product product) => _basket.add(context, product, from: group.store),
                      onOpenProduct: (Product product) =>
                          _basket.open(context, product, from: group.store),
                    ),
                  ],
                ],
              ),
            ),
          if (page != null && page.content.isNotEmpty && _hasMore(page)) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - 4),
            YdPillButton.secondary(
              label: t.isrchSeeAll,
              size: YdPillButtonSize.compact,
              onPressed: () => _seeAll(query),
            ),
          ],
        ],
      ),
    );
  }
}
