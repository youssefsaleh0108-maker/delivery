import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

import 'console_chrome.dart';

/// The panel that slides in from the right when a row or a card is opened.
///
/// The console frames are deliberately flat — a table of partners, a grid of carriers, and nothing
/// stacked on top of them. But every one of those screens sits in front of work that does not fit
/// in a 40px row: the reviewer's verification marks and the applicant's own words, a carrier's
/// payout state, its logins and its roster. The design leaves that detail undrawn rather than
/// deciding against it, so it goes where a console this shape puts detail: beside the list, not
/// over it, so the list it came from stays readable behind.
///
/// A dialog under the hood, and a full-height one against the right edge, which is what makes it a
/// drawer rather than a modal. [Navigator.pop] closes it, so the caller awaits a result exactly as
/// it would from `showDialog`.
Future<T?> showConsoleDrawer<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  Widget? badge,
  required WidgetBuilder builder,
  double width = 460,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: DeliveryColors.ink.withValues(alpha: 0.32),
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (BuildContext context, Animation<double> animation, _, Widget child) {
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      );
    },
    pageBuilder: (BuildContext context, _, __) {
      return Align(
        alignment: Alignment.centerRight,
        child: _DrawerPanel(
          title: title,
          subtitle: subtitle,
          badge: badge,
          width: width,
          child: Builder(builder: builder),
        ),
      );
    },
  );
}

class _DrawerPanel extends StatelessWidget {
  const _DrawerPanel({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.width,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget? badge;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DeliveryColors.white,
      child: SizedBox(
        // Never wider than the window: on a 1024 laptop a fixed 460 beside a 260 rail is already
        // most of the screen, and on anything narrower a fixed panel would simply overflow.
        width: width.clamp(0.0, MediaQuery.sizeOf(context).width),
        height: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(ConsoleMetrics.cardPadding),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: DeliveryColors.border)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                title,
                                overflow: TextOverflow.ellipsis,
                                style: ConsoleText.pageTitleSmall,
                              ),
                            ),
                            if (badge != null) ...<Widget>[
                              const SizedBox(width: DeliverySpacing.sm + 2),
                              badge!,
                            ],
                          ],
                        ),
                        if (subtitle != null) ...<Widget>[
                          const SizedBox(height: DeliverySpacing.xs),
                          Text(subtitle!, style: ConsoleText.pageSubtitle),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: DeliverySpacing.md),
                  ConsoleIconAction(
                    icon: Icons.close,
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(ConsoleMetrics.cardPadding),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled block inside a drawer: a small caps label over its content.
class ConsoleDrawerSection extends StatelessWidget {
  const ConsoleDrawerSection({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.first = false,
  });

  final String title;
  final Widget child;

  /// Sits opposite the label — the action that belongs to this block.
  final Widget? trailing;

  /// The topmost section draws no rule above itself; the header already did.
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : ConsoleMetrics.pageGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (!first) ...<Widget>[
            const Divider(height: 1, color: DeliveryColors.border),
            const SizedBox(height: ConsoleMetrics.pageGap),
          ],
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: DeliveryColors.faint,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: DeliverySpacing.sm + 2),
          child,
        ],
      ),
    );
  }
}

/// The console's filled and outlined buttons, at the size the carrier cards draw them.
///
/// Figma `btn-approve` / `btn-suspend` (3:3014, 3:3016): 16 across and 8 down at radius 8, SemiBold
/// 13 brand on the rose tint, or Medium 13 slate inside a 1px border. Not [ElevatedButton] with a
/// theme override, because the design's version has no elevation, no ripple-sized padding and no
/// 40px minimum height — three things the Material default insists on.
class ConsoleButton extends StatelessWidget {
  const ConsoleButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.tone = ConsoleButtonTone.tinted,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ConsoleButtonTone tone;

  /// Swaps the glyph for a spinner and takes the button out of service, without changing its width
  /// enough to make the row jump.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final bool on = onPressed != null && !busy;

    final Color foreground = switch (tone) {
      ConsoleButtonTone.solid => DeliveryColors.white,
      ConsoleButtonTone.tinted => DeliveryColors.brand,
      ConsoleButtonTone.outlined => DeliveryColors.muted,
      ConsoleButtonTone.destructive => DeliveryAccent.critical.color,
    };
    final Color background = switch (tone) {
      ConsoleButtonTone.solid => DeliveryColors.brand,
      ConsoleButtonTone.tinted => DeliveryColors.brandSoft,
      ConsoleButtonTone.outlined => DeliveryColors.white,
      ConsoleButtonTone.destructive => DeliveryAccent.critical.tint,
    };
    final Color? border = switch (tone) {
      ConsoleButtonTone.outlined => DeliveryColors.border,
      _ => null,
    };

    final Color shown = on ? foreground : DeliveryColors.faint;

    return Material(
      color: on ? background : DeliveryColors.background,
      borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      child: InkWell(
        onTap: on ? onPressed : null,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DeliverySpacing.md,
            vertical: DeliverySpacing.sm,
          ),
          decoration: BoxDecoration(
            border: border == null ? null : Border.all(color: border),
            borderRadius: BorderRadius.circular(DeliveryRadius.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (busy)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: shown),
                )
              else if (icon != null)
                Icon(icon, size: 14, color: shown),
              if (busy || icon != null) const SizedBox(width: DeliverySpacing.sm),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: tone == ConsoleButtonTone.outlined
                        ? FontWeight.w500
                        : FontWeight.w600,
                    color: shown,
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

enum ConsoleButtonTone {
  /// Crimson fill, white label — the one primary action on a screen.
  solid,

  /// The design's rose-tinted button. Reads as primary within a card without competing with a
  /// solid one elsewhere on the page.
  tinted,

  /// Bordered and slate — the design's Suspend.
  outlined,

  /// Bordered in the critical tint, for the action that stops something.
  destructive,
}
