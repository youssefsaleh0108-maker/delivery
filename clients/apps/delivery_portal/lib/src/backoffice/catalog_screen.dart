import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

/// Read-only view of the live catalog across every merchant.
///
/// Uses the same public browse endpoint the customer app will, so it shows exactly what a customer
/// would see — ACTIVE products only. Drafts and archived items are invisible here by design; a
/// merchant's unpublished pricing is not Backoffice's business until it goes live.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.api});

  final CatalogApi api;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final TextEditingController _search = TextEditingController();
  late Future<Paged<Product>> _products = widget.api.browse();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _run() {
    // Block body, not an arrow - see the note in settings_screen.dart.
    setState(() {
      _products = widget.api.browse(search: _search.text.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    // No Center/ConstrainedBox wrapper. A child page of the rail shell should fill the width it
    // is given; the wrapper that used to be here was a no-op once its max width was removed, and
    // leaving it in suggests a constraint that no longer exists.
    return Padding(
          padding: const EdgeInsets.all(DeliverySpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Live catalog', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: DeliverySpacing.md),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        labelText: 'Search products',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onSubmitted: (_) => _run(),
                    ),
                  ),
                  const SizedBox(width: DeliverySpacing.sm),
                  ElevatedButton(onPressed: _run, child: const Text('Search')),
                ],
              ),
              const SizedBox(height: DeliverySpacing.lg),
              Expanded(
                child: FutureBuilder<Paged<Product>>(
                  future: _products,
                  builder: (BuildContext context, AsyncSnapshot<Paged<Product>> snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Could not load: ${snapshot.error}'));
                    }

                    final Paged<Product> page = snapshot.data!;
                    if (page.content.isEmpty) {
                      return const Center(
                        child: Text('No live products yet. Publish one from the Merchant Portal.'),
                      );
                    }

                    // Same grid as the Merchant Portal, deliberately: this screen shows exactly
                    // what a customer would see, and it should look like a catalog rather than a
                    // spreadsheet of it. Shorter cards than the portal's — there are no actions
                    // here, only a look.
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SectionLabel(
                          'Live across every merchant',
                          trailing: Text(
                            '${page.totalElements} products',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: DeliveryColors.muted),
                          ),
                        ),
                        Expanded(
                          child: GridView.builder(
                            padding: EdgeInsets.zero,
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 340,
                              mainAxisSpacing: DeliverySpacing.md,
                              crossAxisSpacing: DeliverySpacing.md,
                              mainAxisExtent: 296,
                            ),
                            itemCount: page.content.length,
                            itemBuilder: (BuildContext context, int index) =>
                                _CatalogCard(product: page.content[index]),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
    );
  }
}

/// One live product, as a customer would see it.
///
/// No actions: the Backoffice looks at the catalog, it does not edit it. A merchant's own portal is
/// the only place a product changes, and putting an Edit button here would imply otherwise.
class _CatalogCard extends StatelessWidget {
  const _CatalogCard({required this.product});

  final Product product;

  /// Keycloak subs are full UUIDs; the first segment is enough to tell merchants apart on screen.
  static String _short(String id) => id.length <= 8 ? id : id.substring(0, 8);

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Stack(
            children: <Widget>[
              DeliveryProductImage(
                // The 320px derivative, not the merchant original - the same swap the merchant
                // portal made on its product rows. The tap below still opens the full-size
                // gallery, which is what a merchant checking their own photo wants to see.
                url: product.listImageUrl,
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
              const Positioned(
                top: DeliverySpacing.sm,
                right: DeliverySpacing.sm,
                // Everything on this screen is live by definition — the endpoint returns ACTIVE
                // products only — but saying so beats leaving the reader to remember it.
                child: DeliveryStatusBadge(
                  status: DeliveryStatusColor.delivered,
                  label: 'Live',
                ),
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
                  const Spacer(),
                  Text(
                    'merchant ${_short(product.merchantId)}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: DeliveryColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
