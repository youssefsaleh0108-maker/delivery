import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'one_time_code.dart';

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

  /// Opens the browser on Google, or null when Google sign-in is not configured. The redesign moves
  /// social sign-in onto the login screen, so this screen no longer draws a Google button; the hook
  /// stays on the widget so the broker round trip has somewhere to return to when it is restored.
  final VoidCallback? onGoogle;

  /// True while a Google round trip is in flight. The role buttons just change screens.
  final bool busy;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  /// The chosen role, acted on by Continue. Order is the default: it is the role almost everybody
  /// arriving here holds, and the design draws it selected and badged Popular.
  int _selected = 0;

  void _continue() {
    if (widget.busy) return;
    switch (_selected) {
      case 0:
        widget.onSignUp();
      case 1:
        (widget.onJoinAsRider ?? widget.onJoinAsPartner)();
      case 2:
        (widget.onJoinAsMerchant ?? widget.onJoinAsPartner)();
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

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
                    _RoleOption(
                      icon: Icons.shopping_bag_outlined,
                      title: t.authRoleWantOrder,
                      subtitle: t.authRoleWantOrderBlurb,
                      selected: _selected == 0,
                      popular: true,
                      onTap: () => setState(() => _selected = 0),
                    ),
                    const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                    _RoleOption(
                      icon: Icons.two_wheeler_outlined,
                      title: t.authRoleWantDeliver,
                      subtitle: t.authRoleWantDeliverBlurb,
                      selected: _selected == 1,
                      onTap: () => setState(() => _selected = 1),
                    ),
                    const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                    _RoleOption(
                      icon: Icons.storefront_outlined,
                      title: t.authRoleWantSell,
                      subtitle: t.authRoleWantSellBlurb,
                      selected: _selected == 2,
                      onTap: () => setState(() => _selected = 2),
                    ),
                    const SizedBox(height: DeliverySpacing.lg),
                    const Spacer(),
                    AuthPrimaryButton(
                      label: t.continueLabel,
                      busy: widget.busy,
                      onPressed: widget.busy ? null : _continue,
                    ),
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

/// One selectable role (Figma `role-card-order` 40:1096 and its deliver / sell twins).
///
/// A white card that takes a brand outline and a brand-tinted icon tile when it is the chosen one,
/// so the selection reads at a glance without a separate radio. The Popular pill is drawn only on
/// the role the design badges.
class _RoleOption extends StatelessWidget {
  const _RoleOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.popular = false,
  });

  final IconData icon;

  /// Already localised by the caller.
  final String title;

  /// Already localised by the caller.
  final String subtitle;

  final bool selected;
  final bool popular;
  final VoidCallback onTap;

  static const double _radius = 16;

  @override
  Widget build(BuildContext context) {
    final BorderRadius corners = BorderRadius.circular(_radius);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: DeliveryColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: corners,
          side: BorderSide(
            color: selected ? DeliveryColors.brand : DeliveryColors.borderFaint,
            width: selected ? 2 : 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(DeliverySpacing.md),
            child: Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? DeliveryColors.brandSoft
                        : DeliveryColors.borderFaint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 24,
                    color:
                        selected ? DeliveryColors.brand : DeliveryColors.muted,
                  ),
                ),
                const SizedBox(width: DeliverySpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: DeliveryColors.ink,
                                height: 1.2,
                              ),
                            ),
                          ),
                          if (popular) ...<Widget>[
                            const SizedBox(width: DeliverySpacing.sm),
                            const _PopularBadge(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
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
            ),
          ),
        ),
      ),
    );
  }
}

/// The brand-tinted "Popular" pill on the first role (Figma `badge` 63:40).
class _PopularBadge extends StatelessWidget {
  const _PopularBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: DeliveryColors.brandSoft,
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
      ),
      child: Text(
        DeliveryStrings.of(context).authRolePopular.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: DeliveryColors.brand,
          letterSpacing: 0.5,
          height: 1.1,
        ),
      ),
    );
  }
}
