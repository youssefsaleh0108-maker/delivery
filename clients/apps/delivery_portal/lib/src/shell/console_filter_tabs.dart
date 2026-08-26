import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

/// One tab in a [ConsoleFilterTabs] row.
class ConsoleFilterTab {
  const ConsoleFilterTab({required this.label, this.count});

  final String label;

  /// Appended in brackets — "Pending Approval (14)". Pass a real count or nothing; a bracketed
  /// number nobody computed is worse than no number.
  final int? count;

  String get text => count == null ? label : '$label ($count)';
}

/// The segmented filter row: a slate trough with the selected tab lifted out of it in white.
///
/// Figma `tabs` (3:2721): 4px trough padding, 8px between tabs, each tab 16 across and 8 down at
/// radius 8. Selected is SemiBold ink on white; the rest are Medium slate on the trough.
class ConsoleFilterTabs extends StatelessWidget {
  const ConsoleFilterTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<ConsoleFilterTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.xs),
      decoration: BoxDecoration(
        color: DeliveryColors.border,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < tabs.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: DeliverySpacing.sm),
            _Tab(
              tab: tabs[i],
              selected: i == selectedIndex,
              onTap: () => onSelected(i),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.tab, required this.selected, required this.onTap});

  final ConsoleFilterTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? DeliveryColors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DeliverySpacing.md,
            vertical: DeliverySpacing.sm,
          ),
          child: Text(
            tab.text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? DeliveryColors.ink : DeliveryColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// The rounded status pills the orders frame uses instead of a segmented trough — "All" filled in
/// crimson beside outlined "Preparing", "Out for Delivery", "Completed".
///
/// A second filter idiom rather than a variant of the first, because the design draws two and they
/// are not interchangeable: the trough switches between *populations*, these switch between
/// *states* of one population.
class ConsoleFilterPills extends StatelessWidget {
  const ConsoleFilterPills({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: DeliverySpacing.sm,
      runSpacing: DeliverySpacing.sm,
      children: <Widget>[
        for (int i = 0; i < labels.length; i++)
          _Pill(
            label: labels[i],
            selected: i == selectedIndex,
            onTap: () => onSelected(i),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap});

  /// The design draws these at radius 20 against the 8 every other control uses — near enough to
  /// fully round at this height, and the thing that tells a *state* filter apart from the bordered
  /// controls beside it at a glance. Not [DeliveryRadius.pill]: 20 is drawn, and on a taller pill
  /// (a wrapped two-line label) the two stop being the same shape.
  static const double _radius = 20;

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? DeliveryColors.brand : DeliveryColors.white,
      borderRadius: BorderRadius.circular(_radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_radius),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DeliverySpacing.md - DeliverySpacing.xs,
            vertical: DeliverySpacing.sm,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? DeliveryColors.brand : DeliveryColors.border,
            ),
            borderRadius: BorderRadius.circular(_radius),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? DeliveryColors.white : DeliveryColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}
