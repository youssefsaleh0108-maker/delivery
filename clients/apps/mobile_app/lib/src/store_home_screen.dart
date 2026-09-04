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
import 'product_detail_screen.dart' show CoverCard, CustomerPhoto;
import 'friend_split_screen.dart';
import 'shops_listing_screen.dart';
import 'store_page_screen.dart';
import 'store_state_mapping.dart';

/// The customer home screen: shops first, products second.
///
/// The order of the page is the order the questions get asked. Which kind of thing do I want
/// (verticals), where have I been before (favourites), what is on offer, and only then the full
/// list. A flat A-Z of every shop answers none of those.
///
/// Drawn to `customer-home` (Figma 3:12): a white header carrying the delivery address and the
/// search field, a scrolling strip of category pills, and then the sections — each a Bold 18
/// heading over a rail or a two-up grid of cards, on the 24px page gutter.
class StoreHomeScreen extends StatefulWidget {
  const StoreHomeScreen({
    super.key,
    required this.storeApi,
    required this.orderApi,
    required this.cart,
    required this.addresses,
    required this.zoneApi,
    this.prefsApi,
    required this.inbox,
    required this.locale,
    required this.session,
    this.profileApi,
    this.splitApi,
    this.transferApi,
    required this.onSignOut,
  });

  final StoreApi storeApi;

  /// Threaded through to the settings page's notification-preferences grid. Null keeps that row
  /// undrawn — the settings screen's own rule — so this screen needs no fallback of its own.
  final NotificationPrefsApi? prefsApi;

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

  /// The account's picture for the header avatar. Null keeps the monogram.
  final ProfileApi? profileApi;

  /// The group-split invitations banner: polls for requests addressed to this account. Both
  /// arrive together or the banner stays undrawn.
  final SplitApi? splitApi;
  final TransferApi? transferApi;
  final Future<void> Function() onSignOut;

  @override
  State<StoreHomeScreen> createState() => _StoreHomeScreenState();
}

