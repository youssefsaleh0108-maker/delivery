/// The portal's sign-in page: the brand panel, the welcome card and the language toggle.
///
/// Split out of `main.dart` so it can be pumped in a test. `main.dart` imports `package:web`,
/// which only compiles for the web, so nothing that imports it can be loaded by `flutter test` —
/// which left the one page every partner meets before anything else as the one page no test could
/// open. PT-10, three English literals and a customer-app prompt, is what that cost.
library;

import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// The bottom stop of the sign-in panel's gradient.
///
/// Rose-900, and the one value on this screen that no token covers: `DeliveryColors.brandDark` is
/// rose-800 (`#9F1239`), a visibly lighter end than the design draws. Kept local rather than added
/// to `delivery_design_system`, which is being edited elsewhere this wave — it should graduate to a
/// `brandDeep` token the next time that file is opened.
const Color _brandGradientEnd = Color(0xFF881337);

/// Below this the brand panel is dropped and the card takes the whole window.
///
/// 480 of panel plus the design's 120px gutters and a 416 card needs ~1100 before the right-hand
/// column starts eating its own margins.
const double _splitPanelBreakpoint = 1040;

/// The sign-in screen: the design's split panel, with the form replaced by the redirect.
///
/// Figma `carrier-login` (22:1306) — a 480px brand panel down the left, the welcome card on the
/// slate page to its right.
///
/// **The design draws an email and a password field, and this does not.** Authentication is a
/// Keycloak OIDC redirect and stays one: the portal never sees a credential, there is one client
/// and one session for all three consoles, and putting a password box on this page would mean
/// either faking it or moving the platform off SSO. So the right panel carries the design's welcome
/// copy and its primary button, and that button starts the redirect. Everything else on the panel —
/// the geometry, the gradient, the type ramp, the language toggle — is as drawn.
class PortalSignInScreen extends StatelessWidget {
  const PortalSignInScreen({
    super.key,
    required this.onSignIn,
    required this.busy,
    required this.locale,
  });

  final Future<void> Function() onSignIn;
  final bool busy;
  final LocaleController locale;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool split = constraints.maxWidth >= _splitPanelBreakpoint;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (split) const _BrandPanel(),
              Expanded(
                child: _SignInPanel(
                  onSignIn: onSignIn,
                  busy: busy,
                  locale: locale,
                  // Without the brand panel there is nothing else on screen, so the card stops
                  // hugging the design's 120px right-hand gutter and simply centres.
                  centred: !split,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The 480px gradient panel: mark at the top, the promise in the middle, the small print at the
/// bottom.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    // Arabic is cursive: letters in a word are joined, and tracking pulls them apart into
    // something that reads as broken type rather than as emphasis. So the eyebrow's letter
    // spacing is the Latin ramp's, and nothing in Arabic.
    final double? eyebrowTracking =
        Directionality.of(context) == TextDirection.rtl ? null : 1;

    return Container(
      width: 480,
      padding: const EdgeInsets.all(DeliverySpacing.xxl),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[DeliveryColors.brand, _brandGradientEnd],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: DeliveryColors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.inventory_2,
                    size: 20, color: DeliveryColors.brand),
              ),
              const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // The mark, untranslated on purpose: a brand name is a name in both languages.
                  const Text(
                    'YouDrop',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: DeliveryColors.white,
                      height: 1.2,
                    ),
                  ),
                  // Deliberately does not name a role. The same page serves all three consoles, and
                  // telling someone which one they are on before they have signed in is a guess.
                  Text(
                    t.portalBrandEyebrow,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: DeliveryColors.onBrandSoft,
                      letterSpacing: eyebrowTracking,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                t.portalBrandHeadline,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.white,
                  height: 42 / 32,
                ),
              ),
              const SizedBox(height: DeliverySpacing.lg),
              Opacity(
                opacity: 0.8,
                child: Text(
                  t.portalBrandBlurb,
                  style: const TextStyle(
                    fontSize: 16,
                    color: DeliveryColors.onBrandSoft,
                    height: 24 / 16,
                  ),
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Opacity(
                opacity: 0.7,
                child: Text(
                  t.portalBrandAudiences,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: DeliveryColors.onBrandSoft,
                  ),
                ),
              ),
              const SizedBox(height: DeliverySpacing.sm),
              // A company's legal name and the year: the same characters in every locale.
              const Opacity(
                opacity: 0.5,
                child: Text(
                  '© 2026 YouDrop Technologies Inc.',
                  style: TextStyle(fontSize: 12, color: DeliveryColors.onBrandSoft),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The right-hand column: language toggle at the top, the 416px welcome card in the middle.
class _SignInPanel extends StatelessWidget {
  const _SignInPanel({
    required this.onSignIn,
    required this.busy,
    required this.locale,
    required this.centred,
  });

  final Future<void> Function() onSignIn;
  final bool busy;
  final LocaleController locale;
  final bool centred;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: centred ? DeliverySpacing.lg : 120,
        vertical: 64,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(
            // Directional, not physical: the toggle sits at the end of the line, which Arabic
            // reads on the left. Pinning it right left it over the card's first words in Arabic.
            alignment: AlignmentDirectional.centerEnd,
            child: _LanguageToggle(locale: locale),
          ),
          // Scrolls rather than overflows. The design is drawn at 800 tall; a browser window with
          // three toolbars open is shorter than the card, and a clipped sign-in button is a user
          // who cannot sign in.
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 416),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        t.portalSignInWelcome,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: DeliveryColors.ink,
                        ),
                      ),
                      const SizedBox(height: DeliverySpacing.sm),
                      // The portal's own line. It used to borrow the customer app's
                      // `signInPrompt` — "Sign in to see what you ordered before" — which is the
                      // store page's prompt to a shopper and says nothing true about a console.
                      Text(
                        t.portalSignInPrompt,
                        style: const TextStyle(fontSize: 14, color: DeliveryColors.muted),
                      ),
                      const SizedBox(height: DeliverySpacing.xl),
                      // The design's primary button, at the design's weight — it just does the one
                      // thing this screen can do.
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: busy ? null : onSignIn,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DeliveryColors.brand,
                            foregroundColor: DeliveryColors.white,
                            disabledBackgroundColor: DeliveryColors.brandLine,
                            disabledForegroundColor: DeliveryColors.white,
                            elevation: 0,
                            padding: const EdgeInsets.all(14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: Text(busy ? '${t.signIn}…' : t.signIn),
                        ),
                      ),
                      const SizedBox(height: DeliverySpacing.md),
                      // Says where the button goes. The redirect is the architecture, not an
                      // accident, and a button that navigates away from the app should say so.
                      Text(
                        t.portalSignInRedirect,
                        style: const TextStyle(
                            fontSize: 13, color: DeliveryColors.faint, height: 1.5),
                      ),
                      const SizedBox(height: DeliverySpacing.xl),
                      Text(
                        t.portalSignInApply,
                        style: const TextStyle(
                            fontSize: 13, color: DeliveryColors.muted, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The design's bordered `AR / EN` toggle — a real switch, not a label.
class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle({required this.locale});

  final LocaleController locale;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return PopupMenuButton<String>(
      tooltip: t.language,
      position: PopupMenuPosition.under,
      initialValue: locale.isArabic ? 'ar' : 'en',
      onSelected: locale.setLanguage,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'en', child: Text(t.english)),
        PopupMenuItem<String>(value: 'ar', child: Text(t.arabic)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DeliverySpacing.md - DeliverySpacing.xs,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: DeliveryColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.language, size: 16, color: DeliveryColors.muted),
            SizedBox(width: DeliverySpacing.xs),
            Text(
              'AR / EN',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
