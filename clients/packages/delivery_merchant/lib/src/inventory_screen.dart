import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'order_detail_screen.dart';
import 'product_form_screen.dart';

/// What is on the shelf — Figma `merchant-inventory` (94:106 phone / 94:3166 web).
///
/// The catalogue screen next door ([ProductListScreen]) answers "what do we sell"; this one answers
/// "how many are left", and the two are deliberately different pages over two different services.
///
/// Three things here are load-bearing and easy to get wrong:
///
/// * **Filtering is server-side.** Unlike the catalogue list, which filters the page it already
///   holds, a stock question needs the database — "low stock" is decided against each item's own
///   threshold, across every page. So a chip tap rebuilds the [PagedList] closure rather than
///   filtering [PagedList.items]; reusing the old closure silently keeps paging the old filter.
/// * **Untracked is not zero.** A product nobody asked inventory to police shows an em dash and
///   the words "Not tracked", never a number. "We are not counting this" and "there are none of
///   these" lead to opposite actions, and a 0 in the column would collapse them.
/// * **An empty tab over a non-empty catalogue is a migration, not a truth.** Every shop that
///   existed before inventory-service has products it has never heard of, so the first empty
///   unfiltered load calls [InventoryApi.sync] exactly once and reloads — see [_maybeSync].
///
/// The service is not deployed yet, and [api] is nullable for exactly that reason: with no client
/// the screen draws a calm unavailable state instead of throwing, and every failure below it
/// resolves to a message and a retry rather than a red screen.
///
/// One widget, two hosts: the Android shell hands it 380dp and a thumb, the portal hands it the
/// space beside its rail. Everything measures [BoxConstraints], never the window.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    this.api,
    required this.catalogApi,
    this.storeApi,
    this.storeId,
    this.onOpenAlerts,
    this.onOpenItem,
  });

  /// inventory-service. Null until the service ships, or wherever a host has none to hand — the
  /// screen then renders [_unavailable] rather than pretending it has a shelf to show.
  final InventoryApi? api;

  /// The catalogue, for the "Add product" button and for the one question inventory cannot answer
  /// about itself: whether an empty inventory sits over a catalogue that is not empty.
  final CatalogApi catalogApi;

  /// Passed straight through to [ProductFormScreen] for the options card. Optional there too.
  final StoreApi? storeApi;

  /// Scopes the list for a staff member who works in one shop. Null lets the server decide from
  /// the caller's own membership, which is what an owner wants.
  final String? storeId;

  /// Opens the stock-alerts screen from the header pill. Null leaves the pill as a read-only
  /// count — the route is wired by the host, and a pill that navigates nowhere is worse than one
  /// that plainly does not.
  final VoidCallback? onOpenAlerts;

  /// Opens one item — the adjust sheet and its movement history. Null falls back to the product
  /// form, so a row is never inert.
  final void Function(InventoryItem item)? onOpenItem;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  /// Below this the page is on a phone: one column, and the header's refresh control gives way to
  /// the pull gesture. Measured against this widget's constraints, not the window — the portal's
  /// rail can leave a desktop as narrow as a handset.
  static const double _phoneWidth = 600;

  /// The row thumbnail, and the padding around it.
  static const double _rowImage = 56;
  static const double _rowPadding = 12;

  /// Room under the last row for the floating button.
  static const double _fabClearance = 88;

  /// Long enough that typing a SKU is one request rather than eight, short enough that it still
  /// feels like the list is following along.
  static const Duration _searchDebounce = Duration(milliseconds: 350);

  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  /// The shelf, a page at a time. Null only while [InventoryScreen.api] is null.
  PagedList<InventoryItem>? _items;

  InventoryFilter _filter = InventoryFilter.all;
  String _query = '';

  /// The header's counts. Null until the first answer; [_summaryFailed] separates "not yet" from
  /// "the server would not say", because only one of those may fall back to a local guess.
  ItemsSummary? _summary;
  bool _summaryFailed = false;

  /// The category count's fallback when the summary endpoint is unavailable — the catalogue knows
  /// how many sections exist even when inventory-service does not answer.
  int? _categoryCount;

  /// [InventoryApi.sync] runs at most once per mount, whatever the list does afterwards. Without
  /// the bound, a shop whose catalogue genuinely has nothing in it would re-import on every reload.
  bool _synced = false;
  bool _syncing = false;

  /// True only while [_startList] is wiring a list up.
  ///
  /// [PagedList.refresh] notifies synchronously before its first await, and during `initState`
  /// that would be a `setState` during build. The state it announces — the first-page spinner — is
  /// read by the very next build anyway, so dropping that one notification costs nothing.
  bool _wiring = false;

  @override
  void initState() {
    super.initState();
    _startList();
    _loadSummary();
    _loadCategoryCount();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _items?.removeListener(_onListChanged);
    _items?.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ loading

  /// Builds a fresh [PagedList] for the current filter and query and starts it.
  ///
  /// A new closure every time, deliberately: [PagedList.fetch] captures the filter, so reusing the
  /// old list after a chip tap would page the old filter's results in under the new chip.
  void _startList() {
    final InventoryApi? api = widget.api;
    if (api == null) {
      return;
    }

    _items?.removeListener(_onListChanged);
    _items?.dispose();

    final InventoryFilter filter = _filter;
    final String query = _query;
    final PagedList<InventoryItem> list = PagedList<InventoryItem>(
      fetch: (int page, int size) => api.items(
        filter: filter,
        search: query.isEmpty ? null : query,
        storeId: widget.storeId,
        page: page,
        size: size,
      ),
    );
    list.addListener(_onListChanged);
    _items = list;

    _wiring = true;
    // Not awaited: the list announces its own progress, and the screen is already drawn against it.
    unawaited(list.refresh());
    _wiring = false;
  }

  void _onListChanged() {
    if (!mounted || _wiring) {
      return;
    }
    setState(() {});
    // A load that found nothing may be a migration rather than an empty shop.
    unawaited(_maybeSync());
  }

  Future<void> _loadSummary() async {
    final InventoryApi? api = widget.api;
    if (api == null) {
      return;
    }
    try {
      final ItemsSummary summary = await api.summary(storeId: widget.storeId);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _summaryFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Not surfaced as an error: the counts are a header line, and losing them must not take the
      // list with them. The line falls back to what the list itself knows.
      setState(() => _summaryFailed = true);
    }
  }

  /// The section count, read from the catalogue so the header still says something true when
  /// inventory-service is the half that is down.
  Future<void> _loadCategoryCount() async {
    try {
      final List<Category> categories = await widget.catalogApi.categories();
      if (!mounted) return;
      setState(() => _categoryCount = categories.length);
    } catch (_) {
      // Leaves the slot at "—". A missing count is not worth a message.
    }
  }

  /// Imports the caller's catalogue into inventory-service, once, when the tab is empty but the
  /// shop is not.
  ///
  /// Only for the unfiltered, unsearched list: "no low-stock items" and "no items at all" are
  /// different answers, and only the second one is a migration.
  Future<void> _maybeSync() async {
    final InventoryApi? api = widget.api;
    final PagedList<InventoryItem>? list = _items;
    if (api == null || list == null || _synced || _syncing) {
      return;
    }
    if (!list.isEmptyAfterLoad ||
        _filter != InventoryFilter.all ||
        _query.isNotEmpty) {
      return;
    }
    _synced = true;

    try {
      final Paged<Product> catalogue = await widget.catalogApi.myProducts(size: 1);
      if (!mounted || catalogue.totalElements == 0) {
        return;
      }
      setState(() => _syncing = true);
      final int imported = await api.sync();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DeliveryStrings.of(context).invSynced(imported))),
      );
      await list.refresh();
      if (mounted) {
        await _loadSummary();
      }
    } catch (_) {
      // The empty state stays, which is the honest reading of a failed import.
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  /// Reloads everything the screen shows. Returns the list's future so [RefreshIndicator] stops
  /// spinning when the request finishes rather than when it is sent.
  Future<void> _refresh() {
    final PagedList<InventoryItem>? list = _items;
    unawaited(_loadSummary());
    if (list == null) {
      return Future<void>.value();
    }
    // PagedList swallows its own failures into `error`; nothing escapes to strand the spinner.
    return list.refresh();
  }

  void _selectFilter(InventoryFilter filter) {
    if (filter == _filter) {
      return;
    }
    setState(() => _filter = filter);
    _startList();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, () {
      final String next = value.trim();
      if (next == _query || !mounted) {
        return;
      }
      setState(() => _query = next);
      _startList();
    });
  }

  void _clearFilters() {
    _debounce?.cancel();
    _search.clear();
    setState(() {
      _query = '';
      _filter = InventoryFilter.all;
    });
    _startList();
  }

  // ------------------------------------------------------------------ actions

  Future<void> _addProduct() async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ProductFormScreen(
          api: widget.catalogApi,
          storeApi: widget.storeApi,
        ),
      ),
    );
    if ((saved ?? false) && mounted) {
      // A new product is a new shelf row, so the counts move too.
      unawaited(_refresh());
    }
  }

  Future<void> _openItem(InventoryItem item) async {
    final void Function(InventoryItem)? handler = widget.onOpenItem;
    if (handler != null) {
      handler(item);
      return;
    }
    // No adjust route wired: fall back to the product itself, so a row is never dead. Read through
    // the catalogue rather than reusing the inventory projection — the form edits a Product.
    try {
      final Product product = await widget.catalogApi.read(item.productId);
      if (!mounted) return;
      final bool? saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => ProductFormScreen(
            api: widget.catalogApi,
            storeApi: widget.storeApi,
            existing: product,
          ),
        ),
      );
      if ((saved ?? false) && mounted) {
        unawaited(_refresh());
      }
    } catch (e) {
      if (!mounted) return;
      final DeliveryStrings t = DeliveryStrings.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageFor(e, fallback: t.somethingWentWrong))),
      );
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < _phoneWidth;

        return Scaffold(
          backgroundColor: DeliveryColors.background,
          // No AppBar and no rail: the framing belongs to whichever app mounts this.
          floatingActionButton: _AddButton(
            label: t.merchbAddProduct,
            onPressed: _addProduct,
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              MerchantScreenHeader(
                title: t.invTitle,
                // The refresh control only exists where there is no pull gesture to replace it.
                trailing: narrow
                    ? null
                    : IconButton(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh, size: 20),
                        color: DeliveryColors.muted,
                        tooltip: t.refresh,
                      ),
              ),
              _summaryBand(t),
              _searchBand(t),
              _filterStrip(t),
              Expanded(child: _body(t, narrow: narrow)),
            ],
          ),
        );
      },
    );
  }

  /// The frame's "234 Products • 18 Categories" line, with the alerts pill on the end.
  ///
  /// A [Wrap] rather than a [Row]: three translated counts and a pill do not fit 380dp in Arabic,
  /// and a header that overflows is worse than one that takes two lines.
  Widget _summaryBand(DeliveryStrings t) {
    final ItemsSummary? summary = _summary;
    // The list's own total is the better product count once it has one — it is the count of what
    // the current filter actually matched, which is what the rows below are.
    final int? products =
        summary?.products ?? (_summaryFailed ? _items?.totalElements : null);
    final int? categories = summary?.categories ?? (_summaryFailed ? _categoryCount : null);
    final int alerts = summary?.alerts ?? 0;

    return Container(
      width: double.infinity,
      color: DeliveryColors.white,
      padding: const EdgeInsetsDirectional.fromSTEB(
        DeliverySpacing.lg,
        DeliverySpacing.md - DeliverySpacing.xs,
        DeliverySpacing.lg,
        0,
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: DeliverySpacing.md,
        runSpacing: DeliverySpacing.sm,
        children: <Widget>[
          _Count(value: products, label: t.invProducts),
          _Count(value: categories, label: t.invCategories),
          if (_syncing)
            _SyncingChip(label: t.invSyncing)
          else if (summary != null && alerts > 0)
            _AlertsPill(
              label: t.invAlertsCount(alerts),
              count: alerts,
              onTap: widget.onOpenAlerts,
            ),
        ],
      ),
    );
  }

  Widget _searchBand(DeliveryStrings t) {
    return Container(
      width: double.infinity,
      color: DeliveryColors.white,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: DeliverySpacing.lg,
        vertical: DeliverySpacing.md - DeliverySpacing.xs,
      ),
      child: YdSearchField(
        controller: _search,
        hintText: t.invSearch,
        // Server-side: the query goes into the request, so it searches every page rather than the
        // twenty rows that happen to be loaded — which is the only way a SKU search is useful.
        onChanged: _onSearchChanged,
        onSubmitted: (String value) {
          _debounce?.cancel();
          final String next = value.trim();
          if (next == _query) {
            return;
          }
          setState(() => _query = next);
          _startList();
        },
      ),
    );
  }

  /// All / Low stock / Out of stock / Active / Hidden — each one a refetch.
  Widget _filterStrip(DeliveryStrings t) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(
        DeliverySpacing.lg,
        0,
        DeliverySpacing.lg,
        DeliverySpacing.md - DeliverySpacing.xs,
      ),
      // Wraps rather than scrolls sideways: five translated chips are wider than a phone, and a
      // horizontal scroller hides the last chip with nothing to say so while adding a second drag
      // direction to a list that already wants a vertical one.
      child: Wrap(
        spacing: DeliverySpacing.sm,
        runSpacing: DeliverySpacing.sm,
        children: <Widget>[
          for (final InventoryFilter filter in InventoryFilter.values)
            YdChip(
              label: filter.labelIn(t),
              selected: _filter == filter,
              onTap: widget.api == null ? null : () => _selectFilter(filter),
            ),
        ],
      ),
    );
  }

  Widget _body(DeliveryStrings t, {required bool narrow}) {
    if (widget.api == null) {
      return _unavailable(t);
    }
    final PagedList<InventoryItem> list = _items!;

    if (list.isLoadingFirstPage || _syncing) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(DeliverySpacing.xl),
          child: CircularProgressIndicator(color: DeliveryColors.brand),
        ),
      );
    }

    final Widget scroller = CustomScrollView(
      // Always scrollable, or the pull gesture is dead on exactly the two states where a merchant
      // most wants to retry: nothing loaded, and nothing found.
      physics: narrow ? const AlwaysScrollableScrollPhysics() : null,
      slivers: <Widget>[
        if (list.error != null && list.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: YdEmptyState(
              icon: Icons.cloud_off_rounded,
              title: t.invCouldNotLoad,
              message: _messageFor(list.error!, fallback: t.somethingWentWrong),
              action: YdPillButton.secondary(
                label: t.tryAgain,
                onPressed: _refresh,
                size: YdPillButtonSize.compact,
                expand: false,
              ),
            ),
          )
        else if (list.isEmptyAfterLoad)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _filtered
                ? YdEmptyState(
                    icon: Icons.search_off_rounded,
                    title: t.invEmpty,
                    action: TextButton(
                      onPressed: _clearFilters,
                      child: Text(t.clear),
                    ),
                  )
                : YdEmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: t.invEmpty,
                    message: t.invEmptyHint,
                  ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              DeliverySpacing.lg,
              DeliverySpacing.lg,
              DeliverySpacing.lg,
              // Clears the floating button and then the gesture bar under it. `paddingOf`, never
              // `viewPaddingOf`: a host that already wrapped this in a SafeArea has spent the inset.
              _fabClearance + MediaQuery.paddingOf(context).bottom,
            ),
            sliver: _grid(list, narrow: narrow),
          ),
      ],
    );

    final Widget listener = NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (shouldLoadMore(notification.metrics)) {
          unawaited(list.loadMore());
        }
        return false;
      },
      child: _capped(scroller),
    );

    if (!narrow) {
      return listener;
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      color: DeliveryColors.brand,
      child: listener,
    );
  }

  /// Whether the empty result is the shop's or the filters'. Only the second offers a "Clear".
  bool get _filtered => _filter != InventoryFilter.all || _query.isNotEmpty;

  /// inventory-service is not reachable — or this host was given no client at all.
  ///
  /// Stated plainly rather than dressed as an error: nothing the merchant did caused it, and there
  /// is nothing here for them to retry into existence.
  Widget _unavailable(DeliveryStrings t) => _capped(
        YdEmptyState(
          icon: Icons.inventory_2_outlined,
          title: t.invCouldNotLoad,
          message: t.invEmptyHint,
        ),
      );

  /// Holds the design's measure and centres it, so the same widget reads the same way in 380dp of
  /// handset and in 1400px of portal.
  Widget _capped(Widget child) => Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: merchantMaxContentWidth),
          child: child,
        ),
      );

  /// One column on a phone, exactly as the frame draws it; more wherever the window has room.
  ///
  /// The row shape never changes — only how many sit side by side, so there is one row to get
  /// right rather than a phone one and a desktop one.
  Widget _grid(PagedList<InventoryItem> list, {required bool narrow}) {
    final List<InventoryItem> items = list.items;
    final double extent = _rowHeight(context);
    // One extra cell for the footer: a spinner, a retry, or nothing.
    final int count = items.length + 1;

    Widget cell(BuildContext context, int index) {
      if (index == items.length) {
        return _Footer(list: list);
      }
      final InventoryItem item = items[index];
      return _InventoryRow(item: item, onTap: () => _openItem(item));
    }

    return SliverGrid.builder(
      gridDelegate: narrow
          ? SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 1,
              mainAxisSpacing: DeliverySpacing.md - DeliverySpacing.xs,
              mainAxisExtent: extent,
            )
          // An extent rather than a column count: the rail collapses and the window resizes, and
          // this reflows without a breakpoint table to keep in sync with one.
          : SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 460,
              mainAxisSpacing: DeliverySpacing.md - DeliverySpacing.xs,
              crossAxisSpacing: DeliverySpacing.md - DeliverySpacing.xs,
              mainAxisExtent: extent,
            ),
      itemCount: count,
      itemBuilder: cell,
    );
  }

  /// How tall one row has to be, given the reader's font size.
  ///
  /// A grid cell must be told its height, and a height in pixels is a promise about text that only
  /// holds at 100%. The frame's row is a 56px thumbnail inside 12px padding with three short lines
  /// beside it; past the point where the reader's font setting grows that text taller than the
  /// photo, the row has to grow with it.
  double _rowHeight(BuildContext context) {
    // Measured off a real body size rather than `scale(1)`: Android's curve is non-linear, so the
    // factor at one pixel is not the factor at fourteen.
    final double factor = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 2.0);
    const double text = 15 * 1.25 + DeliverySpacing.xs + 12 * 1.3 + DeliverySpacing.xs + 12 * 1.3;
    return <double>[
      _rowImage + _rowPadding * 2,
      text * factor + _rowPadding * 2,
    ].reduce((double a, double b) => a > b ? a : b);
  }
}

