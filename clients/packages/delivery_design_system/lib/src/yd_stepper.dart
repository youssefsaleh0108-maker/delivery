import 'package:flutter/material.dart';

import 'tokens.dart';

/// The wizard progress row the signup flows share (Figma `rider-signup-documents` 22:540,
/// `merchant-signup-*`, `carrier-register-*`).
///
/// The design draws this as a **bar**, not as numbered circles: a label row — the step counter in
/// SemiBold 13 [DeliveryColors.brand] on one side, an optional completion label in
/// [DeliveryColors.muted] on the other — sitting above a 4px track in [DeliveryColors.border]
/// with a [DeliveryColors.brand] fill sized to progress. The carrier web wizard splits that track
/// into one segment per step instead of filling it continuously; pass [segmented] for that.
///
/// (The only numbered circles in the file are the oversized `01 / 02 / 03` watermarks in the
/// marketing site's "how it works" band, which is a different component and not this one.)
///
/// Both labels arrive already localised — the package holds no strings, so the caller formats
/// "Step 3 of 4" / "75% Complete" itself.
class YdStepper extends StatelessWidget {
  const YdStepper({
    super.key,
    required this.step,
    required this.totalSteps,
    this.stepLabel,
    this.progressLabel,
    this.segmented = false,
    this.trackHeight = 4,
  }) : assert(totalSteps > 0, 'a wizard needs at least one step');

  /// The step the user is on, 1-based. The bar fills to `step / totalSteps`.
  final int step;

  final int totalSteps;

  /// Leading label, already localised — e.g. "Step 3 of 4". Omit for a bare bar.
  final String? stepLabel;

  /// Trailing label, already localised — e.g. "75% Complete".
  final String? progressLabel;

  /// Draws one segment per step instead of a single continuous fill.
  final bool segmented;

  final double trackHeight;

  double get _fraction => (step / totalSteps).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final BorderRadius corners = BorderRadius.circular(trackHeight / 2);

    final Widget track = segmented
        ? Row(
            children: <Widget>[
              for (int i = 0; i < totalSteps; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: DeliverySpacing.xs + 2),
                Expanded(
                  child: Container(
                    height: trackHeight,
                    decoration: BoxDecoration(
                      color: i < step
                          ? DeliveryColors.brand
                          : DeliveryColors.border,
                      borderRadius: corners,
                    ),
                  ),
                ),
              ],
            ],
          )
        : ClipRRect(
            borderRadius: corners,
            child: Container(
              height: trackHeight,
              color: DeliveryColors.border,
              child: FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: _fraction,
                child: Container(color: DeliveryColors.brand),
              ),
            ),
          );

    final bool hasLabels = stepLabel != null || progressLabel != null;

    return Semantics(
      value: stepLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (hasLabels) ...<Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Flexible(
                  child: Text(
                    stepLabel ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: DeliveryColors.brand,
                      height: 1.2,
                    ),
                  ),
                ),
                if (progressLabel != null)
                  Flexible(
                    child: Text(
                      progressLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: DeliveryColors.muted,
                        height: 1.2,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          ],
          track,
        ],
      ),
    );
  }
}
