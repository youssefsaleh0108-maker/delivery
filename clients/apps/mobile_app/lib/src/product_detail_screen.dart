import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'product_options_sheet.dart';

/// The product detail screen the 2026-08 redesign promotes the options sheet into
/// (Figma `customer-product-detail`, node 3:318).
///
/// Same contract as [showProductOptionsSheet] — it returns a [ConfiguredProduct] or null — so a
/// call site swaps one for the other without touching anything downstream. The pricing rule is the
/// sheet's rule and is not relaxed here: every change of selection re-asks the catalog, and the
/// number on the button is the number the server will charge.
Future<ConfiguredProduct?> showProductDetail(
  BuildContext context, {
  required StoreApi api,
  required Product product,
  required List<OptionGroup> groups,
}) {
  return Navigator.of(context).push<ConfiguredProduct>(MaterialPageRoute<ConfiguredProduct>(
    builder: (BuildContext _) =>
        ProductDetailScreen(api: api, product: product, groups: groups),
  ));
}

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.api,
    required this.product,
    required this.groups,
  });

  final StoreApi api;
  final Product product;

  /// The product's questions. An empty list is fine and common — the screen then shows the photo,
  /// the description and a quantity stepper, which is all a product without options has.
  final List<OptionGroup> groups;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  /// groupId -> chosen option ids. Ordered so the receipt reads in menu order.
  final Map<String, List<String>> _chosen = <String, List<String>>{};

  final PageController _gallery = PageController();
  int _galleryPage = 0;

  int _qty = 1;
  PricedSelection? _priced;
  bool _pricing = false;
  String? _priceError;

  /// What the cross-sell endpoint suggested next to this product. Null until it answers; empty
  /// when it answered with nothing — the rail is simply not drawn in either quiet case.
  List<BoughtTogetherSuggestion>? _suggestions;

  /// True while a suggestion's own option groups are being fetched before it opens.
  bool _openingSuggestion = false;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
    // Pre-tick the defaults, so the common case is one tap.
    for (final OptionGroup group in widget.groups) {
      final List<String> defaults = group.options
          .where((ProductOptionChoice o) => o.isDefault && o.available)
          .map((ProductOptionChoice o) => o.id)
          .take(group.maxSelect)
          .toList();
      if (defaults.isNotEmpty) {
        _chosen[group.id] = defaults;
      }
    }
    _reprice();
  }

  @override
  void dispose() {
    _gallery.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    try {
      final List<BoughtTogetherSuggestion> suggestions =
          await widget.api.boughtTogether(widget.product.id);
      if (!mounted) return;
      setState(() => _suggestions = suggestions);
    } catch (_) {
      // No rail. The suggestions are decoration on a page that works without them, and an error
      // banner over a shelf would be louder than the feature.
    }
  }

  /// Opens a suggested product exactly the way the shelf opens one — its own option groups
  /// fetched first, so a product with required options cannot be added half-configured. The
  /// nested page's answer is popped straight through to whoever opened this one.
  Future<void> _openSuggestion(Product product) async {
    if (_openingSuggestion) return;
    setState(() => _openingSuggestion = true);
    List<OptionGroup> groups;
    try {
      groups = await widget.api.productOptions(product.id);
    } catch (_) {
      if (mounted) {
        setState(() => _openingSuggestion = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(DeliveryStrings.of(context).couldNotReachTheServer)));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _openingSuggestion = false);
    final ConfiguredProduct? configured =
        await Navigator.of(context).push<ConfiguredProduct>(
      MaterialPageRoute<ConfiguredProduct>(
        builder: (_) =>
            ProductDetailScreen(api: widget.api, product: product, groups: groups),
      ),
    );
    if (configured != null && mounted) {
      Navigator.of(context).pop(configured);
    }
  }

  List<String> get _allChosen =>
      widget.groups.expand((OptionGroup g) => _chosen[g.id] ?? const <String>[]).toList();

  /// True when every required group has been answered — the button's enabled state.
  bool get _isComplete => widget.groups.every((OptionGroup g) {
        final int count = (_chosen[g.id] ?? const <String>[]).length;
        return count >= g.minSelect && count <= g.maxSelect;
      });

  /// A product with no options never needs a pricing round trip: its unit price is its price.
  bool get _needsPricing => widget.groups.isNotEmpty;

  double get _unitPrice => _priced?.unitPrice ?? widget.product.price;

  Future<void> _reprice() async {
    if (!_needsPricing || !_isComplete) {
      setState(() {
        _priced = null;
        _priceError = null;
      });
      return;
    }
    setState(() => _pricing = true);
    try {
      final PricedSelection priced =
          await widget.api.priceSelection(widget.product.id, _allChosen);
      if (!mounted) return;
      setState(() {
        _priced = priced;
        _priceError = null;
        _pricing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _priceError = DeliveryStrings.of(context).couldNotPriceCombination;
        _pricing = false;
      });
    }
  }

  void _toggle(OptionGroup group, ProductOptionChoice option) {
    setState(() {
      final List<String> current = List<String>.from(_chosen[group.id] ?? const <String>[]);
      if (group.singleChoice) {
        // Radio behaviour. Re-tapping the selected option in a *required* group keeps it —
        // otherwise the customer can leave a mandatory question unanswered by mistake.
        if (current.contains(option.id) && !group.required) {
          current.clear();
        } else {
          current
            ..clear()
            ..add(option.id);
        }
      } else if (current.contains(option.id)) {
        current.remove(option.id);
      } else if (current.length < group.maxSelect) {
        current.add(option.id);
      } else {
        // At the limit. Say so rather than silently ignoring the tap.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(DeliveryStrings.of(context).chooseUpTo(group.maxSelect, group.name)),
          duration: const Duration(seconds: 2),
        ));
        return;
      }
      _chosen[group.id] = current;
    });
    _reprice();
  }

  /// The first unanswered required group — the button says so instead of a price.
  bool get _missingRequired => widget.groups.any((OptionGroup g) =>
      (_chosen[g.id] ?? const <String>[]).length < g.minSelect);

  void _add() {
    Navigator.of(context).pop(ConfiguredProduct(
      product: widget.product,
      optionIds: _allChosen,
      unitPrice: _unitPrice,
      summary:
          _priced?.options.map((ChosenOption o) => o.summary).join(', ') ?? '',
      qty: _qty,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          _hero(),
          _sheet(),
          _relatedProducts(),
          const SizedBox(height: DeliverySpacing.lg),
        ],
      ),
    );
  }

  /// 280px full-bleed photo with a single translucent back button, per the frame. No scrim: the
  /// shop hero has one, this one deliberately does not.
  Widget _hero() {
    final List<String> images = widget.product.imageUrls;
    return SizedBox(
      height: _heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (images.length <= 1)
            CustomerPhoto(
              url: images.isEmpty ? null : images.first,
              height: _heroHeight,
              icon: Icons.fastfood_outlined,
            )
          else ...<Widget>[
            PageView.builder(
              controller: _gallery,
              itemCount: images.length,
              onPageChanged: (int i) => setState(() => _galleryPage = i),
              itemBuilder: (BuildContext _, int i) => CustomerPhoto(
                url: images[i],
                height: _heroHeight,
                icon: Icons.fastfood_outlined,
              ),
            ),
            PositionedDirectional(
              bottom: DeliverySpacing.md,
              start: 0,
              end: 0,
              child: _galleryDots(images.length),
            ),
          ],
          PositionedDirectional(
            top: DeliverySpacing.lg,
            start: DeliverySpacing.lg,
            child: GlassCircleButton(
              icon: Directionality.of(context) == TextDirection.rtl
                  ? Icons.chevron_right
                  : Icons.chevron_left,
              // The product hero's button is a dark scrim disc, not the shop hero's white glass.
              background: DeliveryColors.ink.withValues(alpha: 0.25),
              semanticLabel: DeliveryStrings.of(context).back,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }

  static const double _heroHeight = 280;

  Widget _galleryDots(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int i = 0; i < count; i++)
          Container(
            width: i == _galleryPage ? 18 : 6,
            height: 6,
            margin: const EdgeInsetsDirectional.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: i == _galleryPage
                  ? DeliveryColors.white
                  : DeliveryColors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(DeliveryRadius.pill),
            ),
          ),
      ],
    );
  }

  /// The white sheet under the photo: name, price, description, the variant groups, and the
  /// add-to-basket row. 24px rounded top corners and the design's heavier `0 8 12` lift.
  Widget _sheet() {
    final Product product = widget.product;
    final String? description = product.description;

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.lg),
      decoration: BoxDecoration(
        color: DeliveryColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(DeliveryRadius.sheet)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: DeliveryColors.ink.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            product.name,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
              height: 1.2,
            ),
          ),
          const SizedBox(height: DeliverySpacing.sm),
          // The design pairs this with a struck-through "was" price. The catalog has no previous
          // price to strike through, and inventing one would be inventing a discount, so only the
          // live price is drawn.
          Text(
            _unitPrice.toStringAsFixed(2),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.brand,
              height: 1.2,
            ),
          ),
          if (description != null && description.isNotEmpty) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Text(
              description,
              style: const TextStyle(
                fontSize: 14,
                color: DeliveryColors.muted,
                height: 1.45,
              ),
            ),
          ],
          if (widget.groups.isNotEmpty) ...<Widget>[
            const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
            const Divider(height: 1, thickness: 1, color: DeliveryColors.border),
            for (final OptionGroup group in widget.groups) _variantSection(group),
          ],
          if (_priceError != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            Text(
              _priceError!,
              style: const TextStyle(fontSize: 12.5, color: DeliveryColors.brand),
            ),
          ],
          const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
          _actionRow(),
        ],
      ),
    );
  }

  Widget _variantSection(OptionGroup group) {
    final List<String> chosen = _chosen[group.id] ?? const <String>[];
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: DeliverySpacing.lg - DeliverySpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  group.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                  ),
                ),
              ),
              // Keeps the rule visible — the sheet showed it and a required group that looks
              // optional is how a customer reaches a disabled button without knowing why.
              Text(
                group.required
                    ? DeliveryStrings.of(context).required
                    : DeliveryStrings.of(context).optional,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: group.required ? DeliveryColors.brand : DeliveryColors.faint,
                ),
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (final ProductOptionChoice option in group.options)
                _variantPill(group, option, selected: chosen.contains(option.id)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _variantPill(
    OptionGroup group,
    ProductOptionChoice option, {
    required bool selected,
  }) {
    final bool enabled = option.available;
    final String label = option.deltaLabel.isEmpty
        ? option.name
        : '${option.name} (${option.deltaLabel})';

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: VariantPill(
        label: enabled
            ? label
            : DeliveryStrings.of(context).optionSoldOut(option.name),
        selected: selected,
        onTap: enabled ? () => _toggle(group, option) : null,
      ),
    );
  }

  Widget _actionRow() {
    final bool canAdd = _isComplete &&
        !_pricing &&
        _priceError == null &&
        (!_needsPricing || _priced != null);
    final double total = _unitPrice * _qty;

    return Row(
      children: <Widget>[
        QuantityStepper(
          quantity: _qty,
          onDecrease: _qty > 1 ? () => setState(() => _qty--) : null,
          onIncrease: _qty < 99 ? () => setState(() => _qty++) : null,
        ),
        const SizedBox(width: DeliverySpacing.md),
        Expanded(
          child: _cta(canAdd: canAdd, total: total),
        ),
      ],
    );
  }

  /// The design's 48px fully-rounded CTA: a SemiBold label and, beside it, the live line total in
  /// a lighter weight.
  Widget _cta({required bool canAdd, required double total}) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Semantics(
      button: true,
      enabled: canAdd,
      child: Material(
        color: canAdd ? DeliveryColors.brand : DeliveryColors.faint,
        borderRadius: BorderRadius.circular(DeliveryRadius.sheet),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: canAdd ? _add : null,
          child: SizedBox(
            height: 48,
            child: Center(
              child: _pricing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: DeliveryColors.white),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          _missingRequired ? t.selectRequiredOptions : t.custAddToBasket,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: DeliveryColors.white,
                          ),
                        ),
                        if (!_missingRequired) ...<Widget>[
                          const SizedBox(width: DeliverySpacing.sm),
                          Text(
                            '•  ${total.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: DeliveryColors.white.withValues(alpha: 0.82),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// The cross-sell rail, wired to what the backend honestly computes: item co-occurrence in
  /// delivered baskets, padded with same-shelf items when the counts run out.
  ///
  /// The section title says which of those it is showing — "Often bought together" only when at
  /// least one row was actually counted from baskets, the same-shelf title when everything is
  /// fill — and a row shows its count only when the server sent one. Nothing is drawn at all
  /// until the endpoint answers, and nothing when it answers empty: an empty recommendation rail
  /// is not a feature.
  Widget _relatedProducts() {
    final List<BoughtTogetherSuggestion>? suggestions = _suggestions;
    if (suggestions == null || suggestions.isEmpty) {
      return const SizedBox.shrink();
    }
    final DeliveryStrings t = DeliveryStrings.of(context);

    final bool anyCounted = suggestions
        .any((BoughtTogetherSuggestion s) => s.basis == CrossSellBasis.boughtTogether);
    final bool allSameShelf = suggestions
        .every((BoughtTogetherSuggestion s) => s.basis == CrossSellBasis.sameAisle);
    final String title = anyCounted
        ? t.crossSellBoughtTogether
        : allSameShelf
            ? t.crossSellSameShelf
            : t.crossSellYouMightAlsoLike;

    return Padding(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          YdSectionHeader(title: title),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: suggestions.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
              itemBuilder: (BuildContext context, int i) =>
                  _suggestionCard(t, suggestions[i]),
            ),
          ),
        ],
      ),
    );
  }

  /// One suggestion in the frame's related-card geometry: the 48px photo tile, the name over the
  /// price, and — only for a counted pair — how many baskets held both.
  Widget _suggestionCard(DeliveryStrings t, BoughtTogetherSuggestion suggestion) {
    final Product product = suggestion.product;

    return Semantics(
      button: true,
      child: Material(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openingSuggestion ? null : () => _openSuggestion(product),
          child: Container(
            width: 200,
            padding: const EdgeInsetsDirectional.all(DeliverySpacing.sm),
            child: Row(
              children: <Widget>[
                CustomerPhoto(
                  url: product.imageUrls.isEmpty ? null : product.imageUrls.first,
                  width: 48,
                  height: 48,
                  radius: DeliveryRadius.sm,
                  icon: Icons.fastfood_outlined,
                ),
                const SizedBox(width: 10),
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
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: DeliveryColors.ink,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: <Widget>[
                          Text(
                            product.price.toStringAsFixed(2),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: DeliveryColors.brand,
                              height: 1.2,
                            ),
                          ),
                          // The count exists only on rows counted from delivered baskets.
                          // A same-shelf row claims no popularity, so none is rendered.
                          if (suggestion.ordersTogether != null) ...<Widget>[
                            const SizedBox(width: DeliverySpacing.sm),
                            Flexible(
                              child: Text(
                                t.crossSellTogetherCount(suggestion.ordersTogether!),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: DeliveryColors.faint,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
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

// ---------------------------------------------------------------------------------------------
// Shared customer-surface parts.
//
// These belong in `delivery_design_system` beside the other `Yd*` widgets, and that is where they
// should end up. They live here for now because the redesign work that introduced them was scoped
// to the customer screens, and this is the file where the design first draws each of them. Every
// measurement below is read off the Figma frames rather than estimated.
// ---------------------------------------------------------------------------------------------

/// The quantity stepper shared by `customer-product-detail` (3:344) and every basket row (3:406).
///
/// A [DeliveryColors.background] track, a white minus disc, the count, and a brand plus disc.
/// A null callback disables that side, which is how the design draws a stepper sitting at 1.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.quantity,
    this.onDecrease,
    this.onIncrease,
    this.decreaseIcon = Icons.remove,
  });

  final int quantity;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  /// Swapped for a bin on a basket row sitting at one, where decrementing removes the line.
  final IconData decreaseIcon;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: DeliverySpacing.sm, vertical: DeliverySpacing.xs),
      decoration: BoxDecoration(
        color: DeliveryColors.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _button(
            icon: decreaseIcon,
            background: DeliveryColors.white,
            foreground: DeliveryColors.ink,
            onPressed: onDecrease,
            semanticLabel: t.custDecreaseQuantity,
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.ink,
              ),
            ),
          ),
          _button(
            icon: Icons.add,
            background: DeliveryColors.brand,
            foreground: DeliveryColors.white,
            onPressed: onIncrease,
            semanticLabel: t.custIncreaseQuantity,
          ),
        ],
      ),
    );
  }

  Widget _button({
    required IconData icon,
    required Color background,
    required Color foreground,
    required VoidCallback? onPressed,
    required String semanticLabel,
  }) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel,
      child: Opacity(
        opacity: onPressed == null ? 0.4 : 1,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox.square(
              dimension: 24,
              child: Icon(icon, size: 12, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}

/// The 28px circular brand add button on every shelf and home tile (Figma `add`, 3:98).
class AddButton extends StatelessWidget {
  const AddButton({super.key, required this.onPressed, this.semanticLabel});

  final VoidCallback? onPressed;
  final String? semanticLabel;

  static const double dimension = 28;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel,
      child: Opacity(
        opacity: onPressed == null ? 0.4 : 1,
        child: Material(
          color: DeliveryColors.brand,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: const SizedBox.square(
              dimension: dimension,
              child: Icon(Icons.add, size: 14, color: DeliveryColors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// The 36px translucent disc the design floats over a hero photo (Figma `back` / `search` /
/// `heart`, 3:233–3:238).
class GlassCircleButton extends StatelessWidget {
  const GlassCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.background,
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  /// Defaults to the shop hero's white glass; the product hero uses a dark disc instead.
  final Color? background;
  final String? semanticLabel;

  static const double dimension = 36;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: background ?? DeliveryColors.white.withValues(alpha: 0.25),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: dimension,
            child: Icon(icon, size: 16, color: DeliveryColors.white),
          ),
        ),
      ),
    );
  }
}

/// The card that leads with a full-bleed cover (Figma `shop-card` 3:65, `grid-card` 3:142).
///
/// Distinct from [YdCard] in exactly one measurement: these two carry the design's wider
/// `0 4 12` lift rather than the `0 4 6` every other card uses, so they are built here instead of
/// through the shared card.
class CoverCard extends StatelessWidget {
  const CoverCard({super.key, required this.child, this.onTap, this.width});

  final Widget child;
  final VoidCallback? onTap;
  final double? width;

  static List<BoxShadow> get shadow => <BoxShadow>[
        BoxShadow(
          color: DeliveryColors.ink.withValues(alpha: 0.03),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final BorderRadius corners = BorderRadius.circular(DeliveryRadius.lg);
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: corners, boxShadow: shadow),
        child: Material(
          color: DeliveryColors.white,
          borderRadius: corners,
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: child),
        ),
      ),
    );
  }
}

