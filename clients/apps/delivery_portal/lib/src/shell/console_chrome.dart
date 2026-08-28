import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

/// The measurements the 2026-08 Figma console frames are drawn on
/// (`backoffice-dashboard` 3:2487, `carrier-dashboard` 3:3429 and the screens that share their
/// chrome).
///
/// Read off the frames rather than guessed, and kept in one place so a page laid out by hand and a
/// page built from [ConsolePage] land on the same grid. Anything already covered by a design-system
/// token — a colour, a radius, a 4-multiple gap — is referenced from there instead of restated
/// here; this holds only the numbers the console layout adds on top.
abstract final class ConsoleMetrics {
  /// The dark rail's fixed width. Not responsive in the design and not made responsive here.
  static const double sidebarWidth = 260;

  /// `main-content` padding, and the gap between the stacked blocks inside it.
  static const double pagePadding = 32;
  static const double pageGap = 24;

  /// The gap the KPI row uses — 20, not the 24 everything else uses. Deliberate in the design.
  static const double kpiGap = 20;

  /// Card interior padding on the console (24), which is one step up from the mobile 16.
  static const double cardPadding = 24;

  /// Table cells: 24 across, 16 down.
  static const double cellPaddingX = 24;
  static const double cellPaddingY = 16;

  /// The square of a topbar icon button: 10px padding around a 16px glyph.
  static const double iconActionSize = 36;
}

/// The console's own type ramp.
///
/// The design system's [TextTheme] is tuned for the phone; the console draws a denser set (13px
/// table text, 11px timestamps, a 28px page title) that would otherwise be re-typed on every
/// screen. Family and fallback come from the ambient theme — `ThemeData.fontFamily` is already
/// Rubik — so nothing here names a font.
abstract final class ConsoleText {
  /// Page title. `Rubik Bold 28`.
  static const TextStyle pageTitle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: DeliveryColors.ink,
    height: 1.2,
  );

  /// The smaller page title the narrower frames use.
  static const TextStyle pageTitleSmall = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: DeliveryColors.ink,
    height: 1.2,
  );

  /// The line under a page title.
  static const TextStyle pageSubtitle = TextStyle(
    fontSize: 14,
    color: DeliveryColors.muted,
  );

  /// Card headings — "Weekly Orders Trend", "Live Activity Log".
  static const TextStyle cardTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: DeliveryColors.ink,
  );

  /// A KPI's caption.
  static const TextStyle kpiLabel = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: DeliveryColors.muted,
  );

  /// A KPI's number.
  static const TextStyle kpiValue = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: DeliveryColors.ink,
  );

  /// Table column headings.
  static const TextStyle tableHeader = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: DeliveryColors.muted,
  );

  /// An ordinary table cell.
  static const TextStyle cell = TextStyle(
    fontSize: 14,
    color: DeliveryColors.ink,
  );

  /// The one cell per row that names the thing — a merchant, an order's customer.
  static const TextStyle cellStrong = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: DeliveryColors.ink,
  );

  /// Secondary cells: categories, dates.
  static const TextStyle cellMuted = TextStyle(
    fontSize: 14,
    color: DeliveryColors.muted,
  );

  /// The cells the design paints crimson — order ids, and nothing else.
  static const TextStyle cellLink = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: DeliveryColors.brand,
  );

  /// Body copy inside a card — an activity line, a description.
  static const TextStyle body = TextStyle(
    fontSize: 13,
    color: DeliveryColors.ink,
  );

  /// Timestamps and other de-emphasised meta.
  static const TextStyle meta = TextStyle(
    fontSize: 11,
    color: DeliveryColors.faint,
  );

  /// Placeholder / input text in the console's controls.
  static const TextStyle control = TextStyle(
    fontSize: 13,
    color: DeliveryColors.ink,
  );

  /// A control's own label — the "Category" on a filter button.
  static const TextStyle controlLabel = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: DeliveryColors.muted,
  );

  /// A form field's label above the box.
  static const TextStyle fieldLabel = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: DeliveryColors.ink,
  );
}

