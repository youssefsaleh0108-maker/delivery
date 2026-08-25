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
/// One widget, two hosts. The portal hands it most of a desktop beside its navigation rail; the
/// Android app hands it 360dp and a gesture bar. What changes between them is the column count, the
/// gutter, and whether the page can be pulled to refresh — see [_ProductListScreenState._phoneWidth].
class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key, required this.api});

  final CatalogApi api;

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

  /// The photo at the top of a card. Fixed, because it is the half of the card that carries no
  /// text and so does not grow with the font setting.
  static const double _cardImageHeight = 168;

  /// Everything under that photo at the default text size: the name, the price, up to two lines of
  /// description and the action row.
  static const double _cardTextHeight = 204;

  /// Room under the last card for the floating "New product" button to sit over nothing rather
  /// than over the thing somebody was about to tap. An extended FAB is 56 high and Scaffold gives
  /// it a 16 margin.
  static const double _fabClearance = 88;

  late Future<Paged<Product>> _products = widget.api.myProducts();

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
        builder: (_) => ProductFormScreen(api: widget.api, existing: existing),
      ),
    );
    if (saved ?? false) {
      _reload();
    }
  }

  Future<void> _publish(Product product) async {
    try {
      await widget.api.publish(product.id);
      _reload();
    } catch (e) {
      if (!mounted) return;
      // The service returns 422 when a product has no image yet. Surfacing the reason beats a
      // generic failure toast, since the fix (add a photo) is not obvious otherwise.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_messageFor(e, fallback: DeliveryStrings.of(context).couldNotPublishProduct)),
      ));
    }
  }

  Future<void> _archive(Product product) async {
    // An AlertDialog and not a full-screen route even on a phone: it is two words and two buttons,
    // and Material already sizes it to the viewport. A route would cost an animation and a back
    // stack entry to ask one question.
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(DeliveryStrings.of(context).archiveThisProduct),
        content: Text(
          DeliveryStrings.of(context).archiveConfirm(product.name),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(DeliveryStrings.of(context).cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(DeliveryStrings.of(context).archive),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await widget.api.archive(product.id);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < _phoneWidth;

        // 24 a side on a 360dp phone spends a seventh of the screen on empty margin, and the photo
        // the merchant is trying to judge would rather have it.
        final double gutter = narrow ? DeliverySpacing.md : DeliverySpacing.lg;

        return Scaffold(
          // No AppBar. The host owns the framing: the portal already draws one above its rail, and
          // a second bar on a 640dp-tall phone is a title, a title, and then two products. The page
          // name and its refresh move into the content, which is where every other merchant page
          // keeps them.
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openForm(),
            backgroundColor: DeliveryColors.brand,
            foregroundColor: DeliveryColors.white,
            icon: const Icon(Icons.add),
            label: Text(t.newProduct),
          ),
          body: FutureBuilder<Paged<Product>>(
            future: _products,
            builder: (BuildContext context, AsyncSnapshot<Paged<Product>> snapshot) {
              final List<Product> products =
                  snapshot.hasData ? snapshot.data!.content : const <Product>[];

              // The header renders in every state, so the page does not lose its title and its
              // refresh button exactly when a merchant is looking for them — while it loads, and
              // when it failed to.
              final Widget? placeholder = _placeholder(t, snapshot);

              final Widget scroller = CustomScrollView(
                // Always scrollable, or the pull-to-refresh below is dead on the two states where
                // a merchant most wants to retry: nothing loaded, and nothing to show.
                physics: narrow ? const AlwaysScrollableScrollPhysics() : null,
                slivers: <Widget>[
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  t.myProducts,
                                  style: Theme.of(context).textTheme.headlineMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                onPressed: _reload,
                                icon: const Icon(Icons.refresh),
                                tooltip: t.refresh,
                              ),
                            ],
                          ),
                          if (products.isNotEmpty) ...<Widget>[
                            const SizedBox(height: DeliverySpacing.md),
                            _stats(t, products),
                            const SizedBox(height: DeliverySpacing.lg),
                            SectionLabel(t.yourProducts),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (placeholder != null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: gutter),
                        child: placeholder,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        gutter,
                        0,
                        gutter,
                        // Clears the floating button, and then the gesture bar under it.
                        // `paddingOf`, not `viewPaddingOf`: a host that already wrapped this in a
                        // SafeArea has spent the inset, and this must not spend it twice.
                        _fabClearance + MediaQuery.paddingOf(context).bottom,
                      ),
                      sliver: _grid(products, narrow: narrow),
                    ),
                ],
              );

              if (!narrow) {
                return scroller;
              }
              // Pull to refresh, because the refresh button now scrolls away with the header and a
              // thumb reaches for the gesture anyway.
              return RefreshIndicator(
                onRefresh: _refresh,
                color: DeliveryColors.brand,
                child: scroller,
              );
            },
          ),
        );
      },
    );
  }

  /// What goes where the grid would be when there is no grid to draw.
  ///
  /// Null means there are products and the caller should draw them.
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
      return _ErrorState(
        message: _messageFor(snapshot.error!, fallback: t.somethingWentWrong),
        onRetry: _reload,
      );
    }
    return snapshot.data!.content.isEmpty ? const _EmptyState() : null;
  }

  /// The top-line counts. [StatRow] reflows to whatever columns fit, so four tiles become two rows
  /// of two on a phone without this screen having to say so.
  Widget _stats(DeliveryStrings t, List<Product> products) {
    final int live = products.where((Product p) => p.status == ProductStatus.active).length;
    final int drafts = products.where((Product p) => p.status == ProductStatus.draft).length;
    final int archived = products.where((Product p) => p.status == ProductStatus.archived).length;
    final int noPicture = products.where((Product p) => p.imageUrls.isEmpty).length;

    return StatRow(tiles: <Widget>[
      StatTile(
        value: '$live',
        label: t.onSale,
        icon: Icons.storefront_rounded,
        accent: DeliveryAccent.positive,
        footnote: t.productsTotal(products.length),
      ),
      StatTile(
        value: '$drafts',
        label: t.drafts,
        icon: Icons.edit_note_rounded,
        // A draft is only worth flagging if there is one: nobody needs an amber tile telling them
        // they have no unfinished work.
        accent: drafts == 0 ? DeliveryAccent.positive : DeliveryAccent.caution,
      ),
      StatTile(
        value: '$noPicture',
        label: t.noPhoto,
        icon: Icons.image_not_supported_outlined,
        accent: noPicture == 0 ? DeliveryAccent.positive : DeliveryAccent.critical,
      ),
      StatTile(
        value: '$archived',
        label: t.archived,
        icon: Icons.inventory_2_outlined,
        accent: DeliveryAccent.neutral,
      ),
    ]);
  }

  /// A grid, and full width, at every size — a product list is a visual scan ("which one is the
  /// burger with the bad photo"), and that scan wants columns wherever there is room for them.
  ///
  /// One column below [_phoneWidth] rather than the two that `maxCrossAxisExtent` would still fit
  /// on a 412dp phone: at two the card is ~184 wide, which leaves the Publish button about four
  /// pixels of slack and none at all once the font setting is above 100%.
  Widget _grid(List<Product> products, {required bool narrow}) {
    final double extent = _cardHeight(context);

    return SliverGrid.builder(
      gridDelegate: narrow
          ? SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 1,
              mainAxisSpacing: DeliverySpacing.md,
              mainAxisExtent: extent,
            )
          // maxCrossAxisExtent rather than a fixed column count: the rail can be collapsed and the
          // window resized, and this reflows without a breakpoint table to maintain.
          : SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 340,
              mainAxisSpacing: DeliverySpacing.md,
              crossAxisSpacing: DeliverySpacing.md,
              // A fixed height, not an aspect ratio. Card content varies — some products have a
              // description, some do not — and an aspect ratio would let one long name overflow
              // every card in the row.
              mainAxisExtent: extent,
            ),
      itemCount: products.length,
      itemBuilder: (BuildContext context, int index) => _ProductCard(
        product: products[index],
        onEdit: () => _openForm(products[index]),
        onPublish: () => _publish(products[index]),
        onArchive: () => _archive(products[index]),
      ),
    );
  }

  /// How tall one card has to be, given the reader's font size.
  ///
  /// A grid cell has to be told its height, and a height in pixels is a promise about text that
  /// only holds at 100%. Android's font setting goes to 200%, and somewhere around 130% the name,
  /// price and description stop fitting the 372 the desktop was drawn at — at which point the fixed
  /// extent clips the action row, which is the one part of the card that has to be tappable. Only
  /// the text half scales; the photo is the same 168 whatever the font is.
  double _cardHeight(BuildContext context) {
    // Measured off a real body size rather than `scale(1)`: Android 14's curve is non-linear, so
    // the factor at one pixel is not the factor at fourteen.
    final double factor = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 2.0);
    return _cardImageHeight + _cardTextHeight * factor;
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.onEdit,
    required this.onPublish,
    required this.onArchive,
  });

  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onPublish;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Stack(
            children: <Widget>[
              // The photo leads, because it is what a merchant checks. A DRAFT product with no
              // image is the one that cannot be published, and at this size that is obvious at a
              // glance instead of being an 84px square someone has to squint at.
              DeliveryProductImage(
                url: product.imageUrls.isEmpty ? null : product.imageUrls.first,
                height: _ProductListScreenState._cardImageHeight,
                width: double.infinity,
                borderRadius: BorderRadius.zero,
                onTap: product.imageUrls.isEmpty
                    ? null
                    : () => showProductImagePreview(
                          context,
                          urls: product.imageUrls,
                          title: product.name,
                        ),
              ),
              // Over the image rather than beside the title: whether a product is live is the
              // second thing to know after what it looks like, and this keeps it on the same
              // sweep of the eye.
              //
              // Directional, so the badge sits in the corner the reader's eye ends on — top-right
              // in English, top-left in Arabic.
              PositionedDirectional(
                top: DeliverySpacing.sm,
                end: DeliverySpacing.sm,
                child: _statusBadge(context, product.status),
              ),
              if (product.imageUrls.length > 1)
                PositionedDirectional(
                  bottom: DeliverySpacing.sm,
                  end: DeliverySpacing.sm,
                  child: _PhotoCount(count: product.imageUrls.length),
                ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(DeliverySpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    product.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: DeliverySpacing.xs),
                  Text(
                    product.price.toStringAsFixed(2),
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (product.description != null && product.description!.isNotEmpty) ...<Widget>[
                    const SizedBox(height: DeliverySpacing.xs),
                    Text(
                      product.description!,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const Spacer(),
                  // One primary action plus an overflow menu, always exactly one line high.
                  //
                  // Three buttons in a Wrap was the obvious thing and it was wrong: at three
                  // columns the card is ~250px, the buttons wrap onto a second and third line, and
                  // the card overflows its grid extent. A wrapping action row cannot have a fixed
                  // height, and a grid cell has to.
                  //
                  // The primary is whatever the product's state is waiting for — a DRAFT is
                  // waiting to be published, anything else is only waiting to be edited.
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: product.status == ProductStatus.draft
                            ? ElevatedButton(
                                onPressed: onPublish,
                                child: Text(
                                  DeliveryStrings.of(context).publish,
                                  // A label that cannot shrink is what tears a narrow card open at
                                  // a large font setting.
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )
                            : OutlinedButton(
                                onPressed: onEdit,
                                child: Text(
                                  DeliveryStrings.of(context).edit,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                      ),
                      _OverflowMenu(
                        product: product,
                        onEdit: onEdit,
                        onArchive: onArchive,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Maps catalog status onto the shared badge palette. DRAFT and ARCHIVED are both "not live", so
  /// both use the neutral offline colour; ACTIVE reuses the delivered green for "good to go".
  /// Takes the context: this is a StatelessWidget helper, so there is no `context` field to read.
  Widget _statusBadge(BuildContext context, ProductStatus status) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return switch (status) {
      ProductStatus.draft =>
        DeliveryStatusBadge(status: DeliveryStatusColor.placed, label: t.draft),
      ProductStatus.active =>
        DeliveryStatusBadge(status: DeliveryStatusColor.delivered, label: t.live),
      ProductStatus.archived =>
        DeliveryStatusBadge(status: DeliveryStatusColor.offline, label: t.archived),
    };
  }
}

/// The actions that are not the primary one.
///
/// A menu rather than more buttons, so the card's action row is a fixed height whatever the card's
/// width — see the note at the call site. Hidden entirely when there is nothing left to offer, so
/// an archived product does not get a menu with one disabled item in it.
class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({
    required this.product,
    required this.onEdit,
    required this.onArchive,
  });

  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final bool showEdit = product.status == ProductStatus.draft;
    final bool showArchive = product.status != ProductStatus.archived;

    if (!showEdit && !showArchive) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<String>(
      tooltip: DeliveryStrings.of(context).moreActions,
      icon: const Icon(Icons.more_vert),
      // The default is 40 and a thumb is not a mouse pointer. The menu is the only way to reach
      // Archive, and on a phone it is also the only way to reach Edit on a draft.
      iconSize: 24,
      constraints: const BoxConstraints(minWidth: 48),
      padding: const EdgeInsets.all(DeliverySpacing.sm + 4),
      onSelected: (String value) => value == 'edit' ? onEdit() : onArchive(),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        if (showEdit)
          PopupMenuItem<String>(value: 'edit', child: Text(DeliveryStrings.of(context).edit)),
        if (showArchive)
          PopupMenuItem<String>(value: 'archive', child: Text(DeliveryStrings.of(context).archive)),
      ],
    );
  }
}

/// "3 photos" over the corner of the image, so a card with more than one is discoverable.
///
/// Without it the preview looks like it shows everything there is, and the second photo — usually
/// the one that reveals a bad listing — is never opened. It is a label and not a control: the whole
/// photo above it opens the preview, which is a target no phone user can miss.
class _PhotoCount extends StatelessWidget {
  const _PhotoCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: DeliverySpacing.sm, vertical: DeliverySpacing.xs / 2),
      decoration: BoxDecoration(
        color: DeliveryColors.ink.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.photo_library_outlined, size: 12, color: DeliveryColors.white),
          const SizedBox(width: DeliverySpacing.xs),
          Text('$count',
              style: const TextStyle(fontSize: 11, color: DeliveryColors.white)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        // Horizontal room of its own: the sentence below is two lines on a phone, and a centred
        // Column will happily lay it out from edge to edge.
        padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(DeliverySpacing.lg),
              decoration: const BoxDecoration(
                color: DeliveryColors.brandSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.storefront_outlined, size: 40, color: DeliveryColors.brand),
            ),
            const SizedBox(height: DeliverySpacing.md),
            Text(
              DeliveryStrings.of(context).noProductsYet,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: DeliverySpacing.xs),
            Text(
              DeliveryStrings.of(context).createYourFirstProduct,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              // The message carries a server sentence and a correlation id, which is several lines
              // at 360dp and used to run off the side of it.
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: DeliverySpacing.md),
            OutlinedButton(onPressed: onRetry, child: Text(DeliveryStrings.of(context).tryAgain)),
          ],
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
