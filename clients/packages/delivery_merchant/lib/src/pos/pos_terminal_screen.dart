import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../order_detail_screen.dart' show merchantMoney;

/// How the terminal hands a finished basket to the payment step.
///
/// A function rather than a direct import of the checkout sheet so the till has exactly one route
/// to money and the host decides what that route is — a modal sheet on a phone, a dialog on the
/// portal. Return the settled [PosSale] when the payment went through, the still-open sale when the
/// cashier changed something and backed out, or null when they simply dismissed it.
typedef PosCheckoutRoute = Future<PosSale?> Function(BuildContext context, PosSale sale);

/// The till — Figma `pos-terminal` (94:4345 phone, 94:5092 web).
///
/// A grid of the shop's own products over a basket, and one button that takes money. It is the
/// highest-traffic screen in the suite: a cashier taps a tile every few seconds all day, so the
/// three things that matter here are the size of the tap target, how little of the tree a tap
/// rebuilds, and that a fast double-tap cannot produce two sales or two half-applied lines.
///
/// **One widget, two layouts, handled inside.** Below 1000 logical pixels the basket collapses into
/// a sticky bar that opens it as a sheet; at or above it the basket is a permanent 380px column
/// beside the grid. The split lives here rather than in two files on purpose — a tender bug must
/// not be able to exist in only one of them.
///
/// **The client never prices anything.** Quantities and product ids go up; every figure on screen
/// comes back down inside a whole [PosSale], which replaces the local one wholesale. Nothing here
/// multiplies a price, sums a column, or increments a quantity locally.
///
/// **Money law.** Totals are the sale's own [Money] strings, and its LBP line is the sale's own
/// `totalLbpExact` at the rate it locked when it opened — never today's market rate, which would
/// make a basket disagree with the receipt it is about to print. [MarketRates] appears in exactly
/// two places, both of them previews of something not yet rung up: the price hint on a catalogue
/// tile, and the LBP line of a sale that has not been given a rate yet.
///
/// **Nothing is opened eagerly.** A register that exists before a cashier taps a tile is an open
/// sale nobody meant to start, and both hosts build this tab before it is looked at. So `initState`
/// only *asks* whether a basket and a shift already exist; the first Add is what opens a sale.
class PosTerminalScreen extends StatefulWidget {
  const PosTerminalScreen({
    super.key,
    required this.api,
    required this.catalogApi,
    required this.storeId,
    this.storeApi,
    this.inventoryApi,
    this.onExit,
    this.onCheckout,
    this.onOpenShift,
  });

  /// pos-service. **Nullable**: the service is not deployed yet, and a host that has not wired it
  /// still mounts this screen. Null draws the catalogue with a calm "register unavailable" band
  /// instead of a crash — a merchant can browse, but nothing rings up.
  final PosApi? api;

  /// The shop's own catalogue — the grid. Always present; product-service is live.
  final CatalogApi catalogApi;

  /// The shop the till belongs to. Null on a host that has not resolved it yet (the portal reads it
  /// once at area build), which disables ringing up for the same reason a null [api] does.
  final String? storeId;

  /// Reserved for the register/shift chrome the hosts wire around this screen. Declared so the
  /// shell and the portal can pass what they already hold without this constructor changing again.
  final StoreApi? storeApi;

  /// Reserved for the same reason. Stock is already on [Product.inStock], so the grid needs no
  /// inventory call of its own.
  final InventoryApi? inventoryApi;

  /// Leaves register mode. Null falls back to popping the route when there is one to pop, so the
  /// header's exit is never a dead control.
  final VoidCallback? onExit;

  /// Where "Charge" goes. Null disables the button rather than throwing — see [PosCheckoutRoute].
  final PosCheckoutRoute? onCheckout;

  /// Opens the shift screen. The header only offers to open a shift when there is somewhere to go.
  final VoidCallback? onOpenShift;

  @override
  State<PosTerminalScreen> createState() => _PosTerminalScreenState();
}

class _PosTerminalScreenState extends State<PosTerminalScreen> {
  /// At and above this the basket is a permanent column; below it, a sticky bar and a sheet.
  ///
  /// Measured off this widget's own constraints, never the window's: the portal hands the screen
  /// whatever is left beside its rail, so a half-width browser is as narrow as a phone here.
  static const double _splitWidth = 1000;

  /// The basket column on the wide layout. Wide enough for a line's name, its stepper and its
  /// total on one row without the name being reduced to two words.
  static const double _cartWidth = 380;

  /// One page of the shop's menu. A till that pages its own catalogue makes a cashier hunt, so the
  /// whole menu is fetched once and filtered in memory — the same call the products screen makes,
  /// asked for in one bite.
  static const int _catalogueSize = 200;

