import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart' show PickedShelfPhoto;
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
/// Opened with [query] for words, or with [photo] for a search by photo — the same screen either way,
/// because a photo ends as words: the server reads the photo once, answers this first page with what
/// it read, and every page after it is the ordinary item search on those words
/// ([PhotoSearchPage.nextQuery]). So the photo is sent once, and the customer can take the words over
/// at any point: the chip under the field puts them in it, and typing leaves the photo behind.
class ItemSearchScreen extends StatefulWidget {
  const ItemSearchScreen({
    super.key,
    required this.storeApi,
    required this.cart,
    required this.addresses,
    this.query,
    this.photo,
    this.maxPhotoBytes,
    required this.onOpenBasket,
    this.orderApi,
    this.onFavoriteChanged,
    this.onPhotoSearchUnavailable,
  }) : assert(query != null || photo != null, 'open the screen with words or with a photo');

  final StoreApi storeApi;
  final Cart cart;
  final DeliveryAddressStore addresses;

  /// The words to search for; null when the screen was opened with a [photo].
  final ItemSearchQuery? query;

  /// The photo to search by, sent once. Null for a search by words.
  final PickedShelfPhoto? photo;

  /// The largest photo the server says it accepts, from the capabilities Home read
  /// ([PhotoSearchCapabilities.maxPhotoBytes]). Null falls back to this build's own cap.
  final int? maxPhotoBytes;

  /// Told when the server says photo search is not available after all, so the camera that opened
  /// this screen stops being offered.
  final VoidCallback? onPhotoSearchUnavailable;

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
  late final TextEditingController _field =
      TextEditingController(text: widget.query?.label ?? '');

  /// The words being searched: the screen's own once a photo has been read, and from the first
  /// keystroke when the customer types over it.
  late ItemSearchQuery _query = widget.query ?? const ItemSearchQuery();

  /// The photo this screen was opened with, until the customer types. Sent once, on the first page.
  late PickedShelfPhoto? _photo = widget.photo;

  /// What the photo was read as, for the chip and the "similar items" line. Null in a text search.
  PhotoSearchPage? _read;

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
      final double? latitude = pinned ? at.latitude : null;
      final double? longitude = pinned ? at.longitude : null;

      // The photo goes with the first page only; what it was read as carries the rest.
      final PickedShelfPhoto? photo = _photo;
      if (photo != null && page == 0) {
        final PhotoSearchPage answer;
        try {
          answer = await widget.storeApi.searchByPhoto(
            bytes: photo.bytes,
            contentType: photo.contentType,
            latitude: latitude,
            longitude: longitude,
            maxBytes: widget.maxPhotoBytes,
          );
        } on PhotoSearchFailure catch (failure) {
          // The camera that opened this screen stops being offered: the server has just said there
          // is no photo search, and a camera that cannot work is worse than none.
          if (failure.code == PhotoSearchFailure.unavailable) {
            widget.onPhotoSearchUnavailable?.call();
          }
          rethrow;
        }
        _read = answer;
        _lastPage = answer;
        // Page two onwards is the ordinary item search on the words the photo came to.
        _query = answer.nextQuery ?? _query;
        return answer;
      }

      final ItemSearchPage answer = await widget.storeApi.searchItems(
        _query,
        latitude: latitude,
        longitude: longitude,
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
    if (next == _query && !_tooShort && _photo == null) return;
    setState(() {
      _tooShort = false;
      _query = next;
      _lastPage = null;
      // Typing takes over from the photo: it is not sent again, and what it was read as goes with it.
      _photo = null;
      _read = null;
    });
    _groups.refresh();
  }

  /// The chip under the field: the words the photo was read as, put into the field and searched.
  void _takeTheWords(String words) {
    _debounce?.cancel();
    _field.text = words;
    _field.selection = TextSelection.collapsed(offset: words.length);
    _searchFor(words);
  }

