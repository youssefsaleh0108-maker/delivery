import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'one_time_code.dart';
import 'role_option_card.dart';

/// Signing in with Google, from the app's side: the question asked before the browser opens, the
/// buttons that ask it, and the screen an account with no role lands on.
///
/// <p><strong>Why the question comes first.</strong> Google creates an account the moment it vouches
/// for somebody, and the realm used to make every one of those accounts a customer. A rider or a shop
/// owner who tapped Google therefore arrived in a basket, with no way to say what they had come for.
/// Asking before the browser opens means the answer travels with the sign-in: a customer is made a
/// customer, and a rider or seller goes straight into their application for the account they just
/// signed in with. See [BrokerSignIn] for what happens to the answer.
///
/// <p>The question is asked in a bottom sheet rather than a screen, because it is a detour on the way
/// to Google rather than a place — dismissing it leaves the person exactly where they were.

/// The three answers, drawn with the Create Account screen's role cards so the two places that ask
/// "how will you use YouDrop" look the same asking it.
class AccountIntentOptions extends StatelessWidget {
  const AccountIntentOptions({
    super.key,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });

  /// Null until somebody picks. Nothing is chosen for them: the answer decides whether they are
  /// reviewed, so it should be one they gave rather than one they failed to change.
  final AccountIntent? selected;
  final ValueChanged<AccountIntent> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    Widget option(AccountIntent intent, IconData icon, String title, String subtitle) =>
        RoleOptionCard(
          icon: icon,
          title: title,
          subtitle: subtitle,
          selected: selected == intent,
          onTap: enabled ? () => onSelected(intent) : null,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        option(AccountIntent.customer, Icons.shopping_bag_outlined,
            t.accountIntentCustomer, t.accountIntentCustomerBlurb),
        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        option(AccountIntent.rider, Icons.two_wheeler_outlined, t.accountIntentRider,
            t.accountIntentRiderBlurb),
        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        option(AccountIntent.seller, Icons.storefront_outlined, t.accountIntentSeller,
            t.accountIntentSellerBlurb),
      ],
    );
  }
}

/// Asks customer, rider or seller in a bottom sheet. Null when it is dismissed without an answer.
///
/// [initial] pre-selects a card — the Create Account screen passes the role card that was already
/// chosen there, so the person confirms rather than answers twice. It is still a confirmation: the
/// sheet is shown every time, because this answer is what decides whether an account is reviewed.
Future<AccountIntent?> showAccountIntentSheet(
  BuildContext context, {
  AccountIntent? initial,
}) {
  return showModalBottomSheet<AccountIntent>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DeliveryColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(DeliveryRadius.sheet)),
    ),
    builder: (BuildContext context) => _AccountIntentSheet(initial: initial),
  );
}

class _AccountIntentSheet extends StatefulWidget {
  const _AccountIntentSheet({this.initial});

  final AccountIntent? initial;

  @override
  State<_AccountIntentSheet> createState() => _AccountIntentSheetState();
}

class _AccountIntentSheetState extends State<_AccountIntentSheet> {
  late AccountIntent? _choice = widget.initial;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final AccountIntent? choice = _choice;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(
            DeliverySpacing.lg, DeliverySpacing.sm, DeliverySpacing.lg, DeliverySpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: DeliveryColors.border,
                  borderRadius: BorderRadius.circular(DeliveryRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: DeliverySpacing.lg),
            Text(
              t.accountIntentSheetTitle,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: DeliveryColors.ink,
                height: 1.2,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t.accountIntentSheetSubtitle,
              style: const TextStyle(
                fontSize: 14,
                color: DeliveryColors.muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: DeliverySpacing.lg),
            AccountIntentOptions(
              selected: choice,
              onSelected: (AccountIntent intent) => setState(() => _choice = intent),
            ),
            const SizedBox(height: DeliverySpacing.lg),
            AuthPrimaryButton(
              label: t.continueWithGoogle,
              onPressed: choice == null ? null : () => Navigator.of(context).pop(choice),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks the question, then hands the answer on. The one place both Google buttons go through, so
/// neither can start a sign-in without it.
Future<void> askThenContinueWithGoogle(
  BuildContext context,
  ValueChanged<AccountIntent> onChosen, {
  AccountIntent? initial,
}) async {
  final AccountIntent? intent = await showAccountIntentSheet(context, initial: initial);
  if (intent != null) onChosen(intent);
}

/// The design's outlined social button (Figma `social-logins` 40:1066): a provider mark and the
/// provider's own name, white on a hairline border.
class SocialAuthButton extends StatelessWidget {
  const SocialAuthButton({
    super.key,
    required this.icon,
    required this.label,
    this.iconColor = DeliveryColors.ink,
    this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final Color iconColor;

  /// A provider's own name — not translated, and so not an l10n string — or a localised sentence
  /// such as "Continue with Google" where the button stands alone.
  final String label;

  /// Null disables it.
  final VoidCallback? onTap;

  /// True while this provider's round trip is in flight: a small spinner where the mark was.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null && !busy,
      child: Material(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          child: Container(
            padding: const EdgeInsetsDirectional.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
              border: Border.all(color: DeliveryColors.borderFaint),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (busy)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: DeliveryColors.brand,
                    ),
                  )
                else
                  Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: DeliverySpacing.sm),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: DeliveryColors.ink,
                      height: 1.2,
                    ),
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

/// The "or continue with" rule between a form and its social buttons.
class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Row(
      children: <Widget>[
        const Expanded(child: Divider(color: DeliveryColors.border, height: 1)),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: DeliverySpacing.sm),
          child: Text(
            t.authOrContinueWith.toLowerCase(),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: DeliveryColors.faint,
              height: 1.2,
            ),
          ),
        ),
        const Expanded(child: Divider(color: DeliveryColors.border, height: 1)),
      ],
    );
  }
}