  /// The tile's photo, and the padding around the tile's contents.
  static const double _tileImage = 88;
  static const double _tilePadding = DeliverySpacing.sm;

  late Future<Paged<Product>> _catalogue = widget.catalogApi.myProducts(size: _catalogueSize);

  /// Fetched once; the taxonomy does not move while the till is open. A failure is not fatal — the
  /// chip strip simply does not draw and the whole menu stays visible.
  late final Future<List<Category>> _categories = widget.catalogApi.categories();

  final TextEditingController _search = TextEditingController();
  String _query = '';
  String? _category;

  /// The basket, and the tiles/lines with a call in flight.
  ///
  /// Notifiers rather than `setState` fields: a quantity change must repaint the grid badge, the
  /// basket and the bar, and nothing else. On the screen a cashier touches a thousand times a day,
  /// rebuilding the header, the search band and the chip strip for every tap is the difference
  /// between a till that feels instant and one that does not.
  final ValueNotifier<PosSale?> _sale = ValueNotifier<PosSale?>(null);
  final ValueNotifier<Set<String>> _busy = ValueNotifier<Set<String>>(<String>{});

  /// The open drawer, when there is one. Probed once; a failure leaves it null, which is also the
  /// ordinary answer before anybody opens one.
  PosShift? _shift;

  /// In-flight `openSale`, so two tiles tapped in the same second cannot open two registers.
  Future<PosSale>? _opening;

  /// Every basket mutation runs through here, in order.
  ///
  /// Each call returns the whole sale, so two of them racing means the slower answer overwrites the
  /// faster one and a line silently disappears. Serialising costs nothing a cashier can feel and
  /// removes the entire class of bug.
  Future<void> _queue = Future<void>.value();

  bool get _live => widget.api != null && widget.storeId != null;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  @override
  void dispose() {
    _search.dispose();
    _sale.dispose();
    _busy.dispose();
    super.dispose();
  }

  /// Asks — never opens. Both calls are reads, both are allowed to fail in silence: pos-service is
  /// not deployed yet, and a till that shouts on every launch about a service the merchant has not
  /// been given would be noise, not information.
  Future<void> _probe() async {
    final PosApi? api = widget.api;
    final String? storeId = widget.storeId;
    if (api == null || storeId == null) {
      return;
    }
    try {
      final PosShift? shift = await api.currentShift(storeId);
      if (mounted && shift != null) {
        setState(() => _shift = shift);
      }
    } catch (_) {
      // No drawer until a later call says otherwise.
    }
    try {
      final PosSale? resumed = await api.resumeOpen(storeId);
      if (mounted && resumed != null) {
        _sale.value = resumed;
      }
    } catch (_) {
      // No basket to resume; the first Add opens one.
    }
  }

  void _reload() {
    // Block body, not an arrow: the arrow form returns the future from the closure and setState
    // asserts against that.
    setState(() {
      _catalogue = widget.catalogApi.myProducts(size: _catalogueSize);
    });
  }

  /// The same reload, finishing only when the request does, for [RefreshIndicator].
  Future<void> _refresh() {
    final Future<Paged<Product>> pending = widget.catalogApi.myProducts(size: _catalogueSize);
    setState(() {
      _catalogue = pending;
    });
    return pending.then<void>((Paged<Product> _) {}, onError: (Object _) {});
  }

  // ------------------------------------------------------------------ the basket

  /// The sale to add to, opening one if this is the first tap.
  ///
  /// The pending future is held so a second caller awaits the same `openSale` instead of making its
  /// own — two registers for one basket is not a state this screen can recover from.
  Future<PosSale> _ensureSale(PosApi api, String storeId) async {
    final PosSale? existing = _sale.value;
    if (existing != null && existing.isOpen) {
      return existing;
    }
    final Future<PosSale> pending = _opening ??= api.openSale(
      storeId,
      registerId: _shift?.registerId,
      shiftId: _shift?.id,
    );
    try {
      final PosSale opened = await pending;
      if (mounted) {
        _sale.value = opened;
      }
      return opened;
    } finally {
      if (identical(_opening, pending)) {
        _opening = null;
      }
    }
  }

  /// Runs one basket mutation: marked busy under [token], queued behind whatever is already in
  /// flight, and reported to the cashier if it fails.
  void _mutate(String token, Future<PosSale> Function(PosApi api, String storeId) action) {
    final PosApi? api = widget.api;
    final String? storeId = widget.storeId;
    if (api == null || storeId == null) {
      _tell(DeliveryStrings.of(context).posTerminalUnavailable);
      return;
    }
    if (_busy.value.contains(token)) {
      return;
    }
    _setBusy(token, true);
    _queue = _queue.then((void _) async {
      try {
        final PosSale updated = await action(api, storeId);
        if (mounted) {
          _sale.value = updated;
        }
      } catch (e) {
        if (mounted) {
          _tell(_messageFor(e, fallback: DeliveryStrings.of(context).posCouldNotLoadSale));
        }
      } finally {
        _setBusy(token, false);
      }
    });
  }

