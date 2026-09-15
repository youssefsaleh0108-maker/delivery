import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'google_sign_in.dart';
import 'one_time_code.dart';
import 'role_option_card.dart';

/// The first thing a signed-out person sees, and the fork in the road.
///
/// <p>Before this, the app auto-launched the Keycloak browser tab on startup. That is the right
/// flow for somebody who already has an account and the wrong one for everybody else: there was no
/// way to create an account from the app at all, and the first thing a new user saw was a browser
/// showing a raw IP address asking for a password.
///
/// <p>Figma `signup-role-selection` (40:1079) draws this as the account's front door: a light
/// screen headed "Create Account", three roles phrased as intentions — "I want to Order / Deliver /
/// Sell" — and a single Continue. Unlike the earlier crimson welcome, which committed the moment a
/// card was tapped, this one lets a role be chosen and reconsidered before Continue acts on it;
/// Order leads a shopper to sign-up, Deliver and Sell each to their partner intro. The footer keeps
/// the way back for anyone who already has an account.
///
/// <p><strong>Continue with Google</strong> sits under Continue once [WelcomeScreen.onGoogle] is
/// given. It still asks customer / rider / seller in a sheet before any browser opens — that answer
/// decides whether the new account is reviewed, so it is confirmed rather than inferred — but the
/// sheet starts on whichever role card is chosen here, so answering twice costs one tap.
///
/// <p>The screen is [DeliveryColors.background], not brand — the crimson brand moment is the splash
/// before it. So the status bar keeps the app-wide dark glyphs; no per-screen override is needed.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    required this.onSignIn,
    required this.onSignUp,
    required this.onJoinAsPartner,
    this.onBack,
    this.onJoinAsRider,
    this.onJoinAsMerchant,
    this.onJoinAsCarrier,
    this.onGoogle,
    this.busy = false,
  });

  /// Back to Sign In, which this screen is reached from. Null leaves the back control off.
  final VoidCallback? onBack;

  final VoidCallback onSignIn;

  /// The Customer role — "I want to Order" — and the footer's counterpart.
  final VoidCallback onSignUp;

  /// The merchant-or-rider fork. Still the destination for both partner roles until the router
  /// offers [onJoinAsRider] and [onJoinAsMerchant] — the choice screen asks the same question the
  /// card already answered, which is one tap of redundancy rather than a broken path.
  final VoidCallback onJoinAsPartner;

  /// Straight into the rider intro, skipping the fork. Null falls back to [onJoinAsPartner].
  final VoidCallback? onJoinAsRider;

  /// Straight into the merchant intro, skipping the fork. Null falls back to [onJoinAsPartner].
  final VoidCallback? onJoinAsMerchant;

  /// Straight into the carrier wizard's pitch. Null leaves the card off the screen entirely
  /// rather than falling back to the fork: a company card that opened a "rider or merchant?"
  /// question would promise something the path behind it cannot keep.
  final VoidCallback? onJoinAsCarrier;

  /// Starts the Google round trip with the answer to the customer / rider / seller sheet, which
  /// this screen shows first. Null leaves the Google button off the screen.
  final ValueChanged<AccountIntent>? onGoogle;

  /// True while a Google round trip is in flight. The spinner is on the Google button, and the
  /// rest of the screen holds still until it comes back.
  final bool busy;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  /// The chosen role, acted on by Continue. Order is the default: it is the role almost everybody
  /// arriving here holds, and the design draws it selected and badged Popular.
  int _selected = 0;

  /// The card chosen here, as the Google sheet's starting answer. The carrier card has no Google
  /// answer — a delivery company applies through its own wizard — so it starts the sheet blank.
  AccountIntent? get _selectedIntent => switch (_selected) {
        0 => AccountIntent.customer,
        1 => AccountIntent.rider,
        2 => AccountIntent.seller,
        _ => null,
      };

  void _continue() {
    if (widget.busy) return;
    switch (_selected) {
      case 0:
        widget.onSignUp();
      case 1:
        (widget.onJoinAsRider ?? widget.onJoinAsPartner)();
      case 2:
        (widget.onJoinAsMerchant ?? widget.onJoinAsPartner)();
      case 3:
        widget.onJoinAsCarrier?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final ValueChanged<AccountIntent>? onGoogle = widget.onGoogle;

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: <Widget>[
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: DeliverySpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SizedBox(height: DeliverySpacing.sm),
                    // The header: the flow's title centred, with the back to Sign In at the start.
                    // This screen is reached from Sign In, so it carries the way back.
                    SizedBox(
                      height: 40,
                      child: Stack(
                        children: <Widget>[
                          Center(
                            child: Text(
                              t.createAccount,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: DeliveryColors.ink,
                                height: 1.2,
                              ),
                            ),
                          ),
                          if (widget.onBack != null)
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: AuthBackButton(
                                onPressed: widget.busy ? null : widget.onBack,
                                semanticLabel: t.back,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: AuthFooterLink(
                        question: t.authAlreadyHaveAnAccount,
                        action: t.authLogIn,
                        onTap: widget.busy ? null : widget.onSignIn,
                      ),
                    ),
                    const SizedBox(height: DeliverySpacing.xl),
                    Text(
                      t.authJoinYoudrop,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: DeliveryColors.ink,
                        height: 1.2,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t.authChooseHowToUse,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: DeliveryColors.muted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: DeliverySpacing.lg),
                    RoleOptionCard(
                      icon: Icons.shopping_bag_outlined,
                      title: t.authRoleWantOrder,
                      subtitle: t.authRoleWantOrderBlurb,
                      selected: _selected == 0,
                      popular: true,
                      onTap: () => setState(() => _selected = 0),
                    ),
                    const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                    RoleOptionCard(
                      icon: Icons.two_wheeler_outlined,
                      title: t.authRoleWantDeliver,
                      subtitle: t.authRoleWantDeliverBlurb,
                      selected: _selected == 1,
                      onTap: () => setState(() => _selected = 1),
                    ),
                    const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                    RoleOptionCard(
                      icon: Icons.storefront_outlined,
                      title: t.authRoleWantSell,
                      subtitle: t.authRoleWantSellBlurb,
                      selected: _selected == 2,
                      onTap: () => setState(() => _selected = 2),
                    ),
                    if (widget.onJoinAsCarrier != null) ...<Widget>[
                      const SizedBox(
                          height: DeliverySpacing.md - DeliverySpacing.xs),
                      RoleOptionCard(
                        icon: Icons.local_shipping_outlined,
                        title: t.carrChoiceCard,
                        subtitle: t.carrChoiceCardBlurb,
                        selected: _selected == 3,
                        onTap: () => setState(() => _selected = 3),
                      ),
                    ],
                    const SizedBox(height: DeliverySpacing.lg),
                    const Spacer(),
                    AuthPrimaryButton(
                      label: t.continueLabel,
                      onPressed: widget.busy ? null : _continue,
                    ),
                    if (onGoogle != null) ...<Widget>[
                      const SizedBox(height: DeliverySpacing.md),
                      const AuthOrDivider(),
                      const SizedBox(height: DeliverySpacing.md),
                      SocialAuthButton(
                        icon: Icons.g_mobiledata,
                        iconColor: DeliveryColors.brand,
                        label: t.continueWithGoogle,
                        busy: widget.busy,
                        onTap: () => askThenContinueWithGoogle(context, onGoogle,
                            initial: _selectedIntent),
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
