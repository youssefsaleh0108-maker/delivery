import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

/// One choice in a short list, drawn as a radio row.
///
/// A whole-width row rather than a chip wherever a choice's words run long — "Starting price (options
/// add to it)" in Arabic is wider than a 320dp phone leaves a chip, and a chip never wraps. The row
/// wraps, and its target is the full width.
class SvcChoiceRow extends StatelessWidget {
  const SvcChoiceRow({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.caption,
  });

  final String label;
  final bool selected;

  /// Null draws the choice as unavailable.
  final VoidCallback? onTap;

  final String? caption;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      enabled: enabled,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
          child: Row(
            children: <Widget>[
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 20,
                color: selected
                    ? DeliveryColors.brand
                    : (enabled ? DeliveryColors.muted : DeliveryColors.border),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          color: enabled ? DeliveryColors.ink : DeliveryColors.faint,
                          height: 1.3,
                        ),
                      ),
                      if (caption != null)
                        Text(
                          caption!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: DeliveryColors.faint,
                            height: 1.3,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A choice a form must have, drawn as [SvcChoiceRow]s — or as chips, for short words — with the
/// field's error beneath it, validated with the rest of the form.
class SvcChoiceField<T> extends FormField<T> {
  SvcChoiceField({
    super.key,
    required List<T> values,
    required String Function(T value) labelOf,
    required ValueChanged<T> onChanged,
    super.initialValue,
    String? requiredMessage,
    bool Function(T value)? isEnabled,
    bool chips = false,
  }) : super(
          validator: (T? value) => value == null ? requiredMessage : null,
          builder: (FormFieldState<T> field) {
            bool enabled(T value) => isEnabled?.call(value) ?? true;
            void pick(T value) {
              field.didChange(value);
              onChanged(value);
            }

            final Widget choices = chips
                ? Wrap(
                    spacing: DeliverySpacing.sm,
                    runSpacing: DeliverySpacing.sm,
                    children: <Widget>[
                      for (final T value in values)
                        Opacity(
                          opacity: enabled(value) ? 1 : 0.45,
                          child: YdChip(
                            label: labelOf(value),
                            selected: field.value == value,
                            onTap: enabled(value) ? () => pick(value) : null,
                          ),
                        ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (final T value in values)
                        SvcChoiceRow(
                          label: labelOf(value),
                          selected: field.value == value,
                          onTap: enabled(value) ? () => pick(value) : null,
                        ),
                    ],
                  );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                choices,
                if (field.errorText != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: DeliverySpacing.xs),
                    child: Text(
                      field.errorText!,
                      style: TextStyle(fontSize: 12, color: DeliveryAccent.critical.onTint),
                    ),
                  ),
              ],
            );
          },
        );
}