  void _setBusy(String token, bool busy) {
    if (!mounted) {
      return;
    }
    final Set<String> next = Set<String>.of(_busy.value);
    if (busy ? !next.add(token) : !next.remove(token)) {
      return;
    }
    _busy.value = next;
  }

  /// A tile tap. Always an `addLine`, never a local increment: the server merges an identical line
  /// and re-prices the basket, and a client that incremented its own copy would be the one thing
  /// on this screen able to disagree with the receipt.
  void _add(Product product) {
    _mutate(product.id, (PosApi api, String storeId) async {
      final PosSale sale = await _ensureSale(api, storeId);
      return api.addLine(sale.id, productId: product.id);
    });
  }

  /// The scanner path, and what a cashier gets for pressing enter in the search box.
  ///
  /// A code that matches something already on screen is added without a round trip; anything else
  /// is handed to the server, which knows the SKUs and barcodes this page has not loaded. "No such
  /// code" comes back as a refusal and is shown as one — it is an answer, not an outage.
  void _submitSearch(List<Product> loaded) {
    final String code = _search.text.trim();
    if (code.isEmpty) {
      return;
    }
    final String needle = code.toLowerCase();
    for (final Product product in loaded) {
      if (product.sku?.toLowerCase() == needle || product.barcode?.toLowerCase() == needle) {
        _clearSearch();
        _add(product);
        return;
      }
    }
    _mutate(code, (PosApi api, String storeId) async {
      final PosSale sale = await _ensureSale(api, storeId);
      final PosSale updated = await api.addLine(sale.id, barcode: code);
      _clearSearch();
      return updated;
    });
  }

  void _clearSearch() {
    if (!mounted) {
      return;
    }
    _search.clear();
    setState(() => _query = '');
  }

  void _setQty(PosSaleLine line, int qty) {
    final PosSale? sale = _sale.value;
    if (sale == null) {
      return;
    }
    _mutate(line.id, (PosApi api, String _) => api.setQty(sale.id, line.id, qty));
  }