/// One shelf, as the frame draws it: photo, name, SKU, and the stock cell that carries the whole
/// point of the screen.
class _InventoryRow extends StatelessWidget {
  const _InventoryRow({required this.item, required this.onTap});

  final InventoryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String? sku = item.sku;

    return YdCard.bordered(
      padding: const EdgeInsets.all(_InventoryScreenState._rowPadding),
      onTap: onTap,
      child: Row(
        children: <Widget>[
          _Thumbnail(
            url: item.listImageUrl,
            label: t.noPhoto,
            unavailableLabel: t.imageUnavailable,
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: DeliverySpacing.xs),
                Text(
                  // A product with no SKU still needs the line, or the row's height changes per
                  // product and the grid stops reading as a list. The barcode is the next best
                  // identifier; failing both, the price is what a merchant recognises the row by.
                  sku != null && sku.isNotEmpty
                      ? t.invSku(sku)
                      : (item.barcode != null && item.barcode!.isNotEmpty
                          ? '${t.invBarcode} ${item.barcode}'
                          // The server's own two-decimal string, never a parsed double.
                          : '\$${item.price.amount}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DeliveryColors.muted,
                    height: 1.3,
                  ),
                ),
                if (item.hidden) ...<Widget>[
                  const SizedBox(height: DeliverySpacing.xs),
                  Text(
                    // Off the storefront, which is a different fact from being out of stock — a
                    // hidden row with forty on the shelf is somebody's forgotten draft.
                    item.status == ProductStatus.draft ? t.draft : t.invFilterHidden,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DeliveryColors.faint,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          _StockCell(item: item),
        ],
      ),
    );
  }
}

/// The number that says how many are left, and the word that says what to think about it.
///
/// An untracked product prints an em dash and "Not tracked" — never a zero. The distinction is the
/// screen's whole reason to exist: a zero on an untracked row would send somebody to restock a
/// shelf that nobody is counting, and would hide a genuine stockout in a list of false ones.
class _StockCell extends StatelessWidget {
  const _StockCell({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    if (!item.tracked) {
      return _cell(
        value: '—',
        caption: t.invNotTracked,
        valueColor: DeliveryColors.faint,
        captionColor: DeliveryColors.faint,
        // Semantics spells it out: a screen reader announcing "dash" would lose the fact.
        semantics: t.invNotTracked,
      );
    }

    final DeliveryAccent? accent = _accentOf(item.severity);
    return _cell(
      value: '${item.available}',
      // The severity's own word when there is something to say, the neutral label otherwise, so
      // the caption is never noise.
      caption: item.severity.isAlerting ? item.severity.labelIn(t) : t.invAvailable,
      valueColor: accent?.color ?? DeliveryColors.ink,
      captionColor: accent?.color ?? DeliveryColors.muted,
      background: accent?.tint,
      semantics: '${t.invAvailable} ${item.available}, ${item.severity.labelIn(t)}',
    );
  }

  /// Severity to accent. `ok` gets none — a healthy shelf is the default, and painting it green
  /// would leave the eye nothing to catch on when something is not.
  static DeliveryAccent? _accentOf(StockSeverity severity) => switch (severity) {
        StockSeverity.ok => null,
        StockSeverity.warning => DeliveryAccent.caution,
        StockSeverity.critical => DeliveryAccent.critical,
        StockSeverity.out => DeliveryAccent.critical,
      };

  Widget _cell({
    required String value,
    required String caption,
    required Color valueColor,
    required Color captionColor,
    required String semantics,
    Color? background,
  }) {
    return Semantics(
      label: semantics,
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 64, maxWidth: 108),
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: DeliverySpacing.sm,
          vertical: DeliverySpacing.xs,
        ),
        decoration: background == null
            ? null
            : BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(merchantChipRadius),
              ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: valueColor,
                height: 1.2,
              ),
            ),
            Text(
              caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: captionColor,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The row's photo, or the glyph that stands in for one.
///
/// [DeliveryProductImage]'s own empty state is an icon over the words "No photo", which needs more
/// height than this row gives it — so the empty slot is the glyph alone, with the sentence attached
/// as a tooltip and a semantic label.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.url,
    required this.label,
    required this.unavailableLabel,
  });

  final String? url;

  /// Already localised by the caller.
  final String label;

  /// What a photo whose presigned link has expired says instead. Also already localised.
  final String unavailableLabel;

  @override
  Widget build(BuildContext context) {
    const double size = _InventoryScreenState._rowImage;

    if (url == null || url!.isEmpty) {
      return Tooltip(
        message: label,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: DeliveryColors.background,
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
          ),
          child: Icon(
            Icons.inventory_2_outlined,
            size: 22,
            color: DeliveryColors.faint,
            semanticLabel: label,
          ),
        ),
      );
    }
    return SizedBox.square(
      dimension: size,
      child: DeliveryProductImage(
        url: url,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        unavailableLabel: unavailableLabel,
      ),
    );
  }
}

