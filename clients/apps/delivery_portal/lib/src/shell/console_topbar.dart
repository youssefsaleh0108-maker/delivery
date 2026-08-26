import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

import 'console_chrome.dart';

/// The white page header at the top of every console screen.
///
/// Figma `header` (3:2529 / 3:3462): title over an optional subtitle on the left, a row of controls
/// on the right, 24px of breathing room and then a 1px rule across the full content width.
///
/// It is not an [AppBar]. The console has no app bar — the rail is the chrome, and this is part of
/// the page, which is why it scrolls with a screen that chooses to scroll it and why it sits inside
/// the page's own 32px padding rather than outside it.
class ConsoleTopbar extends StatelessWidget {
  const ConsoleTopbar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.titleStyle,
  });

  final String title;

  /// The design's second line. Omit it and the title sits alone, vertically centred against the
  /// actions.
  final String? subtitle;

  /// Laid out right-aligned with the design's 16px gap. Typically a [ConsoleSearchField] and a
  /// [ConsoleIconAction] or two.
  final List<Widget> actions;

  /// Defaults to [ConsoleText.pageTitle] (Bold 28). Screens with a narrower content column pass
  /// [ConsoleText.pageTitleSmall].
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: ConsoleMetrics.pageGap),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(title, style: titleStyle ?? ConsoleText.pageTitle),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: DeliverySpacing.xs),
                  Text(subtitle!, style: ConsoleText.pageSubtitle),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...<Widget>[
            const SizedBox(width: DeliverySpacing.md),
            Wrap(
              spacing: DeliverySpacing.md,
              runSpacing: DeliverySpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

/// The `main-content` frame: 32px padding, a [ConsoleTopbar], then the screen's blocks 24px apart.
///
/// Every console screen has this shape, so it is worth one widget rather than the same Padding and
/// the same SizedBoxes on eleven pages. [scrollable] is the usual case — a table longer than the
/// window has to scroll somewhere, and the rail must not scroll with it.
class ConsolePage extends StatelessWidget {
  const ConsolePage({
    super.key,
    required this.header,
    required this.children,
    this.scrollable = true,
    this.gap = ConsoleMetrics.pageGap,
  });

  final ConsoleTopbar header;
  final List<Widget> children;
  final bool scrollable;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final List<Widget> blocks = <Widget>[
      header,
      for (final Widget child in children) ...<Widget>[SizedBox(height: gap), child],
    ];

    final Widget column = Column(
      // Stretch: the header's rule, the KPI row and a table card all run the full content width.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: scrollable ? MainAxisSize.min : MainAxisSize.max,
      children: blocks,
    );

    return Container(
      color: DeliveryColors.background,
      padding: const EdgeInsets.all(ConsoleMetrics.pagePadding),
      child: scrollable ? SingleChildScrollView(child: column) : column,
    );
  }
}