class _StoreHomeScreenState extends State<StoreHomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  StoreFilters _filters = const StoreFilters();

  /// Whether the refine row under the search field is showing.
  ///
  /// The design draws a single sliders glyph inside the search field and no filter row. The
  /// filters behind that glyph are live features, so they are kept and the glyph is what opens
  /// them — which is what a sliders icon beside a search box means anyway.
  bool _filtersOpen = false;

  /// The main grid, loaded a page at a time as the customer scrolls. The rails above it are
  /// deliberately capped rather than paged — they are horizontal strips showing a handful of
  /// items, and a rail nobody can reach the end of does not need infinite scroll.
  late final PagedList<StoreCard> _stores = PagedList<StoreCard>(
    pageSize: 20,
    fetch: (int page, int size) => widget.storeApi.browseWith(_filters, page: page, size: size),
  );

  List<StoreCard> _favorites = <StoreCard>[];

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
    _loadHeaderAvatar();
    _loadSplitRequests();
    // The search hint cycles categories; the banner pager advances itself. Both are paused by
    // nothing and cost one setState — cheap enough to just run for the screen's life.
    _hintTimer = Timer.periodic(const Duration(milliseconds: 2800), (_) {
      if (mounted && _chips.isNotEmpty && _searchController.text.isEmpty) {
        setState(() => _hintIndex++);
      }
    });
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _banners.length < 2 || !_bannerController.hasClients) {
        return;
      }
      final int next = (_bannerPage + 1) % _banners.length;
      _bannerController.animateToPage(next,
          duration: const Duration(milliseconds: 450), curve: Curves.easeOut);
    });
  }

  Timer? _hintTimer;
  int _hintIndex = 0;

  final PageController _bannerController =
      PageController(viewportFraction: 0.92);
  Timer? _bannerTimer;
  int _bannerPage = 0;

  void _onStoresChanged() {
    if (!mounted) return;
    setState(() {});
    // The offers chip filters CLIENT-side (see _visibleStores), so a fetched page can contribute
    // zero visible rows. Left alone, the grid stops growing and the empty state shows while
    // offer-bearing shops still exist on later pages — so keep pulling until something is visible
    // or the pages genuinely run out. loadMore() is re-entry-guarded, so this cannot stack.
    if (_filters.offersOnly &&
        _visibleStores.isEmpty &&
        _stores.hasMore &&
        !_stores.isLoadingFirstPage &&
        !_stores.isLoadingMore) {
      _stores.loadMore();
    }
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _bannerTimer?.cancel();
    _bannerController.dispose();
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
        widget.storeApi.banners(),
        widget.storeApi.categoryChips(),
      ]);
      if (!mounted) return;
      setState(() {
        _favorites = (results[1]! as Paged<StoreCard>).content;
        _banners = results[2]! as List<HomeBanner>;
        _chips = results[3]! as List<CategoryChip>;
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

  // The See-All directory chip left with the pill strip: the frame's category cards scroll the
  // whole set right here and each opens its own listing, so the separate directory screen has no
  // seat on this header any more.

  /// Patches BOTH of this screen's lists with a card whose favourite flag is the truth: the grid
  /// in place, and the "Your favourites" rail by insertion or removal. One method, because the two
  /// used to be patched in one place and rolled back in another — a failed unfavourite restored
  /// the star on the grid but left the card missing from the rail until the next refresh. It is
  /// also the hook the store page calls, so a heart toggled THERE appears here immediately,
  /// without refetching anything — this screen stays alive in the shell's IndexedStack, so the
  /// setState lands on a live State.
  void _applyFavorite(StoreCard store) {
    _stores.replaceWhere((StoreCard s) => s.id == store.id, store);
    if (!mounted) return;
    setState(() {
      final List<StoreCard> without =
          _favorites.where((StoreCard s) => s.id != store.id).toList();
      _favorites = store.favorite ? <StoreCard>[store, ...without] : without;
    });
  }

  /// Optimistic: the star fills immediately and is put back if the call fails. Both endpoints are
  /// idempotent, so a double tap cannot desynchronise anything.
  Future<void> _toggleFavorite(StoreCard store) async {
    final bool nowFavorite = !store.favorite;
    _applyFavorite(store.copyWith(favorite: nowFavorite));

    try {
      if (nowFavorite) {
        await widget.storeApi.star(store.id);
      } else {
        await widget.storeApi.unstar(store.id);
      }
    } catch (_) {
      if (!mounted) return;
      _applyFavorite(store.copyWith(favorite: !nowFavorite));
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
        onFavoriteChanged: _applyFavorite,
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

  /// Applied here rather than in the query: "has a promotion" is a property of the offers attached
  /// to a card, not a column the storefront query can filter on.
  List<StoreCard> get _visibleStores => _filters.offersOnly
      ? _stores.items.where((StoreCard s) => s.topOffer != null).toList()
      : _stores.items;

  // ------------------------------------------------------------------------------------- layout

  /// The page gutter every section in the design sits on.
  static const double _gutter = DeliverySpacing.lg;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: DeliveryColors.brand,
          onRefresh: _load,
          child: Stack(
            children: <Widget>[
              _feed(t),
              // The labels-only category row rides in over the feed once the tile strip has
              // scrolled under the pinned search bar — so at rest there is one category row,
              // not two stacked copies of the same names.
              PositionedDirectional(
                top: _searchBarExtent,
                start: 0,
                end: 0,
                child: IgnorePointer(
                  ignoring: !_labelsPinned,
                  child: AnimatedOpacity(
                    opacity: _labelsPinned ? 1 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: SizedBox(
                      height: _labelsExtent,
                      child: _categoryLabelsBar(t),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _feed(DeliveryStrings t) {
    return NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification notification) {
              // depth 0 only: notifications BUBBLE, so without it every horizontal rail on this
              // screen — the category strip, banners, offers, favourites — reached here carrying
              // its own metrics, and a rail a few hundred pixels long satisfies the near-the-end
              // check at position zero. One sideways swipe on the chips was pulling store page
              // after store page, which is what quietly turned this paged screen back into
              // load-everything.
              if (notification.depth == 0 &&
                  shouldLoadMore(notification.metrics)) {
                // Guarded inside PagedList: a scroll fires this many times per second and only the
                // first one may start a request.
                _stores.loadMore();
              }
              if (notification.depth == 0) {
                _updateLabelsPinned();
              }
              return false;
            },
            child: CustomScrollView(
              controller: _scrollController,
              slivers: <Widget>[
                SliverToBoxAdapter(child: _greetingHeader()),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _PinnedBoxDelegate(
                    height: _searchBarExtent,
                    child: KeyedSubtree(key: _searchKey, child: _searchBar(t)),
                  ),
                ),
                SliverToBoxAdapter(child: _splitRequestBanner(t)),
                SliverToBoxAdapter(
                    child: KeyedSubtree(key: _stripKey, child: _categoryStrip())),
                if (_filtersOpen) SliverToBoxAdapter(child: _filterRow()),
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
                  if (_banners.isNotEmpty) SliverToBoxAdapter(child: _bannerRail()),
                  if (_favorites.isNotEmpty)
                    SliverToBoxAdapter(child: _featuredSection()),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          _gutter, DeliverySpacing.sm, _gutter, DeliverySpacing.md - 4),
                      child: YdSectionHeader(
                        // The frame's own heading for the unfiltered list; a banner-driven
                        // vertical filter still names the vertical.
                        title: _filters.vertical?.labelIn(t) ??
                            t.custActiveStoresNearby,
                        // Plural-aware via ICU. Arabic has six plural categories, not two, so a
                        // `count == 1 ? 'shop' : 'shops'` ternary cannot be translated correctly.
                        // The SERVER's total where it is truthful, so the number does not climb
                        // as pages arrive. The offers chip filters client-side, so under it the
                        // only honest count is what is actually on screen.
                        subtitle: t.shopsDelivering(_filters.offersOnly
                            ? _visibleStores.length
                            : _stores.totalElements ?? _visibleStores.length),
                        fontSize: 18,
                      ),
                    ),
                  ),
                  if (_visibleStores.isEmpty)
                    SliverToBoxAdapter(child: _emptyState())
                  else
                    _storeGrid(),
                  SliverToBoxAdapter(child: _gridFooter()),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: DeliverySpacing.lg)),
              ],
            ),
    );
  }

  /// Whether the labels-only category overlay is riding over the feed. True exactly while the
  /// tile strip is scrolled up underneath the pinned search bar.
  bool _labelsPinned = false;
  final GlobalKey _stripKey = GlobalKey();
  final GlobalKey _searchKey = GlobalKey();

  void _updateLabelsPinned() {
    bool pinned;
    final RenderObject? strip = _stripKey.currentContext?.findRenderObject();
    final RenderObject? search = _searchKey.currentContext?.findRenderObject();
    if (strip is! RenderBox || !strip.attached) {
      // The strip's sliver has been recycled, which only happens once it is well off-screen
      // above; at rest it is always attached.
      pinned = _scrollController.hasClients &&
          _scrollController.offset > _searchBarExtent;
    } else if (search is! RenderBox || !search.attached) {
      pinned = false;
    } else {
      final double stripBottom =
          strip.localToGlobal(Offset.zero).dy + strip.size.height;
      final double searchBottom =
          search.localToGlobal(Offset.zero).dy + search.size.height;
      pinned = stripBottom <= searchBottom;
    }
    if (pinned != _labelsPinned) {
      setState(() => _labelsPinned = pinned);
    }
  }

  /// The white `home-header`: the delivery address on one row, the search field under it.
  /// The header avatar's viewing URL. Fetched once; the monogram covers every failure.
  String? _headerAvatarUrl;

  /// Split invitations waiting on this account — drives the banner under the header.
  List<SplitPlan> _splitRequests = <SplitPlan>[];

  Future<void> _loadSplitRequests() async {
    final SplitApi? api = widget.splitApi;
    if (api == null) return;
    try {
      final List<SplitPlan> requests = await api.requests();
      if (!mounted) return;
      setState(() => _splitRequests = requests);
    } catch (_) {
      // No banner; the requests screen is still reachable next load.
    }
  }

  /// The frame's invitation banner: who invited you, one tap to your share.
  Widget _splitRequestBanner(DeliveryStrings t) {
    if (_splitRequests.isEmpty ||
        widget.splitApi == null ||
        widget.transferApi == null) {
      return const SizedBox.shrink();
    }
    final SplitPlan plan = _splitRequests.first;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
          _gutter, DeliverySpacing.sm, _gutter, 0),
      child: Material(
        color: DeliveryColors.brandSoft,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => FriendSplitScreen(
                splitApi: widget.splitApi!,
                transferApi: widget.transferApi!,
                plan: plan,
                myUsername: widget.session.username ?? '',
              ),
            ));
            _loadSplitRequests();
          },
          child: Padding(
            padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
            child: Row(
              children: <Widget>[
                const Icon(Icons.group_rounded,
                    size: 20, color: DeliveryColors.brand),
                const SizedBox(width: DeliverySpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        t.custSplitRequestBanner(plan.hostName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: DeliveryColors.ink,
                          height: 1.25,
                        ),
                      ),
                      Text(
                        t.custPayYourShare,
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: DeliveryColors.brand,
                            height: 1.3),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 18, color: DeliveryColors.brand),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadHeaderAvatar() async {
    final ProfileApi? api = widget.profileApi;
    if (api == null) return;
    try {
      final String? url = await api.myAvatarUrl();
      if (!mounted) return;
      setState(() => _headerAvatarUrl = url);
    } catch (_) {
      // The monogram stands.
    }
  }

  /// The design's `profile-header`: the avatar (which opens the profile drawer), the greeting,
  /// the delivery location under it, and the bell in the end slot.
  ///
  /// The bell is the one departure from the frame, which puts a brand chip there instead: the
  /// unread count is load-bearing on the tab the customer lives in, and a decoration is not.
  /// Settings lost its seat because the drawer now carries everything it opened.
  Widget _greetingHeader() {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String firstName = widget.session.displayName.split(' ').first;

    return Container(
      color: DeliveryColors.white,
      padding: const EdgeInsetsDirectional.fromSTEB(
          _gutter, DeliverySpacing.md - 4, _gutter, DeliverySpacing.md),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              _headerAvatar(t),
              const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      t.custHiName(firstName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: DeliveryColors.ink,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    InkWell(
                      onTap: () => showAddressSheet(context, widget.addresses,
                          zoneApi: widget.zoneApi),
                      borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(Icons.location_on_outlined,
                              size: 14, color: DeliveryColors.brand),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              widget.addresses
                                  .headerLabelOr(t.setDeliveryAddress),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: DeliveryColors.muted,
                                height: 1.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(Icons.keyboard_arrow_down,
                              size: 14, color: DeliveryColors.muted),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              _headerAction(
                icon: Icons.notifications_outlined,
                semanticLabel: t.alerts,
                badgeCount: widget.inbox.unread,
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => NotificationsScreen(inbox: widget.inbox),
                )),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The pinned search bar. The hint cycles through the live category names — an invitation,
  /// not a label — and freezes the moment the customer types.
  static const double _searchBarExtent = 64;

  Widget _searchBar(DeliveryStrings t) {
    return Container(
      color: DeliveryColors.white,
      padding: const EdgeInsetsDirectional.fromSTEB(_gutter, 6, _gutter, 10),
      alignment: Alignment.center,
      child: YdSearchField(
        controller: _searchController,
        hintText: t.searchShops,
        animatedHint: _chips.isEmpty
            ? null
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (Widget child, Animation<double> a) =>
                    FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.6),
                      end: Offset.zero,
                    ).animate(a),
                    child: child,
                  ),
                ),
                child: Text(
                  t.custSearchInCategory(
                      _chips[_hintIndex % _chips.length].name),
                  key: ValueKey<int>(_hintIndex % _chips.length),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: DeliveryColors.faint,
                    height: 1.2,
                  ),
                ),
              ),
        onChanged: _onSearchChanged,
        searchSemanticLabel: t.searchShops,
        filterSemanticLabel: t.custFilters,
        filterIcon: Icons.tune,
        onFilterTap: () => setState(() => _filtersOpen = !_filtersOpen),
      ),
    );
  }

  /// The compact category row that stays pinned under the search once the photo tiles scroll
  /// away — labels only, per the operator's ask; the photo strip remains the rich version above.
  static const double _labelsExtent = 44;

  Widget _categoryLabelsBar(DeliveryStrings t) {
    final List<StoreVertical> verticals = _chipVerticals;
    return Container(
      color: DeliveryColors.white,
      alignment: AlignmentDirectional.centerStart,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: _gutter, vertical: 8),
        children: <Widget>[
          for (final StoreVertical vertical in verticals) ...<Widget>[
            InkWell(
              borderRadius: BorderRadius.circular(DeliveryRadius.pill),
              onTap: () => _openListing(vertical),
              child: Container(
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: DeliveryColors.background,
                  borderRadius: BorderRadius.circular(DeliveryRadius.pill),
                ),
                child: Text(
                  _chipLabel(vertical),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.ink,
                    height: 1.2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  /// The face that opens the profile drawer — the drawer lives on the shell's Scaffold above
  /// this screen, which is what Scaffold.of finds from here.
  Widget _headerAvatar(DeliveryStrings t) {
    final String? url = _headerAvatarUrl;
    final Widget face = url == null
        ? StoreMonogram(name: widget.session.displayName, size: 40, radius: 20)
        : ClipOval(
            child: Image(
              image: DeliveryImages.provider(url),
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                  StoreMonogram(
                      name: widget.session.displayName, size: 40, radius: 20),
            ),
          );

    return Semantics(
      button: true,
      label: t.custAccountSettings,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => Scaffold.of(context).openDrawer(),
        child: face,
      ),
    );
  }

  Widget _headerAction({
    required IconData icon,
    required String semanticLabel,
    required VoidCallback onPressed,
    int badgeCount = 0,
  }) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Material(
            color: DeliveryColors.background,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: SizedBox.square(
                dimension: 32,
                child: Icon(icon, size: 18, color: DeliveryColors.ink),
              ),
            ),
          ),
          if (badgeCount > 0)
            PositionedDirectional(
              top: -4,
              end: -4,
              child: Container(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: DeliveryColors.brand,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.white,
                    height: 1.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The horizontally scrolling pill strip. Ends in the door to the full directory — the design
  /// gives the categories screen no other entrance.
  /// The frame's category CARDS — a white tile per vertical, the glyph in a brand-soft square
  /// over the label — each opening that category's own listing screen rather than filtering the
  /// grid in place, which is how the frame's flow reads (home → listing → shop).
  Widget _categoryStrip() {
    final List<StoreVertical> verticals = _chipVerticals;

    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.fromSTEB(
            _gutter, DeliverySpacing.md, DeliverySpacing.md, DeliverySpacing.xs),
        children: <Widget>[
          for (final StoreVertical vertical in verticals) ...<Widget>[
            _categoryCard(vertical),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  /// The tinted-glyph tile: every category renders this — brand glyph on the soft brand fill.
  Widget _categoryIconTile(StoreVertical vertical) => Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: DeliveryColors.brandSoft,
          borderRadius: BorderRadius.circular(DeliveryRadius.sm + 2),
        ),
        child: Icon(iconForVertical(vertical),
            size: 20, color: DeliveryColors.brand),
      );

  Widget _categoryCard(StoreVertical vertical) {
    return Semantics(
      button: true,
      label: _chipLabel(vertical),
      child: Material(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          onTap: () => _openListing(vertical),
          child: Container(
            width: 82,
            padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
              border: Border.all(color: DeliveryColors.borderFaint),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _categoryIconTile(vertical),
                const SizedBox(height: 6),
                Text(
                  _chipLabel(vertical),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    // Smaller and a touch tighter than the shop-name scale — the tile is 82px
                    // wide and the longer vertical names (Restaurants, Pharmacies) were riding
                    // the ellipsis at 11.5. This fits them whole.
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    letterSpacing: -0.1,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openListing(StoreVertical? vertical) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ShopsListingScreen(
        storeApi: widget.storeApi,
        orderApi: widget.orderApi,
        cart: widget.cart,
        initialVertical: vertical,
        chips: _chips,
      ),
    ));
  }

  /// The refine row the sliders glyph opens, in the same pill language as the strip above it.
  Widget _filterRow() {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return SizedBox(
      height: YdChip.minHeight + DeliverySpacing.md,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.fromSTEB(
            _gutter, 0, DeliverySpacing.md, DeliverySpacing.md),
        children: <Widget>[
          YdChip(
            label: t.filterOffers,
            icon: Icons.local_offer_outlined,
            selected: _filters.offersOnly,
            onTap: () => setState(
                () => _filters = _filters.copyWith(offersOnly: !_filters.offersOnly)),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          YdChip(
            label: t.filterUnder30,
            icon: Icons.bolt_outlined,
            selected: _filters.maxEtaMinutes != null,
            onTap: () {
              setState(() => _filters = _filters.maxEtaMinutes == null
                  ? _filters.copyWith(maxEtaMinutes: 30)
                  : _filters.copyWith(clearEta: true));
              _reloadStoresOnly();
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
              _reloadStoresOnly();
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
              _reloadStoresOnly();
            },
          ),
          if (_filters.isActive) ...<Widget>[
            const SizedBox(width: DeliverySpacing.sm),
            YdChip(
              label: t.clear,
              icon: Icons.close,
              onTap: () {
                setState(() => _filters = _filters.cleared());
                _reloadStoresOnly();
              },
            ),
          ],
        ],
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
    return const SizedBox.shrink();
  }

  /// The banner carousel: full-bleed artwork the Backoffice curates, advancing on its own
  /// every four seconds at the operator's request. Swiping by hand still works and the timer
  /// picks up from wherever the customer left it.
  Widget _bannerRail() {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: DeliverySpacing.sm),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 150,
            child: PageView.builder(
              controller: _bannerController,
              itemCount: _banners.length,
              onPageChanged: (int i) => setState(() => _bannerPage = i),
              itemBuilder: (BuildContext context, int i) => Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 5),
                child: _bannerCard(_banners[i]),
              ),
            ),
          ),
          if (_banners.length > 1) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (int i = 0; i < _banners.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _bannerPage ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _bannerPage
                          ? DeliveryColors.brand
                          : DeliveryColors.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _bannerCard(HomeBanner banner) {
    final String? image = banner.imageUrl;
    return SizedBox(
      width: double.infinity,
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
                Image(
                  image: DeliveryImages.provider(image),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const DecoratedBox(
                    decoration: BoxDecoration(color: DeliveryColors.brand),
                  ),
                ),

              // Keeps the caption legible over whatever the artwork happens to be.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.transparent,
                      DeliveryColors.ink.withValues(alpha: 0.75),
                    ],
                    stops: const <double>[0.45, 1],
                  ),
                ),
              ),
              PositionedDirectional(
                start: DeliverySpacing.md,
                end: DeliverySpacing.md,
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
                        color: DeliveryColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    if (banner.subtitle != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        banner.subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: DeliveryColors.white.withValues(alpha: 0.82),
                          fontSize: 12,
                          height: 1.3,
                        ),
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
            onFavoriteChanged: _applyFavorite,
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

  /// The `featured-section`: a Bold 18 heading with a text action, over a rail of 260px shop
  /// cards. The shops on it are the customer's own starred ones.
  Widget _featuredSection() {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: DeliverySpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                _gutter, DeliverySpacing.sm, _gutter, DeliverySpacing.md - 4),
            child: YdSectionHeader(
              title: t.yourFavourites,
              fontSize: 18,
              actionLabel: t.custSeeAll,
              // The favourites are shops, so "See All" means the shop list filtered to them —
              // which is this screen's own grid with the starred ones at the top of it.
              onAction: () => _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              ),
            ),
          ),
          SizedBox(
            height: _shopCardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsetsDirectional.symmetric(horizontal: _gutter),
              itemCount: _favorites.length,
              separatorBuilder: (_, __) => const SizedBox(width: DeliverySpacing.md),
              itemBuilder: (BuildContext context, int i) => _shopCard(_favorites[i]),
            ),
          ),
        ],
      ),
    );
  }

  static const double _shopCoverHeight = 130;
  static const double _shopCardHeight = 208;

  /// `shop-card`: a 260px card, a 130px cover, then the name and the meta line.
  Widget _shopCard(StoreCard store) {
    return CoverCard(
      width: 260,
      onTap: () => _openStore(store),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CustomerPhoto(
            // A 130px cover in a horizontally scrolling rail — a list surface, and one that loads
            // several covers at once. The derivative, falling back to the full-size URL itself.
            url: store.listCoverUrl,
            width: double.infinity,
            height: _shopCoverHeight,
            icon: iconForVertical(store.vertical),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  store.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: DeliverySpacing.sm),
                _storeMeta(store),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The meta line the design draws under a shop's name: rating, bullet, ETA, bullet, and the
  /// delivery flag in green when it is free.
  ///
  /// [compact] drops the delivery flag. The two-up card is 171px wide — the width the frame itself
  /// draws it at — and three values plus two separators do not fit there at 12px in either
  /// language. The fee is one tap away on the shop page and is still on the wider carousel card;
  /// an ellipsised ETA would have cost more than it saved.
  Widget _storeMeta(StoreCard store, {bool compact = false}) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final DeliveryStoreState state = storeStateOf(store.availability);
    final bool free = store.deliveryFee == 0;
    final bool closed = state == DeliveryStoreState.closed;

    return Row(
      children: <Widget>[
        if (store.rating != null) ...<Widget>[
          Icon(Icons.star_rounded, size: 14, color: DeliveryAccent.caution.color),
          const SizedBox(width: DeliverySpacing.xs),
          Text(
            store.rating!.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.ink,
            ),
          ),
          const _MetaBullet(),
        ],
        // A shut shop is the thing worth reading first; an ETA it will not honour is noise.
        Flexible(
          child: Text(
            closed ? t.statusClosed : store.etaLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: closed ? FontWeight.w600 : FontWeight.w400,
              color: closed ? DeliveryColors.faint : DeliveryColors.muted,
            ),
          ),
        ),
        if (!compact && !closed) ...<Widget>[
          const _MetaBullet(),
          Flexible(
            child: Text(
              free ? t.freeDelivery : store.deliveryFee.toStringAsFixed(2),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: free ? DeliveryAccent.positive.color : DeliveryColors.muted,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// The full shop list, in the design's two-up card.
  ///
  /// The frame draws `Popular Right Now` here — a two-up grid of *products* with a one-tap add.
  /// There is no cross-shop product feed to fill it from (products are read per store), so the
  /// grid holds what this screen actually browses, shops, in the same card geometry with the shop
  /// meta line where the design puts the price row.
  Widget _storeGrid() {
    return SliverPadding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: _gutter),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          // Two columns on a phone; more on a tablet or the web build, without a breakpoint table
          // to maintain.
          maxCrossAxisExtent: 230,
          mainAxisSpacing: DeliverySpacing.md - 4,
          crossAxisSpacing: DeliverySpacing.md - 4,
          mainAxisExtent: _itemCardHeight,
        ),
        delegate: SliverChildBuilderDelegate(
          (BuildContext context, int i) => _itemCard(_visibleStores[i]),
          childCount: _visibleStores.length,
        ),
      ),
    );
  }

  static const double _itemCoverHeight = 100;
  static const double _itemCardHeight = 192;

  Widget _itemCard(StoreCard store) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return YdCard(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
      onTap: () => _openStore(store),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Stack(
            children: <Widget>[
              CustomerPhoto(
                // The storefront grid: a 100px cover, once per shop, for every shop on screen.
                url: store.listCoverUrl,
                height: _itemCoverHeight,
                width: double.infinity,
                radius: DeliveryRadius.md,
                icon: iconForVertical(store.vertical),
              ),
              if (store.topOffer != null)
                PositionedDirectional(
                  top: DeliverySpacing.sm,
                  start: DeliverySpacing.sm,
                  child: YdBadge.brand(label: store.topOffer!.badgeLabel, fontSize: 10),
                ),
              PositionedDirectional(
                top: DeliverySpacing.xs,
                end: DeliverySpacing.xs,
                // Starring is a live feature the frame has no slot for; it goes where a favourite
                // always goes, in the corner of the picture.
                child: GestureDetector(
                  onTap: () => _toggleFavorite(store),
                  child: Semantics(
                    button: true,
                    label: store.favorite ? t.removeFromFavourites : t.addToFavourites,
                    child: Container(
                      padding: const EdgeInsetsDirectional.all(5),
                      decoration: BoxDecoration(
                        color: DeliveryColors.white.withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        store.favorite ? Icons.favorite : Icons.favorite_border,
                        size: 14,
                        color: DeliveryColors.brand,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.sm),
          Text(
            store.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
              height: 1.25,
            ),
          ),
          const SizedBox(height: DeliverySpacing.sm),
          _storeMeta(store, compact: true),
        ],
      ),
    );
  }

  Widget _emptyState() {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.xl),
      child: YdEmptyState(
        icon: Icons.storefront,
        title: t.noShopsMatch,
        message: _filters.isActive ? t.tryClearingAFilter : t.nothingDeliveringHere,
      ),
    );
  }

  Widget _errorState() {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.cloud_off_rounded, size: 40, color: DeliveryColors.faint),
          const SizedBox(height: DeliverySpacing.md),
          Text(t.couldNotLoadStorefront,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 16, color: DeliveryColors.ink)),
          const SizedBox(height: DeliverySpacing.xs),
          Text('$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: DeliveryColors.muted, fontSize: 12)),
          const SizedBox(height: DeliverySpacing.md),
          YdPillButton(
            label: t.tryAgain,
            onPressed: _load,
            size: YdPillButtonSize.compact,
            expand: false,
          ),
        ],
      ),
    );
  }
}

/// The faint bullet the design puts between meta values.
class _MetaBullet extends StatelessWidget {
  const _MetaBullet();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsetsDirectional.symmetric(horizontal: DeliverySpacing.sm - 2),
      child: Text('•', style: TextStyle(fontSize: 12, color: DeliveryColors.faint)),
    );
  }
}

/// A fixed-extent pinned header: the search bar and the labels row don't shrink or float,
/// they simply hold their line while the feed scrolls beneath.
class _PinnedBoxDelegate extends SliverPersistentHeaderDelegate {
  _PinnedBoxDelegate({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(height: height, child: child);
  }

  @override
  bool shouldRebuild(covariant _PinnedBoxDelegate oldDelegate) =>
      oldDelegate.height != height || oldDelegate.child != child;
}
