/// The console's smaller controls: the pieces the 2026-08 Figma carrier frames draw that the
/// first pass of the shell did not need.
///
/// Same rules as the rest of `shell/` — every colour, radius and spacing step comes from
/// `delivery_design_system`'s tokens rather than from a literal, and nothing here knows what a
/// carrier is. They live beside [ConsoleCard] and friends so the next console to want a read-only
/// field or a tinted tag finds one instead of writing a fifth.
///
/// Kept in its own file rather than appended to `console_chrome.dart` deliberately: that file is
/// owned by the shell work and this file is additive, so the two never have to be merged.
library;

import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

import 'console_chrome.dart';

/// The design's filled action button: crimson, radius 8, SemiBold 13 white, an optional 16px
/// leading glyph.
///
/// Figma `add-rider-btn` (3:3639) and `save-settings-btn` (3:3973) — the same button at two sizes,
/// which is why [wide] is a flag rather than a second widget.
///
/// A null [onPressed] renders the design's shape in the faint tier instead of hiding it. Several
/// buttons on these frames are drawn ahead of the endpoint that would answer them, and a greyed
/// control beside a [ConsoleComingSoonChip] is a truer picture of the platform than a gap.
class ConsolePrimaryButton extends StatelessWidget {
  const ConsolePrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.wide = false,
    this.busy = false,
    this.color = DeliveryColors.brand,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// The full-width save variant: 24 across, 12 down, SemiBold 14.
  final bool wide;

  /// Swaps the leading glyph for a spinner and refuses taps, without changing the button's width —
  /// a button that shrinks while it is working moves everything beside it.
  final bool busy;

  /// The Approve button on the onboarding frame is emerald rather than crimson; everything else
  /// takes the default.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final bool on = onPressed != null && !busy;
    final Color fill = on ? color : DeliveryColors.border;
    final Color foreground = on ? DeliveryColors.white : DeliveryColors.faint;

    final Widget content = Row(
      mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (busy)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
          )
        else if (icon != null)
          Icon(icon, size: 16, color: foreground),
        if (busy || icon != null) const SizedBox(width: DeliverySpacing.sm),
        // Flexible, not bare: the design pairs this button 50/50 with another inside a card, and at
        // three cards across "Approve Rider" is wider than the half it is given.
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: wide ? 14 : 13,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ),
      ],
    );

    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      child: InkWell(
        onTap: on ? onPressed : null,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        child: Padding(
          padding: wide
              ? const EdgeInsets.symmetric(
                  horizontal: DeliverySpacing.lg,
                  vertical: DeliverySpacing.md - DeliverySpacing.xs,
                )
              : const EdgeInsets.symmetric(
                  horizontal: DeliverySpacing.md,
                  vertical: DeliverySpacing.sm,
                ),
          child: content,
        ),
      ),
    );
  }
}

/// The tinted, borderless button the design pairs with a filled one — "Reject Application" in soft
/// red beside "Approve Rider" in solid green.
///
/// Figma `reject-btn` (3:3803): the accent's own 12% wash behind its strong value, radius 8, 16
/// across and 10 down. The pair is drawn 50/50, so both are usually wrapped in [Expanded].
class ConsoleSoftButton extends StatelessWidget {
  const ConsoleSoftButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.accent = DeliveryAccent.critical,
    this.busy = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final DeliveryAccent accent;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final bool on = onPressed != null && !busy;
    final Color foreground = on ? accent.color : DeliveryColors.faint;

