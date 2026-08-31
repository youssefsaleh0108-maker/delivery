import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'biometric_lock.dart';
import 'forgot_password_screen.dart';
import 'one_time_code.dart';
import 'passcode_pad.dart';

/// Signing in without leaving the app: who you are, and your passcode.
///
/// <p>This replaces the Chrome custom tab. Android will not let an app hide the address bar in one
/// — a deliberate anti-phishing measure — so every sign-in used to open a browser showing a bare IP
/// address, which is exactly what a phishing page looks like.
///
/// <p><strong>What that costs.</strong> The credential is typed into this app rather than into a
/// page served by Keycloak, so the app is trusted with it. That rules out SSO and a second factor,
/// and the OAuth spec discourages it for third-party clients. It is defensible here because this is
/// the platform's own first-party app against its own realm — see
/// [AuthService.signInWithPassword].
///
/// <p><strong>One form, and a keypad behind it.</strong> Figma `sign-in` (40:1026) draws a single
/// screen: the brand lockup, an email-or-phone address, a password, Log In. The credential this
/// realm holds is a six-digit passcode, so the drawn password field accepts exactly that — same
/// field, same call, digits only. The keypad the screen used to force everybody through is still
/// here, one tap away in the field's suffix, because it is the only place the fingerprint key can
/// live: [PasscodePad] carries it in the slot under the 7, where a phone lock screen puts it and
/// where a thumb already knows to go.
enum _Step { credentials, passcode }

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.authService,
    required this.onSignedIn,
    required this.onBack,
    required this.onCreateAccount,
    this.locale,
    this.passwordResetApi,
  });

  final AuthService authService;
  final ValueChanged<AuthSession> onSignedIn;
  final VoidCallback onBack;
  final VoidCallback onCreateAccount;

  /// Drives the AR/EN pill on this screen. It is the signed-out landing now, so the language
  /// control lives here — a person who cannot read it has to be able to change it from here, before
  /// they are past the first screen. Null hides the pill.
  final LocaleController? locale;

  /// The forgotten-passcode client behind the "Forgot password?" link.
  ///
  /// Optional, and — unusually for this codebase — a null here does NOT turn the feature off. The
  /// reset endpoints are open by design, so [ForgotPasswordScreen] builds its own client against
  /// the same `API_BASE_URL` define when none is passed. This exists so a caller that already has
  /// a wired Dio can share it, and so a test can inject one.
  final PasswordResetApi? passwordResetApi;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final BiometricLock _biometrics = BiometricLock();

  /// Whether the fingerprint key is offered on the pad.
  ///
  /// Three things have to hold: the phone can do it, somebody enabled it here, and there is a
  /// session on this device to unlock. Without the last one there is nothing a fingerprint could
  /// produce — it proves who is holding the phone, it does not fetch a token from the server.
  bool _fingerprintOffered = false;

  /// The stashed identity a fingerprint could sign back in AFTER a sign-out, or null when the
  /// offer comes from a still-live session (or there is no offer at all).
  BiometricCandidate? _candidate;

  /// The name on the "Continue as" card, whichever path put it there.
  String? _bioName;

  @override
  void initState() {
    super.initState();
    _checkFingerprint();
    _prefillLastLogin();
  }

  /// The identifier typed at the last successful sign-in — a returning user types only their
  /// passcode. A convenience, not a secret, so it survives sign-out on purpose.
  Future<void> _prefillLastLogin() async {
    final String? last = await widget.authService.lastLogin();
    if (!mounted || last == null || last.isEmpty) return;
    if (_username.text.trim().isEmpty) {
      setState(() => _username.text = last);
    }
  }

  Future<void> _checkFingerprint() async {
    if (!await _biometrics.isAvailable) return;
    // A still-live session first — the pre-sign-out case this screen always handled.
    if (await _biometrics.isEnabledForAnyone()) {
      final AuthSession? stored = await widget.authService.restore();
      if (!mounted) return;
      if (stored != null) {
        setState(() {
          _fingerprintOffered = true;
          _bioName = stored.displayName;
        });
        return;
      }
    }
    // Then the stash: the identity kept through a sign-out because its owner turned the
    // fingerprint toggle on. Offered only while that toggle still holds.
    final BiometricCandidate? candidate =
        await widget.authService.biometricCandidate();
    if (candidate == null || !mounted) return;
    if (!await _biometrics.isEnabledFor(candidate.subject)) {
      // The toggle went off since the stash was made; the stash goes with it.
      await widget.authService.clearBiometricStash();
      return;
    }
    if (!mounted) return;
    setState(() {
      _fingerprintOffered = true;
      _candidate = candidate;
      _bioName = candidate.displayName;
      if (_username.text.trim().isEmpty && candidate.username.isNotEmpty) {
        _username.text = candidate.username;
      }
    });
  }

  /// The "Not you?" link: forget the stashed identity and sign in plainly.
  Future<void> _forgetCandidate() async {
    await widget.authService.clearBiometricStash();
    if (!mounted) return;
    setState(() {
      _fingerprintOffered = _candidate == null && _fingerprintOffered;
      _candidate = null;
      _bioName = null;
      _username.clear();
    });
  }

  /// Unlocks the stored session instead of typing the passcode.
  Future<void> _useFingerprint() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });

    final BiometricResult result =
        await _biometrics.authenticate(t.unlockWithFingerprint);
    if (!mounted) return;

    if (result != BiometricResult.ok) {
      setState(() {
        _busy = false;
        _error = result == BiometricResult.unavailable
            ? t.fingerprintNotSetUp
            : t.couldNotVerifyYou;
      });
      return;
    }

    // Two doors behind the same fingerprint: a still-live session restores; a stashed one — kept
    // through sign-out by the owner's own toggle — redeems as an ordinary refresh grant.
    AuthSession? session;
    if (_candidate != null) {
      try {
        session = await widget.authService.redeemBiometricStash();
      } catch (_) {
        // Revoked, expired, or the realm was rebuilt. The stash is already cleared; the passcode
        // is the way in, and the message says so rather than blaming the finger.
        if (!mounted) return;
        setState(() {
          _busy = false;
          _fingerprintOffered = false;
          _candidate = null;
          _bioName = null;
          _error = t.custBioExpired;
        });
        return;
      }
    } else {
      session = await widget.authService.restore();
    }
    if (!mounted) return;
    if (session == null) {
      // The session went away between offering the key and pressing it — a sign-out elsewhere, or
      // a refresh token the server rejected. The passcode is still the way in.
      setState(() {
        _busy = false;
        _fingerprintOffered = false;
        _error = t.couldNotVerifyYou;
      });
      return;
    }
    widget.onSignedIn(session);
  }

  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();

  _Step _step = _Step.credentials;
  String _passcode = '';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _hasUsername => _username.text.trim().isNotEmpty;

  /// Moves to the keypad, which needs the address committed first so it can name who is signing in
  /// — that is what catches a wrong-account mistake before six digits are refused.
  void _toKeypad() {
    if (!_hasUsername) {
      setState(() => _error = DeliveryStrings.of(context).requiredField);
      return;
    }
    setState(() {
      _error = null;
      _passcode = '';
      _step = _Step.passcode;
    });
  }

  void _submitCredentials() {
    if (!_hasUsername) {
      setState(() => _error = DeliveryStrings.of(context).requiredField);
      return;
    }
    if (_password.text.length != PasscodePad.passcodeLength) {
      setState(() =>
          _error = DeliveryStrings.of(context).passcodeMustBeSixDigits);
      return;
    }
    _submit(_password.text);
  }

  Future<void> _submit(String passcode) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final AuthSession session =
          await widget.authService.signInWithPassword(_username.text, passcode);
      // The identifier that just worked, kept so next time only the passcode is typed.
      await widget.authService.rememberLastLogin(_username.text.trim());
      if (!mounted) return;
      widget.onSignedIn(session);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
        // Cleared, so the next attempt starts from empty dots. Leaving six filled circles under an
        // error reads as "that is still there" and the pad refuses further digits.
        _passcode = '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // Not the credential — saying "wrong passcode" here sends somebody to reset one that is
        // perfectly correct.
        _error = DeliveryStrings.of(context).couldNotReachTheServer;
        _passcode = '';
      });
    }
  }

  /// Opens the reset flow and, when it succeeds, leaves the person on the credentials step with
  /// their address still filled in and the passcode field cleared — the passcode they had in mind
  /// is not the one that works any more.
  Future<void> _openPasswordReset() async {
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ForgotPasswordScreen(
          api: widget.passwordResetApi,
          initialEmail: _username.text.trim(),
        ),
      ),
    );
    if (!mounted || changed != true) return;
    setState(() {
      _step = _Step.credentials;
      _password.clear();
      _passcode = '';
      _error = null;
    });
  }

  void _back() {
    if (_step == _Step.credentials) {
      widget.onBack();
    } else {
      setState(() {
        _step = _Step.credentials;
        _passcode = '';
        _error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool onCredentials = _step == _Step.credentials;

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
                    const SizedBox(height: DeliverySpacing.md),
                    // The design's sign-in has no back control: it is the root of the auth flow, and
                    // the "Sign Up" link below is the way across to the other side. The keypad is a
                    // step pushed on top of the form, so that one keeps a back arrow to return to it.
                    if (!onCredentials)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: AuthBackButton(
                          onPressed: _busy ? null : _back,
                          semanticLabel: t.back,
                        ),
                      ),
                    if (onCredentials)
                      ..._credentials(t)
                    else
                      ..._keypad(t),
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: DeliverySpacing.md),
                      AuthErrorNote(message: _error!),
                    ],
                    if (onCredentials) ...<Widget>[
                      // The frame floats the footer at the bottom of the screen, well clear of the
                      // social row — the spacer is that gap.
                      const SizedBox(height: DeliverySpacing.lg),
                      const Spacer(),
                      AuthFooterLink(
                        question: t.authDontHaveAnAccount,
                        action: t.authSignUp,
                        onTap: _busy ? null : widget.onCreateAccount,
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

  // ------------------------------------------------------------------ the drawn login form

  List<Widget> _credentials(DeliveryStrings t) => <Widget>[
        // Not in the frame, and kept anyway: this is the signed-out landing, and the pill is the
        // one road to Arabic before anybody can read a settings screen.
        if (widget.locale != null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: _LanguagePill(locale: widget.locale!),
          ),
        const SizedBox(height: DeliverySpacing.sm),
        const _BrandLockup(),
        const SizedBox(height: DeliverySpacing.xl),
        // The remembered face: one fingerprint back in, or "not you" to sign in plainly. Only
        // drawn when there is genuinely a session behind it — see _checkFingerprint.
        if (_fingerprintOffered && _bioName != null) ...<Widget>[
          Semantics(
            button: true,
            label: t.custContinueAs(_bioName!),
            child: Material(
              color: DeliveryColors.white,
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
              child: InkWell(
                borderRadius: BorderRadius.circular(DeliveryRadius.md),
                onTap: _busy ? null : _useFingerprint,
                child: Container(
                  padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
                  decoration: BoxDecoration(
                    border: Border.all(color: DeliveryColors.brand, width: 1.2),
                    borderRadius: BorderRadius.circular(DeliveryRadius.md),
                  ),
                  child: Row(
                    children: <Widget>[
                      StoreMonogram(name: _bioName!, size: 40, radius: 20),
                      const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
                      Expanded(
                        child: Text(
                          t.custContinueAs(_bioName!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: DeliveryColors.ink,
                            height: 1.25,
                          ),
                        ),
                      ),
                      const Icon(Icons.fingerprint,
                          size: 26, color: DeliveryColors.brand),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_candidate != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: _busy ? null : _forgetCandidate,
                child: Text(
                  t.custNotYou,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.muted,
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: DeliverySpacing.sm),
          const SizedBox(height: DeliverySpacing.sm),
        ],
        AuthField(
          label: t.authEmailOrPhone,
          hint: t.authEmailOrPhoneHint,
          controller: _username,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.username],
          // No autocorrect and no capitals: both mangle a username, and the resulting failure looks
          // like a wrong passcode rather than a keyboard being helpful.
          textCapitalization: TextCapitalization.none,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: DeliverySpacing.md),
        _passwordField(t),
        const SizedBox(height: DeliverySpacing.lg),
        AuthPrimaryButton(
          label: t.authLogIn,
          busy: _busy,
          onPressed: _busy ? null : _submitCredentials,
        ),
        const SizedBox(height: DeliverySpacing.lg),
        _SocialAuth(enabled: !_busy),
      ];

  /// The design's password group (Figma `password-input-group` 40:1054): the label with "Forgot?"
  /// pulled to the end of its row, then the obscured six-digit field.
  ///
  /// The drawn field carries no suffix, but the flow has two things the design does not show and
  /// still needs a home for — the fingerprint key, when there is a stored session to unlock, and
  /// the keypad otherwise, for a thumb that would rather not use the OS keyboard. Both live in the
  /// suffix slot, one at a time: fingerprint when it is on offer, the keypad when it is not.
  Widget _passwordField(DeliveryStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            AuthFieldLabel(label: t.password),
            const Spacer(),
            // Live: the onboarding service's open password-reset pair. Carries whatever is already in
            // the address field so somebody who typed their email and then could not remember their
            // passcode does not type it a second time.
            Semantics(
              button: true,
              child: InkWell(
                onTap: _busy ? null : _openPasswordReset,
                borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Text(
                    t.authForgotShort,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: DeliveryColors.brand,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _password,
          enabled: !_busy,
          obscureText: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autofillHints: const <String>[AutofillHints.password],
          // The realm's credential is six digits. Filtering here is what keeps a vendor keyboard's
          // comma or minus sign out of a field that would otherwise fail as a wrong passcode.
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(PasscodePad.passcodeLength),
          ],
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submitCredentials(),
          style: const TextStyle(
            fontSize: 14,
            color: DeliveryColors.ink,
            height: 1.3,
          ),
          decoration: InputDecoration(
            hintText: t.authPasscodeHint,
            isDense: true,
            contentPadding: const EdgeInsetsDirectional.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            suffixIcon: Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Semantics(
                button: true,
                label: _fingerprintOffered
                    ? t.unlockWithFingerprint
                    : t.authUseTheKeypad,
                child: InkResponse(
                  onTap: _busy
                      ? null
                      : (_fingerprintOffered ? _useFingerprint : _toKeypad),
                  radius: 20,
                  child: Icon(
                    _fingerprintOffered ? Icons.fingerprint : Icons.dialpad,
                    size: 20,
                    color: _fingerprintOffered
                        ? DeliveryColors.brand
                        : DeliveryColors.faint,
                  ),
                ),
              ),
            ),
            suffixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
              borderSide: const BorderSide(color: DeliveryColors.borderFaint),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
              borderSide: const BorderSide(color: DeliveryColors.borderFaint),
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ the keypad behind it

  List<Widget> _keypad(DeliveryStrings t) => <Widget>[
        Text(
          t.enterYourPasscode,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 6),
        // Naming the account here is what catches "I typed the wrong address" before six digits
        // have been entered and refused.
        Text(
          _username.text.trim(),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: DeliveryColors.muted,
            height: 1.4,
          ),
        ),
        const SizedBox(height: DeliverySpacing.lg),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: DeliverySpacing.xl),
            child: Center(
                child: CircularProgressIndicator(color: DeliveryColors.brand)),
          )
        else
          PasscodePad(
            value: _passcode,
            enabled: !_busy,
            onChanged: (String v) => setState(() => _passcode = v),
            onCompleted: () => _submit(_passcode),
            onFingerprint:
                _fingerprintOffered && !_busy ? _useFingerprint : null,
          ),
      ];
}

/// The small brand lockup at the head of the auth screens (Figma 22:58): a 28px brand tile at
/// [DeliveryRadius.sm] carrying the 16px mark, then the wordmark in Bold 18.
class AuthBrandRow extends StatelessWidget {
  const AuthBrandRow({super.key});

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: DeliveryColors.brand,
            borderRadius: BorderRadius.circular(DeliveryRadius.sm),
          ),
          child: const Icon(Icons.shopping_bag_outlined,
              size: 16, color: DeliveryColors.white),
        ),
        const SizedBox(width: DeliverySpacing.sm),
        Text(
          t.appTitle,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

/// The brand lockup at the head of the sign-in (Figma `logo-wrapper` 40:1037): the pin-drop badge
/// beside the two-tone wordmark, one centred row, nothing under it. The updated frame dropped the
/// tagline and the welcome copy — the form itself is the greeting now.
///
/// The badge is the design's own export (`logo-mark` 69:29, at 4x). The wordmark is split — ink
/// "You", brand "Drop" — the way the design draws it; a fixed product name, not a localised
/// string, so the two halves are literals here.
class _BrandLockup extends StatelessWidget {
  const _BrandLockup();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Image.asset(
          'assets/illustrations/brand_mark.png',
          width: 40,
          height: 40,
        ),
        const SizedBox(width: 8),
        const Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: 'You',
                style: TextStyle(color: DeliveryColors.ink),
              ),
              TextSpan(
                text: 'Drop',
                style: TextStyle(color: DeliveryColors.brand),
              ),
            ],
          ),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            height: 1.0,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}

/// The divider and the two social buttons (Figma `social-logins` 40:1066).
///
/// Neither provider works: the Google identity provider on this realm has no client id or secret —
/// Google refuses to register a redirect URI on a bare IP over http, which is what this deployment
/// is — and Apple is not configured at all. The updated design drops the "Soon" chip and draws them
/// as plain buttons, so that is what is rendered; a tap says so in a snackbar rather than quietly
/// opening a browser onto a broker that will refuse.
class _SocialAuth extends StatelessWidget {
  const _SocialAuth({required this.enabled});

  final bool enabled;

  void _comingSoon(BuildContext context, String provider) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(t.authSocialComingSoon(provider))));
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(child: Divider(color: DeliveryColors.border, height: 1)),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: DeliverySpacing.sm),
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
        ),
        const SizedBox(height: DeliverySpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: _SocialButton(
                icon: Icons.g_mobiledata,
                iconColor: DeliveryColors.brand,
                label: 'Google',
                onTap: enabled ? () => _comingSoon(context, 'Google') : null,
              ),
            ),
            const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
            Expanded(
              child: _SocialButton(
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

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.icon,
    required this.label,
    this.iconColor = DeliveryColors.ink,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;

  /// A provider's own name — not translated, and so not an l10n string.
  final String label;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DeliveryColors.white,
      borderRadius: BorderRadius.circular(DeliveryRadius.md),
      child: InkWell(
        onTap: onTap,
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
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: DeliverySpacing.sm),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: DeliveryColors.ink,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The AR/EN language pill in the sign-in header corner.
///
/// Shows the language you would be switching *to*, in that language's own name — the honest label
/// when a third language is added. A bordered white pill with ink lettering, for the light screen.
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
        color: DeliveryColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.pill),
          side: const BorderSide(color: DeliveryColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => locale.setLanguage(isArabic ? 'en' : 'ar'),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.language, size: 16, color: DeliveryColors.muted),
                const SizedBox(width: DeliverySpacing.xs),
                Text(
                  target,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.ink,
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
