import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

import 'console_search_field.dart';

/// One choice in a [ConsoleSelect].
class ConsoleOption {
  const ConsoleOption({required this.label, required this.value});

  final String label;

  /// Null is the "all of them" entry every one of these filters starts on.
  final String? value;
}

/// The design's bordered dropdown: a glyph, the current choice, and a chevron.
///
/// Figma `filter-btn` (3:2731) and the riders frame's `carrier-selector` (3:3144) are the same
/// control drawn twice, so it is one widget here. It borrows [ConsoleFilterButton]'s surface and
/// adds the menu.
///
/// Anchored with `showMenu` rather than wrapped in a [PopupMenuButton]: the button already owns an
/// InkWell, and a PopupMenuButton around it never receives the tap — the ink well swallows it and
/// the menu simply never opens. Found by a test that tapped the filter and got a row's drawer
/// instead, which is exactly the sort of thing a wrapper hides.
class ConsoleSelect extends StatelessWidget {
  const ConsoleSelect({
    super.key,
    required this.label,
    required this.icon,
    required this.options,
    required this.onSelected,
    this.tooltip,
  });

  /// What the button reads right now — the chosen option, or the "all" label.
  final String label;

  final IconData icon;
  final List<ConsoleOption> options;
  final ValueChanged<String?> onSelected;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (BuildContext buttonContext) {
        final Widget button = ConsoleFilterButton(
          label: label,
          icon: icon,
          onPressed: () => _open(buttonContext),
          trailing: const Icon(Icons.expand_more, size: 14, color: DeliveryColors.muted),
        );
        return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
      },
    );
  }

  Future<void> _open(BuildContext context) async {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    final RenderBox? overlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final Offset topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final int? picked = await showMenu<int>(
      context: context,
      color: DeliveryColors.white,
      // Under the button and flush with its left edge, the way the design draws it open.
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        topLeft.dy + box.size.height + DeliverySpacing.xs,
        overlay.size.width - topLeft.dx - box.size.width,
        0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.md)),
      items: <PopupMenuEntry<int>>[
        for (int i = 0; i < options.length; i++)
          PopupMenuItem<int>(
            value: i,
            height: 40,
            child: Text(
              options[i].label,
              style: const TextStyle(fontSize: 13, color: DeliveryColors.ink),
            ),
          ),
      ],
    );

    if (picked == null) return;
    onSelected(options[picked].value);
  }
}