    return Material(
      color: on ? accent.tint : DeliveryColors.background,
      borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      child: InkWell(
        onTap: on ? onPressed : null,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DeliverySpacing.md,
            vertical: 10,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (busy)
                SizedBox(
                  width: 14,
                  height: 14,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: foreground),
                )
              else if (icon != null)
                Icon(icon, size: 16, color: foreground),
              if (busy || icon != null) const SizedBox(width: DeliverySpacing.sm),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: foreground,
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

/// The small brand-tinted text chip: "Upload Logo".
///
/// Figma `change-logo-btn` (3:3928): rose wash, 12 across, 6 down, radius 6, SemiBold 12 crimson.
class ConsoleTintButton extends StatelessWidget {
  const ConsoleTintButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bool on = onPressed != null;
    return Material(
      color: on ? DeliveryColors.brandSoft : DeliveryColors.background,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DeliverySpacing.md - DeliverySpacing.xs,
            vertical: 6,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: on ? DeliveryColors.brand : DeliveryColors.faint,
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled, read-only value box — the whole of the design's settings form.
///
/// Figma `input-field` (3:3931 and siblings): SemiBold 13 slate label over a slate-50 box with a
/// 1px border at radius 8 and 12px of padding, the value in Regular 14 ink.
///
/// Read-only on purpose and not an oversight: every field the carrier settings frame draws is
/// either owned by the Backoffice (legal name, payout account) or has no endpoint at all, so an
/// editable box would be a text field whose contents go nowhere. [trailing] carries the design's
/// copy glyph.
class ConsoleReadOnlyField extends StatelessWidget {
  const ConsoleReadOnlyField({
    super.key,
    required this.label,
    required this.value,
    this.trailing,
    this.placeholder = false,
  });

  final String label;
  final String value;
  final Widget? trailing;

  /// Draws [value] in the faint tier — for "nothing on file", which is a different statement from
  /// a value that happens to be short.
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: DeliveryColors.muted,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
          decoration: BoxDecoration(
            color: DeliveryColors.background,
            border: Border.all(color: DeliveryColors.border),
            borderRadius: BorderRadius.circular(DeliveryRadius.sm),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: placeholder ? DeliveryColors.faint : DeliveryColors.ink,
                  ),
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: DeliverySpacing.sm),
                trailing!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The uppercase divider label inside a card — "ONBOARDING DOCUMENTATION CHECK".
///
/// Figma 3:3783: SemiBold 12, 0.5px tracking, slate-400.
class ConsoleSectionLabel extends StatelessWidget {
  const ConsoleSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: DeliveryColors.faint,
      ),
    );
  }
}

/// The rose count chip beside a heading — "3 Applications Left".
///
/// Figma 3:3769: rose wash, 8 across, 2 down, radius 10, SemiBold 12 crimson.
class ConsoleCountChip extends StatelessWidget {
  const ConsoleCountChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: DeliveryColors.brandSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: DeliveryColors.brand,
        ),
      ),
    );
  }
}

/// The small state badge on a checklist row — Approved / Pending Verification / Uploaded.
///
/// Figma `badge` (3:3788): 8 across, 2 down, radius 6, SemiBold 11 on the accent's own wash.
/// Smaller and squarer than [ConsoleStatusPill], which is the row-level badge on a table.
class ConsoleSmallBadge extends StatelessWidget {
  const ConsoleSmallBadge({
    super.key,
    required this.label,
    this.accent = DeliveryAccent.positive,
  });

  final String label;
  final DeliveryAccent accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: accent.tint,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: accent.color,
        ),
      ),
    );
  }
}

/// A soft outlined tag — the settings frame's dispatch regions.
///
/// Figma 3:3951: slate-50 fill, 1px border, 12 across, 6 down, radius 12, Regular 13 slate.
class ConsoleTagChip extends StatelessWidget {
  const ConsoleTagChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DeliverySpacing.md - DeliverySpacing.xs,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: DeliveryColors.background,
        border: Border.all(color: DeliveryColors.border),
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, color: DeliveryColors.muted),
      ),
    );
  }
}

/// The two-up segmented switch the settings frame uses for the portal language.
///
/// Figma 3:3961: slate-50 trough with a 1px border at radius 8 and 4px of padding; the chosen
/// option is a crimson block at radius 6, 12 across and 6 down, SemiBold 13 white; the other is
/// SemiBold 13 slate on the trough.
///
/// Distinct from [ConsoleFilterTabs], which is a filter over a list. This one sets a preference.
class ConsoleSegmented extends StatelessWidget {
  const ConsoleSegmented({
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
    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.xs),
      decoration: BoxDecoration(
        color: DeliveryColors.background,
        border: Border.all(color: DeliveryColors.border),
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < labels.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: DeliverySpacing.xs),
            Material(
              color: i == selectedIndex ? DeliveryColors.brand : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                onTap: () => onSelected(i),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DeliverySpacing.md - DeliverySpacing.xs,
                    vertical: 6,
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: i == selectedIndex
                          ? DeliveryColors.white
                          : DeliveryColors.muted,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A lettered identity tile, where the design draws a photograph.
///
/// The platform holds no avatar for a rider, an applicant or a company — a Keycloak subject is a
/// uuid and a display name — so the drawn photo has no source. Rather than a grey placeholder box
/// (which says nothing) or a stock face (which would be a lie about a real person), this keeps the
/// design's exact geometry and fills it with the initial in the brand wash.
///
/// [size] is the outer square; [radius] null draws a circle, which is what the sidebar and the
/// applicant cards use.
class ConsoleAvatar extends StatelessWidget {
  const ConsoleAvatar({
    super.key,
    required this.name,
    this.size = 40,
    this.radius,
  });

  final String name;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final String trimmed = name.trim();
    final String initial =
        trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DeliveryColors.brandSoft,
        shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: radius == null ? null : BorderRadius.circular(radius!),
      ),
      child: Text(
        initial,
        style: TextStyle(
          // Roughly 45% of the tile, which is where the design's photographs sit optically.
          fontSize: size * 0.45,
          fontWeight: FontWeight.w700,
          color: DeliveryColors.brand,
        ),
      ),
    );
  }
}