  /// The shop line and "N more in this shop". With the customer's address book, as Home opens a
  /// shop, so the shop's "Delivery area" map can say whether the chosen address is inside it.
  void _openShop(StoreCard store, {String? search}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (BuildContext _) => StorePageScreen(
        storeApi: widget.storeApi,
        orderApi: widget.orderApi,
        cart: widget.cart,
        storeId: store.id,
        preview: store,
        addresses: widget.addresses,
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
          _photoNote(t),
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

  /// What the photo was read as: the words as a chip that takes over the search, and the line that
  /// says these shops sell the same kind of thing rather than the thing itself.
  Widget _photoNote(DeliveryStrings t) {
    final PhotoSearchPage? read = _read;
    final String? words = read?.understood.label;
    if (read == null || words == null) {
      return const SizedBox.shrink();
    }
    return Container(
      color: DeliveryColors.white,
      padding: const EdgeInsetsDirectional.fromSTEB(
          DeliverySpacing.md, 0, DeliverySpacing.md, DeliverySpacing.md - 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Semantics(
              button: true,
              hint: t.psrchLooksLikeHint,
              child: ActionChip(
                avatar: const Icon(Icons.photo_camera_outlined, size: 16, color: DeliveryColors.brand),
                label: Text(t.psrchLooksLike(words)),
                labelStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: DeliveryColors.ink),
                backgroundColor: DeliveryColors.brandSoft,
                side: const BorderSide(color: DeliveryColors.brandLine),
                onPressed: () => _takeTheWords(words),
              ),
            ),
          ),
          if (read.similar && _groups.items.isNotEmpty) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            Text(
              t.psrchSimilar,
              style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  /// A photo the server would not read or search, in the words of the code it answered with.
  String _photoFailureText(DeliveryStrings t, PhotoSearchFailure failure) {
    if (failure.isLimit) {
      return switch (failure.scope) {
        PhotoSearchFailure.scopeMinute => t.psrchLimitMinute,
        PhotoSearchFailure.scopePlatform => t.psrchLimitPlatform,
        _ => t.psrchLimitDay(failure.limit ?? 0),
      };
    }
    return switch (failure.code) {
      PhotoSearchFailure.unavailable => t.psrchUnavailable,
      PhotoSearchFailure.busy => t.psrchBusy,
      PhotoSearchFailure.tooLarge => t.psrchTooLarge,
      PhotoSearchFailure.wrongType => t.psrchWrongType,
      PhotoSearchFailure.unreadable => t.psrchUnreadable,
      PhotoSearchFailure.refused => t.psrchRefused,
      _ => t.psrchFailed,
    };
  }

  /// Whether sending the same photo again could give a different answer.
  static bool _worthRetrying(PhotoSearchFailure failure) =>
      failure.code == PhotoSearchFailure.busy || failure.code == PhotoSearchFailure.failed;

  Widget _body(DeliveryStrings t, {required bool nearby}) {
    if (_tooShort) {
      return YdEmptyState(icon: Icons.search_rounded, title: t.isrchTypeMore);
    }
    if (_groups.isLoadingFirstPage) {
      // A photo takes a few seconds to read, so the wait says what is happening rather than spinning
      // over nothing.
      if (_photo != null) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const CircularProgressIndicator(color: DeliveryColors.brand),
            const SizedBox(height: DeliverySpacing.md),
            Text(
              t.psrchLooking,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: DeliveryColors.muted, height: 1.35),
            ),
          ],
        );
      }
      return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
    }
    // The photo was read, and there was no product in it: nothing was searched, and asking again with
    // the same photo would read the same.
    if (_read case final PhotoSearchPage read when !read.understood.isProduct) {
      return YdEmptyState(icon: Icons.image_not_supported_outlined, title: t.psrchNotAProduct);
    }
    if (_groups.error case final PhotoSearchFailure failure when _groups.isEmpty) {
      return YdEmptyState(
        icon: failure.isLimit ? Icons.hourglass_empty_rounded : Icons.photo_camera_outlined,
        title: _photoFailureText(t, failure),
        action: _worthRetrying(failure)
            ? YdPillButton(
                label: t.tryAgain,
                expand: false,
                size: YdPillButtonSize.compact,
                onPressed: _groups.refresh,
              )
            : null,
      );
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
        // After a photo, the words the customer would recognise are the ones it was read as, not the
        // spelling the search matched on.
        title: itemSearchEmptyTitle(t, _read?.understood.label ?? _query.label, nearby: nearby),
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
