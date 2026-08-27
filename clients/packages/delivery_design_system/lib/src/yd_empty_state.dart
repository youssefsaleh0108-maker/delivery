import 'package:flutter/material.dart';

import 'tokens.dart';

/// The centred "there is nothing here yet" block.
///
/// The redesign does not draw an empty state on any frame — every list is shown full — so this is
/// built out of the design's own parts rather than invented: the 64px [DeliveryColors.brandSoft]
/// icon badge from the OTP screen's illustration (22:165), a Bold 16 title, and a 13
/// [DeliveryColors.muted] body. Screens keep their existing empty-state wiring and just restyle
/// through this.
///
/// Note the palette rule in `tokens.dart`: brand text at body size does not clear AA on
/// [DeliveryColors.brandSoft], so the copy here is [DeliveryColors.ink] and
/// [DeliveryColors.muted] and only the glyph is brand.
class YdEmptyState extends StatelessWidget {
  const YdEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.padding = const EdgeInsets.all(DeliverySpacing.lg),
  });

  final IconData icon;

  /// Already localised by the caller.
  final String title;

  /// Optional supporting line, already localised.
  final String? message;

  /// Optional call to action — normally a [YdPillButton].
  final Widget? action;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: DeliveryColors.brandSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: DeliveryColors.brand),
            ),
            const SizedBox(height: DeliverySpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: DeliveryColors.ink,
                height: 1.3,
              ),
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: DeliveryColors.muted,
                  height: 18 / 13,
                ),
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: DeliverySpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
