import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'basket_add.dart';
import 'cart.dart';
import 'delivery_address.dart';
import 'item_search_widgets.dart';
import 'store_page_screen.dart';

/// Every shop that sells what the customer searched for, a page at a time: "See all items" from
/// Home's search.
///
/// Modelled on the Services tab's results ([ServiceSearchResultsScreen]): a header, a search field
/// with the words in it, and the answer under it. Each shop is an [ItemSearchGroupCard] with its best
/// three matches; "N more in this shop" opens the shop searched for the same words, which matches the
/// same way. Add works as on a shop's page ([BasketAdd]), and the basket bar appears once the basket
/// has something in it.
///
/// Around the pin on the customer's selected address, nearest first after the best match, within the
/// server's own radius. With no pin every live shop is searched, and one line says the list is not in
/// distance order. The pin travels in the request body, never in a URL ([StoreApi.searchItems]).
///
/// The words are the only thing this screen asks the server for, so the field is also where a later
/// search by photo will add its camera: [query] is an [ItemSearchQuery], which a photo's terms fill as
/// well as typed text does.
class ItemSearchScreen extends StatefulWidget {
  const ItemSearchScreen({
    super.key,
    required this.storeApi,
    required this.cart,
    required this.addresses,
    required this.query,
    required this.onOpenBasket,
    this.orderApi,
    this.onFavoriteChanged,
  });

  final StoreApi storeApi;
  final Cart cart;
  final DeliveryAddressStore addresses;
  final ItemSearchQuery query;

  /// The shell's way to its Basket tab, for the basket bar and the shop-limit dialog. See
  /// [StorePageScreen.onOpenBasket].
  final VoidCallback onOpenBasket;

  /// Handed to every shop page opened from here: its Buy Again tab reads it.
  final OrderApi? orderApi;

  /// Told when a shop's heart changes on a page opened from here, so Home's lists stay right.
  final void Function(StoreCard store)? onFavoriteChanged;

  @override
  State<ItemSearchScreen> createState() => _ItemSearchScreenState();
}

class _ItemSearchScreenState extends State<ItemSearchScreen> {
  late final TextEditingController _field = TextEditingController(text: widget.query.label);
  late ItemSearchQuery _query = widget.query;

  /// Whether the field holds something too short to search, so the screen asks for more instead.
  bool _tooShort = false;

  /// The last page's own account of itself: whether it was around a point, and whether it reached
  /// the server's ceiling. The list below keeps only the shops.
  ItemSearchPage? _lastPage;

  Timer? _debounce;

  late final BasketAdd _basket = BasketAdd(
      storeApi: widget.storeApi, cart: widget.cart, onOpenBasket: widget.onOpenBasket);

  late final PagedList<ItemSearchGroup> _groups = PagedList<ItemSearchGroup>(
    pageSize: 10,
    fetch: (int page, int size) async {
      final DeliveryAddress? at = widget.addresses.selected;
      final bool pinned = at != null && at.hasPoint;
      final ItemSearchPage answer = await widget.storeApi.searchItems(
        _query,
        latitude: pinned ? at.latitude : null,
        longitude: pinned ? at.longitude : null,
        page: page,
        size: size,
      );
      _lastPage = answer;
      return answer;
    },
  );

  @override
  void initState() {
    super.initState();
    _groups.addListener(_rebuild);
    _groups.refresh();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    _groups.removeListener(_rebuild);
    _groups.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// Whether the customer's address carries a pin, and so whether the search is around it.
  bool get _pinned => widget.addresses.selected?.hasPoint ?? false;

  /// Debounced like Home's search box: one question for the words, not one per keystroke.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _searchFor(value));
  }

  void _searchFor(String value) {
    final String words = value.trim();
    if (words.characters.length < ItemSearchQuery.minLength) {
      setState(() => _tooShort = true);
      return;
    }
    final ItemSearchQuery next = ItemSearchQuery.text(words);
    if (next == _query && !_tooShort) return;
    setState(() {
      _tooShort = false;
      _query = next;
      _lastPage = null;
    });
    _groups.refresh();
  }