/// The white surface every console block sits on: 1px border, radius 16, and the design's very
/// faint lift.
///
/// A border *and* a shadow, which the mobile cards deliberately avoid — on a page this wide the
/// shadow alone stops separating a card from the slate background.
abstract final class ConsoleSurface {
  static BoxDecoration card({Color color = DeliveryColors.white}) => BoxDecoration(
        color: color,
        border: Border.all(color: DeliveryColors.border),
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: DeliveryColors.ink.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 4),
          ),
        ],
      );

  /// A control-sized surface: same white, same border, the smaller radius.
  static BoxDecoration get control => BoxDecoration(
        color: DeliveryColors.white,
        border: Border.all(color: DeliveryColors.border),
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      );
}

/// A plain console card — [ConsoleSurface.card] with the design's 24px padding and an optional
/// title line.
class ConsoleCard extends StatelessWidget {
  const ConsoleCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(ConsoleMetrics.cardPadding),
  });

  final Widget child;

  /// Rendered in [ConsoleText.cardTitle] above [child], with the design's 20px gap.
  final String? title;

  /// Sits opposite the title — a legend, a "view all" link, a [ConsoleComingSoonChip].
  final Widget? trailing;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: ConsoleSurface.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (title != null || trailing != null) ...<Widget>[
            Row(
              children: <Widget>[
                if (title != null)
                  Expanded(child: Text(title!, style: ConsoleText.cardTitle))
                else
                  const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
          ],
          child,
        ],
      ),
    );
  }
}

/// The console's quiet pill: slate on the page background, hairlined, 11px SemiBold.
///
/// Deliberately unbrand-coloured. It qualifies the thing beside it — a state, a caveat, a note
/// about the platform — and a crimson chip would pull more attention than the value it is
/// attached to. (Brand text at this size on [DeliveryColors.brandSoft] is also below AA, per the
/// note in `tokens.dart`.)
///
/// Split out from [ConsoleComingSoonChip], which it now draws. The two had been the same class,
/// so a real state that happens to want a quiet pill — a provisional score, say — could only get
/// one by wearing the "no backend answers this yet" widget. That made the chip's own name stop
/// meaning anything, and made grepping for unfinished work report finished work.
class ConsoleQuietChip extends StatelessWidget {
  const ConsoleQuietChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DeliverySpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: DeliveryColors.background,
        border: Border.all(color: DeliveryColors.border),
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: DeliveryColors.muted,
        ),
      ),
    );
  }
}

/// The mark put on an affordance the design draws but no backend answers yet.
///
/// A [ConsoleQuietChip] with one fixed meaning. Keep it for exactly that meaning: this type is
/// what a sweep for unfinished surfaces counts, so wearing it for a real state hides the real
/// ones in the noise.
class ConsoleComingSoonChip extends StatelessWidget {
  const ConsoleComingSoonChip({super.key, this.label = 'Coming soon'});

  final String label;

  @override
  Widget build(BuildContext context) => ConsoleQuietChip(label: label);
}

/// The square icon button the design puts in the page header — the notification bell, and anything
/// else that belongs beside it.
///
/// A null [onPressed] renders the same box in the faint tier rather than hiding it: the design draws
/// the control, and a greyed one plus a tooltip is a truer picture than an empty corner.
class ConsoleIconAction extends StatelessWidget {
  const ConsoleIconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.badge = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Draws the design's unread dot on the top-right corner.
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final Widget box = Container(
      width: ConsoleMetrics.iconActionSize,
      height: ConsoleMetrics.iconActionSize,
      alignment: Alignment.center,
      decoration: ConsoleSurface.control,
      child: Icon(
        icon,
        size: 16,
        color: onPressed == null ? DeliveryColors.faint : DeliveryColors.muted,
      ),
    );

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        child: badge
            ? Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  box,
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: DeliveryColors.brand,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              )
            : box,
      ),
    );
  }
}