/// One figure from the header line: the number over the word it counts.
///
/// A null value prints an em dash rather than a zero — "we have not been told how many products
/// there are" is not "there are no products", and the header is the one place a merchant reads a
/// count without checking it.
class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label});

  final int? value;

  /// Already localised by the caller.
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Text(
          value == null ? '—' : '$value',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
            height: 1.2,
          ),
        ),
        const SizedBox(width: DeliverySpacing.xs),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: DeliveryColors.muted,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

/// The frame's "5 Alerts" pill.
///
/// Tinted amber rather than brand: it is a count of things that need attention, and on a screen
/// where the brand colour is already the primary button it would stop standing for anything.
/// Inert when the host wired no alerts route — the number is still worth showing.
class _AlertsPill extends StatelessWidget {
  const _AlertsPill({required this.label, required this.count, this.onTap});

  /// Already localised by the caller — the whole sentence, for the tooltip and assistive tech.
  final String label;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final BorderRadius corners = BorderRadius.circular(DeliveryRadius.pill);

    final Widget pill = Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: DeliverySpacing.md - DeliverySpacing.xs,
        vertical: DeliverySpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: DeliveryAccent.caution.tint,
        borderRadius: corners,
        border: Border.all(color: DeliveryAccent.caution.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.warning_amber_rounded,
            size: 14,
            color: DeliveryAccent.caution.color,
          ),
          const SizedBox(width: DeliverySpacing.xs),
          Text(
            '$count ${t.invAlerts}',
            maxLines: 1,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: DeliveryAccent.caution.color,
              height: 1.2,
            ),
          ),
          if (onTap != null) ...<Widget>[
            const SizedBox(width: DeliverySpacing.xs),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: DeliveryAccent.caution.color,
            ),
          ],
        ],
      ),
    );

    return Tooltip(
      message: label,
      child: Semantics(
        button: onTap != null,
        label: label,
        excludeSemantics: true,
        child: onTap == null
            ? pill
            : InkWell(
                onTap: onTap,
                borderRadius: corners,
                child: pill,
              ),
      ),
    );
  }
}

