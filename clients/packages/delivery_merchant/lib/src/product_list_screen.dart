import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'product_form_screen.dart';

/// The merchant's own catalog: everything this shop owns, in any status.
///
/// Reads `/api/products/mine`, which is scoped to the caller's `sub` server-side — the client never
/// sends a merchant id, and could not widen the result if it tried.
///
/// Drawn to the 2026-08 Figma frame `merchant-products` (3:1893): a white screen header over a
/// white search band, a horizontally scrolling category strip, and one bordered row per product
/// carrying a 64px photo, the name, the price in brand, and an availability switch with a state
/// label under it. The switch is the design's whole point — availability is the thing a merchant
/// changes twenty times a day, and it now takes one tap instead of a menu.
///
/// One widget, two hosts. The portal hands it most of a desktop beside its navigation rail; the
/// Android app hands it 360dp and a gesture bar. What changes between them is the column count and
/// whether the page can be pulled to refresh — see [_ProductListScreenState._phoneWidth].
class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key, required this.api, this.storeApi});

  final CatalogApi api;

  /// Only used to read a product's option groups on the form behind this screen — see
  /// [ProductFormScreen.storeApi]. Optional so the hosts that have no [StoreApi] to hand keep
  /// compiling; the form then draws the design's options card in its empty state.
  final StoreApi? storeApi;

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  /// Below this the page is on a phone and lays out in one column.
  ///
  /// Measured against this widget's own constraints rather than the window's: the portal gives the
  /// page whatever is left beside its rail, so a half-width browser is as narrow as a phone here,
  /// and a phone in landscape is not a desktop.
  static const double _phoneWidth = 600;

  /// The photo on a row, and the padding around it. 64 and 12, read off the frame — together they
  /// set the row's floor height at 88 whatever the text does.
  static const double _rowImage = 64;
  static const double _rowPadding = 12;

  /// Room under the last row for the floating "Add Product" button to sit over nothing rather than
  /// over the thing somebody was about to tap.
  static const double _fabClearance = 88;

  late Future<Paged<Product>> _products = widget.api.myProducts();

  /// Fetched once; the category tree does not change while the screen is open. A failure here is
  /// not fatal — the strip simply does not draw and the whole catalog stays visible.
  late final Future<List<Category>> _categories = widget.api.categories();

  final TextEditingController _search = TextEditingController();

  /// Client-side, because `/api/products/mine` takes neither a query nor a category. That is
  /// honest for a shop's own menu — it is one page of its own products, not the storefront index.
  String _query = '';
  String? _category;

  /// Products whose availability switch is mid-flight, so a second tap cannot race the first.
  final Set<String> _busy = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    // Block body, not an arrow: the arrow form returns the future from the closure, and setState
    // asserts against that. Only fires in debug builds, because release strips asserts.
    setState(() {
      _products = widget.api.myProducts();
    });
  }

  /// The same reload, but finishing only when the request does.
  ///
  /// [RefreshIndicator] keeps spinning until its future completes, so it cannot use [_reload] —
  /// that one returns the moment the request is *sent*.
  Future<void> _refresh() {
    final Future<Paged<Product>> pending = widget.api.myProducts();
    setState(() {
      _products = pending;
    });
    // The failure is the FutureBuilder's to render. Letting it escape here would be an uncaught
    // exception and a spinner that never stops.
    return pending.then<void>((Paged<Product> _) {}, onError: (Object _) {});
  }

  Future<void> _openForm([Product? existing]) async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ProductFormScreen(
          api: widget.api,
          storeApi: widget.storeApi,
          existing: existing,
        ),
      ),
    );
    if (saved ?? false) {
      _reload();
    }
  }

  /// The availability switch, in both directions.
  ///
  /// On is `publish` — the service refuses with 422 if the product has no photo yet, and that
  /// reason is worth showing, because the fix (add a photo) is not otherwise obvious. Off is
  /// `archive`, which is the only "not on the shelf" the service offers and is reversible by
  /// publishing again — so the switch really is a switch, not a one-way door.
  Future<void> _setAvailable(Product product, bool available) async {
    if (_busy.contains(product.id)) {
      return;
    }
    final DeliveryStrings t = DeliveryStrings.of(context);

    if (!available) {
      // Kept from the previous screen. Taking a listing off the shelf is not destructive, but it
      // does stop customers finding it, and a mis-tapped switch should not do that silently.
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text(t.archiveThisProduct),
          content: Text(t.archiveConfirm(product.name)),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t.cancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t.archive),
            ),
          ],
        ),
      );
      if (!(confirmed ?? false) || !mounted) {
        return;
      }
    }

    setState(() => _busy.add(product.id));
    try {
      if (available) {
        await widget.api.publish(product.id);
      } else {
        await widget.api.archive(product.id);
      }
      if (!mounted) return;
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_messageFor(e, fallback: t.couldNotPublishProduct)),
      ));
    } finally {
      if (mounted) setState(() => _busy.remove(product.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < _phoneWidth;

        return Scaffold(
          backgroundColor: DeliveryColors.background,
          // No AppBar. The host owns the framing: the portal already draws one above its rail, and
          // the design's own chrome — the 4-tab bar — belongs to whichever app is hosting this.
          floatingActionButton: _AddProductButton(
            label: t.merchbAddProduct,
            onPressed: () => _openForm(),
          ),
          body: Column(
            children: <Widget>[
              YdScreenHeader(
                title: t.merchbMenuItems,
                subtitle: t.merchbManageAvailability,
                // The refresh button only exists where there is no pull gesture to replace it.
                // On a phone it would also centre the title, which the frame does not.
                trailing: narrow
                    ? null
                    : IconButton(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh, size: 20),
                        color: DeliveryColors.ink,
                        tooltip: t.refresh,
                      ),
              ),
              _searchBand(t),
              _categoryStrip(),
              Expanded(child: _list(t, narrow: narrow)),
            ],
          ),
        );
      },
    );
  }

  /// The design's white band under the header, holding the shared search field.
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
        hintText: t.merchbSearchMenuItems,
        onChanged: (String value) => setState(() => _query = value.trim().toLowerCase()),
      ),
    );
  }

  /// The horizontally scrolling category chips, on the page background rather than on the header.
  ///
  /// Drawn only once the taxonomy has loaded, and only when there is more than nothing to filter
  /// by — a strip holding one "All" chip filters nothing and just eats 60px of a phone.
  Widget _categoryStrip() {
    return FutureBuilder<List<Category>>(
      future: _categories,
      builder: (BuildContext context, AsyncSnapshot<List<Category>> snapshot) {
        final List<Category> roots = snapshot.data ?? const <Category>[];
        if (roots.isEmpty) {
          return const SizedBox.shrink();
        }
        final DeliveryStrings t = DeliveryStrings.of(context);

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

  Widget _list(DeliveryStrings t, {required bool narrow}) {
    return FutureBuilder<Paged<Product>>(
      future: _products,
      builder: (BuildContext context, AsyncSnapshot<Paged<Product>> snapshot) {
        final Widget? placeholder = _placeholder(t, snapshot);
        final List<Product> visible = placeholder != null
            ? const <Product>[]
            : _filter(snapshot.data!.content);

        final Widget scroller = CustomScrollView(
          // Always scrollable, or the pull-to-refresh below is dead on the two states where a
          // merchant most wants to retry: nothing loaded, and nothing to show.
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
                    onPressed: () => setState(() {
                      _search.clear();
                      _query = '';
                      _category = null;
                    }),
                    child: Text(t.clear),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  DeliverySpacing.lg,
                  DeliverySpacing.lg,
                  DeliverySpacing.lg,
                  // Clears the floating button, and then the gesture bar under it. `paddingOf`,
                  // not `viewPaddingOf`: a host that already wrapped this in a SafeArea has spent
                  // the inset, and this must not spend it twice.
                  _fabClearance + MediaQuery.paddingOf(context).bottom,
                ),
                sliver: _grid(visible, narrow: narrow),
              ),
          ],
        );

        if (!narrow) {
          return scroller;
        }
        // Pull to refresh, because the refresh button is not drawn at this width.
        return RefreshIndicator(
          onRefresh: _refresh,
          color: DeliveryColors.brand,
          child: scroller,
        );
      },
    );
  }

  List<Product> _filter(List<Product> products) {
    return products.where((Product p) {
      if (_category != null && p.categoryId != _category) {
        return false;
      }
      if (_query.isEmpty) {
        return true;
      }
      return p.name.toLowerCase().contains(_query);
    }).toList();
  }

  /// What goes where the list would be when there is no list to draw.
  ///
  /// Null means the request succeeded and the caller should filter and draw it.
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
        title: t.somethingWentWrong,
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
        title: t.noProductsYet,
        message: t.createYourFirstProduct,
      );
    }
    return null;
  }

  /// One column at phone width, exactly as the frame draws it; more columns wherever the window
  /// has room, because a portal pane 1100px wide showing one 1100px-wide row is a waste of a desk.
  ///
  /// The row shape is identical either way — only how many sit side by side changes.
  Widget _grid(List<Product> products, {required bool narrow}) {
    final double extent = _rowHeight(context);

    return SliverGrid.builder(
      gridDelegate: narrow
          ? SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 1,
              mainAxisSpacing: DeliverySpacing.md - DeliverySpacing.xs,
              mainAxisExtent: extent,
            )
          // maxCrossAxisExtent rather than a fixed column count: the rail can be collapsed and the
          // window resized, and this reflows without a breakpoint table to maintain.
          : SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 420,
              mainAxisSpacing: DeliverySpacing.md - DeliverySpacing.xs,
              crossAxisSpacing: DeliverySpacing.md - DeliverySpacing.xs,
              mainAxisExtent: extent,
            ),
      itemCount: products.length,
      itemBuilder: (BuildContext context, int index) => _ProductRow(
        product: products[index],
        busy: _busy.contains(products[index].id),
        onEdit: () => _openForm(products[index]),
        onAvailability: (bool value) => _setAvailable(products[index], value),
      ),
    );
  }

  /// How tall one row has to be, given the reader's font size.
  ///
  /// A grid cell has to be told its height, and a height in pixels is a promise about text that
  /// only holds at 100%. The frame's row is 88 — a 64px photo inside 12px padding — and the text
  /// beside it (Bold 15 name over SemiBold 14 price) fits inside that until the font setting grows
  /// it past the photo, which is the point where the row has to grow too.
  double _rowHeight(BuildContext context) {
    // Measured off a real body size rather than `scale(1)`: Android 14's curve is non-linear, so
    // the factor at one pixel is not the factor at fourteen.
    final double factor = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 2.0);
    const double text = 15 * 1.25 + DeliverySpacing.xs + 14 * 1.25;
    return <double>[
      _rowImage + _rowPadding * 2,
      text * factor + _rowPadding * 2,
    ].reduce((double a, double b) => a > b ? a : b);
  }
}