  void _openShop(StoreCard store, {String? search}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (BuildContext _) => StorePageScreen(
        storeApi: widget.storeApi,
        orderApi: widget.orderApi,
        cart: widget.cart,
        storeId: store.id,
        preview: store,
        onFavoriteChanged: widget.onFavoriteChanged,
        onOpenBasket: widget.onOpenBasket,
        initialSearch: search,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool nearby = _lastPage?.nearby ?? _pinned;

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SafeArea(
            bottom: false,
            child: YdScreenHeader(
              title: itemSearchTitle(t, nearby: nearby),
              onBack: () => Navigator.of(context).maybePop(),
              backSemanticLabel: t.back,
            ),
          ),
          Container(
            color: DeliveryColors.white,
            padding: const EdgeInsetsDirectional.fromSTEB(
                DeliverySpacing.md, 0, DeliverySpacing.md, DeliverySpacing.md - 4),
            child: YdSearchField(
              controller: _field,
              hintText: t.isrchFieldHint,
              searchSemanticLabel: t.isrchFieldHint,
              onChanged: _onChanged,
              onSubmitted: (String value) {
                _debounce?.cancel();
                _searchFor(value);
              },
            ),
          ),
          if (!nearby)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                  DeliverySpacing.md, DeliverySpacing.md - 4, DeliverySpacing.md, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.location_off_outlined, size: 16, color: DeliveryColors.muted),
                  const SizedBox(width: DeliverySpacing.sm),
                  Expanded(
                    child: Text(
                      t.isrchNotByDistance,
                      style: const TextStyle(
                          fontSize: 12, color: DeliveryColors.muted, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: _body(t, nearby: nearby)),
        ],
      ),
      // The shop page's own bar and wiring: subscribed inside, so the bar arrives with the first
      // item rather than on the next unrelated rebuild (sticky_basket_bar_test.dart). No shortfall
      // advice: that belongs on the page of the shop it is about.
      bottomNavigationBar: AnimatedBuilder(
        animation: widget.cart,
        builder: (BuildContext context, _) => widget.cart.isEmpty
            ? const SizedBox.shrink()
            : StickyBasketBar(
                itemCount: widget.cart.itemCount,
                total: widget.cart.subtotal.toStringAsFixed(2),
                label: t.viewBasket,
                onTap: widget.onOpenBasket,
              ),
      ),
    );
  }

  Widget _body(DeliveryStrings t, {required bool nearby}) {
    if (_tooShort) {
      return YdEmptyState(icon: Icons.search_rounded, title: t.isrchTypeMore);
    }
    if (_groups.isLoadingFirstPage) {
      return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
    }
    // The server would not search these words as typed ("a.", six words): asking again gets the same
    // answer, so the screen says what to change and offers no retry.
    if (_groups.error case final ItemSearchRefusal refusal when _groups.isEmpty) {
      return YdEmptyState(icon: Icons.search_rounded, title: itemSearchRefusalText(t, refusal));
    }
    if (_groups.isEmpty && _groups.error != null) {
      return YdEmptyState(
        icon: Icons.cloud_off_rounded,
        title: t.isrchCouldNotSearch,
        action: YdPillButton(
          label: t.tryAgain,
          expand: false,
          size: YdPillButtonSize.compact,
          onPressed: _groups.refresh,
        ),
      );
    }
    if (_groups.isEmptyAfterLoad) {
      return YdEmptyState(
        icon: Icons.search_off_rounded,
        title: itemSearchEmptyTitle(t, _query.label, nearby: nearby),
        message: itemSearchTruncatedNote(t, _lastPage),
      );
    }
    final List<ItemSearchGroup> groups = _groups.items;
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (notification.depth == 0 && shouldLoadMore(notification.metrics)) {
          _groups.loadMore();
        }
        return false;
      },
      child: AnimatedBuilder(
        // The rows show how many of each product are in the basket, and the LBP line appears the
        // moment the platform's rate arrives.
        animation: Listenable.merge(<Listenable>[widget.cart, MarketRates.instance]),
        builder: (BuildContext context, _) => ListView.separated(
          padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
          itemCount: groups.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: DeliverySpacing.md - 4),
          itemBuilder: (BuildContext context, int i) {
            if (i == groups.length) return _footer();
            final ItemSearchGroup group = groups[i];
            return ItemSearchGroupCard(
              group: group,
              nearby: nearby,
              maxItems: 3,
              cart: widget.cart,
              onOpenShop: () => _openShop(group.store),
              onAdd: (Product product) => _basket.add(context, product, from: group.store),
              onOpenProduct: (Product product) =>
                  _basket.open(context, product, from: group.store),
              onMoreInShop: () => _openShop(group.store, search: _query.label),
            );
          },
        ),
      ),
    );
  }

  Widget _footer() {
    if (_groups.isLoadingMore) {
      return const Padding(
        padding: EdgeInsetsDirectional.all(DeliverySpacing.md),
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.brand),
          ),
        ),
      );
    }
    return const SizedBox(height: DeliverySpacing.md);
  }
}