/// The design's variant pill (Figma `variant-pill-active` / `variant-pill`, 3:339–3:341).
///
/// Selected is the brand tint with a brand hairline and a SemiBold brand label; unselected is
/// white with the ordinary card border and a muted Regular label.
class VariantPill extends StatelessWidget {
  const VariantPill({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
  });

  /// Already localised, or a name straight from the catalog.
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      selected: selected,
      child: Material(
        color: selected ? DeliveryColors.brandSoft : DeliveryColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected ? DeliveryColors.brand : DeliveryColors.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: DeliverySpacing.md, vertical: DeliverySpacing.sm),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? DeliveryColors.brand : DeliveryColors.muted,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A photo slot that fills its box and degrades to a styled placeholder.
///
/// Distinct from `DeliveryProductImage`: that one carries its own English caption and its own
/// radius conventions, and the customer frames want a silent slot at an exact size instead.
/// Sizes are always given explicitly by the caller, because every image in this design has a
/// measured box.
class CustomerPhoto extends StatelessWidget {
  const CustomerPhoto({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.radius = 0,
    this.icon = Icons.image_outlined,
  });

  final String? url;
  final double? width;
  final double? height;
  final double radius;

  /// The glyph shown when there is no photo — a vertical-appropriate one reads better than a
  /// generic frame.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final Widget placeholder = ColoredBox(
      color: DeliveryColors.borderFaint,
      child: Center(
        child: Icon(icon, size: 22, color: DeliveryColors.faint),
      ),
    );

    Widget content;
    if (url == null || url!.isEmpty) {
      content = placeholder;
    } else {
      content = Image.network(
        url!,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (BuildContext _, Widget child, ImageChunkEvent? progress) =>
            progress == null ? child : placeholder,
      );
    }

    content = SizedBox(width: width, height: height, child: content);
    return radius == 0
        ? content
        : ClipRRect(borderRadius: BorderRadius.circular(radius), child: content);
  }
}
