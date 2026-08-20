import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'address_sheet.dart';
import 'cart.dart';
import 'delivery_address.dart';
import 'notification_inbox.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';
import 'store_page_screen.dart';
import 'store_state_mapping.dart';

/// The customer home screen: shops first, products second.
///
/// The order of the page is the order the questions get asked. Which kind of thing do I want
/// (verticals), where have I been before (favourites), what is on offer, and only then the full
/// list. A flat A-Z of every shop answers none of those.
class StoreHomeScreen extends StatefulWidget {
  const StoreHomeScreen({
    super.key,
    required this.storeApi,
    required this.orderApi,
    required this.cart,
    required this.addresses,
    required this.zoneApi,
    required this.inbox,
    required this.locale,
    required this.session,
    required this.onSignOut,
  });

  final StoreApi storeApi;

  /// Threaded through to the store page purely so its Buy Again tab has a history to read.
  final OrderApi orderApi;
  final Cart cart;
  final DeliveryAddressStore addresses;

  /// Offered to the address sheet so a customer can say which area they are in.
  final DeliveryZoneApi zoneApi;

  /// Drives the bell badge in the app bar. Owned by the shell so the count stays right whichever
  /// tab is showing.
  final NotificationInbox inbox;

  /// Drives the language toggle. Switching rebuilds the whole app in the other direction.
  final LocaleController locale;
  final AuthSession session;
  final Future<void> Function() onSignOut;

  @override
  State<StoreHomeScreen> createState() => _StoreHomeScreenState();
}

