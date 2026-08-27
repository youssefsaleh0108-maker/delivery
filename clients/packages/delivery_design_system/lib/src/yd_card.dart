import 'package:flutter/material.dart';

import 'tokens.dart';

/// The redesign's white content card (Figma `shop-card` 3:65, `item-card` 3:93,
/// `menu-item` 3:713, `task-card`).
///
/// Two dialects, and the design uses them in different places rather than interchangeably:
///
/// * the default — white, radius [DeliveryRadius.lg], no border, lifted by [softShadow]
///   (`0 4 6 rgba(15,23,42,0.03)`, read off the frames). This is the customer/rider/merchant
///   *app* card.
/// * [YdCard.bordered] — white, radius [DeliveryRadius.lg], a 1px [DeliveryColors.border]
///   hairline and no shadow. This is what the butler panels, the signup document rows and the
///   web-console surfaces draw.
///
/// [DeliveryShadows.card] is the older, heavier lift and is deliberately not reused here: the
/// redesign's card shadow is barely there, and swapping one for the other is visible.
class YdCard extends StatelessWidget {
  const YdCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(DeliverySpacing.md),
    this.onTap,
    this.radius = DeliveryRadius.lg,
    this.color = DeliveryColors.white,
    this.width,
    this.clipContent = false,
  })  : bordered = false,
        borderColor = DeliveryColors.border;

  /// The 1px-hairline dialect: no shadow, a [DeliveryColors.border] outline.
  const YdCard.bordered({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(DeliverySpacing.md),
    this.onTap,
    this.radius = DeliveryRadius.lg,
    this.color = DeliveryColors.white,
    this.width,
    this.clipContent = false,
    this.borderColor = DeliveryColors.border,
  }) : bordered = true;

  final Widget child;

  /// Defaults to the design's 16px card padding. Pass [EdgeInsets.zero] for a card whose child
  /// bleeds to the corners (an image header, a list of rows with their own padding).
  final EdgeInsetsGeometry padding;

  /// Makes the whole card tappable, with the ink ripple clipped to [radius].
  final VoidCallback? onTap;

  final double radius;
  final Color color;
  final double? width;

  /// Clips the child to the corner radius — needed when the card leads with a full-bleed image,
  /// as the shop cards do.
  final bool clipContent;

  final bool bordered;
  final Color borderColor;

  /// The redesign's card shadow: `0 4 6 rgba(15,23,42,0.03)`, i.e. [DeliveryColors.ink] at 3%.
  static List<BoxShadow> get softShadow => <BoxShadow>[
        BoxShadow(
          color: DeliveryColors.ink.withValues(alpha: 0.03),
          blurRadius: 6,
          offset: const Offset(0, 4),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final BorderRadius corners = BorderRadius.circular(radius);

    Widget content = Padding(padding: padding, child: child);
    if (clipContent) {
      content = ClipRRect(borderRadius: corners, child: content);
    }

    if (onTap != null) {
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: corners,
          child: content,
        ),
      );
    }

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: color,
        borderRadius: corners,
        border: bordered ? Border.all(color: borderColor) : null,
        boxShadow: bordered ? null : softShadow,
      ),
      child: content,
    );
  }
}
