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
/// <p>Three doors, ordered by how many people take them. Almost everyone signing in is a returning
/// shopper, so that is the primary button; creating an account is the common second; joining as a
/// partner is rare and deliberately last — it leads to a reviewed application, not an account.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.onSignIn,
    required this.onSignUp,
    required this.onJoinAsPartner,
    this.onGoogle,
    this.busy = false,
  });

  final VoidCallback onSignIn;
  final VoidCallback onSignUp;
  final VoidCallback onJoinAsPartner;

  /// Opens the browser on Google, or null when Google sign-in is not configured.
  ///
  /// Null hides the control entirely rather than disabling it. A greyed-out Google button still
  /// reads as "this should work", and a tester who taps one that cannot work learns nothing except
  /// that the app is broken. It comes back the moment a client id and secret exist — see the
  /// identity provider in infra/keycloak/realm-delivery-platform.json.
  final VoidCallback? onGoogle;

  /// True while the Google round trip is in flight. Only that path can be busy here — the other
  /// buttons just change screens.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      backgroundColor: DeliveryColors.brand,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DeliverySpacing.xl),
          child: Column(
            children: <Widget>[
              const Spacer(flex: 3),

              // The same mark as the splash and the launcher icon, so the three read as one app.
              Container(
                padding: const EdgeInsets.all(DeliverySpacing.lg),
                decoration: const BoxDecoration(
                  color: DeliveryColors.white,
                  borderRadius: BorderRadius.all(Radius.circular(28)),
                ),
                child: const Icon(Icons.shopping_bag,
                    size: 56, color: DeliveryColors.brand),
              ),
              const SizedBox(height: DeliverySpacing.lg),
              Text(
                t.appTitle,
                style: theme.textTheme.displaySmall?.copyWith(
                  color: DeliveryColors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: DeliverySpacing.xs),
              Text(
                t.splashTagline,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: DeliveryColors.white.withValues(alpha: 0.85)),
              ),

              const Spacer(flex: 4),

              // Only when there is somewhere to send them. See [onGoogle].
              if (onGoogle != null) ...<Widget>[
              // An icon, not a full-width button. Google is one way in among several and the
              // passcode is the one most people here will use, so it sits beside the others rather
              // than above them competing with the primary action.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Tooltip(
                    message: t.continueWithGoogle,
                    child: Semantics(
                      button: true,
                      // The label the icon does not carry. Without it a screen reader announces
                      // "button" and nothing else.
                      label: t.continueWithGoogle,
                      child: InkWell(
                        onTap: busy ? null : onGoogle,
                        customBorder: const CircleBorder(),
                        child: Container(
                          height: 56,
                          width: 56,
                          decoration: const BoxDecoration(
                            color: DeliveryColors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: busy
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                // Google's brand guidelines want their own mark here. Until that
                                // asset is in the repo this is a stand-in, not a finished button.
                                : const Icon(Icons.g_mobiledata,
                                    size: 36, color: DeliveryColors.ink),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DeliverySpacing.lg),
              ],

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: busy ? null : onSignIn,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: DeliveryColors.white,
                    side: const BorderSide(color: DeliveryColors.white, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.md),
                  ),
                  child: Text(t.signInWithAPasscode,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: DeliverySpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: busy ? null : onSignUp,
                  style: OutlinedButton.styleFrom(
                    // TRANSPARENT, explicitly. The app theme gives every OutlinedButton a white
                    // background — right on the white screens it was designed for, and invisible
                    // here, where white-on-white made the label disappear entirely. Overriding the
                    // foreground alone is not enough; the background has to be cleared too.
                    backgroundColor: Colors.transparent,
                    foregroundColor: DeliveryColors.white,
                    side: const BorderSide(color: DeliveryColors.white, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.md),
                  ),
                  child: Text(t.createAccount,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),

              const SizedBox(height: DeliverySpacing.lg),

              // Visually separated, because it is a different KIND of thing. The two buttons above
              // end with the person using the app; this one ends with a form somebody reviews.
              Row(
                children: <Widget>[
                  Expanded(child: Divider(color: DeliveryColors.white.withValues(alpha: 0.3))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.sm),
                    child: Text(
                      t.orJoinUs,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: DeliveryColors.white.withValues(alpha: 0.75)),
                    ),
                  ),
                  Expanded(child: Divider(color: DeliveryColors.white.withValues(alpha: 0.3))),
                ],
              ),
              const SizedBox(height: DeliverySpacing.sm),

              TextButton.icon(
                onPressed: onJoinAsPartner,
                icon: const Icon(Icons.storefront_outlined, color: DeliveryColors.white),
                label: Text(
                  t.sellOrDeliverWithUs,
                  style: const TextStyle(color: DeliveryColors.white, fontSize: 15),
                ),
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