/// One column of a [ConsoleBarChart].
class ConsoleBar {
  const ConsoleBar({required this.label, required this.value, this.tooltip});

  /// The x-axis caption — a clock time, a weekday.
  final String label;

  final num value;

  /// What hovering says. Defaults to `label: value`.
  final String? tooltip;
}

/// The design's column chart, as drawn: 130px tall, 16px bars with a 4px top radius, 32px between
/// columns, captions in Regular 11 slate-400.
///
/// Figma `chart-visual` (3:3528) draws two series per column — Express and Standard. The platform
/// has no service tiers, so this renders one series and the caller says so beside the legend; the
/// geometry is otherwise the design's, which is what makes the card read right when a second
/// series does eventually exist.
class ConsoleBarChart extends StatelessWidget {
  const ConsoleBarChart({
    super.key,
    required this.bars,
    this.height = 130,
    this.color = DeliveryColors.brand,
    this.emptyLabel = 'Nothing to chart yet',
  });

  final List<ConsoleBar> bars;
  final double height;
  final Color color;

  /// Shown in place of the columns when every value is zero — a row of hairlines looks like a
  /// rendering fault rather than a quiet day.
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final num peak = bars.isEmpty
        ? 0
        : bars.map((ConsoleBar b) => b.value).reduce((num a, num b) => a > b ? a : b);

    if (bars.isEmpty || peak <= 0) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(emptyLabel, style: ConsoleText.pageSubtitle),
        ),
      );
    }

    return SizedBox(
      height: height + 20,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            for (int i = 0; i < bars.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: DeliverySpacing.xl),
              _Column(bar: bars[i], peak: peak, height: height, color: color),
            ],
          ],
        ),
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.bar,
    required this.peak,
    required this.height,
    required this.color,
  });

  final ConsoleBar bar;
  final num peak;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // A zero column keeps a 2px hairline so the reader can see the slot exists and is empty,
    // rather than seeing a gap and counting the columns wrong.
    final double filled = bar.value <= 0 ? 2 : (bar.value / peak) * height;

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        Tooltip(
          message: bar.tooltip ?? '${bar.label}: ${bar.value}',
          child: Container(
            width: 16,
            height: filled.clamp(2, height),
            decoration: BoxDecoration(
              color: bar.value <= 0 ? DeliveryColors.border : color,
              // 4px, the only radius on these frames the token scale does not carry.
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ),
        ),
        const SizedBox(height: DeliverySpacing.sm),
        Text(bar.label, style: ConsoleText.meta),
      ],
    );
  }
}

/// The chart card's legend entry: a 12px rounded swatch and its name.
///
/// Figma 3:3522: radius 3, 6px gap, Regular 12 slate.
class ConsoleLegendSwatch extends StatelessWidget {
  const ConsoleLegendSwatch({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: DeliveryColors.muted)),
      ],
    );
  }
}

/// One line of the design's activity feed: a coloured bullet, the sentence, and when.
///
/// Figma `activity-row` (3:3568): 8px dot at radius 4, 12px gap, Regular 13 ink over Regular 11
/// slate-400, 16px between rows.
class ConsoleActivityRow extends StatelessWidget {
  const ConsoleActivityRow({
    super.key,
    required this.message,
    required this.when,
    this.accent = DeliveryAccent.info,
  });

  final String message;
  final String when;
  final DeliveryAccent accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          // The dot is optically centred on the first line of 13px text, not on the block.
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: accent.color,
              // The bullet is drawn as a 4-radius square rather than a circle.
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(message, style: ConsoleText.body),
              const SizedBox(height: 2),
              Text(when, style: ConsoleText.meta),
            ],
          ),
        ),
      ],
    );
  }
}
