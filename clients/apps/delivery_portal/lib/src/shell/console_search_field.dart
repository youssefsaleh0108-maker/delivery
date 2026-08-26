import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

import 'console_chrome.dart';

/// The console's search box.
///
/// Figma `search` (3:2727) and `global-search` (3:2534): white, 1px slate border, radius 8, a 16px
/// glyph then the text, 14 across and 8 down. The topbar variant is 16/8 with a 10px gap and a
/// fixed 240 — pass [padding] and [gap] for that one.
///
/// Real input, not the design's static placeholder text: every screen that carries one of these
/// filters a list that is already in memory.
class ConsoleSearchField extends StatelessWidget {
  const ConsoleSearchField({
    super.key,
    required this.hintText,
    this.controller,
    this.onChanged,
    this.width = 232,
    this.padding = const EdgeInsets.symmetric(
      horizontal: DeliverySpacing.md - 2,
      vertical: DeliverySpacing.sm,
    ),
    this.gap = DeliverySpacing.sm,
    this.enabled = true,
  });

  /// The topbar's wider variant, drawn on every console frame's header.
  const ConsoleSearchField.global({
    super.key,
    required this.hintText,
    this.controller,
    this.onChanged,
    this.width = 240,
    this.enabled = true,
  })  : padding = const EdgeInsets.symmetric(
          horizontal: DeliverySpacing.md,
          vertical: DeliverySpacing.sm,
        ),
        gap = 10;

  final String hintText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final double width;
  final EdgeInsetsGeometry padding;
  final double gap;

  /// False renders the design's box with the glyph and hint greyed — for a search the platform
  /// draws but cannot answer yet. Pair it with a [ConsoleComingSoonChip] nearby.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: padding,
      decoration: ConsoleSurface.control,
      child: Row(
        children: <Widget>[
          const Icon(Icons.search, size: 16, color: DeliveryColors.faint),
          SizedBox(width: gap),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              enabled: enabled,
              style: ConsoleText.control,
              cursorColor: DeliveryColors.brand,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: hintText,
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: DeliveryColors.faint,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The bordered icon-and-label button that sits beside a search box — the "Category" filter.
///
/// Same surface as [ConsoleSearchField] so the pair reads as one control group. A null [onPressed]
/// greys it rather than removing it, for the filters the design draws ahead of the API.
class ConsoleFilterButton extends StatelessWidget {
  const ConsoleFilterButton({
    super.key,
    required this.label,
    this.icon = Icons.tune,
    this.onPressed,
    this.trailing,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  /// Appended after the label — a chevron on a real dropdown, a [ConsoleComingSoonChip] on a
  /// filter that is only drawn.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final Color foreground =
        onPressed == null ? DeliveryColors.faint : DeliveryColors.muted;

    return Material(
      color: DeliveryColors.white,
      borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DeliverySpacing.md - 2,
            vertical: DeliverySpacing.sm,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: DeliveryColors.border),
            borderRadius: BorderRadius.circular(DeliveryRadius.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: DeliverySpacing.sm),
              Text(
                label,
                style: ConsoleText.controlLabel.copyWith(color: foreground),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: DeliverySpacing.sm),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