/// The sign-in screen's social row (Figma `social-logins` 40:1066): the rule, then Google and
/// Apple side by side.
///
/// Google asks customer / rider / seller first and then hands the answer to [onGoogle]; the round
/// trip itself belongs to whoever owns the session. Null [onGoogle] falls back to saying Google is
/// coming soon, as the row did before Google existed, rather than drawing a dead button.
///
/// Apple stays "coming soon". It is not a matter of credentials like Google: Keycloak has no Apple
/// provider and Apple's client secret is a JWT that expires every six months — see
/// `infra/keycloak/SOCIAL-SIGN-IN-SETUP.md`.
class SocialSignInRow extends StatelessWidget {
  const SocialSignInRow({
    super.key,
    required this.enabled,
    this.onGoogle,
    this.googleBusy = false,
  });

  final bool enabled;
  final ValueChanged<AccountIntent>? onGoogle;
  final bool googleBusy;

  void _comingSoon(BuildContext context, String provider) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t.authSocialComingSoon(provider))));
  }

  @override
  Widget build(BuildContext context) {
    final ValueChanged<AccountIntent>? google = onGoogle;
    return Column(
      children: <Widget>[
        const AuthOrDivider(),
        const SizedBox(height: DeliverySpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: SocialAuthButton(
                icon: Icons.g_mobiledata,
                iconColor: DeliveryColors.brand,
                label: 'Google',
                busy: googleBusy,
                onTap: !enabled
                    ? null
                    : google == null
                        ? () => _comingSoon(context, 'Google')
                        : () => askThenContinueWithGoogle(context, google),
              ),
            ),
            const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
            Expanded(
              child: SocialAuthButton(
                icon: Icons.apple,
                iconColor: DeliveryColors.ink,
                label: 'Apple',
                onTap: enabled ? () => _comingSoon(context, 'Apple') : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Where an account that holds no role lands: the same question, asked as a screen.
///
/// Reached when somebody signed in with Google and then backed out of their application, when a
/// role could not be added, or when an account with no role signs in some other way. Before this,
/// such an account fell through the role branch into the customer shell — a shop it had no role to
/// use. Answering here runs the same step the Google sheet leads to, with no browser in between.
class AccountSetupScreen extends StatefulWidget {
  const AccountSetupScreen({
    super.key,
    required this.session,
    required this.onChoose,
    required this.onSignOut,
    this.busy = false,
  });

  final AuthSession session;
  final ValueChanged<AccountIntent> onChoose;
  final VoidCallback onSignOut;

  /// True while the answer is being acted on.
  final bool busy;

  @override
  State<AccountSetupScreen> createState() => _AccountSetupScreenState();
}

class _AccountSetupScreenState extends State<AccountSetupScreen> {
  AccountIntent? _choice;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final AccountIntent? choice = _choice;
    final String who = widget.session.email ?? widget.session.displayName;

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: <Widget>[
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: DeliverySpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SizedBox(height: DeliverySpacing.xl),
                    Text(
                      t.accountSetupTitle,
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
                      t.accountSetupSubtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: DeliveryColors.muted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: DeliverySpacing.md),
                    // Whose account this is, so a shared phone does not set up the wrong person.
                    Row(
                      children: <Widget>[
                        const Icon(Icons.account_circle_outlined,
                            size: 18, color: DeliveryColors.muted),
                        const SizedBox(width: DeliverySpacing.xs),
                        Flexible(
                          child: Text(
                            who,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: DeliveryColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: DeliverySpacing.lg),
                    AccountIntentOptions(
                      selected: choice,
                      enabled: !widget.busy,
                      onSelected: (AccountIntent intent) => setState(() => _choice = intent),
                    ),
                    const SizedBox(height: DeliverySpacing.lg),
                    const Spacer(),
                    AuthPrimaryButton(
                      label: t.continueLabel,
                      busy: widget.busy,
                      onPressed: choice == null || widget.busy
                          ? null
                          : () => widget.onChoose(choice),
                    ),
                    const SizedBox(height: DeliverySpacing.sm),
                    Center(
                      child: TextButton(
                        onPressed: widget.busy ? null : widget.onSignOut,
                        style: TextButton.styleFrom(foregroundColor: DeliveryColors.muted),
                        child: Text(t.signOut),
                      ),
                    ),
                    const SizedBox(height: DeliverySpacing.md),
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
