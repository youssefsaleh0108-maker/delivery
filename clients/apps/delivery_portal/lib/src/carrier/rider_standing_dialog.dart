import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import '../shell/console_controls.dart';
import '../shell/shell.dart';

/// What the suspension dialog comes back with: the reason the server requires, and a note.
class RiderStandingAnswer {
  const RiderStandingAnswer({this.reason, this.note});

  /// Null on a reinstatement, which needs none.
  final SuspensionReason? reason;
  final String? note;
}

/// Suspending or reinstating one rider — the profile's "Suspend Rider" / "Reinstate Rider".
///
/// The reason is typed rather than free text because the server's enum is what the record is
/// searched by later; the note beside it is the free half, and optional on both. Moved out of the
/// old fleet table unchanged in behaviour, and localised on the way: it is now reached from a page
/// that is.
class RiderStandingDialog extends StatefulWidget {
  const RiderStandingDialog({super.key, required this.name, required this.suspending});

  final String name;
  final bool suspending;

  static Future<RiderStandingAnswer?> show(
    BuildContext context, {
    required String name,
    required bool suspending,
  }) =>
      showDialog<RiderStandingAnswer>(
        context: context,
        builder: (BuildContext context) =>
            RiderStandingDialog(name: name, suspending: suspending),
      );

  @override
  State<RiderStandingDialog> createState() => _RiderStandingDialogState();
}

/// A suspension reason in the reader's language. The model's own label is English, for logs.
String suspensionReasonLabel(DeliveryStrings t, SuspensionReason reason) => switch (reason) {
      SuspensionReason.fraud => t.carrRidersReasonFraud,
      SuspensionReason.abuse => t.carrRidersReasonAbuse,
      SuspensionReason.nonPayment => t.carrRidersReasonNonPayment,
      SuspensionReason.policyViolation => t.carrRidersReasonPolicyViolation,
      SuspensionReason.partnerRequest => t.carrRidersReasonPartnerRequest,
      SuspensionReason.other => t.carrRidersReasonOther,
    };

class _RiderStandingDialogState extends State<RiderStandingDialog> {
  SuspensionReason? _reason;
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    // Dead until a reason is chosen: "suspended" with no reason is not a record anybody can act on.
    final bool ready = !widget.suspending || _reason != null;

    return AlertDialog(
      backgroundColor: DeliveryColors.white,
      surfaceTintColor: DeliveryColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
      title: Text(
        widget.suspending
            ? t.carrRidersSuspendTitle(widget.name)
            : t.carrRidersReinstateTitle(widget.name),
        style: ConsoleText.cardTitle,
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.suspending ? t.carrRidersSuspendBody : t.carrRidersReinstateBody,
              style: ConsoleText.pageSubtitle,
            ),
            if (widget.suspending) ...<Widget>[
              const SizedBox(height: DeliverySpacing.md),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ConsoleSelect(
                  label: _reason == null
                      ? t.carrRidersChooseReason
                      : suspensionReasonLabel(t, _reason!),
                  icon: Icons.flag_outlined,
                  options: <ConsoleOption>[
                    for (final SuspensionReason r in SuspensionReason.values)
                      ConsoleOption(label: suspensionReasonLabel(t, r), value: r.wire),
                  ],
                  onSelected: (String? wire) =>
                      setState(() => _reason = SuspensionReason.fromWire(wire)),
                ),
              ),
            ],
            const SizedBox(height: DeliverySpacing.md),
            TextField(
              controller: _note,
              maxLines: 3,
              maxLength: 500,
              style: ConsoleText.cell,
              cursorColor: DeliveryColors.brand,
              decoration: InputDecoration(
                hintText: t.carrRidersNoteHint,
                hintStyle: const TextStyle(fontSize: 14, color: DeliveryColors.faint),
                filled: true,
                fillColor: DeliveryColors.background,
                border: _border(DeliveryColors.border),
                enabledBorder: _border(DeliveryColors.border),
                focusedBorder: _border(DeliveryColors.brand),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            t.cancel,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.muted,
            ),
          ),
        ),
        if (widget.suspending)
          ConsoleSoftButton(
            label: t.carrRidersSuspendRider,
            accent: DeliveryAccent.caution,
            onPressed: ready ? () => _pop(context) : null,
          )
        else
          ConsolePrimaryButton(
            label: t.carrRidersReinstateRider,
            color: DeliveryAccent.positive.color,
            onPressed: () => _pop(context),
          ),
      ],
    );
  }

  static OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        borderSide: BorderSide(color: color),
      );

  void _pop(BuildContext context) {
    final String note = _note.text.trim();
    Navigator.pop(
      context,
      RiderStandingAnswer(reason: _reason, note: note.isEmpty ? null : note),
    );
  }
}
