import 'package:flutter/material.dart';

import 'tokens.dart';

/// The softer layout kit: the pieces a friendly dashboard is actually made of.
///
/// Added 2026-08-12. The interface before this was structurally sound but visually flat — every
/// surface was a bordered white card in one brand colour, so nothing looked more or less important
/// than anything else. These give a screen a shape you can read at a glance: numbers at the top,
/// labelled groups below, and colour that means something.

// ---------------------------------------------------------------------------- headings

/// A small-caps group label.
///
/// Groups do more work than a heading of the same size in sentence case: they read as furniture
/// rather than as content, so the eye skips them until it needs them. That is exactly what a label
/// over a row of buttons should do.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;

  /// Optional right-hand affordance — a count, or a "see all".
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.9,
                color: DeliveryColors.muted,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------- surfaces

/// The standard card: white, rounded, lifted by a shadow rather than ringed by a border.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(DeliverySpacing.md),
    this.onTap,
    this.accent,
    this.selected = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  /// Draws a coloured edge down the leading side — the reference's way of saying "this row has a
  /// state" without spending a whole chip on it.
  final Color? accent;

  /// Rings the card in the brand colour. For a choice the user has made, not for emphasis.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(DeliveryRadius.lg);

    // A Stack rather than a stretched Row.
    //
    // Running the stripe down a Row with CrossAxisAlignment.stretch reads well and is wrong:
    // stretch gives every child a *tight* height, so wherever this card's own height is unbounded
    // — inside a Wrap, a Column, a ListView, which is most places — the child is asked to be
    // infinitely tall and layout fails. Release builds drop the assertion, so it degrades quietly
    // instead of announcing itself.
    //
    // Positioning the stripe instead lets the content decide the height, and the stripe then
    // matches whatever that turns out to be — which is what the stretched Row was for.
    Widget body = Padding(padding: padding, child: child);
    if (accent != null) {
      body = Stack(
        // The content still receives the card's own constraints, so a card in a full-width slot
        // still fills it.
        fit: StackFit.passthrough,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(
                padding.left + 4, padding.top, padding.right, padding.bottom),
            child: child,
          ),
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: ColoredBox(color: accent!),
          ),
        ],
      );
    }

    Widget surface = Container(
      decoration: BoxDecoration(
        color: DeliveryColors.white,
        borderRadius: radius,
        boxShadow: DeliveryShadows.card,
        border: selected ? Border.all(color: DeliveryColors.brand, width: 1.5) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: body,
    );

    if (onTap == null) return surface;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: radius, child: surface),
    );
  }
}

/// A short explanatory note on a tinted field.
///
/// For the sentence that stops somebody misreading the controls above it. Tinted rather than plain
/// so it is clearly commentary and not another control.
class SoftNote extends StatelessWidget {
  const SoftNote({
    super.key,
    required this.text,
    this.accent = DeliveryAccent.info,
    this.icon,
  });

  final String text;
  final DeliveryAccent accent;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.sm + 2),
      decoration: BoxDecoration(
        color: accent.tint,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon ?? Icons.info_outline_rounded, size: 17, color: accent.color),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, height: 1.35, color: accent.color),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------- numbers

/// One number that matters, with the thing it counts underneath.
///
/// The accent is the whole point: a row of these in five colours tells you where to look before
/// you have read a single word.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.accent,
    this.footnote,
    this.onTap,
  });

  final String value;
  final String label;
  final IconData icon;
  final DeliveryAccent accent;

  /// A share or a delta — the small figure top-right in the reference.
  final String? footnote;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.all(DeliverySpacing.sm + 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.tint,
                  borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                ),
                child: Icon(icon, size: 17, color: accent.color),
              ),
              const Spacer(),
              if (footnote != null)
                // Flexible, so a footnote longer than the tile truncates instead of overflowing.
                // These tiles are laid out by column count, not by content, so how much room a
                // footnote gets is decided by the window — not by whoever wrote the string.
                Flexible(
                  child: Text(footnote!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: DeliveryColors.muted)),
                ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.sm),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.05,
              color: accent.color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: DeliveryColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// A row of [StatTile]s that wraps rather than overflowing.