/// "Bringing your catalogue in…", while the one-time import runs.
class _SyncingChip extends StatelessWidget {
  const _SyncingChip({required this.label});

  /// Already localised by the caller.
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SizedBox.square(
          dimension: 12,
          child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.brand),
        ),
        const SizedBox(width: DeliverySpacing.sm),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: DeliveryColors.muted,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

/// The last cell in the grid: a spinner while the next page is in flight, a retry when a page
/// failed after earlier ones loaded, nothing otherwise.
///
/// The retry matters more here than on a customer shelf — a merchant scrolling to page four of
/// their inventory is looking for one specific item, and a list that silently stops is a list that
/// says the item does not exist.
class _Footer extends StatelessWidget {
  const _Footer({required this.list});

  final PagedList<InventoryItem> list;

  @override
  Widget build(BuildContext context) {
    if (list.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(DeliverySpacing.md),
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: DeliveryColors.brand),
          ),
        ),
      );
    }
    if (list.error != null && list.items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(DeliverySpacing.sm),
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
}

/// The frame's extended FAB: a brand pill with a plus, lifted by a brand-tinted shadow.
///
/// Not a [FloatingActionButton.extended], which is 56 tall — the frame's is 44, and next to a 56px
/// inventory row the difference is the difference between a button and a landmark.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.onPressed});

  /// Already localised by the caller.
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final BorderRadius corners = BorderRadius.circular(DeliveryRadius.pill);

    return Semantics(
      button: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: corners,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: DeliveryColors.brand.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: DeliveryColors.brand,
          borderRadius: corners,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: DeliverySpacing.lg - DeliverySpacing.xs,
                vertical: DeliverySpacing.md - DeliverySpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.add, size: 18, color: DeliveryColors.white),
                  const SizedBox(width: DeliverySpacing.sm),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: DeliveryColors.white,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pulls the human-readable half out of an RFC 9457 problem response.
///
/// A file-private copy of `product_list_screen.dart`'s, pending the spec's promotion of it into
/// `order_detail_screen.dart` beside `merchantMoney` — done centrally, so this file does not race
/// another screen for the same edit.
String _messageFor(Object error, {required String fallback}) {
  if (error is DioException) {
    final Object? body = error.response?.data;
    if (body is Map<String, dynamic>) {
      final String? detail = body['detail'] as String?;
      final String? correlationId = body['correlationId'] as String?;
      if (detail != null) {
        return correlationId == null ? detail : '$detail (ref: $correlationId)';
      }
    }
  }
  return fallback;
}