  /// Abandons the basket. A void, because that is what pos-service calls throwing away an open
  /// sale — and it is confirmed, because a mis-tap here loses a customer's whole order.
  Future<void> _clearSale() async {
    final PosSale? sale = _sale.value;
    final PosApi? api = widget.api;
    if (sale == null || api == null) {
      return;
    }
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(t.posClearSale),
        content: Text(t.posLinesCount(sale.itemCount)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.posClearSale),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) {
      return;
    }
    try {
      await api.voidSale(sale.id, reason: t.posClearSale);
    } catch (e) {
      if (!mounted) {
        return;
      }
      _tell(_messageFor(e, fallback: t.posCouldNotLoadSale));
      return;
    }
    if (!mounted) {
      return;
    }
    _sale.value = null;
  }

  /// Hands the basket to the payment step and reads what comes back.
  ///
  /// A settled sale ends this basket — the next tile tap opens a fresh one. A sale that is still
  /// open replaces the local copy, because the checkout step may have applied a discount before
  /// the cashier backed out of it.
  Future<void> _charge() async {
    final PosSale? sale = _sale.value;
    final PosCheckoutRoute? route = widget.onCheckout;
    if (sale == null || sale.isEmpty || route == null) {
      return;
    }
    final DeliveryStrings t = DeliveryStrings.of(context);
    final PosSale? settled = await route(context, sale);
    if (!mounted || settled == null) {
      return;
    }
    if (settled.isOpen) {
      _sale.value = settled;
      return;
    }
    _sale.value = null;
    _tell(t.posSaleCompleted);
  }

  void _tell(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------ layout

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final VoidCallback? exit =
        widget.onExit ?? (navigator.canPop() ? () => navigator.maybePop<void>() : null);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool split = constraints.maxWidth >= _splitWidth;

        return Scaffold(
          backgroundColor: DeliveryColors.background,
          // No AppBar and no bottom nav: the host owns that framing, and this screen is mounted
          // inside both a rail and a tab bar.
          body: Column(
            children: <Widget>[
              YdScreenHeader(
                title: t.posTitle,
                subtitle: t.dashSwitchToPos,
                onBack: exit,
                backSemanticLabel: t.back,
                trailing: _shiftChip(t),
              ),
              if (!_live) _unavailableBand(t),
              Expanded(
                child: split
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(child: _catalogueColumn(t, narrow: false)),
                          const VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: DeliveryColors.border,
                          ),
                          SizedBox(
                            width: _cartWidth,
                            child: _basket(t, sheet: false),
                          ),
                        ],
                      )
                    : _catalogueColumn(t, narrow: true),
              ),
              if (!split) _stickyBar(t),
            ],
          ),
        );
      },
    );
  }

  /// The header's end slot: what the drawer is doing, or a way to open one.
  Widget? _shiftChip(DeliveryStrings t) {
    final PosShift? shift = _shift;
    if (shift != null && shift.isOpen) {
      return YdBadge.accent(
        label: t.posShiftActive(shift.salesCount),
        accent: DeliveryAccent.positive,
        uppercase: false,
      );
    }
    final VoidCallback? open = widget.onOpenShift;
    if (open == null || !_live) {
      return null;
    }
    return YdChip(label: t.posOpenShift, icon: Icons.lock_open_outlined, onTap: open);
  }

  /// Said once, at the top, in the calmest place available: pos-service is not there.
  ///
  /// The catalogue below stays browsable on purpose — a merchant looking at their own menu is a
  /// working screen, and an empty page would read as a broken app rather than a missing service.
  Widget _unavailableBand(DeliveryStrings t) {
    return Container(
      width: double.infinity,
      color: DeliveryAccent.caution.tint,
      padding: const EdgeInsets.symmetric(
        horizontal: DeliverySpacing.lg,
        vertical: DeliverySpacing.md - DeliverySpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline, size: 18, color: DeliveryAccent.caution.color),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              t.posTerminalUnavailable,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.ink,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _catalogueColumn(DeliveryStrings t, {required bool narrow}) {
    return Column(
      children: <Widget>[
        _searchBand(t),
        _categoryStrip(t),
        Expanded(child: _grid(t, narrow: narrow)),
      ],
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
      child: FutureBuilder<Paged<Product>>(
        future: _catalogue,
        builder: (BuildContext context, AsyncSnapshot<Paged<Product>> snapshot) {
          final List<Product> loaded = snapshot.data?.content ?? const <Product>[];
          return YdSearchField(
            controller: _search,
            hintText: t.posSearchProducts,
            searchSemanticLabel: t.posSearchProducts,
            textInputAction: TextInputAction.search,
            onChanged: (String value) => setState(() => _query = value.trim().toLowerCase()),
            // Enter is the scanner's key. A wedge scanner types the code and presses it, which is
            // why the search box doubles as the scan target rather than there being a second one.
            onSubmitted: (String _) => _submitSearch(loaded),
            filterIcon: Icons.qr_code_scanner,
            filterSemanticLabel: t.posScanBarcode,
            onFilterTap: _live ? () => _submitSearch(loaded) : null,
          );
        },
      ),
    );
  }

  /// All, then the shop's sections. Drawn only once there is more than "All" to choose between.
  Widget _categoryStrip(DeliveryStrings t) {
    return FutureBuilder<List<Category>>(
      future: _categories,
      builder: (BuildContext context, AsyncSnapshot<List<Category>> snapshot) {
        final List<Category> roots = snapshot.data ?? const <Category>[];
        if (roots.isEmpty) {
          return const SizedBox.shrink();
        }
        return SizedBox(
          height: YdChip.minHeight + DeliverySpacing.lg,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsetsDirectional.fromSTEB(
              DeliverySpacing.lg,
              DeliverySpacing.md - DeliverySpacing.xs,
              DeliverySpacing.lg,
              DeliverySpacing.md - DeliverySpacing.xs,
            ),
            children: <Widget>[
              for (final ({String? id, String label}) chip in <({String? id, String label})>[
                (id: null, label: t.all),
                for (final Category category in roots) (id: category.id, label: category.name),
              ]) ...<Widget>[
                YdChip(
                  label: chip.label,
                  selected: _category == chip.id,
                  elevated: true,
                  onTap: () => setState(() => _category = chip.id),
                ),
                const SizedBox(width: 10),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _grid(DeliveryStrings t, {required bool narrow}) {
    return FutureBuilder<Paged<Product>>(
      future: _catalogue,
      builder: (BuildContext context, AsyncSnapshot<Paged<Product>> snapshot) {
        final Widget? placeholder = _placeholder(t, snapshot);
        final List<Product> visible =
            placeholder != null ? const <Product>[] : _filter(snapshot.data!.content);

        final Widget scroller = ListenableBuilder(
          // Repaints on a basket change (the tile's quantity badge), on a busy change (its
          // spinner), and when the market rate lands (the LBP hint) — and on nothing else.
          listenable: Listenable.merge(<Listenable?>[_sale, _busy, MarketRates.instance]),
          builder: (BuildContext context, Widget? _) {
            final Map<String, int> inBasket = _quantities();
            return CustomScrollView(
              physics: narrow ? const AlwaysScrollableScrollPhysics() : null,
              slivers: <Widget>[
                if (placeholder != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.lg),
                      child: placeholder,
                    ),
                  )
                else if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: YdEmptyState(
                      icon: Icons.search_off,
                      title: t.merchbNoMatchingItems,
                      action: TextButton(
                        onPressed: () {
                          _search.clear();
                          setState(() {
                            _query = '';
                            _category = null;
                          });
                        },
                        child: Text(t.clear),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.all(DeliverySpacing.lg),
                    sliver: SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        // 240 on the portal's half of the split, 180 on a phone — two columns at
                        // 380dp, which is the smallest tile a thumb can hit without aiming.
                        maxCrossAxisExtent: narrow ? 180 : 240,
                        mainAxisSpacing: DeliverySpacing.md - DeliverySpacing.xs,
                        crossAxisSpacing: DeliverySpacing.md - DeliverySpacing.xs,
                        mainAxisExtent: _tileExtent(context),
                      ),
                      itemCount: visible.length,
                      itemBuilder: (BuildContext context, int index) {
                        final Product product = visible[index];
                        return _ProductTile(
                          product: product,
                          quantity: inBasket[product.id] ?? 0,
                          busy: _busy.value.contains(product.id),
                          onTap: _live ? () => _add(product) : null,
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        );

        if (!narrow) {
          return scroller;
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          color: DeliveryColors.brand,
          child: scroller,
        );
      },
    );
  }

  /// How many of each catalogue product are already on the basket, for the tile badge.
  Map<String, int> _quantities() {
    final PosSale? sale = _sale.value;
    if (sale == null) {
      return const <String, int>{};
    }
    final Map<String, int> counts = <String, int>{};
    for (final PosSaleLine line in sale.lines) {
      final String? id = line.productId;
      if (id != null) {
        counts[id] = (counts[id] ?? 0) + line.qty;
      }
    }
    return counts;
  }

  List<Product> _filter(List<Product> products) {
    return products.where((Product product) {
      if (product.status == ProductStatus.archived) {
        // An archived listing is off the shelf. It is still in the catalogue, but a till that
        // offers it is a till that sells something the shop has stopped selling.
        return false;
      }
      if (_category != null && product.categoryId != _category) {
        return false;
      }
      if (_query.isEmpty) {
        return true;
      }
      return product.name.toLowerCase().contains(_query) ||
          (product.sku?.toLowerCase().contains(_query) ?? false) ||
          (product.barcode?.toLowerCase().contains(_query) ?? false);
    }).toList();
  }

  Widget? _placeholder(DeliveryStrings t, AsyncSnapshot<Paged<Product>> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(DeliverySpacing.xl),
          child: CircularProgressIndicator(color: DeliveryColors.brand),
        ),
      );
    }
    if (snapshot.hasError) {
      return YdEmptyState(
        icon: Icons.cloud_off_rounded,
        title: t.posCouldNotLoadCatalogue,
        message: _messageFor(snapshot.error!, fallback: t.somethingWentWrong),
        action: YdPillButton.secondary(
          label: t.tryAgain,
          onPressed: _reload,
          size: YdPillButtonSize.compact,
          expand: false,
        ),
      );
    }
    if (snapshot.data!.content.isEmpty) {
      return YdEmptyState(
        icon: Icons.storefront_outlined,
        title: t.posNoProducts,
        message: t.posNoProductsHint,
      );
    }
    return null;
  }

  /// How tall one tile has to be, given the reader's font size.
  ///
  /// A grid cell must be told its height, and a height in pixels is a promise about text that only
  /// holds at 100%. Only the text block scales — the photo is a photo at any font size.
  double _tileExtent(BuildContext context) {
    final double factor = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 2.0);
    // Name over two lines at 13, the price at 14, the LBP hint at 11.
    const double text = 13 * 1.3 * 2 + DeliverySpacing.xs + 14 * 1.25 + 2 + 11 * 1.2;
    return _tileImage + DeliverySpacing.sm + text * factor + _tilePadding * 2;
  }

  // ------------------------------------------------------------------ the basket, drawn

  /// The basket, identical in the wide column and in the phone's sheet.
  Widget _basket(DeliveryStrings t, {required bool sheet}) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable?>[_sale, _busy, MarketRates.instance]),
      builder: (BuildContext context, Widget? _) {
        final PosSale? sale = _sale.value;
        final bool empty = sale == null || sale.isEmpty;

        return Container(
          color: DeliveryColors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _basketHeader(t, sale: sale, empty: empty, sheet: sheet),
              Expanded(
                child: empty
                    ? YdEmptyState(
                        icon: Icons.shopping_bag_outlined,
                        title: t.posCartEmpty,
                        message: t.posCartEmptyHint,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DeliverySpacing.md,
                          vertical: DeliverySpacing.sm,
                        ),
                        itemCount: sale.lines.length,
                        separatorBuilder: (BuildContext context, int _) =>
                            const Divider(height: 1, color: DeliveryColors.borderFaint),
                        itemBuilder: (BuildContext context, int index) {
                          final PosSaleLine line = sale.lines[index];
                          return _BasketLine(
                            line: line,
                            busy: _busy.value.contains(line.id),
                            onQuantity: (int qty) => _setQty(line, qty),
                          );
                        },
                      ),
              ),
              if (!empty) _totals(t, sale),
              _chargeBar(t, sale: sale, empty: empty, inSheet: sheet),
            ],
          ),
        );
      },
    );
  }

  Widget _basketHeader(
    DeliveryStrings t, {
    required PosSale? sale,
    required bool empty,
    required bool sheet,
  }) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        DeliverySpacing.md,
        DeliverySpacing.md - DeliverySpacing.xs,
        DeliverySpacing.sm,
        DeliverySpacing.md - DeliverySpacing.xs,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  t.posCart,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t.posLinesCount(sale?.itemCount ?? 0),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DeliveryColors.faint,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (!empty)
            TextButton(
              onPressed: _clearSale,
              child: Text(t.posClearSale),
            ),
          if (sheet)
            IconButton(
              onPressed: () => Navigator.of(context).maybePop<void>(),
              icon: const Icon(Icons.close, size: 20),
              color: DeliveryColors.muted,
              tooltip: t.back,
            ),
        ],
      ),
    );
  }

  /// The server's own figures, in the server's own order. Nothing here is computed.
  Widget _totals(DeliveryStrings t, PosSale sale) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DeliverySpacing.md,
        DeliverySpacing.sm,
        DeliverySpacing.md,
        0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _totalRow(t.posSubtotal, t.posUsd(sale.subtotal.amount)),
          if (!sale.discount.isZero)
            _totalRow(t.posDiscount, '-${t.posUsd(sale.discount.unsigned)}'),
          if (!sale.tax.isZero) _totalRow(t.posTax, t.posUsd(sale.tax.amount)),
          if (!sale.outstanding.isZero && !sale.paid.isZero)
            _totalRow(t.posOutstanding, t.posUsd(sale.outstanding.amount)),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.3),
            ),
          ),
          Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.ink,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  /// The total and the one button that takes money, at the bottom of the basket.
  Widget _chargeBar(
    DeliveryStrings t, {
    required PosSale? sale,
    required bool empty,
    required bool inSheet,
  }) {
    final String total = t.posUsd(sale?.total.amount ?? '0.00');
    final String? lbp = _lbpLine(t, sale);

    return Container(
      padding: EdgeInsets.fromLTRB(
        DeliverySpacing.md,
        DeliverySpacing.md - DeliverySpacing.xs,
        DeliverySpacing.md,
        DeliverySpacing.md - DeliverySpacing.xs +
            // The sheet spends its own inset; the column sits above whatever the host drew.
            (inSheet ? MediaQuery.paddingOf(context).bottom : 0),
      ),
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(top: BorderSide(color: DeliveryColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: Text(
                  t.posTotal,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.muted,
                    height: 1.3,
                  ),
                ),
              ),
              _MoneyStack(usd: total, lbp: lbp, alignEnd: true),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          YdPillButton(
            label: '${t.posCharge}  $total',
            onPressed: (!empty && _live && widget.onCheckout != null)
                ? () async {
                    if (inSheet) {
                      // The sheet closes first: a half-tendered sale behind a basket sheet is two
                      // layers of modal over the same money.
                      await Navigator.of(context).maybePop<void>();
                    }
                    await _charge();
                  }
                : null,
            icon: Icons.point_of_sale,
          ),
        ],
      ),
    );
  }

  /// The phone's persistent bar: how many, how much, and Charge.
  ///
  /// Drawn even when the basket is empty so the total's position never moves under a thumb that is
  /// already travelling towards it.
  Widget _stickyBar(DeliveryStrings t) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable?>[_sale, MarketRates.instance]),
      builder: (BuildContext context, Widget? _) {
        final PosSale? sale = _sale.value;
        final bool empty = sale == null || sale.isEmpty;
        final String total = t.posUsd(sale?.total.amount ?? '0.00');

        return Container(
          decoration: const BoxDecoration(
            color: DeliveryColors.white,
            border: Border(top: BorderSide(color: DeliveryColors.border)),
          ),
          padding: EdgeInsets.fromLTRB(
            DeliverySpacing.md,
            DeliverySpacing.sm + DeliverySpacing.xs,
            DeliverySpacing.md,
            DeliverySpacing.sm + DeliverySpacing.xs + MediaQuery.paddingOf(context).bottom,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: InkWell(
                  onTap: empty ? null : _openBasketSheet,
                  borderRadius: BorderRadius.circular(DeliveryRadius.md),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.xs),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                t.posLinesCount(sale?.itemCount ?? 0),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: DeliveryColors.muted,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              _MoneyStack(usd: total, lbp: _lbpLine(t, sale), alignEnd: false),
                            ],
                          ),
                        ),
                        if (!empty)
                          const Icon(
                            Icons.keyboard_arrow_up,
                            size: 20,
                            color: DeliveryColors.faint,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
              // Bounded rather than expanded: the label carries the amount, so the button grows
              // with the total instead of squeezing the figure beside it.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: YdPillButton(
                  label: '${t.posCharge}  $total',
                  onPressed: (!empty && _live && widget.onCheckout != null) ? _charge : null,
                  size: YdPillButtonSize.compact,
                  expand: false,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openBasketSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DeliveryColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(DeliveryRadius.sheet)),
      ),
      builder: (BuildContext context) => SafeArea(
        top: false,
        child: SizedBox(
          // Tall enough to hold a real basket, short enough that the grid behind it stays visible
          // — the cashier is still deciding what else to ring up.
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: _basket(DeliveryStrings.of(context), sheet: true),
        ),
      ),
    );
  }

  /// The second currency under the total.
  ///
  /// A sale that has been given a rate renders ITS rate and ITS pounds — the figures the receipt
  /// will carry. Only a basket with no rate yet falls back to the platform rate, and that is a
  /// preview of something not yet rung up.
  String? _lbpLine(DeliveryStrings t, PosSale? sale) {
    if (sale != null && sale.lbpPerUsd > 0 && sale.totalLbpExact > 0) {
      return t.posLbp(_group(sale.totalLbpExact));
    }
    final MarketRates rates = MarketRates.instance;
    final int? cents = sale?.total.minorUnits;
    if (!rates.hasLbp || cents == null || cents == 0) {
      return null;
    }
    return t.posLbp(_group(_previewLbp(cents, rates.lbpPerUsd)));
  }
}

