import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

// The stepper and the CTA are the redesign's, shared with the full product screen that replaced
// this sheet on the shop page. See the note at the foot of that file for why they live there.
import 'product_detail_screen.dart' show QuantityStepper;

/// What the customer chose, and what the catalog says it costs.
class ConfiguredProduct {
  const ConfiguredProduct({
    required this.product,
    required this.optionIds,
    required this.unitPrice,
    required this.summary,
    this.qty = 1,
  });

  final Product product;
  final List<String> optionIds;
  final double unitPrice;

  /// "Choose Size: Large (36 Cm), Extras: Extra cheese" — as the server phrased it.
  final String summary;
  final int qty;
}

/// Asks a product's questions before it goes in the basket.
///
/// Prices are never computed here. Every change re-asks the catalog, which is the same endpoint
/// Order Manager calls at checkout — so the number on this button is the number that gets charged,
/// by construction rather than by two implementations agreeing.
///
/// The 2026-08 redesign promotes this to a full screen — see `product_detail_screen.dart`, which
/// the shop page now opens instead. The sheet stays for any caller that wants the lighter surface,
/// restyled to the same visual language so the two do not read as two different products.
Future<ConfiguredProduct?> showProductOptionsSheet(
  BuildContext context, {
  required StoreApi api,
  required Product product,
  required List<OptionGroup> groups,
}) {
  return showModalBottomSheet<ConfiguredProduct>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DeliveryColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(DeliveryRadius.sheet)),
    ),
    builder: (BuildContext context) =>
        _OptionsSheet(api: api, product: product, groups: groups),
  );
}

class _OptionsSheet extends StatefulWidget {
  const _OptionsSheet({required this.api, required this.product, required this.groups});

  final StoreApi api;
  final Product product;
  final List<OptionGroup> groups;

  @override
  State<_OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends State<_OptionsSheet> {
  /// groupId -> chosen option ids. Ordered so the receipt reads in menu order.
  final Map<String, List<String>> _chosen = <String, List<String>>{};

  int _qty = 1;
  PricedSelection? _priced;
  bool _pricing = false;
  String? _priceError;

  @override
  void initState() {
    super.initState();
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

  List<String> get _allChosen =>
      widget.groups.expand((OptionGroup g) => _chosen[g.id] ?? const <String>[]).toList();

  /// True when every required group has been answered — the button's enabled state.
  bool get _isComplete => widget.groups.every((OptionGroup g) {
        final int count = (_chosen[g.id] ?? const <String>[]).length;
        return count >= g.minSelect && count <= g.maxSelect;
      });

  Future<void> _reprice() async {
    if (!_isComplete) {
      // Nothing to price yet; the button stays disabled and says what is missing.
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
    } catch (e) {
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

  /// The first unanswered required group, for the button label.
  String? get _missing {
    for (final OptionGroup group in widget.groups) {
      if ((_chosen[group.id] ?? const <String>[]).length < group.minSelect) {
        return group.name;
      }
    }
    return null;
  }

  void _add() {
    final PricedSelection? priced = _priced;
    if (priced == null) return;
    Navigator.of(context).pop(ConfiguredProduct(
      product: widget.product,
      optionIds: _allChosen,
      unitPrice: priced.unitPrice,
      summary: priced.options.map((ChosenOption o) => o.summary).join(', '),
      qty: _qty,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final double total = (_priced?.unitPrice ?? widget.product.price) * _qty;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (BuildContext context, ScrollController controller) => Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsetsDirectional.fromSTEB(DeliverySpacing.lg,
                  DeliverySpacing.sm, DeliverySpacing.lg, DeliverySpacing.md),
              children: <Widget>[
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: DeliveryColors.border,
                      borderRadius: BorderRadius.circular(DeliveryRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: DeliverySpacing.md),
                Text(widget.product.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: DeliveryColors.ink,
                      height: 1.2,
                    )),
                const SizedBox(height: DeliverySpacing.sm),
                Text(
                  widget.product.price.toStringAsFixed(2),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.brand,
                  ),
                ),
                if (widget.product.description != null &&
                    widget.product.description!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: DeliverySpacing.sm),
                  Text(widget.product.description!,
                      style: const TextStyle(
                          fontSize: 14, color: DeliveryColors.muted, height: 1.45)),
                ],
                const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
                const Divider(height: 1, thickness: 1, color: DeliveryColors.border),
                for (final OptionGroup group in widget.groups) _group(group),
              ],
            ),
          ),
          _footer(total),
        ],
      ),
    );
  }

  Widget _group(OptionGroup group) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: DeliverySpacing.lg - DeliverySpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(group.name,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.ink)),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              Text(group.rule,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: group.required ? DeliveryColors.brand : DeliveryColors.faint,
                  )),
            ],
          ),
          const SizedBox(height: DeliverySpacing.sm),
          for (final ProductOptionChoice option in group.options) _option(group, option),
        ],
      ),
    );
  }

  Widget _option(OptionGroup group, ProductOptionChoice option) {
    final bool selected = (_chosen[group.id] ?? const <String>[]).contains(option.id);
    final bool enabled = option.available;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        onTap: enabled ? () => _toggle(group, option) : null,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(vertical: DeliverySpacing.sm),
          child: Row(
            children: <Widget>[
              Icon(
                group.singleChoice
                    ? (selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked)
                    : (selected ? Icons.check_box : Icons.check_box_outline_blank),
                color: selected ? DeliveryColors.brand : DeliveryColors.faint,
                size: 20,
              ),
              const SizedBox(width: DeliverySpacing.sm + 2),
              Expanded(
                child: Text(
                  enabled ? option.name : DeliveryStrings.of(context).optionSoldOut(option.name),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? DeliveryColors.ink : DeliveryColors.muted,
                  ),
                ),
              ),
              if (option.deltaLabel.isNotEmpty)
                Text(option.deltaLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      // A discount is not a surcharge; showing both in the same colour makes a
                      // cheaper size look like an upsell.
                      color: option.priceDelta < 0
                          ? DeliveryAccent.positive.color
                          : DeliveryColors.muted,
                    )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer(double total) {
    final String? missing = _missing;
    final bool canAdd = _isComplete && _priced != null && !_pricing && _priceError == null;

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: DeliveryColors.white,
          border: Border(top: BorderSide(color: DeliveryColors.border)),
        ),
        padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (_priceError != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: DeliverySpacing.sm),
                child: Text(_priceError!,
                    style: const TextStyle(color: DeliveryColors.brand, fontSize: 12.5)),
              ),
            Row(
              children: <Widget>[
                QuantityStepper(
                  quantity: _qty,
                  onDecrease: _qty > 1 ? () => setState(() => _qty--) : null,
                  onIncrease: _qty < 99 ? () => setState(() => _qty++) : null,
                ),
                const SizedBox(width: DeliverySpacing.md),
                Expanded(
                  child: YdPillButton(
                    // Generic rather than "Choose $missing": a group named "Choose Size" would
                    // make that read "Choose Choose Size". The specific group is already marked
                    // Required in the list above.
                    label: missing != null
                        ? DeliveryStrings.of(context).selectRequiredOptions
                        : DeliveryStrings.of(context)
                            .addWithTotal(total.toStringAsFixed(2)),
                    busy: _pricing,
                    onPressed: canAdd ? _add : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
