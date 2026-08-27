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
/// <p>The redesign's welcome screen asks this question with its own rider and merchant cards, so
/// most people never reach this screen any more. It stays because the router can still send
/// somebody here — and because "which of these are you" needs an answer either way — restyled into
/// the same card language the welcome uses, in the light dialect these screens are drawn in.
///
/// Nothing here needs an account. Both paths run on the open endpoints and create the account only
/// once somebody is approved, which is said on the screen rather than left to be discovered.
class PartnerChoiceScreen extends StatelessWidget {
  const PartnerChoiceScreen({
    super.key,
    required this.onChoose,
    required this.onClose,
  });

  final void Function(PartnerKind kind) onChoose;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(
        title: t.partnerChoiceTitle,
        onBack: onClose,
        backSemanticLabel: t.cancel,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(DeliverySpacing.lg),
          children: <Widget>[
            Text(
              t.partnerChoiceIntro,
              style: const TextStyle(
                fontSize: 13,
                color: DeliveryColors.muted,
                height: 18 / 13,
              ),
            ),
            const SizedBox(height: DeliverySpacing.lg),
            _RoleCard(
              icon: Icons.storefront,
              title: t.applyAsMerchant,
              blurb: t.applyAsMerchantBlurb,
              onTap: () => onChoose(PartnerKind.merchant),
            ),
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            _RoleCard(
              icon: Icons.two_wheeler,
              title: t.applyAsRider,
              blurb: t.applyAsRiderBlurb,
              onTap: () => onChoose(PartnerKind.rider),
            ),
            const SizedBox(height: DeliverySpacing.lg),
            SoftNote(
              text: t.guestApplicationExplainer,
              icon: Icons.person_outline,
            ),
          ],
        ),
      ),
    );
  }
}

/// [YdRoleCard]'s light twin: the same 44px tile, Bold 16 title, 13 subtitle and end chevron, on a
/// white surface instead of the brand fill.
///
/// Not a parameter on the shared widget — that one exists precisely because every colour in it is
/// an on-brand token, and threading a palette through it would leave a component that is two
/// components wearing one name.
class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.blurb,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String blurb;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool rtl = Directionality.of(context) == TextDirection.rtl;

    return YdCard(
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: DeliveryColors.brandSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 22, color: DeliveryColors.brand),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: DeliverySpacing.xs),
                Text(
                  blurb,
                  style: const TextStyle(
                    fontSize: 13,
                    color: DeliveryColors.muted,
                    height: 18 / 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Icon(
            rtl ? Icons.chevron_left : Icons.chevron_right,
            size: 20,
            color: DeliveryColors.faint,
          ),
        ],
      ),
    );
  }
}