/// The platform-rate preview, rounded to a note that exists — the same thousand [MarketRates]
/// rounds to, computed from integer cents so the dollar figure itself is never parsed.
int _previewLbp(int cents, double rate) => (cents * rate / 100 / 1000).round() * 1000;

/// Thousands separators. Local rather than borrowed from [MarketRates] because that one also
/// appends an English "LBP", and the label around this comes from the ARB.
String _group(int amount) {
  final String digits = amount.abs().toString();
  final StringBuffer out = StringBuffer(amount < 0 ? '-' : '');
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      out.write(',');
    }
    out.write(digits[i]);
  }
  return out.toString();
}

/// A dollar figure with its pounds underneath — USD primary, LBP secondary, everywhere.
class _MoneyStack extends StatelessWidget {
  const _MoneyStack({required this.usd, required this.lbp, required this.alignEnd});

  /// Already localised and already formatted by the caller.
  final String usd;
  final String? lbp;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          usd,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
            height: 1.2,
          ),
        ),
        if (lbp != null)
          Text(
            lbp!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.faint,
              height: 1.3,
            ),
          ),
      ],
    );
  }
}

/// One sellable thing, as a tap target.
///
/// The whole tile is the button — a cashier aims at the picture, not at a control inside it. The
/// quantity already on the basket rides in the corner so a second tap is an informed one.
class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.quantity,
    required this.busy,
    required this.onTap,
  });

  final Product product;
  final int quantity;
  final bool busy;

  /// Null when there is no register to add to; the tile stays legible and stops responding.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final MarketRates rates = MarketRates.instance;
    final String usd = t.posUsd(merchantMoney(product.price));
    final String? lbp = rates.hasLbp
        ? t.posLbp(_group(_previewLbp((product.price * 100).round(), rates.lbpPerUsd)))
        : null;

    // Merged rather than relabelled: the name, the price and the basket count are three Texts that
    // together are one thing a screen reader should read in one breath, and the tap action stays
    // on the card's own InkWell where assistive tech expects it.
    return MergeSemantics(
      child: Tooltip(
        message: product.sku == null ? product.name : '${product.name} · ${t.invSku(product.sku!)}',
        child: YdCard.bordered(
          padding: const EdgeInsets.all(_PosTerminalScreenState._tilePadding),
          onTap: busy ? null : onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                height: _PosTerminalScreenState._tileImage,
                width: double.infinity,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: DeliveryProductImage(
                        url: product.listImageUrl,
                        borderRadius: BorderRadius.circular(DeliveryRadius.md),
                        emptyLabel: t.noPhoto,
                        unavailableLabel: t.imageUnavailable,
                      ),
                    ),
                    if (busy)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: DeliveryColors.white.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(DeliveryRadius.md),
                          ),
                          child: const Center(
                            child: SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: DeliveryColors.brand,
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (quantity > 0)
                      PositionedDirectional(
                        top: 4,
                        end: 4,
                        child: _QuantityBadge(quantity: quantity),
                      )
                    else if (!product.inStock)
                      PositionedDirectional(
                        top: 4,
                        start: 4,
                        child: YdBadge.accent(
                          label: t.invStatusOut,
                          accent: DeliveryAccent.critical,
                          fontSize: 9,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: DeliverySpacing.sm),
              Expanded(
                child: Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: DeliverySpacing.xs),
              Text(
                usd,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.brand,
                  height: 1.25,
                ),
              ),
              if (lbp != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  lbp,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: DeliveryColors.faint,
                    height: 1.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "3 of these are already on the basket", in the corner of a tile.
class _QuantityBadge extends StatelessWidget {
  const _QuantityBadge({required this.quantity});

  final int quantity;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: DeliveryColors.brand,
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
        boxShadow: YdCard.softShadow,
      ),
      child: Text(
        '$quantity',
        maxLines: 1,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: DeliveryColors.white,
          height: 1.1,
        ),
      ),
    );
  }
}

