import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// The option editor: every group on a product, and what each one asks the customer.
///
/// Its own file rather than another 300 lines inside the product form, because the form is already
/// the longest screen in the package and this is a self-contained sheet with its own model.
///
/// It edits a COPY and returns it only on Save. The endpoint behind it REPLACES the whole option
/// structure, so a sheet that mutated the caller's list as it went would leave a half-edited menu
/// behind on cancel — and cancel is exactly what somebody presses on realising they were deleting
/// the wrong group.
class ProductOptionsEditor extends StatefulWidget {
  const ProductOptionsEditor({super.key, required this.groups});

  /// The product's current groups, already read from the server. Editing from an unknown starting
  /// point is what the caller must avoid: a replace with a short list deletes the rest.
  final List<OptionGroupDraft> groups;

  @override
  State<ProductOptionsEditor> createState() => _ProductOptionsEditorState();
}

class _ProductOptionsEditorState extends State<ProductOptionsEditor> {
  late final List<OptionGroupDraft> _groups = widget.groups
      .map((OptionGroupDraft g) => OptionGroupDraft(
            name: g.name,
            minSelect: g.minSelect,
            maxSelect: g.maxSelect,
            options: g.options
                .map((OptionDraft o) => OptionDraft(
                    name: o.name, priceDelta: o.priceDelta, isDefault: o.isDefault))
                .toList(),
          ))
      .toList();

  /// The first group the server would refuse, named — so Save explains which one rather than
  /// failing after the round trip.
  String? _firstProblem(DeliveryStrings t) {
    for (final OptionGroupDraft g in _groups) {
      final String? problem = g.problem;
      if (problem == null) continue;
      final String named = g.name.trim().isEmpty ? t.merchbUntitledGroup : g.name.trim();
      switch (problem) {
        case 'nameRequired':
          return t.merchbGroupNeedsName;
        case 'needsAnOption':
          return t.merchbGroupNeedsOption(named);
        case 'optionNameRequired':
          return t.merchbOptionNeedsName(named);
        case 'minAboveMax':
          return t.merchbMinAboveMax(named);
        case 'minAboveOptionCount':
          return t.merchbMinAboveCount(named);
        default:
          return t.merchbGroupOutOfRange(named);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String? problem = _firstProblem(t);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(DeliveryRadius.sheet)),
        ),
        child: Column(
          children: <Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: DeliveryColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(DeliverySpacing.md),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      t.merchbVariantsOptions,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700, color: DeliveryColors.ink),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _groups.add(
                        OptionGroupDraft(name: '', options: <OptionDraft>[OptionDraft()]))),
                    child: Text(t.merchbAddGroup),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _groups.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(DeliverySpacing.lg),
                        child: Text(
                          t.merchbNoOptionsYet,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13, color: DeliveryColors.muted),
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: controller,
                      padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: DeliverySpacing.md),
                      itemCount: _groups.length,
                      separatorBuilder: (BuildContext _, int __) =>
                          const SizedBox(height: DeliverySpacing.md),
                      itemBuilder: (BuildContext context, int i) => _GroupEditor(
                        // Keyed on the draft itself: removing a group in the middle must not leave
                        // the next one's text fields showing the removed one's contents.
                        key: ObjectKey(_groups[i]),
                        group: _groups[i],
                        onChanged: () => setState(() {}),
                        onRemove: () => setState(() => _groups.removeAt(i)),
                      ),
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(DeliverySpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (problem != null) ...<Widget>[
                      // Brand crimson, not a red of its own: this design system has no error
                      // colour, and inventing one here would put a shade on screen that appears
                      // nowhere else in the product. Crimson is what it uses to demand attention.
                      Text(problem,
                          style: const TextStyle(fontSize: 12, color: DeliveryColors.brand)),
                      const SizedBox(height: DeliverySpacing.sm),
                    ],
                    YdPillButton(
                      label: t.save,
                      // Disabled rather than sending something the server will refuse: the
                      // constraints are mirrored client-side precisely so it can be said here,
                      // beside the field, instead of as a 400 afterwards.
                      onPressed:
                          problem != null ? null : () => Navigator.of(context).pop(_groups),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One group: its name, how many answers may be chosen, and the answers.
class _GroupEditor extends StatelessWidget {
  const _GroupEditor({
    super.key,
    required this.group,
    required this.onChanged,
    required this.onRemove,
  });

  final OptionGroupDraft group;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  initialValue: group.name,
                  decoration: InputDecoration(labelText: t.merchbGroupName),
                  onChanged: (String v) {
                    group.name = v;
                    onChanged();
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                color: DeliveryColors.muted,
                tooltip: t.merchbRemoveGroup,
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.sm),
          // The server DERIVES "required" from the minimum and "single choice" from the maximum,
          // so those two numbers are what is offered. A separate required switch beside a minimum
          // of zero would let a merchant set a contradiction the server would silently overrule.
          Row(
            children: <Widget>[
              Expanded(
                child: _CountField(
                  label: t.merchbMinSelect,
                  value: group.minSelect,
                  fallback: 0,
                  onChanged: (int v) {
                    group.minSelect = v;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              Expanded(
                child: _CountField(
                  label: t.merchbMaxSelect,
                  value: group.maxSelect,
                  fallback: 1,
                  onChanged: (int v) {
                    group.maxSelect = v;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(top: DeliverySpacing.xs),
            child: Text(
              group.minSelect > 0 ? t.merchbRuleRequired : t.merchbRuleOptional,
              style: const TextStyle(fontSize: 11, color: DeliveryColors.faint),
            ),
          ),
          const Divider(height: DeliverySpacing.lg, color: DeliveryColors.border),
          for (int i = 0; i < group.options.length; i++)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: DeliverySpacing.sm),
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      initialValue: group.options[i].name,
                      decoration: InputDecoration(labelText: t.merchbOptionName),
                      onChanged: (String v) {
                        group.options[i].name = v;
                        onChanged();
                      },
                    ),
                  ),
                  const SizedBox(width: DeliverySpacing.sm),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      initialValue: group.options[i].priceDelta == 0
                          ? ''
                          : group.options[i].priceDelta.toStringAsFixed(2),
                      // Signed on purpose: "Small" may be worth LESS than the base price, and the
                      // model documents priceDelta as signed.
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: InputDecoration(labelText: t.merchbPriceDelta),
                      onChanged: (String v) {
                        group.options[i].priceDelta = double.tryParse(v.trim()) ?? 0;
                        onChanged();
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: DeliveryColors.muted,
                    tooltip: t.merchbRemoveOption,
                    onPressed: () {
                      group.options.removeAt(i);
                      onChanged();
                    },
                  ),
                ],
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () {
                group.options.add(OptionDraft());
                onChanged();
              },
              child: Text(t.merchbAddOption),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small integer field.
///
/// Typed rather than stepped: a group may legitimately allow up to fifty, and nobody should tap a
/// plus button fifty times to say so.
class _CountField extends StatelessWidget {
  const _CountField({
    required this.label,
    required this.value,
    required this.fallback,
    required this.onChanged,
  });

  final String label;
  final int value;

  /// What an empty or unparseable field means. Not zero for both: a maximum of zero would be a
  /// group nobody can answer, so its floor is one.
  final int fallback;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
        initialValue: '$value',
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
        onChanged: (String v) => onChanged(int.tryParse(v.trim()) ?? fallback),
      );
}
