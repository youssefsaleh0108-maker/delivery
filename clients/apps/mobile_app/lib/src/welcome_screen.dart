import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// The first thing a signed-out person sees, and the fork in the road.
///
/// <p>Before this, the app auto-launched the Keycloak browser tab on startup. That is the right
/// flow for somebody who already has an account and the wrong one for everybody else: there was no
/// way to create an account from the app at all, and the first thing a new user saw was a browser
/// showing a raw IP address asking for a password.
///
/// <p>Figma `unified-welcome` (22:8) turns the three doors into three *roles* rather than three
/// verbs. That is a better question to ask first: "which of these are you" has one obvious answer
/// for everybody, where "sign in / create account / join as partner" asked a returning merchant to
/// work out which of the three they were. Customer leads to sign-up, rider and merchant to their
/// own intro; the footer keeps the way back for anyone who already has an account.
///
/// <p>The whole screen is [DeliveryColors.brand], so every colour on it is an on-brand token —
/// the cards are white at 15% inside a white-at-20% hairline, exactly as drawn.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.onSignIn,
    required this.onSignUp,
    required this.onJoinAsPartner,
    this.onJoinAsRider,
    this.onJoinAsMerchant,
    this.onGoogle,
    this.locale,
    this.busy = false,
  });

  final VoidCallback onSignIn;

  /// The Customer card, and the footer's counterpart.
  final VoidCallback onSignUp;

  /// The merchant-or-rider fork. Still the destination for both partner cards until the router
  /// offers [onJoinAsRider] and [onJoinAsMerchant] — the choice screen asks the same question the
  /// card already answered, which is one tap of redundancy rather than a broken path.
  final VoidCallback onJoinAsPartner;

  /// Straight into the rider intro, skipping the fork. Null falls back to [onJoinAsPartner].
  final VoidCallback? onJoinAsRider;

  /// Straight into the merchant intro, skipping the fork. Null falls back to [onJoinAsPartner].
  final VoidCallback? onJoinAsMerchant;

  /// Opens the browser on Google, or null when Google sign-in is not configured.
  ///
  /// Null hides the control entirely rather than disabling it. A greyed-out Google button still
  /// reads as "this should work", and a tester who taps one that cannot work learns nothing except
  /// that the app is broken. It comes back the moment a client id and secret exist — see the
  /// identity provider in infra/keycloak/realm-delivery-platform.json. The redesign moves social
  /// sign-in to the login screen; this stays wired so the broker round trip keeps a way in.
  final VoidCallback? onGoogle;

  /// Drives the design's language pill (22:20). Null hides it — a pill that cannot change the
  /// language is worse than no pill.
  final LocaleController? locale;

  /// True while the Google round trip is in flight. Only that path can be busy here — the other
  /// buttons just change screens.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Scaffold(
      backgroundColor: DeliveryColors.brand,
      body: SafeArea(
        child: CustomScrollView(
          slivers: <Widget>[
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Column(
                    children: <Widget>[
                      if (locale != null)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                            top: 12,
                            start: DeliverySpacing.lg,
                            end: DeliverySpacing.lg,
                          ),
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: _LanguagePill(locale: locale!),
                          ),
                        ),
                      const SizedBox(height: 56),
                      const _BrandHero(),
                      const SizedBox(height: DeliverySpacing.lg),
                    ],
                  ),

                  // The three doors. Ordered as the design orders them: the role almost everybody
                  // arriving here holds, then the two that lead to a reviewed application.
                  Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: DeliverySpacing.lg),
                    child: Column(
                      children: <Widget>[
                        YdRoleCard(
                          icon: Icons.shopping_bag_outlined,
                          title: t.authRoleCustomer,
                          subtitle: t.authRoleCustomerBlurb,
                          onTap: busy ? () {} : onSignUp,
                        ),
                        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                        YdRoleCard(
                          icon: Icons.two_wheeler,
                          title: t.authRoleRider,
                          subtitle: t.authRoleRiderBlurb,
                          onTap: busy ? () {} : (onJoinAsRider ?? onJoinAsPartner),
                        ),
                        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                        YdRoleCard(
                          icon: Icons.storefront,
                          title: t.authRoleMerchant,
                          subtitle: t.authRoleMerchantBlurb,
                          onTap:
                              busy ? () {} : (onJoinAsMerchant ?? onJoinAsPartner),
                        ),
                        if (onGoogle != null) ...<Widget>[
                          const SizedBox(height: DeliverySpacing.md),
                          YdPillButton.onBrand(
                            label: t.continueWithGoogle,
                            icon: Icons.g_mobiledata,
                            busy: busy,
                            onPressed: onGoogle,
                          ),
                        ],
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      top: DeliverySpacing.lg,
                      bottom: 20,
                      start: DeliverySpacing.lg,
                      end: DeliverySpacing.lg,
                    ),
                    child: AuthFooterLinkOnBrand(
                      question: t.authAlreadyHaveAnAccount,
                      action: t.signIn,
                      onTap: busy ? null : onSignIn,
                    ),
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

/// The 100px white ring, the wordmark and the tagline (Figma `brand-hero` 22:24).
///
/// The mark is the same one the splash and the launcher icon carry, so the three read as one app.
class _BrandHero extends StatelessWidget {
  const _BrandHero();

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Column(
      children: <Widget>[
        Container(
          width: 100,
          height: 100,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: DeliveryColors.white,
            shape: BoxShape.circle,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.shopping_bag_outlined,
              size: 48, color: DeliveryColors.brand),
        ),
        const SizedBox(height: DeliverySpacing.md),
        Text(
          t.appTitle,
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w800,
            color: DeliveryColors.white,
            letterSpacing: -1,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          t.authTagline,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: DeliveryColors.onBrandSoft.withValues(alpha: 0.9),
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

/// The translucent language pill in the top corner (Figma `lang-selector` 22:20).
///
/// The design letters it "AR / EN". This shows the language you would be switching *to*, in that
/// language's own name — which is what the two words in the drawn pill are standing in for, and the
/// only version of it that stays true when a third language is added.
class _LanguagePill extends StatelessWidget {
  const _LanguagePill({required this.locale});

  final LocaleController locale;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final String target = isArabic ? t.english : t.arabic;

    return Semantics(
      button: true,
      label: t.language,
      value: target,
      child: Material(
        color: DeliveryColors.onBrandSurface,
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => locale.setLanguage(isArabic ? 'en' : 'ar'),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.language,
                    size: 16, color: DeliveryColors.white),
                const SizedBox(width: DeliverySpacing.xs),
                Text(
                  target,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.white,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The welcome footer's sentence, in the on-brand dialect (Figma 24:22).
///
/// The same shape as the auth screens' footer link, but drawn on the brand fill: a rose-tinted
/// question and a white answer. Kept here rather than parameterising the light one, because the two
/// never appear on the same screen and the colours are the only thing they disagree about.
class AuthFooterLinkOnBrand extends StatelessWidget {
  const AuthFooterLinkOnBrand({
    super.key,
    required this.question,
    required this.action,
    required this.onTap,
  });

  /// Already localised by the caller.
  final String question;

  /// Already localised by the caller.
  final String action;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: DeliverySpacing.xs,
      children: <Widget>[
        Text(
          question,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: DeliveryColors.onBrandSoft.withValues(alpha: 0.9),
            height: 1.3,
          ),
        ),
        Semantics(
          button: true,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(DeliveryRadius.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
              child: Text(
                action,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.white,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
