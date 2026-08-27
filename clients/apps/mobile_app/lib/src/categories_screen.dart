import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'product_detail_screen.dart' show CoverCard, CustomerPhoto;
import 'store_state_mapping.dart';

/// The category directory (Figma `customer-categories`, node 3:130).
///
/// A grid of every vertical the storefront sells, each with the number of shops behind it. The
/// counts are asked of the storefront one vertical at a time — a page of size 1, read for its
/// `totalElements` — because there is no counts endpoint and inventing the numbers would make the
/// whole screen decorative. A vertical whose count has not arrived yet simply shows no caption
/// rather than a zero it cannot stand behind.
///
/// Pops with the chosen [StoreVertical]. The caller — the home screen — applies it to the grid it
/// already owns, which is the filtered shop list this screen navigates into.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({
    super.key,
    required this.storeApi,
    this.chips = const <CategoryChip>[],
  });

  final StoreApi storeApi;

  /// The curated strip from the home screen, reused for its names and artwork so the two screens
  /// cannot disagree about what a category is called.
  final List<CategoryChip> chips;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  /// vertical -> how many shops the storefront has in it. Absent until the count lands.
  final Map<StoreVertical, int> _counts = <StoreVertical, int>{};

  bool _loading = true;

  late final List<StoreVertical> _verticals = widget.chips.isEmpty
      ? StoreVertical.values
      : <StoreVertical>{...widget.chips.map((CategoryChip c) => c.vertical)}.toList();

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  /// One tiny request per vertical, in parallel. Each asks for a single card and reads the total
  /// off the page envelope, so nothing here downloads a catalogue to count it.
  Future<void> _loadCounts() async {
    await Future.wait(_verticals.map((StoreVertical vertical) async {
      try {
        final Paged<StoreCard> page = await widget.storeApi
            .browseWith(StoreFilters(vertical: vertical), size: 1);
        if (!mounted) return;
        setState(() => _counts[vertical] = page.totalElements);
      } catch (_) {
        // A count that will not load is not a reason to withhold the category.
      }
    }));
    if (mounted) setState(() => _loading = false);
  }

  CategoryChip? _chipFor(StoreVertical vertical) {
    for (final CategoryChip chip in widget.chips) {
      if (chip.vertical == vertical) return chip;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(
        title: t.custAllCategories,
        onBack: () => Navigator.of(context).maybePop(),
        backSemanticLabel: t.back,
      ),
      body: GridView.builder(
        padding: const EdgeInsetsDirectional.all(DeliverySpacing.lg),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: DeliverySpacing.md,
          mainAxisSpacing: DeliverySpacing.md,
          // 90px cover plus the 12px-padded info block. Fixed rather than a ratio: the card's
          // content is a fixed stack, and a ratio stretches the cover on a wide screen.
          mainAxisExtent: _cardHeight,
        ),
        itemCount: _verticals.length,
        itemBuilder: (BuildContext context, int i) => _card(_verticals[i]),
      ),
    );
  }

  static const double _coverHeight = 90;
  static const double _cardHeight = 152;

  Widget _card(StoreVertical vertical) {
    final CategoryChip? chip = _chipFor(vertical);
    final int? count = _counts[vertical];
    final DeliveryStrings t = DeliveryStrings.of(context);

    return CoverCard(
      onTap: () => Navigator.of(context).pop(vertical),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CustomerPhoto(
            url: chip?.imageUrl,
            width: double.infinity,
            height: _coverHeight,
            icon: iconForVertical(vertical),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(iconForVertical(vertical),
                        size: 16, color: DeliveryColors.brand),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        chip?.name ?? vertical.labelIn(t),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: DeliveryColors.ink,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DeliverySpacing.xs),
                SizedBox(
                  height: 14,
                  child: count == null
                      ? (_loading ? const _CountShimmer() : const SizedBox.shrink())
                      : Text(
                          t.custShopsInCategory(count),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: DeliveryColors.faint,
                            height: 1.2,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Holds the caption's place while its count is in flight, so the grid does not reflow under the
/// reader as the answers arrive one by one.
class _CountShimmer extends StatelessWidget {
  const _CountShimmer();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        width: 54,
        height: 8,
        decoration: BoxDecoration(
          color: DeliveryColors.borderFaint,
          borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        ),
      ),
    );
  }
}
