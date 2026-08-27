import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'biometric_lock.dart';
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
/// <p><strong>One form, and a keypad behind it.</strong> Figma `customer-login` (22:46) draws a
/// single screen: an address, a password, Sign In. The credential this realm holds is a six-digit
/// passcode, so the drawn password field accepts exactly that — same field, same call, digits
/// only. The keypad the screen used to force everybody through is still here, one tap away and
/// restyled, because it is the only place the fingerprint key can live: [PasscodePad] carries it in
/// the slot under the 7, where a phone lock screen puts it and where a thumb already knows to go.
enum _Step { credentials, passcode }

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.authService,
    required this.onSignedIn,
    required this.onBack,
    required this.onCreateAccount,
  });

  final AuthService authService;
  final ValueChanged<AuthSession> onSignedIn;
  final VoidCallback onBack;
  final VoidCallback onCreateAccount;

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

  @override
  void initState() {
    super.initState();
    _checkFingerprint();
  }

  Future<void> _checkFingerprint() async {
    if (!await _biometrics.isAvailable) return;
    if (!await _biometrics.isEnabledForAnyone()) return;
    final AuthSession? stored = await widget.authService.restore();
    if (!mounted) return;
    setState(() => _fingerprintOffered = stored != null);
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

    final AuthSession? session = await widget.authService.restore();
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

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: <Widget>[
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: DeliverySpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const SizedBox(height: DeliverySpacing.md),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: AuthBackButton(
                            onPressed: _busy ? null : _back,
                            semanticLabel: t.back,
                          ),
                        ),
                        const SizedBox(height: DeliverySpacing.md),
                        const AuthBrandRow(),
                        const SizedBox(height: DeliverySpacing.md),
                        if (_step == _Step.credentials)
                          ..._credentials(t)
                        else
                          ..._keypad(t),
                        if (_error != null) ...<Widget>[
                          const SizedBox(height: DeliverySpacing.md),
                          AuthErrorNote(message: _error!),
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
                    child: AuthFooterLink(
                      question: t.authDontHaveAnAccount,
                      action: t.authSignUp,
                      onTap: _busy ? null : widget.onCreateAccount,
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

  // ------------------------------------------------------------------ the drawn login form

  List<Widget> _credentials(DeliveryStrings t) => <Widget>[
        Text(
          t.welcomeBack,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          t.authSignInSubtitle,
          style: const TextStyle(
            fontSize: 14,
            color: DeliveryColors.muted,
            height: 1.4,
          ),
        ),
        const SizedBox(height: DeliverySpacing.lg),
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
        AuthField(
          label: t.password,
          hint: t.authPasscodeHint,
          controller: _password,
          enabled: !_busy,
          obscure: true,
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
        ),
        const SizedBox(height: DeliverySpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            // The keypad the pad-first flow used to force on everybody, kept as the way to the
            // fingerprint key and to a thumb-sized target.
            Semantics(
              button: true,
              child: InkWell(
                onTap: _busy ? null : _toKeypad,
                borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        _fingerprintOffered ? Icons.fingerprint : Icons.dialpad,
                        size: 16,
                        color: DeliveryColors.brand,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        t.authUseTheKeypad,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: DeliveryColors.brand,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Drawn, and honestly inert: there is no password-reset endpoint on this realm yet, and
            // a link that silently does nothing is worse than one that says so.
            YdComingSoon.wrap(
              label: t.authComingSoon,
              child: Text(
                t.authForgotPassword,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DeliveryColors.brand,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: DeliverySpacing.md + DeliverySpacing.sm),
        AuthPrimaryButton(
          label: t.signIn,
          busy: _busy,
          onPressed: _busy ? null : _submitCredentials,
        ),
        const SizedBox(height: DeliverySpacing.lg),
        _SocialAuth(enabled: !_busy),
      ];

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

/// The divider and the two social buttons (Figma `social-auth` 22:81).
///
/// Both are drawn and neither works: the Google identity provider on this realm has no client id
/// or secret — Google refuses to register a redirect URI on a bare IP over http, which is what this
/// deployment is — and Apple is not configured at all. They are rendered exactly as designed and
/// marked, rather than quietly opening a browser onto a broker that will refuse.
class _SocialAuth extends StatelessWidget {
  const _SocialAuth({required this.enabled});

  final bool enabled;

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
                t.authOrContinueWith.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DeliveryColors.faint,
                  letterSpacing: 0.5,
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
              child: YdComingSoon.wrap(
                label: t.authComingSoon,
                child: const _SocialButton(
                    icon: Icons.g_mobiledata, label: 'Google'),
              ),
            ),
            const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
            Expanded(
              child: YdComingSoon.wrap(
                label: t.authComingSoon,
                child: const _SocialButton(icon: Icons.apple, label: 'Apple'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.icon, required this.label});

  final IconData icon;

  /// A provider's own name — not translated, and so not an l10n string.
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        border: Border.all(color: DeliveryColors.borderFaint),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 18, color: DeliveryColors.ink),
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
    );
  }
}
