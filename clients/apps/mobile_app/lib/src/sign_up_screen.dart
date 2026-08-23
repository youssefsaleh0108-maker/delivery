import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import 'passcode_pad.dart';

/// Creating a shopper's account, in three steps.
///
/// <p>Email, then the code sent to it, then a name and a password. The order is the point: the
/// address is proved BEFORE an account exists, so the endpoint behind this cannot be used to create
/// accounts on addresses the caller does not own. It is the same one-time code machinery the
/// reviewed partner applications use, with the same cooldown and daily cap behind it.
///
/// <p>A shopper is not reviewed. Merchants and riders are, because the platform is deciding whether
/// to do business with them — nobody waits for approval to order dinner.
enum _Step { email, code, details }

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({
    super.key,
    required this.api,
    required this.authService,
    required this.onSignedIn,
    required this.onBack,
  });

  final OnboardingApi api;
  final AuthService authService;
  final ValueChanged<AuthSession> onSignedIn;
  final VoidCallback onBack;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  _Step _step = _Step.email;

  final TextEditingController _email = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  /// Entered twice on the pad. This IS the Keycloak password, not a local unlock on top of one.
  String _passcode = '';
  String _confirmPasscode = '';

  /// The proof, held between step two and step three. Spent by the sign-up call.
  String? _token;
  String _verifiedEmail = '';

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  void _fail(Object e) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      // Dio wraps the server's message; the useful half is what the service said, which for this
      // flow is things like "wait before asking for another code" or "that code is wrong".
      _error = e is DioException
          ? (e.response?.data is Map
              ? '${(e.response!.data as Map<String, dynamic>)['message'] ?? (e.response!.data as Map<String, dynamic>)['detail'] ?? e.message}'
              : DeliveryStrings.of(context).somethingWentWrong)
          : DeliveryStrings.of(context).somethingWentWrong;
    });
  }

  Future<void> _sendCode() async {
    final String address = _email.text.trim();
    if (address.isEmpty || !address.contains('@')) {
      setState(() => _error = DeliveryStrings.of(context).enterAValidEmail);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.requestCode('EMAIL', address);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = _Step.code;
      });
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _confirmCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ({String token, String destination}) confirmed =
          await widget.api.confirmCode('EMAIL', _email.text.trim(), _code.text.trim());
      if (!mounted) return;
      setState(() {
        _busy = false;
        _token = confirmed.token;
        // The NORMALISED address, not what was typed. Verifying "Sam@Example.com " and then
        // signing up with the raw string would be refused for a reason nobody could see.
        _verifiedEmail = confirmed.destination;
        _step = _Step.details;
      });
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _createAccount() async {
    if (_firstName.text.trim().isEmpty) {
      setState(() => _error = DeliveryStrings.of(context).requiredField);
      return;
    }
    if (_passcode.length != PasscodePad.passcodeLength) {
      setState(() => _error = DeliveryStrings.of(context).passcodeMustBeSixDigits);
      return;
    }
    if (_passcode != _confirmPasscode) {
      setState(() {
        _error = DeliveryStrings.of(context).passcodesDoNotMatch;
        // Only the confirmation is cleared. Wiping both would make somebody re-enter a passcode
        // they almost certainly got right the first time.
        _confirmPasscode = '';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.signUp(
        email: _verifiedEmail,
        verificationToken: _token!,
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim().isEmpty ? null : _lastName.text.trim(),
        password: _passcode,
      );
      // Straight in. Asking somebody to sign in with a password they typed ten seconds ago is a
      // step that exists only because the implementation found it convenient.
      final AuthSession session = await widget.authService
          .signInWithPassword(_verifiedEmail, _passcode);
      if (!mounted) return;
      widget.onSignedIn(session);
    } catch (e) {
      _fail(e);
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
                  // Back walks the steps, not straight out. Losing a verified address because
                  // somebody wanted to fix a typo in their name would mean waiting out the
                  // cooldown for a new code.
                  if (_step == _Step.email) {
                    widget.onBack();
                  } else {
                    setState(() {
                      _error = null;
                      _step = _step == _Step.details ? _Step.code : _Step.email;
                    });
                  }
                },
        ),
        title: Text(t.createAccount),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(DeliverySpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _StepDots(step: _step),
              const SizedBox(height: DeliverySpacing.xl),
              ...switch (_step) {
                _Step.email => _emailStep(t),
                _Step.code => _codeStep(t),
                _Step.details => _detailsStep(t),
              },
              if (_error != null) ...<Widget>[
                const SizedBox(height: DeliverySpacing.md),
                _ErrorBox(message: _error!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _emailStep(DeliveryStrings t) => <Widget>[
        Text(t.whatIsYourEmail, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: DeliverySpacing.xs),
        Text(t.weSendACodeToCheckItReachesYou,
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: DeliverySpacing.xl),
        TextField(
          controller: _email,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textCapitalization: TextCapitalization.none,
          autofillHints: const <String>[AutofillHints.email],
          decoration: InputDecoration(
            labelText: t.yourEmail,
            prefixIcon: const Icon(Icons.mail_outline),
          ),
        ),
        const SizedBox(height: DeliverySpacing.xl),
        _PrimaryButton(busy: _busy, label: t.sendCode, onPressed: _sendCode),
      ];

  List<Widget> _codeStep(DeliveryStrings t) => <Widget>[
        Text(t.theCodeWeSent, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: DeliverySpacing.xs),
        Text(_email.text.trim(), style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: DeliverySpacing.xl),
        // A passcode entry, not a text field: the code is short, numeric and fixed-length, so the
        // input should say so. Digits only, a number pad, and one glance to check what was typed.
        TextField(
          controller: _code,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          textAlign: TextAlign.center,
          autofocus: true,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: 16,
          ),
          decoration: const InputDecoration(
            hintText: '······',
            counterText: '',
          ),
          onChanged: (String v) {
            // Submits itself on the last digit. Asking somebody to type six digits and then reach
            // for a button is a step with no purpose.
            if (v.length == 6 && !_busy) _confirmCode();
          },
        ),
        const SizedBox(height: DeliverySpacing.xl),
        _PrimaryButton(busy: _busy, label: t.verify, onPressed: _confirmCode),
        const SizedBox(height: DeliverySpacing.sm),
        TextButton(
          onPressed: _busy ? null : _sendCode,
          child: Text(t.sendAnother),
        ),
      ];

  List<Widget> _detailsStep(DeliveryStrings t) => <Widget>[
        Text(t.aboutYou, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: DeliverySpacing.xs),
        Row(
          children: <Widget>[
            const Icon(Icons.verified, size: 16, color: DeliveryColors.brand),
            const SizedBox(width: 6),
            Expanded(
              child: Text(_verifiedEmail,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
        const SizedBox(height: DeliverySpacing.xl),
        TextField(
          controller: _firstName,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          autofillHints: const <String>[AutofillHints.givenName],
          decoration: InputDecoration(
            labelText: t.yourName,
            prefixIcon: const Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: DeliverySpacing.md),
        TextField(
          controller: _lastName,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          autofillHints: const <String>[AutofillHints.familyName],
          decoration: InputDecoration(
            labelText: t.lastNameOptional,
            prefixIcon: const Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: DeliverySpacing.xl),
        Text(
          _confirmPasscode.isEmpty && _passcode.length < PasscodePad.passcodeLength
              ? t.chooseAPasscode
              : t.confirmYourPasscode,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: DeliverySpacing.xs),
        Text(t.sixDigitsYouWillUseToSignIn,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: DeliverySpacing.lg),
        // One pad, two passes. The first fills _passcode; once it is full the same pad collects the
        // confirmation, so there is never a second keypad on screen competing for the thumb.
        PasscodePad(
          value: _passcode.length < PasscodePad.passcodeLength ? _passcode : _confirmPasscode,
          enabled: !_busy,
          onChanged: (String v) => setState(() {
            if (_passcode.length < PasscodePad.passcodeLength) {
              _passcode = v;
            } else {
              _confirmPasscode = v;
            }
          }),
          onCompleted: () {
            // Nothing to do when the FIRST pass completes: the pad simply starts filling the
            // confirmation on the next digit. Only a full confirmation submits.
            if (_confirmPasscode.length == PasscodePad.passcodeLength) {
              _createAccount();
            }
          },
        ),
      ];
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (final _Step s in _Step.values)
          Expanded(
            child: Container(
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: s.index <= step.index
                    ? DeliveryColors.brand
                    : DeliveryColors.brandLine,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
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

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.busy,
    required this.label,
    required this.onPressed,
  });

  final bool busy;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: busy ? null : onPressed,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.md),
      ),
      child: busy
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: DeliveryColors.white),
            )
          : Text(label),
    );
  }
}
