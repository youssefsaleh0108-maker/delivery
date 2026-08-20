import 'package:flutter/material.dart';

import 'panels.dart';
import 'tokens.dart';

/// One day in a [TrendChart].
///
/// Two numbers per day, and the second is always a subset of the first — orders and how many of
/// them were delivered, jobs and how many completed. Drawing the whole as a pale bar with the
/// completed part solid inside it means the gap between them is visible as a gap, which is the
/// thing worth noticing and the thing two separate bars would make you compute.
class TrendPoint {
  const TrendPoint({
    required this.label,
    required this.total,
    required this.completed,
    required this.money,
  });

  /// Short enough for an axis: a weekday initial, or a day number.
  final String label;
  final num total;
  final num completed;

  /// Shown in the tooltip rather than plotted. Two scales on one chart is two charts.
  final double money;
}

/// A small bar chart for "how has it been going".
///
/// Hand-drawn rather than a charting package, on purpose. This is a bar per day with two numbers
/// each — the smallest thing a chart library does, and the cost of the library is a dependency in
/// four apps, a theme to override, and a set of defaults that look like somebody else's product.
/// The whole of this is under a hundred lines and matches the brand because it is built from it.
///
/// Deliberately has no y-axis. A bar chart of fourteen values that is read at a glance for shape
/// does not need gridlines to be useful, and the exact number is one hover away — where somebody
/// who actually wants a figure will look for it.
class TrendChart extends StatefulWidget {
  const TrendChart({
    super.key,
    required this.points,
    required this.emptyLabel,
    this.height = 132,
    this.formatMoney,
  });

  final List<TrendPoint> points;

  /// Shown instead of an all-zero chart. A flat row of nothing reads as broken, not as quiet.
  final String emptyLabel;
  final double height;

  /// How to render the money in the tooltip. Null hides it.
  final String Function(double)? formatMoney;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  int? _hovered;

  @override
  Widget build(BuildContext context) {
    final num peak = widget.points.fold<num>(
        0, (num a, TrendPoint p) => p.total > a ? p.total : a);

    if (widget.points.isEmpty || peak == 0) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(widget.emptyLabel,
              style: const TextStyle(fontSize: 13, color: DeliveryColors.muted)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: widget.height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (int i = 0; i < widget.points.length; i++)
                Expanded(child: _bar(i, widget.points[i], peak)),
            ],
          ),
        ),
        const SizedBox(height: DeliverySpacing.xs),
        // The labels sit outside the bar row so a long label cannot push a bar's baseline up and
        // leave one day looking shorter than it is.
        Row(
          children: <Widget>[
            for (final TrendPoint point in widget.points)
              Expanded(
                child: Text(
                  point.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600, color: DeliveryColors.muted),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _bar(int index, TrendPoint point, num peak) {
    final bool active = _hovered == index;
    final double full = (point.total / peak).clamp(0.04, 1).toDouble();
    final double done = point.total == 0 ? 0 : (point.completed / point.total).clamp(0.0, 1.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = index),
      onExit: (_) => setState(() => _hovered = null),
      child: Tooltip(
        message: _tooltip(point),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: FractionallySizedBox(
            heightFactor: full,
            alignment: Alignment.bottomCenter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: active ? DeliveryColors.brandLine : DeliveryColors.brandSoft,
                borderRadius: BorderRadius.circular(4),
              ),
              child: FractionallySizedBox(
                heightFactor: done,
                alignment: Alignment.bottomCenter,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: active ? DeliveryColors.brandDark : DeliveryColors.brand,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _tooltip(TrendPoint point) {
    final StringBuffer text = StringBuffer('${point.label}: ${point.total}');
    if (point.completed != point.total) {
      text.write(' (${point.completed})');
    }
    if (widget.formatMoney != null && point.money > 0) {
      text.write(' · ${widget.formatMoney!(point.money)}');
    }
    return text.toString();
  }
}

/// A number and how it compares with the last one, side by side.
///
/// The comparison is the reason a dashboard exists: "42 orders" is a fact and "42 orders, up from
/// 31" is information. Kept as one widget so the arrow, the colour and the words can never disagree
/// with each other, which is what happens when each screen assembles its own.
class TrendHeadline extends StatelessWidget {
  const TrendHeadline({
    super.key,
    required this.value,
    required this.label,
    required this.comparison,
    required this.direction,
    this.icon,
  });

  final String value;
  final String label;

  /// Already-worded, because the wording is a translation: "12% up on yesterday".
  final String comparison;
  final TrendDirection direction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 16, color: DeliveryColors.muted),
                const SizedBox(width: DeliverySpacing.xs),
              ],
              Flexible(
                child: Text(
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
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.xs),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.05),
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Icon(direction.icon, size: 14, color: direction.color),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  comparison,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: direction.color),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Which way a figure moved.
///
/// Down is not painted red. A quiet Tuesday is not an error, and a dashboard that shows alarm every
/// time trade dips is one people stop reading — the colour is saved for things that need doing.
enum TrendDirection {
  up(Icons.trending_up_rounded, DeliveryAccent.positive),
  down(Icons.trending_down_rounded, null),
  flat(Icons.trending_flat_rounded, null);

  const TrendDirection(this.icon, this._accent);

  final IconData icon;
  final DeliveryAccent? _accent;

  Color get color => _accent?.color ?? DeliveryColors.muted;

  /// Compares like with like. Both zero is flat, not a fall from nothing.
  static TrendDirection between(num now, num before) {
    if (now == before) return TrendDirection.flat;
    return now > before ? TrendDirection.up : TrendDirection.down;
  }
}
