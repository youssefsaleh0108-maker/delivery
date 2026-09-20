import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// Tells a working rider that customers cannot see them, why, and the one thing that fixes it.
///
/// Drawn only for the [RiderLocationStatus.hidesRider] states — a rider who is off duty with
/// nothing in hand is not being watched, so their location being off is nobody's problem and
/// nothing is shown. Each state names its own cause, because each has a different way out: the
/// phone's location switch, the permission prompt, this app's settings page, or nothing the app
/// can open (a mock-location app, a wrong clock, no signal, positions the platform keeps refusing,
/// orders to more than one door with no word of which is next), where the banner says what to do
/// and offers no button rather than a button that cannot work.
///
/// Amber rather than red: this is the rider's call to act, not the app failing.
class RiderLocationBanner extends StatelessWidget {
  const RiderLocationBanner({
    super.key,
    required this.status,
    required this.onAllow,
    required this.onOpenSettings,
  });

  final RiderLocationStatus status;

  /// Shows the system permission prompt again.
  final VoidCallback onAllow;

  /// Opens the phone's location switch or this app's settings page, whichever [status] needs.
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    if (!status.hidesRider) return const SizedBox.shrink();

    final DeliveryStrings t = DeliveryStrings.of(context);
    final (String title, String body, String? action, VoidCallback? onAction) = switch (status) {
      RiderLocationStatus.servicesOff => (
          t.riderGpsOffTitle,
          t.riderGpsServicesOffBody,
          t.locTurnOn,
          onOpenSettings,
        ),
      RiderLocationStatus.denied => (
          t.riderGpsOffTitle,
          t.riderGpsDeniedBody,
          t.riderGpsAllow,
          onAllow,
        ),
      RiderLocationStatus.deniedForever => (
          t.riderGpsOffTitle,
          t.riderGpsBlockedBody,
          t.locOpenSettings,
          onOpenSettings,
        ),
      RiderLocationStatus.approximate => (
          t.riderGpsApproximateTitle,
          t.riderGpsApproximateBody,
          t.locOpenSettings,
          onOpenSettings,
        ),
      RiderLocationStatus.mocked => (t.riderGpsMockedTitle, t.riderGpsMockedBody, null, null),
      RiderLocationStatus.clockWrong => (t.riderGpsClockTitle, t.riderGpsClockBody, null, null),
      // The way out is on the order itself — Start navigation on the one they are heading to —
      // so the banner says where it is rather than offering a button that could only guess.
      RiderLocationStatus.legUnknown =>
        (t.riderGpsLegUnknownTitle, t.riderGpsLegUnknownBody, null, null),
      // The last three never get here (the early return above); listed for exhaustiveness.
      RiderLocationStatus.noFix ||
      RiderLocationStatus.idle ||
      RiderLocationStatus.locating ||
      RiderLocationStatus.sharing =>
        (t.riderGpsNoFixTitle, t.riderGpsNoFixBody, null, null),
    };

    const DeliveryAccent accent = DeliveryAccent.caution;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
        decoration: BoxDecoration(
          color: accent.tint,
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          border: Border.all(color: accent.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.location_off_rounded, size: 20, color: accent.color),
                const SizedBox(width: DeliverySpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: accent.onTint,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: DeliverySpacing.xs),
            Padding(
              // Under the title, not under the icon: the two lines read as one message.
              padding: const EdgeInsetsDirectional.only(start: 20 + DeliverySpacing.sm),
              child: Text(
                body,
                style: TextStyle(fontSize: 12.5, color: accent.onTint, height: 1.35),
              ),
            ),
            if (action != null && onAction != null) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 20 + DeliverySpacing.sm),
                child: YdPillButton.secondary(
                  label: action,
                  onPressed: onAction,
                  size: YdPillButtonSize.compact,
                  expand: false,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
