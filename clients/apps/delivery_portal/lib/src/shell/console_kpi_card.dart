import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

import 'console_chrome.dart';

/// The line under a KPI's number: a movement, and what it is measured against.
///
/// There is no week-over-week aggregation endpoint on the platform today, so most call sites will
/// leave this null and show a [ConsoleComingSoonChip] instead. It exists for the figures that *can*
/// be derived from data already loaded — a share of a list, a count against a total — and never for
/// a number that would have to be invented.
class ConsoleKpiTrend {
  const ConsoleKpiTrend({
    required this.delta,
    required this.caption,
    this.accent = DeliveryAccent.positive,
    this.rising = true,
  });

  /// The movement itself — "+14.3%", "73% utilization", "+4 new".
  final String delta;

  /// What it is measured against — "vs last week".
  final String caption;

  final DeliveryAccent accent;

  /// Picks the arrow. Direction only; the colour is [accent]'s job, because a rise is not always
  /// good news.
  final bool rising;
}

/// One figure from the console's KPI row.
///
/// Figma `kpi-card` (3:2542 and siblings): white card, 24px padding, the caption opposite a
/// rose-tinted icon tile, then the number and its trend line.
class ConsoleKpiCard extends StatelessWidget {
  const ConsoleKpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.trend,
    this.footnote,
    this.onTap,
  });

  final String label;

  /// Already formatted. This widget does not know about currencies or thousands separators, and
  /// must not start guessing at them.
  final String value;

  final IconData icon;

  /// The design's green movement row. Null draws nothing — see [ConsoleKpiTrend].
  final ConsoleKpiTrend? trend;

  /// Occupies the trend row when there is no trend to show; a [ConsoleComingSoonChip] usually.
  final Widget? footnote;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget card = Container(
      padding: const EdgeInsets.all(ConsoleMetrics.cardPadding),
      decoration: ConsoleSurface.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: ConsoleText.kpiLabel,
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: DeliveryColors.brandSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: DeliveryColors.brand),
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ConsoleText.kpiValue,
          ),
          if (trend != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            _TrendRow(trend: trend!),
          ] else if (footnote != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            footnote!,
          ],
        ],
      ),
    );

    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DeliveryRadius.lg),
      child: card,
    );
  }
}

class _TrendRow extends StatelessWidget {
  const _TrendRow({required this.trend});

  final ConsoleKpiTrend trend;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(
          trend.rising ? Icons.arrow_outward : Icons.south_east,
          size: 14,
          color: trend.accent.color,
        ),
        const SizedBox(width: DeliverySpacing.xs),
        Flexible(
          child: Text(
            trend.delta,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: trend.accent.color,
            ),
          ),
        ),
        const SizedBox(width: DeliverySpacing.xs),
        Flexible(
          child: Text(
            trend.caption,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: DeliveryColors.faint),
          ),
        ),
      ],
    );
  }
}

/// The four-across KPI row, with the design's 20px gutters.
///
/// Wraps rather than overflowing: the design is drawn at 1440 and the same four cards at 1100 would
/// otherwise squeeze their numbers into ellipses.
class ConsoleKpiRow extends StatelessWidget {
  const ConsoleKpiRow({super.key, required this.cards, this.minCardWidth = 220});

  final List<Widget> cards;
  final double minCardWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double gap = ConsoleMetrics.kpiGap;
        final int fit = ((constraints.maxWidth + gap) / (minCardWidth + gap)).floor();
        final int perRow = fit.clamp(1, cards.isEmpty ? 1 : cards.length);
        final double width =
            (constraints.maxWidth - gap * (perRow - 1)) / perRow;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final Widget card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}
