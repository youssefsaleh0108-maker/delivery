import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'partner_application_screen.dart';

/// The fork between selling and delivering.
///
/// "Sell or deliver with us" used to lead straight into the rider form, so a shop tapping it was
/// asked which delivery company it wanted to ride for. There was no way to apply as a merchant from
/// the app at all — the one thing the label promised first.
///
/// Nothing here needs an account. Both paths run on the open endpoints and create the account only
/// once somebody is approved, which is said on the screen rather than left to be discovered.
class PartnerChoiceScreen extends StatelessWidget {
  const PartnerChoiceScreen({super.key, required this.onChoose, required this.onClose});

  final void Function(PartnerKind kind) onChoose;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.partnerChoiceTitle),
        leading: IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close),
          tooltip: t.cancel,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(DeliverySpacing.lg),
        children: <Widget>[
          Text(t.partnerChoiceIntro, style: theme.textTheme.bodyMedium),
          const SizedBox(height: DeliverySpacing.lg),
          _choice(
            context,
            icon: Icons.storefront_outlined,
            title: t.applyAsMerchant,
            blurb: t.applyAsMerchantBlurb,
            onTap: () => onChoose(PartnerKind.merchant),
          ),
          const SizedBox(height: DeliverySpacing.md),
          _choice(
            context,
            icon: Icons.pedal_bike_outlined,
            title: t.applyAsRider,
            blurb: t.applyAsRiderBlurb,
            onTap: () => onChoose(PartnerKind.rider),
          ),
          const SizedBox(height: DeliverySpacing.lg),
          SoftNote(text: t.guestApplicationExplainer, icon: Icons.person_outline),
        ],
      ),
    );
  }

  Widget _choice(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String blurb,
    required VoidCallback onTap,
  }) {
    final ThemeData theme = Theme.of(context);
    return SoftCard(
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 32, color: DeliveryColors.brand),
          const SizedBox(width: DeliverySpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(blurb, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: DeliveryColors.muted),
        ],
      ),
    );
  }
}