/// One product, as the frame draws it: photo, name, price, availability.
///
/// The whole row opens the form — the design gives a row no edit affordance of its own, and the
/// row itself is the largest target on the screen. The photo keeps its own tap, which opens the
/// full-size preview rather than the editor.
class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.busy,
    required this.onEdit,
    required this.onAvailability,
  });

  final Product product;
  final bool busy;
  final VoidCallback onEdit;
  final ValueChanged<bool> onAvailability;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool available = product.status == ProductStatus.active;

    return YdCard.bordered(
      padding: const EdgeInsets.all(_ProductListScreenState._rowPadding),
      onTap: onEdit,
      child: Row(
        children: <Widget>[
          if (product.imageUrls.isEmpty)
            // [DeliveryProductImage]'s own empty state is an icon over the words "No photo", which
            // needs about 66px of height and this row gives it 64 — and at that size the caption is
            // barely readable anyway. So the thumbnail slot falls back to the glyph alone, with the
            // same sentence attached as a semantic label and a tooltip.
            Tooltip(
              message: t.noPhoto,
              child: Container(
                width: _ProductListScreenState._rowImage,
                height: _ProductListScreenState._rowImage,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: DeliveryColors.background,
                  borderRadius: BorderRadius.circular(DeliveryRadius.md),
                ),
                child: Icon(
                  Icons.image_outlined,
                  size: 24,
                  color: DeliveryColors.faint,
                  semanticLabel: t.noPhoto,
                ),
              ),
            )
          else
            SizedBox.square(
              dimension: _ProductListScreenState._rowImage,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: DeliveryProductImage(
                      url: product.imageUrls.first,
                      borderRadius: BorderRadius.circular(DeliveryRadius.md),
                      onTap: () => showProductImagePreview(
                        context,
                        urls: product.imageUrls,
                        title: product.name,
                      ),
                    ),
                  ),
                  // The row shows one photo, and the preview behind it shows all of them — so a
                  // product with several needs to say so, or the extra ones are invisible and the
                  // merchant has no reason to tap. Carried over from the card grid this row
                  // replaced; the design's 64px thumbnail has no room for a caption, so it is a
                  // corner badge with the same sentence attached for assistive tech.
                  if (product.imageUrls.length > 1)
                    PositionedDirectional(
                      end: 3,
                      bottom: 3,
                      child: _PhotoCountBadge(
                        count: product.imageUrls.length,
                        label: t.photoCount(product.imageUrls.length),
                      ),
                    ),
                ],
              ),
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
                const SizedBox(height: DeliverySpacing.xs),
                Text(
                  product.price.toStringAsFixed(2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.brand,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.md),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _AvailabilitySwitch(
                value: available,
                busy: busy,
                semanticLabel: t.merchbAvailability,
                onChanged: onAvailability,
              ),
              const SizedBox(height: DeliverySpacing.xs),
              Text(
                _stateLabel(t, product.status),
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: available ? DeliveryAccent.positive.color : DeliveryColors.faint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The frame labels only two states, "Available" and "Off-shelf". The catalog has three, and the
  /// third one matters: a DRAFT has never been published and usually cannot be, because it has no
  /// photo yet. Collapsing it into "Off-shelf" would hide the one thing the merchant has to fix,
  /// so the draft keeps its own word in the frame's colour and position.
  String _stateLabel(DeliveryStrings t, ProductStatus status) => switch (status) {
        ProductStatus.active => t.merchbAvailable,
        ProductStatus.draft => t.draft,
        ProductStatus.archived => t.merchbOffShelf,
      };
}

/// "This product has more than one photo", in the corner of a 64px thumbnail.
///
/// Deliberately tiny: it rides on top of the photo, and anything larger would cover the thing it
/// is annotating. The count is the useful half, so the glyph is only there to say what the number
/// counts; the whole sentence is on the tooltip and the semantic label.
class _PhotoCountBadge extends StatelessWidget {
  const _PhotoCountBadge({required this.count, required this.label});

  final int count;

  /// Already localised by the caller.
  final String label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: DecoratedBox(
          decoration: BoxDecoration(
            // Ink at 70%, not a solid chip: the photo underneath still reads through it, which is
            // what keeps a 26px badge from looking like a sticker somebody left on the picture.
            color: DeliveryColors.ink.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(DeliveryRadius.sm),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.photo_library_outlined,
                  size: 10,
                  color: DeliveryColors.white,
                ),
                const SizedBox(width: 2),
                Text(
                  '$count',
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.white,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The frame's 48x26 availability toggle.
///
/// Hand-drawn rather than a Material [Switch]: the platform switch is a fixed 52x32 in Material 3
/// and scaling it distorts the thumb, while the row's whole rhythm — a 64px photo, a two-line text
/// stack, and this — is set by the 26px height the design chose.
class _AvailabilitySwitch extends StatelessWidget {
  const _AvailabilitySwitch({
    required this.value,
    required this.busy,
    required this.semanticLabel,
    required this.onChanged,
  });

  final bool value;
  final bool busy;

  /// Already localised by the caller.
  final String semanticLabel;

  final ValueChanged<bool> onChanged;

  static const double _width = 48;
  static const double _height = 26;
  static const double _thumb = 20;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      enabled: !busy,
      label: semanticLabel,
      child: InkWell(
        onTap: busy ? null : () => onChanged(!value),
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          width: _width,
          height: _height,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? DeliveryColors.brand : DeliveryColors.border,
            borderRadius: BorderRadius.circular(DeliveryRadius.pill),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            // Directional, so the switch travels the way the reader reads.
            alignment: value ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
            child: busy
                ? const SizedBox.square(
                    dimension: _thumb,
                    child: Padding(
                      padding: EdgeInsets.all(3),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: DeliveryColors.white,
                      ),
                    ),
                  )
                : Container(
                    width: _thumb,
                    height: _thumb,
                    decoration: BoxDecoration(
                      color: DeliveryColors.white,
                      shape: BoxShape.circle,
                      boxShadow: YdCard.softShadow,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The frame's extended FAB: a brand pill with a plus, lifted by a brand-tinted shadow rather than
/// the neutral one every other surface uses.
///
/// Not a [FloatingActionButton.extended], which is 56 tall — the frame's is 44, and next to a
/// 64px product row the difference is the difference between a button and a landmark.
class _AddProductButton extends StatelessWidget {
  const _AddProductButton({required this.label, required this.onPressed});

  /// Already localised by the caller.
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // The frame says 28 on a 44-tall pill, which is fully rounded — so the pill token says it.
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
/// The service always includes a `correlationId`; showing it lets a merchant quote one value that
/// finds their exact request across every service it touched (Section 10).
/// The fallback is required rather than defaulted: a default would have to be a compile-time
/// constant, which a translated string is not.
String _messageFor(Object error, {required String fallback}) {
  if (error is DioException) {
    final Object? body = error.response?.data;
    if (body is Map<String, dynamic>) {
      final String? detail = body['detail'] as String?;
      final String? correlationId = body['correlationId'] as String?;
      if (detail != null) {
        // The reference is appended in the shape the merchant would read it out over the phone.
        // Not translated: it is a literal id in parentheses, and the surrounding detail is the
        // server's own sentence.
        return correlationId == null ? detail : '$detail (ref: $correlationId)';
      }
    }
  }
  return fallback;
}
