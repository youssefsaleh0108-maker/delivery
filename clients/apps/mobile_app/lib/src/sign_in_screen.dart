import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'biometric_lock.dart';
import 'passcode_pad.dart';

/// Signing in without leaving the app: who you are, then your passcode.
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
/// <p><strong>Two screens, not one form.</strong> The passcode pad needs the whole width, and
/// showing it under a username field means a cramped keypad or a scrolling login. Splitting them
/// also means the username is committed before the pad appears, so the pad can name who is signing
/// in — which is what makes a wrong-account mistake visible before six digits are entered.
enum _Step { username, passcode }

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

    final BiometricResult result = await _biometrics.authenticate(t.unlockWithFingerprint);
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

  _Step _step = _Step.username;
  String _passcode = '';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  void _continue() {
    if (_username.text.trim().isEmpty) {
      setState(() => _error = DeliveryStrings.of(context).requiredField);
      return;
    }
    setState(() {
      _error = null;
      _step = _Step.passcode;
    });
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final AuthSession session = await widget.authService
          .signInWithPassword(_username.text, _passcode);
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

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: _busy
              ? null
              : () {
                  if (_step == _Step.username) {
                    widget.onBack();
                  } else {
                    setState(() {
                      _step = _Step.username;
                      _passcode = '';
                      _error = null;
                    });
                  }
                },
        ),
        title: Text(t.signIn),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(DeliverySpacing.xl),
          child: _step == _Step.username ? _usernameStep(t) : _passcodeStep(t),
        ),
      ),
    );
  }

  Widget _usernameStep(DeliveryStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(t.welcomeBack, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: DeliverySpacing.xs),
        Text(t.signInPrompt, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: DeliverySpacing.xl),
        TextField(
          controller: _username,
          enabled: !_busy,
          autofocus: true,
          autofillHints: const <String>[AutofillHints.username],
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          // No autocorrect and no capitals: both mangle a username, and the resulting failure looks
          // like a wrong passcode rather than a keyboard being helpful.
          autocorrect: false,
          textCapitalization: TextCapitalization.none,
          onSubmitted: (_) => _continue(),
          decoration: InputDecoration(
            labelText: t.usernameOrEmail,
            prefixIcon: const Icon(Icons.person_outline),
          ),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: DeliverySpacing.md),
          _ErrorBox(message: _error!),
        ],
        const SizedBox(height: DeliverySpacing.xl),
        ElevatedButton(
          onPressed: _busy ? null : _continue,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.md),
          ),
          child: Text(t.continueLabel),
        ),
        const SizedBox(height: DeliverySpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(t.noAccountYet, style: Theme.of(context).textTheme.bodyMedium),
            TextButton(
              onPressed: _busy ? null : widget.onCreateAccount,
              child: Text(t.createAccount),
            ),
          ],
        ),
      ],
    );
  }

  Widget _passcodeStep(DeliveryStrings t) {
    return Column(
      children: <Widget>[
        Text(t.enterYourPasscode, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: DeliverySpacing.xs),
        // Naming the account here is what catches "I typed the wrong username" before six digits
        // have been entered and refused.
        Text(_username.text.trim(), style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: DeliverySpacing.xl),

        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: DeliverySpacing.xl),
            child: CircularProgressIndicator(),
          )
        else
          PasscodePad(
            value: _passcode,
            enabled: !_busy,
            onChanged: (String v) => setState(() => _passcode = v),
            onCompleted: _submit,
            onFingerprint: _fingerprintOffered && !_busy ? _useFingerprint : null,
          ),

        if (_error != null) ...<Widget>[
          const SizedBox(height: DeliverySpacing.md),
          _ErrorBox(message: _error!),
        ],
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.md),
      decoration: BoxDecoration(
        color: DeliveryColors.brandSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DeliveryColors.brandLine),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline, color: DeliveryColors.brand, size: 20),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(message, style: const TextStyle(color: DeliveryColors.brandDark)),
          ),
        ],
      ),
    );
  }
}
