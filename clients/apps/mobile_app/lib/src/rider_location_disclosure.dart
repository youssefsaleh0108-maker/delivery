import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// Shows [RiderLocationDisclosure] and says whether the rider chose to go on to the phone's own
/// location prompt. Dismissing the sheet is "not now".
Future<bool> showRiderLocationDisclosure(BuildContext context) async {
  final bool? goOn = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: DeliveryColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(DeliveryRadius.sheet)),
    ),
    builder: (BuildContext context) => const RiderLocationDisclosure(),
  );
  return goOn ?? false;
}

/// What a rider reads right before the phone asks for their location: who will see it, when, and
/// how long it is kept.
///
/// Shown only when the system prompt is about to appear (the rider location reporter asks for it,
/// see `RiderLocationReporter.explainBeforeAsking`), so it is the rider's one chance to understand
/// the question before answering it. "Not now" leaves the permission as it was; the banner's
/// "Allow location" brings this sheet back before the prompt.
///
/// Every line is a rule the platform enforces rather than a promise made here:
/// - the customer of the delivery the rider is on — only that delivery's customer, never another
///   customer's, and not while the rider is at another customer's door (order-tracking,
///   `TrackingService#sightingFor`);
/// - the shop until the order is collected, and only once the rider is near it;
/// - the rider's delivery company while they are on duty (`PresenceService#locationOf`);
/// - YouDrop support, which also keeps the last position the phone reported;
/// - only while the app is open and the rider is working (the reporter runs in the foreground
///   only, on duty or with an order in hand);
/// - the route of a delivery is kept for 30 days (`delivery.tracking.raw-ping-retention-days`)
///   and then deleted; what is kept after it holds no position.
class RiderLocationDisclosure extends StatelessWidget {
  const RiderLocationDisclosure({super.key});

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(
          DeliverySpacing.lg, DeliverySpacing.md, DeliverySpacing.lg, DeliverySpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: DeliveryColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: DeliverySpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.my_location_rounded, size: 22, color: DeliveryColors.brand),
              const SizedBox(width: DeliverySpacing.sm),
              Expanded(
                child: Text(
                  t.riderGpsDisclosureTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md),
          Text(
            t.riderGpsDisclosureIntro,
            style: const TextStyle(fontSize: 14, color: DeliveryColors.ink, height: 1.4),
          ),
          const SizedBox(height: DeliverySpacing.sm),
          _Line(icon: Icons.person_outline_rounded, text: t.riderGpsDisclosureCustomer),
          _Line(icon: Icons.storefront_outlined, text: t.riderGpsDisclosureShop),
          _Line(icon: Icons.local_shipping_outlined, text: t.riderGpsDisclosureCompany),
          _Line(icon: Icons.support_agent_rounded, text: t.riderGpsDisclosureSupport),
          const SizedBox(height: DeliverySpacing.md),
          _Line(icon: Icons.visibility_outlined, text: t.riderGpsDisclosureWhen, quiet: true),
          _Line(icon: Icons.history_rounded, text: t.riderGpsDisclosureKept, quiet: true),
          const SizedBox(height: DeliverySpacing.lg),
          YdPillButton(
            label: t.riderGpsDisclosureContinue,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: DeliverySpacing.sm),
          YdPillButton.secondary(
            label: t.riderGpsDisclosureNotNow,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}

/// One line of the sheet: a glyph at the reading edge and the sentence beside it.
class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.quiet = false});

  final IconData icon;
  final String text;

  /// The when-and-how-long lines, set a step quieter than the list of who.
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: quiet ? DeliveryColors.muted : DeliveryColors.brand),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: quiet ? 13 : 14,
                fontWeight: quiet ? FontWeight.w400 : FontWeight.w600,
                color: quiet ? DeliveryColors.muted : DeliveryColors.ink,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