class _StoreHomeScreenState extends State<StoreHomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  StoreFilters _filters = const StoreFilters();

  /// The main grid, loaded a page at a time as the customer scrolls. The rails above it are
  /// deliberately capped rather than paged — they are horizontal strips showing a handful of
  /// items, and a rail nobody can reach the end of does not need infinite scroll.
  late final PagedList<StoreCard> _stores = PagedList<StoreCard>(
    pageSize: 20,
    fetch: (int page, int size) => widget.storeApi.browseWith(_filters, page: page, size: size),
  );

  List<StoreCard> _favorites = <StoreCard>[];
  List<Offer> _platformOffers = <Offer>[];

  /// Designed banners from the Backoffice, and the category strip. Both are small curated lists —
  /// a rail nobody can reach the end of does not need paging.
  List<HomeBanner> _banners = <HomeBanner>[];
  List<CategoryChip> _chips = <CategoryChip>[];

  static const int _railPageSize = 10;

  bool _loadingRails = true;
  Object? _error;

  /// Debounces the search box. Typing "pizza" is five keystrokes and should not be five round
  /// trips, and the results of the first four are all stale by the time they land.
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _stores.addListener(_onStoresChanged);
    _load();
  }

  void _onStoresChanged() => setState(() {});

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    _stores.removeListener(_onStoresChanged);
    _stores.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loadingRails = true;
      _error = null;
    });
    try {
      // The grid and the two rails are independent reads, so they go together rather than one
      // after another. Each asks for one page — nothing here fetches a whole collection.
      //
      // Typed as Future<Object?> because the grid refresh completes with void while the rails
      // complete with a page; a homogeneous Future<Object> list will not accept the mix.
      final List<Object?> results = await Future.wait(<Future<Object?>>[
        _stores.refresh(),
        widget.storeApi.favorites(size: _railPageSize),
        widget.storeApi.platformOffers(size: _railPageSize),
        widget.storeApi.banners(),
        widget.storeApi.categoryChips(),
      ]);
      if (!mounted) return;
      setState(() {
        _favorites = (results[1]! as Paged<StoreCard>).content;
        _platformOffers = (results[2]! as Paged<Offer>).content;
        _banners = results[3]! as List<HomeBanner>;
        _chips = results[4]! as List<CategoryChip>;
        _loadingRails = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loadingRails = false;
      });
    }
  }

  /// Re-runs only the grid, for a filter or search change. The rails do not depend on the filters.
  Future<void> _reloadStoresOnly() => _stores.refresh();

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _filters = _filters.copyWith(
            search: value.trim().isEmpty ? null : value.trim(),
            clearSearch: value.trim().isEmpty,
          ));
      _reloadStoresOnly();
    });
  }

  void _selectVertical(StoreVertical? vertical) {
    setState(() => _filters = vertical == null
        ? _filters.copyWith(clearVertical: true)
        : _filters.copyWith(vertical: vertical));
    _reloadStoresOnly();
  }

  /// Optimistic: the star fills immediately and is put back if the call fails. Both endpoints are
  /// idempotent, so a double tap cannot desynchronise anything.
  Future<void> _toggleFavorite(StoreCard store) async {
    final bool nowFavorite = !store.favorite;
    _stores.replaceWhere(
        (StoreCard s) => s.id == store.id, store.copyWith(favorite: nowFavorite));
    setState(() {
      _favorites = nowFavorite
          ? <StoreCard>[store.copyWith(favorite: true), ..._favorites]
          : _favorites.where((StoreCard s) => s.id != store.id).toList();
    });

    try {
      if (nowFavorite) {
        await widget.storeApi.star(store.id);
      } else {
        await widget.storeApi.unstar(store.id);
      }
    } catch (_) {
      if (!mounted) return;
      _stores.replaceWhere(
          (StoreCard s) => s.id == store.id, store.copyWith(favorite: !nowFavorite));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DeliveryStrings.of(context).couldNotUpdateFavourites)),
      );
    }
  }

  void _openStore(StoreCard store) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (BuildContext _) => StorePageScreen(
        storeApi: widget.storeApi,
        orderApi: widget.orderApi,
        cart: widget.cart,
        storeId: store.id,
        preview: store,
      ),
    ));
  }

  /// The verticals to show as chips.
  ///
  /// Driven by the curated categories when there are any, falling back to the full enum — so the
  /// strip still works on a database where nobody has tagged a category yet.
  List<StoreVertical> get _chipVerticals => _chips.isEmpty
      ? StoreVertical.values
      : _chips.map((CategoryChip c) => c.vertical).toList();

  CategoryChip? _chipFor(StoreVertical vertical) {
    for (final CategoryChip c in _chips) {
      if (c.vertical == vertical) return c;
    }
    return null;
  }

  /// The curated name wins over the enum's built-in label: Food may be what the business calls
  /// what the code calls RESTAURANT.
  String _chipLabel(StoreVertical vertical) =>
      _chipFor(vertical)?.name ?? vertical.labelIn(DeliveryStrings.of(context));

  String? _chipImage(StoreVertical vertical) => _chipFor(vertical)?.imageUrl;

  /// Applied here rather than in the query: "has a promotion" is a property of the offers attached
  /// to a card, not a column the storefront query can filter on.
  List<StoreCard> get _visibleStores => _filters.offersOnly
      ? _stores.items.where((StoreCard s) => s.topOffer != null).toList()
      : _stores.items;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: RefreshIndicator(
        color: DeliveryColors.brand,
        onRefresh: _load,
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification notification) {
            if (shouldLoadMore(notification.metrics)) {
              // Guarded inside PagedList: a scroll fires this many times per second and only the
              // first one may start a request.
              _stores.loadMore();
            }
            return false;
          },
          child: CustomScrollView(
          controller: _scrollController,
          slivers: <Widget>[
            _appBar(),
            SliverToBoxAdapter(child: _searchField()),
            SliverToBoxAdapter(
              child: ChipStrip<StoreVertical>(
                values: _chipVerticals,
                labelOf: _chipLabel,
                iconOf: iconForVertical,
                imageOf: _chipImage,
                selected: _filters.vertical,
                allLabel: DeliveryStrings.of(context).all,
                // Picture above the label: on the home screen the artwork is what the eye
                // navigates by. The store page keeps pills, where the text is the choice.
                layout: ChipStripLayout.stacked,
                onSelected: _selectVertical,
              ),
            ),
            SliverToBoxAdapter(child: _filterBar()),
            if (_stores.isLoadingFirstPage || _loadingRails)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
              )
            else if (_error != null)
              SliverFillRemaining(hasScrollBody: false, child: _errorState())
            else ...<Widget>[
              // Banners sit above the offers rail: designed artwork the business chose to lead
              // with, ahead of the mechanical list of discounts.
              if (_banners.isNotEmpty) _bannerRail(),
              if (_platformOffers.isNotEmpty) _offersRail(),
              if (_favorites.isNotEmpty) ...<Widget>[
                SliverToBoxAdapter(
                  child: SectionHeader(title: DeliveryStrings.of(context).yourFavourites, subtitle: DeliveryStrings.of(context).starredShops),
                ),
                SliverToBoxAdapter(child: _favoritesRail()),
              ],
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: _filters.vertical?.labelIn(DeliveryStrings.of(context)) ?? DeliveryStrings.of(context).allStores,
                  // Plural-aware via ICU. Arabic has six plural categories, not two, so a
                  // `count == 1 ? 'shop' : 'shops'` ternary cannot be translated correctly.
                  subtitle: DeliveryStrings.of(context).shopsDelivering(_visibleStores.length),
                ),
              ),
              if (_visibleStores.isEmpty)
                SliverToBoxAdapter(child: _emptyState())
              else
                _storeGrid(),
              SliverToBoxAdapter(child: _gridFooter()),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: DeliverySpacing.xl)),
          ],
          ),
        ),
      ),
    );
  }

  /// What sits under the grid: a spinner while the next page loads, a retry if it failed, and
  /// nothing at all once everything has been seen.
  Widget _gridFooter() {
    if (_stores.isLoadingMore) {
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
    // A page that failed after some had already loaded: keep what we have and offer another go,
    // rather than replacing the list with an error.
    if (_stores.error != null && _stores.items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(DeliverySpacing.md),
        child: Center(
          child: TextButton.icon(
            onPressed: _stores.loadMore,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(DeliveryStrings.of(context).couldNotLoadMore),
            style: TextButton.styleFrom(foregroundColor: DeliveryColors.brand),
          ),
        ),
      );
    }
    if (!_stores.hasMore && _stores.items.length > 8) {
      return const Padding(
        padding: EdgeInsets.all(DeliverySpacing.lg),
        child: Center(
          child: Text("That's every shop delivering to you",
              style: TextStyle(fontSize: 12.5, color: DeliveryColors.muted)),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _appBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: DeliveryColors.brand,
      foregroundColor: DeliveryColors.white,
      elevation: 0,
      // The mark, not a back arrow — this is the root of the app. The title stays the delivery
      // address, which is the one thing on this bar the customer needs to check and change.
      leading: const Padding(
        padding: EdgeInsets.only(left: DeliverySpacing.md),
        child: Center(child: DeliveryLogo.mark(size: 26)),
      ),
      leadingWidth: 26 + DeliverySpacing.md + DeliverySpacing.sm,
      titleSpacing: DeliverySpacing.sm,
      title: InkWell(
        onTap: () => showAddressSheet(context, widget.addresses, zoneApi: widget.zoneApi),
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(DeliveryStrings.of(context).deliverTo,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, height: 1.1)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      widget.addresses.headerLabelOr(DeliveryStrings.of(context).setDeliveryAddress),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700, height: 1.3),
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
      // Ordered so settings sits at the very end of the bar and alerts just inside it. In Arabic
      // the whole row mirrors, which is what should happen — settings stays at the end, and the
      // end is the left.
      actions: <Widget>[
        // Alerts live here rather than in the bottom bar: notifications are something you glance
        // at, not a place you navigate to, and the badge is visible from every tab this way.
        IconButton(
          tooltip: DeliveryStrings.of(context).alerts,
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => NotificationsScreen(inbox: widget.inbox),
          )),
          icon: Badge(
            isLabelVisible: widget.inbox.unread > 0,
            label: Text('${widget.inbox.unread}'),
            backgroundColor: DeliveryColors.white,
            textColor: DeliveryColors.brand,
            child: const Icon(Icons.notifications_outlined),
          ),
        ),
        // Settings, not Account. Pushed rather than a tab: it is somewhere you go, change one
        // thing, and leave — which is what a route means and what a tab does not.
        IconButton(
          tooltip: DeliveryStrings.of(context).settings,
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => SettingsScreen(locale: widget.locale),
          )),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    );
  }

  Widget _searchField() {
    return Container(
      color: DeliveryColors.brand,
      padding: const EdgeInsets.fromLTRB(
          DeliverySpacing.md, 0, DeliverySpacing.md, DeliverySpacing.md),
      // Fully rounded, and lifted off the header. A search box is the one control on this screen
      // somebody is looking for before they know what they want, so it reads as an object sitting
      // on the page rather than as a slot cut into the header.
      child: Material(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
        elevation: 0,
        child: TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: DeliveryStrings.of(context).searchShops,
            hintStyle: const TextStyle(color: DeliveryColors.muted, fontSize: 14.5),
            prefixIcon: const Icon(Icons.search_rounded, color: DeliveryColors.muted, size: 21),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DeliveryRadius.pill),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: DeliverySpacing.md, vertical: DeliverySpacing.sm + 5),
            isDense: true,
          ),
        ),
      ),
    );
  }

  Widget _filterBar() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
            horizontal: DeliverySpacing.md, vertical: DeliverySpacing.sm),
        children: <Widget>[
          _filterChip(
            label: DeliveryStrings.of(context).filterOffers,
            icon: Icons.local_offer_rounded,
            selected: _filters.offersOnly,
            onTap: () => setState(
                () => _filters = _filters.copyWith(offersOnly: !_filters.offersOnly)),
          ),
          _filterChip(
            label: DeliveryStrings.of(context).filterUnder30,
            icon: Icons.bolt_rounded,
            selected: _filters.maxEtaMinutes != null,
            onTap: () {
              setState(() => _filters = _filters.maxEtaMinutes == null
                  ? _filters.copyWith(maxEtaMinutes: 30)
                  : _filters.copyWith(clearEta: true));
              _reloadStoresOnly();
            },
          ),
          _filterChip(
            label: DeliveryStrings.of(context).filterFreeDelivery,
            icon: Icons.delivery_dining_rounded,
            selected: _filters.maxDeliveryFee != null,
            onTap: () {
              setState(() => _filters = _filters.maxDeliveryFee == null
                  ? _filters.copyWith(maxDeliveryFee: 0)
                  : _filters.copyWith(clearFee: true));
              _reloadStoresOnly();
            },
          ),
          _filterChip(
            label: '4.5+',
            icon: Icons.star_rounded,
            selected: _filters.minRating != null,
            onTap: () {
              setState(() => _filters = _filters.minRating == null
                  ? _filters.copyWith(minRating: 4.5)
                  : _filters.copyWith(clearRating: true));
              _reloadStoresOnly();
            },
          ),
          if (_filters.isActive)
            TextButton.icon(
              onPressed: () {
                setState(() => _filters = _filters.cleared());
                _reloadStoresOnly();
              },
              icon: const Icon(Icons.close_rounded, size: 16),
              label: Text(DeliveryStrings.of(context).clear),
              style: TextButton.styleFrom(foregroundColor: DeliveryColors.brand),
            ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: DeliverySpacing.sm),
      child: FilterChip(
        selected: selected,
        onSelected: (_) => onTap(),
        avatar: Icon(icon,
            size: 16, color: selected ? DeliveryColors.white : DeliveryColors.muted),
        label: Text(label),
        labelStyle: TextStyle(
          color: selected ? DeliveryColors.white : DeliveryColors.ink,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        backgroundColor: DeliveryColors.white,
        selectedColor: DeliveryColors.brand,
        checkmarkColor: DeliveryColors.white,
        showCheckmark: false,
        side: BorderSide(color: selected ? DeliveryColors.brand : DeliveryColors.border),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DeliveryRadius.pill)),
      ),
    );
  }

  /// The banner carousel: full-bleed artwork the Backoffice curates.
  ///
  /// A horizontally paged strip rather than an auto-rotating carousel. Auto-rotation moves the
  /// thing a customer is reading out from under them, and it steals the first tap.
  Widget _bannerRail() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: DeliverySpacing.md),
        child: SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.md),
            itemCount: _banners.length,
            separatorBuilder: (_, __) => const SizedBox(width: DeliverySpacing.sm + 4),
            itemBuilder: (BuildContext context, int i) => _bannerCard(_banners[i]),
          ),
        ),
      ),
    );
  }

  Widget _bannerCard(HomeBanner banner) {
    final String? image = banner.imageUrl;
    return SizedBox(
      width: 300,
      child: Material(
        color: DeliveryColors.brand,
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: banner.isTappable ? () => _openBanner(banner) : null,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // No artwork yet is an ordinary state — a banner can be drafted before design
              // delivers. The brand gradient stands in rather than a broken frame.
              if (image == null || image.isEmpty)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[DeliveryColors.brand, DeliveryColors.brandDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                )
              else
                Image.network(
                  image,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const DecoratedBox(
                    decoration: BoxDecoration(color: DeliveryColors.brand),
                  ),
                ),

              // Keeps the caption legible over whatever the artwork happens to be.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Colors.transparent, Colors.black87],
                    stops: <double>[0.45, 1],
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
                    Text(
                      banner.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    if (banner.subtitle != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        banner.subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12.5, height: 1.3),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Follows a banner's destination.
  ///
  /// URL banners are not opened: launching an external browser needs a url_launcher dependency and
  /// a policy about which hosts are allowed, and an unhandled tap is better than an unvetted one.
  void _openBanner(HomeBanner banner) {
    switch (banner.linkKind) {
      case BannerLinkKind.store:
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (BuildContext _) => StorePageScreen(
            storeApi: widget.storeApi,
            orderApi: widget.orderApi,
            cart: widget.cart,
            storeId: banner.linkTarget!,
          ),
        ));
      case BannerLinkKind.category:
        // Filters the grid to whichever vertical that category stands for.
        final CategoryChip? chip = _chips.cast<CategoryChip?>().firstWhere(
            (CategoryChip? c) => c?.id == banner.linkTarget, orElse: () => null);
        if (chip != null) {
          _selectVertical(chip.vertical);
        }
      case BannerLinkKind.url:
      case BannerLinkKind.none:
        break;
    }
  }

  Widget _offersRail() {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: DeliveryStrings.of(context).offersForYou),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.md),
              itemCount: _platformOffers.length,
              separatorBuilder: (_, __) => const SizedBox(width: DeliverySpacing.sm + 4),
              itemBuilder: (BuildContext context, int i) {
                final Offer offer = _platformOffers[i];
                return Container(
                  width: 258,
                  padding: const EdgeInsets.all(DeliverySpacing.md),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: <Color>[DeliveryColors.brand, DeliveryColors.brandDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(DeliveryRadius.lg),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Text(
                              offer.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: DeliveryColors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            if (offer.subtitle != null) ...<Widget>[
                              const SizedBox(height: DeliverySpacing.xs),
                              Text(
                                offer.subtitle!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 12.5,
                                  height: 1.25,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Icon(Icons.local_offer_rounded,
                          color: Colors.white24, size: 40),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _favoritesRail() {
    return SizedBox(
      height: 116,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.md),
        itemCount: _favorites.length,
        separatorBuilder: (_, __) => const SizedBox(width: DeliverySpacing.sm + 4),
        itemBuilder: (BuildContext context, int i) {
          final StoreCard store = _favorites[i];
          return StorefrontMiniCard(
            name: store.name,
            state: storeStateOf(store.availability),
            etaLabel: store.etaLabel,
            logoUrl: store.logoUrl,
            rating: store.rating,
            onTap: () => _openStore(store),
          );
        },
      ),
    );
  }

  Widget _storeGrid() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.md),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          // A single column on a phone, two or more on a tablet or the web build, without a
          // breakpoint table to maintain.
          maxCrossAxisExtent: 460,
          mainAxisSpacing: DeliverySpacing.md,
          crossAxisSpacing: DeliverySpacing.md,
          // Fixed height rather than an aspect ratio: the card's content is a fixed stack of
          // rows, so a ratio would stretch the cover on wide screens and clip the text on narrow
          // ones.
          mainAxisExtent: 236,
        ),
        delegate: SliverChildBuilderDelegate(
          (BuildContext context, int i) {
            final StoreCard store = _visibleStores[i];
            return StorefrontCard(
              name: store.name,
              tagline: store.tagline,
              tags: store.tags,
              state: storeStateOf(store.availability),
              etaLabel: store.etaLabel,
              feeLabel: store.feeLabel,
              rating: store.rating,
              ratingCount: store.ratingCount,
              coverUrl: store.coverUrl,
              logoUrl: store.logoUrl,
              offerLabel: store.topOffer?.badgeLabel,
              favorite: store.favorite,
              onTap: () => _openStore(store),
              onFavoriteToggled: () => _toggleFavorite(store),
            );
          },
          childCount: _visibleStores.length,
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.all(DeliverySpacing.xl),
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(DeliverySpacing.md),
            decoration: const BoxDecoration(
                color: DeliveryColors.brandSoft, shape: BoxShape.circle),
            child: const Icon(Icons.storefront_rounded,
                size: 32, color: DeliveryColors.brand),
          ),
          const SizedBox(height: DeliverySpacing.md),
          Text(DeliveryStrings.of(context).noShopsMatch,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: DeliverySpacing.xs),
          Text(
            _filters.isActive
                ? DeliveryStrings.of(context).tryClearingAFilter
                : DeliveryStrings.of(context).nothingDeliveringHere,
            textAlign: TextAlign.center,
            style: const TextStyle(color: DeliveryColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _errorState() {
    return Padding(
      padding: const EdgeInsets.all(DeliverySpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.cloud_off_rounded, size: 40, color: DeliveryColors.muted),
          const SizedBox(height: DeliverySpacing.md),
          Text(DeliveryStrings.of(context).couldNotLoadStorefront,
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: DeliverySpacing.xs),
          Text('$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: DeliveryColors.muted, fontSize: 12)),
          const SizedBox(height: DeliverySpacing.md),
          FilledButton(onPressed: _load, child: Text(DeliveryStrings.of(context).tryAgain)),
        ],
      ),
    );
  }
}