/// One line on the basket: what it is, how many, what it came to.
///
/// The stepper's last decrement is a zero, which is how pos-service is told to take the line off —
/// so there is no separate delete button to mis-tap.
class _BasketLine extends StatelessWidget {
  const _BasketLine({required this.line, required this.busy, required this.onQuantity});

  final PosSaleLine line;
  final bool busy;
  final ValueChanged<int> onQuantity;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  line.isOpenItem && line.productName.isEmpty ? t.posOpenItem : line.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
                if (line.optionsSummary.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    line.optionsSummary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: DeliveryColors.faint,
                      height: 1.3,
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  t.posUsd(line.unitPrice.amount),
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DeliveryColors.muted,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          _QuantityStepper(
            quantity: line.qty,
            busy: busy,
            decreaseLabel: line.qty > 1 ? t.posQuantity : t.posRemoveLine,
            increaseLabel: t.posQuantity,
            onChanged: onQuantity,
          ),
          const SizedBox(width: DeliverySpacing.sm),
          SizedBox(
            width: 68,
            child: Text(
              t.posUsd(line.lineTotal.amount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: DeliveryColors.ink,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Minus, the number, plus. 32px targets, which is the smallest the design draws for a control a
/// cashier hits repeatedly.
class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.busy,
    required this.decreaseLabel,
    required this.increaseLabel,
    required this.onChanged,
  });

  final int quantity;
  final bool busy;

  /// Already localised by the caller.
  final String decreaseLabel;
  final String increaseLabel;

  final ValueChanged<int> onChanged;

  static const double _button = 32;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _StepperButton(
          icon: quantity > 1 ? Icons.remove : Icons.delete_outline,
          semanticLabel: decreaseLabel,
          onPressed: busy ? null : () => onChanged(quantity - 1),
        ),
        SizedBox(
          width: _button,
          child: busy
              ? const Center(
                  child: SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.brand),
                  ),
                )
              : Text(
                  '$quantity',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.2,
                  ),
                ),
        ),
        _StepperButton(
          icon: Icons.add,
          semanticLabel: increaseLabel,
          onPressed: busy ? null : () => onChanged(quantity + 1),
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;

  /// Already localised by the caller.
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel,
      child: Material(
        color: DeliveryColors.background,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(DeliveryRadius.sm),
          child: SizedBox.square(
            dimension: _QuantityStepper._button,
            child: Icon(
              icon,
              size: 16,
              color: onPressed == null ? DeliveryColors.faint : DeliveryColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pulls the human-readable half out of an RFC 9457 problem response.
///
/// A file-private copy of `product_list_screen.dart`'s extractor. The spec promotes this into the
/// package's shared-vocabulary file in the same wave; until that lands, copying it is preferable to
/// this screen swallowing a server's reason for refusing a line.
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
