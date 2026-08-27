import 'package:flutter/material.dart';

import 'tokens.dart';

/// The redesign's 56px white screen header (Figma `screen-header`, e.g. nodes 3:693, 20:14).
///
/// Measured off the frames: 56px tall, white, 24px horizontal padding, 1px bottom border.
/// Title Rubik Bold 18 ink. With a back button (32px circle on the background token, radius 16)
/// or a trailing widget the title centres between balanced 32px slots, exactly as the Butler
/// header draws it; without either it sits at the start like Account Settings.
class YdScreenHeader extends StatelessWidget implements PreferredSizeWidget {
  const YdScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing,
    this.backSemanticLabel,
  });

  /// Header title — already localised by the caller.
  final String title;

  /// Optional second line, muted 12.
  final String? subtitle;

  /// Shows the design's 32px circular back button when non-null.
  final VoidCallback? onBack;

  /// Optional widget in the end slot (an action icon, a chip...).
  final Widget? trailing;

  /// Accessibility label for the back button, localised by the caller.
  final String? backSemanticLabel;

  static const double height = 56;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final bool hasSides = onBack != null || trailing != null;

    final Widget titleBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          hasSides ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: DeliveryColors.muted),
          ),
      ],
    );

    return Container(
      // A minimum, not a fixed height. The design's 56px is what this renders at every default
      // text size, which is the point of the token — but Android scales text system-wide, and at
      // the largest setting an 18px title over a 12px subtitle needs about 85px. A hard `height`
      // clipped that and painted the overflow stripe across the top of the screen; growing instead
      // costs nothing at 1x and keeps the header readable at 2x.
      constraints: const BoxConstraints(minHeight: height),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: DeliverySpacing.lg),
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: hasSides
          ? Row(
              children: <Widget>[
                if (onBack != null)
                  YdBackButton(onPressed: onBack!, semanticLabel: backSemanticLabel)
                else
                  const SizedBox.square(dimension: YdBackButton.dimension),
                Expanded(child: Center(child: titleBlock)),
                if (trailing != null)
                  trailing!
                else
                  const SizedBox.square(dimension: YdBackButton.dimension),
              ],
            )
          : Align(alignment: AlignmentDirectional.centerStart, child: titleBlock),
    );
  }
}

/// The 32px circular back button the design draws inside headers and at the top of wizard
/// steps: background-token fill, radius 16, an 18px chevron that mirrors in RTL.
class YdBackButton extends StatelessWidget {
  const YdBackButton({super.key, required this.onPressed, this.semanticLabel});

  final VoidCallback onPressed;

  /// Localised accessibility label supplied by the caller.
  final String? semanticLabel;

  static const double dimension = 32;

  @override
  Widget build(BuildContext context) {
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: DeliveryColors.background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: dimension,
            child: Icon(
              rtl ? Icons.chevron_right : Icons.chevron_left,
              size: 18,
              color: DeliveryColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
