import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

import 'console_chrome.dart';

/// The square or circular mark that stands in for a photograph the platform does not have.
///
/// The Figma console tables draw a photograph in every leading cell — a 40px rounded-8 shop logo on
/// `backoffice-merchants` (3:2746), a 36px circular portrait on `backoffice-riders` (3:3166). No
/// endpoint on this side returns either: an onboarding application carries a business name and a
/// contact, a fleet roster carries Keycloak subjects. Drawing a grey placeholder box in every row
/// would spend the design's geometry on nothing, so this keeps the geometry and fills it with the
/// one thing that is real — the first letter of the name — on the brand tint.
///
/// The same substitution the sidebar's footer card makes for the signed-in user's avatar, and made
/// the same way on purpose: two different stand-ins for a missing portrait would read as two
/// different kinds of thing.
class ConsoleInitialTile extends StatelessWidget {
  const ConsoleInitialTile({
    super.key,
    required this.label,
    this.size = 40,
    this.radius = DeliveryRadius.sm,
    this.color = DeliveryColors.brand,
  });

  /// A 36px circle, per the riders table and the sidebar footer.
  const ConsoleInitialTile.circle({
    super.key,
    required this.label,
    this.size = 36,
    this.color = DeliveryColors.brand,
  }) : radius = null;

  final String label;
  final double size;

  /// Null draws a circle.
  final double? radius;

  final Color color;

  @override
  Widget build(BuildContext context) {
    final String initial = _initialOf(label);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: radius == null ? null : BorderRadius.circular(radius!),
      ),
      child: Text(
        initial,
        style: TextStyle(
          // Scaled off the box rather than fixed, so the 36 and the 40 read as one family.
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  /// The first letter that is one, so an id like `a1b2-…` and a name like `Rose & Crust` both
  /// produce something a reader can tell apart. Falls back to a bullet rather than to an empty box.
  static String _initialOf(String label) {
    for (final int unit in label.trim().runes) {
      final String c = String.fromCharCode(unit);
      if (RegExp(r'[A-Za-z؀-ۿ]').hasMatch(c)) return c.toUpperCase();
    }
    final String trimmed = label.trim();
    return trimmed.isEmpty ? '•' : trimmed.substring(0, 1).toUpperCase();
  }
}

/// A compact key-and-value block: the label above the value, several of them across a row.
///
/// Carries the free-form answers an onboarding application arrives with (vehicle, work region,
/// business type) and the fixed facts beside them, in the console's own type tiers rather than in a
/// table — these are read once, when somebody is deciding, not scanned down a column.
class ConsoleFactGrid extends StatelessWidget {
  const ConsoleFactGrid({super.key, required this.facts, this.columnWidth = 200});

  final List<ConsoleFact> facts;

  /// Each fact gets at most this much; they wrap onto a new line rather than shrinking.
  final double columnWidth;

  @override
  Widget build(BuildContext context) {
    if (facts.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: DeliverySpacing.lg,
      runSpacing: DeliverySpacing.md,
      children: <Widget>[
        for (final ConsoleFact fact in facts)
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: columnWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  fact.label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: DeliveryColors.faint,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        fact.value,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: fact.absent ? DeliveryColors.faint : DeliveryColors.ink,
                        ),
                      ),
                    ),
                    if (fact.mark != null) ...<Widget>[
                      const SizedBox(width: DeliverySpacing.xs + 1),
                      Icon(fact.mark!.icon, size: 15, color: fact.mark!.accent.color),
                    ],
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One entry in a [ConsoleFactGrid].
class ConsoleFact {
  const ConsoleFact(this.label, this.value, {this.mark, this.absent = false});

  final String label;
  final String value;

  /// A verification tick or a warning beside the value.
  final ConsoleFactMark? mark;

  /// Draws the value in the faint tier — for "Not given" and its like.
  final bool absent;
}

/// The glyph beside a fact's value, and what it means.
class ConsoleFactMark {
  const ConsoleFactMark(this.icon, this.accent);

  const ConsoleFactMark.verified()
      : icon = Icons.verified_rounded,
        accent = DeliveryAccent.positive;

  const ConsoleFactMark.unverified()
      : icon = Icons.error_outline_rounded,
        accent = DeliveryAccent.caution;

  final IconData icon;
  final DeliveryAccent accent;
}

/// The line pinned under a table with a column the platform has nothing to fill from.
///
/// A single sentence and one quiet chip rather than a chip in every affected cell: the design's
/// columns stay drawn and stay empty, and this says once why — which is the honest reading, and
/// the only one that does not put a number nobody measured in front of an operator.
///
/// The chip is a [ConsoleQuietChip] and the label defaults to "No source", not "Coming soon".
/// Both of these notes explain an *absent source*, and one of them — no rider on this platform
/// carries a work region — is a fact about the data model rather than a queue position. Promising
/// an operator that a column is arriving, when nothing is coming, is the failure this widget was
/// written to avoid; it should not commit it in its own chip. Callers whose column really is
/// waiting on an endpoint pass a label that says so.
class ConsoleInertNote extends StatelessWidget {
  const ConsoleInertNote({super.key, required this.text, this.chipLabel = 'No source'});

  final String text;
  final String chipLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        ConsoleQuietChip(label: chipLabel),
        const SizedBox(width: DeliverySpacing.sm + 2),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: DeliveryColors.faint),
          ),
        ),
      ],
    );
  }
}

/// The em-dash a cell holds when there is nothing true to put in it.
///
/// Not a zero. A rider who has made no deliveries today and a rider whose deliveries nobody counts
/// are different facts, and "0" says the first when the truth is the second.
class ConsoleNoValue extends StatelessWidget {
  const ConsoleNoValue({super.key, this.tooltip});

  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    const Widget dash = Text('—', style: TextStyle(fontSize: 14, color: DeliveryColors.faint));
    if (tooltip == null) return dash;
    return Tooltip(message: tooltip!, child: dash);
  }
}
