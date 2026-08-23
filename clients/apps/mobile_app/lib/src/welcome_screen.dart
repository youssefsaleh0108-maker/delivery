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
  });

  final VoidCallback onSignIn;
  final VoidCallback onSignUp;
  final VoidCallback onJoinAsPartner;

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

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onSignIn,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DeliveryColors.white,
                    foregroundColor: DeliveryColors.brand,
                    padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.md),
                  ),
                  child: Text(t.signIn,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: DeliverySpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onSignUp,
                  style: OutlinedButton.styleFrom(
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