///
/// Wrap, not a Row: four tiles fit a tablet and two fit a narrow phone, and a horizontal scroll for
/// the top-line numbers would hide half of them behind a gesture nobody knows to make.
class StatRow extends StatelessWidget {
  const StatRow({super.key, required this.tiles, this.minTileWidth = 150});

  final List<Widget> tiles;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double gap = DeliverySpacing.sm;
        final int columns =
            ((constraints.maxWidth + gap) / (minTileWidth + gap)).floor().clamp(1, tiles.length);
        final double width = (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final Widget tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

/// How much of something has been used, as a bar with its numbers above it.
class UsageBar extends StatelessWidget {
  const UsageBar({
    super.key,
    required this.label,
    required this.used,
    required this.total,
    this.accent = DeliveryAccent.positive,
    this.format,
  });

  final String label;
  final double used;
  final double total;
  final DeliveryAccent accent;

  /// How to render each number. Defaults to one decimal place.
  final String Function(double)? format;

  @override
  Widget build(BuildContext context) {
    final String Function(double) fmt = format ?? (double v) => v.toStringAsFixed(1);
    // Clamped so a quota someone has overrun renders as full rather than as a bar overflowing its
    // own track, which reads as a rendering bug rather than as an overrun.
    final double fraction = total <= 0 ? 0 : (used / total).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(label.toUpperCase(),
                style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    letterSpacing: 0.6, color: DeliveryColors.muted)),
            const Spacer(),
            Text('${fmt(used)} / ${fmt(total)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: DeliverySpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(DeliveryRadius.pill),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: accent.tint,
            valueColor: AlwaysStoppedAnimation<Color>(accent.color),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------- actions

/// One action in a grid: an icon on a soft tint, with its name under it.
///
/// For the secondary things a screen can do. The primary action stays a full-width filled button —
/// a grid of equals has no primary, which is fine for "reset MAC / live ping" and wrong for "pay".
class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = DeliveryAccent.neutral,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final DeliveryAccent accent;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: SoftCard(
        onTap: enabled ? onTap : null,
        padding: const EdgeInsets.symmetric(
            horizontal: DeliverySpacing.sm, vertical: DeliverySpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: accent.tint, shape: BoxShape.circle),
              child: Icon(icon, size: 19, color: accent.color),
            ),
            const SizedBox(height: DeliverySpacing.sm),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

/// A grid of [ActionTile]s, three across on anything phone-width or wider.
class ActionGrid extends StatelessWidget {
  const ActionGrid({super.key, required this.actions, this.minTileWidth = 104});

  final List<Widget> actions;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double gap = DeliverySpacing.sm;
        final int columns = ((constraints.maxWidth + gap) / (minTileWidth + gap))
            .floor()
            .clamp(1, actions.length);
        final double width = (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final Widget action in actions) SizedBox(width: width, child: action),
          ],
        );
      },
    );
  }
}

/// The screen's main action: full width, filled, unmissable.
class PrimaryAction extends StatelessWidget {
  const PrimaryAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = DeliveryColors.brand,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: DeliveryColors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DeliveryRadius.md)),
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: DeliveryColors.white),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: 19),
                    const SizedBox(width: DeliverySpacing.sm),
                  ],
                  Text(label,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ],
              ),
      ),
    );
  }
}

/// A small state pill: a dot and a word, on the state's own tint.
class StatePill extends StatelessWidget {
  const StatePill({
    super.key,
    required this.label,
    required this.accent,
    this.showDot = true,
  });

  final String label;
  final DeliveryAccent accent;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.tint,
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (showDot) ...<Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: accent.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: accent.color)),
        ],
      ),
    );
  }
}
