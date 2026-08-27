import 'package:flutter/material.dart';

import 'tokens.dart';

/// How a [YdPillButton] is painted.
enum YdPillButtonVariant {
  /// The customer app's primary CTA: solid [DeliveryColors.brand], white label.
  /// Figma `checkout-button` (3:471) — 52 tall, fully rounded, SemiBold 16 white.
  primary,

  /// The quieter twin: white fill, 1px [DeliveryColors.border], [DeliveryColors.ink] label.
  secondary,

  /// For use *on* a brand-coloured screen, where a white button would shout and a bordered one
  /// would vanish: [DeliveryColors.onBrandSurface] (white at 15%) with a white label.
  onBrand,
}

/// The two heights the design draws.
enum YdPillButtonSize {
  /// 52px — the full-width bottom CTA.
  regular(52, 16),

  /// 44px — the inline/secondary action, and anything sitting in a row of two.
  compact(44, 15);

  const YdPillButtonSize(this.height, this.fontSize);

  final double height;
  final double fontSize;
}

/// The redesign's fully-rounded primary call to action.
///
/// The customer app rounds its tall CTAs completely (radius 26 on a 52px button, i.e.
/// [DeliveryRadius.pill]); the signup wizards use a 16-radius rectangle instead and should reach
/// for a plain `ElevatedButton`, which the theme now shapes for them. This widget is the pill.
///
/// The label is a [String] the caller has already localised — this package holds no user-facing
/// text of its own.
class YdPillButton extends StatelessWidget {
  const YdPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = YdPillButtonVariant.primary,
    this.size = YdPillButtonSize.regular,
    this.icon,
    this.trailing,
    this.expand = true,
    this.busy = false,
  });

  /// Convenience for the white/bordered dialect.
  const YdPillButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = YdPillButtonSize.regular,
    this.icon,
    this.trailing,
    this.expand = true,
    this.busy = false,
  }) : variant = YdPillButtonVariant.secondary;

  /// Convenience for the translucent-on-brand dialect.
  const YdPillButton.onBrand({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = YdPillButtonSize.regular,
    this.icon,
    this.trailing,
    this.expand = true,
    this.busy = false,
  }) : variant = YdPillButtonVariant.onBrand;

  /// Already localised by the caller.
  final String label;

  /// `null` disables the button, which is also how the design draws its inactive CTAs.
  final VoidCallback? onPressed;

  final YdPillButtonVariant variant;
  final YdPillButtonSize size;

  /// Optional leading glyph, 18px, tinted to match the label.
  final IconData? icon;

  /// Optional end-slot widget (a count, a chevron, a [YdComingSoon] chip).
  final Widget? trailing;

  /// Full width by default, which is how every bottom CTA in the design is drawn.
  final bool expand;

  /// Swaps the label for a spinner and refuses taps — for CTAs that fire a request.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !busy;

    late final Color background;
    late final Color foreground;
    BorderSide? side;

    switch (variant) {
      case YdPillButtonVariant.primary:
        background = enabled ? DeliveryColors.brand : DeliveryColors.brandLine;
        foreground = DeliveryColors.white;
      case YdPillButtonVariant.secondary:
        background = DeliveryColors.white;
        foreground = enabled ? DeliveryColors.ink : DeliveryColors.faint;
        side = const BorderSide(color: DeliveryColors.border);
      case YdPillButtonVariant.onBrand:
        background = DeliveryColors.onBrandSurface;
        foreground = DeliveryColors.white;
        side = const BorderSide(color: DeliveryColors.onBrandBorder);
    }

    final Widget content = busy
        ? SizedBox.square(
            dimension: size.fontSize + 4,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(foreground),
            ),
          )
        : Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: DeliverySpacing.sm),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: size.fontSize,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                    height: 1.2,
                  ),
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: DeliverySpacing.sm),
                trailing!,
              ],
            ],
          );

    final BorderRadius corners = BorderRadius.circular(DeliveryRadius.pill);

    return SizedBox(
      width: expand ? double.infinity : null,
      height: size.height,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: corners,
          side: side ?? BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: corners,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: DeliverySpacing.lg,
            ),
            child: Center(
              widthFactor: expand ? null : 1,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
