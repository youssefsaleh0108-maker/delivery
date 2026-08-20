import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'product_form_screen.dart';

/// The Merchant Portal MVP's main screen: everything this merchant owns, in any status.
///
/// Reads `/api/products/mine`, which is scoped to the caller's `sub` server-side — the client never
/// sends a merchant id, and could not widen the result if it tried.
class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key, required this.api});

  final CatalogApi api;

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  late Future<Paged<Product>> _products = widget.api.myProducts();

  void _reload() {
    // Block body, not an arrow: the arrow form returns the future from the closure, and setState
    // asserts against that. Only fires in debug builds, because release strips asserts.
    setState(() {
      _products = widget.api.myProducts();
    });
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
    return Scaffold(
      appBar: AppBar(
        title: Text(DeliveryStrings.of(context).myProducts),
        actions: <Widget>[
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: DeliveryStrings.of(context).refresh,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: DeliveryColors.brand,
        foregroundColor: DeliveryColors.white,
        icon: const Icon(Icons.add),
        label: Text(DeliveryStrings.of(context).newProduct),
      ),
      body: FutureBuilder<Paged<Product>>(
        future: _products,
        builder: (BuildContext context, AsyncSnapshot<Paged<Product>> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(message: _messageFor(snapshot.error!, fallback: DeliveryStrings.of(context).somethingWentWrong), onRetry: _reload);
          }

          final List<Product> products = snapshot.data!.content;
          if (products.isEmpty) {
            return const _EmptyState();
          }

          final int live =
              products.where((Product p) => p.status == ProductStatus.active).length;
          final int drafts =
              products.where((Product p) => p.status == ProductStatus.draft).length;
          final int archived =
              products.where((Product p) => p.status == ProductStatus.archived).length;
          final int noPicture = products.where((Product p) => p.imageUrls.isEmpty).length;

          // A grid, and full width. A product list is a visual scan — "which one is the burger
          // with the bad photo" — and a single column of wide rows makes that scan long and
          // narrow. The Center/ConstrainedBox wrapper that used to be here forced the content
          // into a column in the middle of the page and left the rest of the window empty.
          return CustomScrollView(
            slivers: <Widget>[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(DeliverySpacing.lg, DeliverySpacing.lg,
                    DeliverySpacing.lg, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      StatRow(tiles: <Widget>[
                        StatTile(
                          value: '$live',
                          label: DeliveryStrings.of(context).onSale,
                          icon: Icons.storefront_rounded,
                          accent: DeliveryAccent.positive,
                          footnote: DeliveryStrings.of(context).productsTotal(products.length),
                        ),
                        StatTile(
                          value: '$drafts',
                          label: DeliveryStrings.of(context).drafts,
                          icon: Icons.edit_note_rounded,
                          // A draft is only worth flagging if there is one: nobody needs an amber
                          // tile telling them they have no unfinished work.
                          accent: drafts == 0
                              ? DeliveryAccent.positive
                              : DeliveryAccent.caution,
                        ),
                        StatTile(
                          value: '$noPicture',
                          label: DeliveryStrings.of(context).noPhoto,
                          icon: Icons.image_not_supported_outlined,
                          accent: noPicture == 0
                              ? DeliveryAccent.positive
                              : DeliveryAccent.critical,
                        ),
                        StatTile(
                          value: '$archived',
                          label: DeliveryStrings.of(context).archived,
                          icon: Icons.inventory_2_outlined,
                          accent: DeliveryAccent.neutral,
                        ),
                      ]),
                      const SizedBox(height: DeliverySpacing.lg),
                      SectionLabel(DeliveryStrings.of(context).yourProducts),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(DeliverySpacing.lg, 0, DeliverySpacing.lg,
                    DeliverySpacing.xl * 2),
                sliver: _grid(products),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _grid(List<Product> products) {
          return SliverGrid.builder(
            // maxCrossAxisExtent rather than a fixed column count: the rail can be collapsed and
            // the window resized, and this reflows without a breakpoint table to maintain.
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 340,
              mainAxisSpacing: DeliverySpacing.md,
              crossAxisSpacing: DeliverySpacing.md,
              // A fixed height, not an aspect ratio. Card content varies — some products have a
              // description, some do not — and an aspect ratio would let one long name overflow
              // every card in the row.
              mainAxisExtent: 372,
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
                height: 168,
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
              Positioned(
                top: DeliverySpacing.sm,
                right: DeliverySpacing.sm,
                child: _statusBadge(context, product.status),
              ),
              if (product.imageUrls.length > 1)
                Positioned(
                  bottom: DeliverySpacing.sm,
                  right: DeliverySpacing.sm,
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
                                onPressed: onPublish, child: Text(DeliveryStrings.of(context).publish))
                            : OutlinedButton(onPressed: onEdit, child: Text(DeliveryStrings.of(context).edit)),
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
/// the one that reveals a bad listing — is never opened.
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
          Text(DeliveryStrings.of(context).noProductsYet, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: DeliverySpacing.xs),
          Text(
            DeliveryStrings.of(context).createYourFirstProduct,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: DeliverySpacing.md),
          OutlinedButton(onPressed: onRetry, child: Text(DeliveryStrings.of(context).tryAgain)),
        ],
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
