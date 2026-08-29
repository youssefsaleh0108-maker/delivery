import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'one_time_code.dart';
import 'partner_application_screen.dart' show PartnerKind;

/// The intro a would-be partner sees before the application form (Figma `rider-signup-intro`
/// 40:1180 and `merchant-signup-intro` 40:1226).
///
/// One screen, two kinds: the illustration, the headline, the three selling points and the call to
/// action all come from [kind], because the two frames are the same layout with a rider's copy or a
/// merchant's. It sells the role, then Continue hands off to [PartnerApplicationScreen]; the header
/// keeps a way back to the role screen and a "Log In" for somebody who already has an account.
class PartnerIntroScreen extends StatelessWidget {
  const PartnerIntroScreen({
    super.key,
    required this.kind,
    required this.onContinue,
    required this.onBack,
    required this.onLogIn,
  });

  final PartnerKind kind;

  /// On to the application form for this [kind].
  final VoidCallback onContinue;

  /// Back to the role screen (or the fork) this was reached through.
  final VoidCallback onBack;

  /// For a partner who already has an account.
  final VoidCallback onLogIn;

  bool get _isRider => kind == PartnerKind.rider;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    final String asset = _isRider
        ? 'assets/illustrations/rider_intro.png'
        : 'assets/illustrations/merchant_intro.png';
    final String header = _isRider ? t.riderIntroHeader : t.merchantIntroHeader;
    final String loginQuestion =
        _isRider ? t.authAlreadyHaveAnAccount : t.merchantIntroHeaderLogin;
    final String title = _isRider ? t.riderIntroTitle : t.merchantIntroTitle;
    final String subtitle =
        _isRider ? t.riderIntroSubtitle : t.merchantIntroSubtitle;
    final String cta = _isRider ? t.applyToDeliver : t.registerStoreNow;

    final List<(String, String)> points = _isRider
        ? <(String, String)>[
            (t.riderPerk1Title, t.riderPerk1Body),
            (t.riderPerk2Title, t.riderPerk2Body),
            (t.riderPerk3Title, t.riderPerk3Body),
          ]
        : <(String, String)>[
            (t.merchantBenefit1Title, t.merchantBenefit1Body),
            (t.merchantBenefit2Title, t.merchantBenefit2Body),
            (t.merchantBenefit3Title, t.merchantBenefit3Body),
          ];

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: <Widget>[
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(height: DeliverySpacing.sm),
                  // Header: back at the start, the role's own label at the end.
                  Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: DeliverySpacing.lg),
                    child: Row(
                      children: <Widget>[
                        AuthBackButton(onPressed: onBack, semanticLabel: t.back),
                        const Spacer(),
                        Text(
                          header,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: DeliveryColors.brand,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: AuthFooterLink(
                      question: loginQuestion,
                      action: t.authLogIn,
                      onTap: onLogIn,
                    ),
                  ),
                  const SizedBox(height: DeliverySpacing.md),
                  // The illustration, a rounded banner inset from the edges.
                  Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: DeliverySpacing.lg),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(DeliveryRadius.lg),
                      child: Image.asset(
                        asset,
                        height: 190,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: DeliverySpacing.lg),
                  Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: DeliverySpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: DeliveryColors.ink,
                            height: 1.2,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 14,
                            color: DeliveryColors.muted,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: DeliverySpacing.lg),
                        for (final (String, String) p in points) ...<Widget>[
                          _Point(title: p.$1, body: p.$2, rider: _isRider),
                          const SizedBox(height: DeliverySpacing.md),
                        ],
                      ],
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: DeliverySpacing.lg,
                      end: DeliverySpacing.lg,
                      bottom: 20,
                    ),
                    child: AuthPrimaryButton(label: cta, onPressed: onContinue),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One selling point: a marker glyph, then a bold line and a muted one.
///
/// The marker is the design's — a brand star on the rider frame, a positive-green check on the
/// merchant one — because the two frames mark their lists differently.
class _Point extends StatelessWidget {
  const _Point({required this.title, required this.body, required this.rider});

  final String title;
  final String body;
  final bool rider;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          rider ? Icons.star_rounded : Icons.check_circle,
          size: 22,
          color: rider ? DeliveryColors.brand : DeliveryAccent.positive.color,
        ),
        const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.ink,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 13,
                  color: DeliveryColors.muted,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
