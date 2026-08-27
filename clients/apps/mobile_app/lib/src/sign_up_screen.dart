import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'one_time_code.dart';
import 'passcode_pad.dart';

/// Creating a shopper's account: one form, then the code that proves the address.
///
/// <p>Figma `customer-signup` (22:100) draws the whole account on one screen and `customer-otp`
/// (22:165) the code after it. That order is not just a layout preference — it is the security
/// property this flow already had, kept: the address is proved BEFORE an account exists, so the
/// endpoint behind this cannot be used to create accounts on addresses the caller does not own.
/// Nothing is sent to `/signup` until the code has come back verified.
///
/// <p>It replaces three narrow steps (email, code, name-and-passcode) with the two the design
/// draws. The same three calls run underneath, in the same order.
///
/// <p>A shopper is not reviewed. Merchants and riders are, because the platform is deciding whether
/// to do business with them — nobody waits for approval to order dinner.
enum _Step { details, code }

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
  _Step _step = _Step.details;

  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _code = TextEditingController();

  /// Entered twice on the form. This IS the Keycloak password, not a local unlock on top of one,
  /// which is why it is six digits and nothing else.
  final TextEditingController _passcode = TextEditingController();
  final TextEditingController _confirmPasscode = TextEditingController();

  bool _acceptedTerms = false;

  /// The proof, held between the code step and the sign-up call. Spent by it.
  String? _token;
  String _verifiedEmail = '';

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final TextEditingController c in <TextEditingController>[
      _name, _email, _passcode, _confirmPasscode
    ]) {
      c.addListener(_refresh);
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _name, _email, _phone, _code, _passcode, _confirmPasscode
    ]) {
      c.removeListener(_refresh);
      c.dispose();
    }
    super.dispose();
  }

  void _fail(Object e) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      // Dio wraps the server's message; the useful half is what the service said, which for this
      // flow is things like "wait before asking for another code" or "that code is wrong".
      _error = e is DioException && e.response?.data is Map
          ? '${(e.response!.data as Map<String, dynamic>)['message'] ?? (e.response!.data as Map<String, dynamic>)['detail'] ?? DeliveryStrings.of(context).somethingWentWrong}'
          : DeliveryStrings.of(context).somethingWentWrong;
    });
  }

  bool get _formComplete =>
      _name.text.trim().isNotEmpty &&
      _email.text.trim().contains('@') &&
      _passcode.text.length == PasscodePad.passcodeLength &&
      _confirmPasscode.text.length == PasscodePad.passcodeLength &&
      _acceptedTerms;

  /// Sends the code that proves the address. Nothing is created yet.
  Future<void> _sendCode() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String address = _email.text.trim();
    if (address.isEmpty || !address.contains('@')) {
      setState(() => _error = t.enterAValidEmail);
      return;
    }
    if (_passcode.text.length != PasscodePad.passcodeLength) {
      setState(() => _error = t.passcodeMustBeSixDigits);
      return;
    }
    if (_passcode.text != _confirmPasscode.text) {
      setState(() {
        _error = t.passcodesDoNotMatch;
        // Only the confirmation is cleared. Wiping both would make somebody re-enter a passcode
        // they almost certainly got right the first time.
        _confirmPasscode.clear();
      });
      return;
    }
    if (!_acceptedTerms) {
      setState(() => _error = t.authPleaseAcceptTheTerms);
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

  /// Confirms the code, then — and only then — creates the account and signs in.
  Future<void> _confirmAndCreate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ({String token, String destination}) confirmed = await widget.api
          .confirmCode('EMAIL', _email.text.trim(), _code.text.trim());
      if (!mounted) return;
      _token = confirmed.token;
      // The NORMALISED address, not what was typed. Verifying "Sam@Example.com " and then signing
      // up with the raw string would be refused for a reason nobody could see.
      _verifiedEmail = confirmed.destination;

      final String full = _name.text.trim();
      final int space = full.indexOf(' ');

      await widget.api.signUp(
        email: _verifiedEmail,
        verificationToken: _token!,
        firstName: space == -1 ? full : full.substring(0, space),
        lastName: space == -1 ? null : full.substring(space + 1).trim(),
        password: _passcode.text,
      );

      // Straight in. Asking somebody to sign in with a passcode they typed a minute ago is a step
      // that exists only because the implementation found it convenient.
      final AuthSession session = await widget.authService
          .signInWithPassword(_verifiedEmail, _passcode.text);
      if (!mounted) return;
      widget.onSignedIn(session);
    } catch (e) {
      if (mounted) _code.clear();
      _fail(e);
    }
  }

  void _back() {
    if (_step == _Step.details) {
      widget.onBack();
      return;
    }
    // Back walks the steps, not straight out. Losing a verified address because somebody wanted to
    // fix a typo in their name would mean waiting out the cooldown for a new code.
    setState(() {
      _error = null;
      _code.clear();
      _step = _Step.details;
    });
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
                        const SizedBox(height: DeliverySpacing.sm),
                        if (_step == _Step.details)
                          ..._detailsStep(t)
                        else
                          ..._codeStep(t),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        AuthPrimaryButton(
                          label: _step == _Step.details
                              ? t.createAccount
                              : t.verify,
                          busy: _busy,
                          onPressed: _busy
                              ? null
                              : _step == _Step.details
                                  ? (_formComplete ? _sendCode : null)
                                  : (_code.text.length ==
                                          OneTimeCodeField.length
                                      ? _confirmAndCreate
                                      : null),
                        ),
                        if (_step == _Step.details) ...<Widget>[
                          const SizedBox(height: DeliverySpacing.md),
                          AuthFooterLink(
                            question: t.authAlreadyHaveAnAccount,
                            action: t.signIn,
                            onTap: _busy ? null : widget.onBack,
                          ),
                        ],
                      ],
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

  // ------------------------------------------------------------------ 1. the account

  List<Widget> _detailsStep(DeliveryStrings t) => <Widget>[
        Text(
          t.createAccount,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
            height: 1.25,
          ),
        ),
        const SizedBox(height: DeliverySpacing.sm),
        Text(
          t.authCreateAccountSubtitle,
          style: const TextStyle(
            fontSize: 13,
            color: DeliveryColors.muted,
            height: 1.4,
          ),
        ),
        const SizedBox(height: DeliverySpacing.md),
        AuthField(
          label: t.authFullName,
          hint: t.authFullNameHint,
          controller: _name,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.name],
        ),
        const SizedBox(height: 14),
        AuthField(
          label: t.authEmailAddress,
          hint: t.authEmailHint,
          controller: _email,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.none,
          autofillHints: const <String>[AutofillHints.email],
        ),
        const SizedBox(height: 14),
        // Drawn, and inert. `/api/onboarding/signup` takes an address, a name and a passcode and
        // nothing else — a number typed here would be collected and dropped, which is worse than
        // not asking for it. It becomes real when the endpoint grows a phone field.
        YdComingSoon.wrap(
          label: t.authComingSoon,
          child: AuthField(
            label: t.authPhoneNumber,
            hint: t.authPhoneHint,
            controller: _phone,
            enabled: false,
            keyboardType: TextInputType.phone,
          ),
        ),
        const SizedBox(height: 14),
        AuthField(
          label: t.password,
          hint: t.authPasscodeHint,
          controller: _passcode,
          enabled: !_busy,
          obscure: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(PasscodePad.passcodeLength),
          ],
        ),
        const SizedBox(height: DeliverySpacing.sm),
        _PasscodeMeter(entered: _passcode.text.length),
        const SizedBox(height: 14),
        AuthField(
          label: t.authConfirmPassword,
          hint: t.authPasscodeHint,
          controller: _confirmPasscode,
          enabled: !_busy,
          obscure: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(PasscodePad.passcodeLength),
          ],
        ),
        const SizedBox(height: DeliverySpacing.md),
        _TermsAgreement(
          accepted: _acceptedTerms,
          enabled: !_busy,
          onChanged: (bool v) => setState(() => _acceptedTerms = v),
        ),
      ];

  // ------------------------------------------------------------------ 2. the code

  List<Widget> _codeStep(DeliveryStrings t) => <Widget>[
        const SizedBox(height: DeliverySpacing.sm),
        // The 64px brand-tinted badge the design heads this screen with.
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: DeliveryColors.brandSoft,
            borderRadius: BorderRadius.circular(DeliveryRadius.sheet),
          ),
          child: const Icon(Icons.mark_email_unread_outlined,
              size: 32, color: DeliveryColors.brand),
        ),
        const SizedBox(height: DeliverySpacing.md),
        Text(
          t.authVerifyYourEmail,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          t.codeSentTo(_email.text.trim()),
          style: const TextStyle(
            fontSize: 14,
            color: DeliveryColors.muted,
            height: 18 / 14,
          ),
        ),
        const SizedBox(height: DeliverySpacing.lg),
        OneTimeCodeField(
          controller: _code,
          enabled: !_busy,
          autofocus: true,
          onCompleted: _confirmAndCreate,
        ),
        const SizedBox(height: DeliverySpacing.lg),
        Center(
          child: AuthFooterLink(
            question: t.didntGetIt,
            action: t.sendAnother,
            onTap: _busy ? null : _sendCode,
          ),
        ),
      ];
}

/// The three-segment meter under the passcode field (Figma `password-strength` 22:141).
///
/// The design measures password *strength*. This credential cannot have any: it is exactly six
/// digits by definition, so every valid one is as strong as every other, and a meter reading "Good"
/// on all of them would be decoration pretending to be information. It measures what is actually
/// varying — how much of the six is entered — in the geometry and colours the design drew.
class _PasscodeMeter extends StatelessWidget {
  const _PasscodeMeter({required this.entered});

  final int entered;

  static const int _segments = 3;
  static const int _perSegment =
      PasscodePad.passcodeLength ~/ _segments;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool complete = entered >= PasscodePad.passcodeLength;
    final Color filled = DeliveryAccent.positive.color;

    return Row(
      children: <Widget>[
        for (int i = 0; i < _segments; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: DeliverySpacing.xs),
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: entered >= (i + 1) * _perSegment
                    ? filled
                    : DeliveryColors.borderFaint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
        const SizedBox(width: DeliverySpacing.sm),
        Text(
          complete ? t.authPasscodeComplete : t.authPasscodeKeepGoing,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: complete ? filled : DeliveryColors.faint,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

/// The terms row (Figma `terms-agreement` 22:152): a 20px brand checkbox at radius 6, then the
/// sentence with the two documents picked out in brand SemiBold.
///
/// The checkbox is real and gates the button. The two document names are drawn as the design draws
/// them and are deliberately not links — there is no terms page to open yet, and a link that goes
/// nowhere is a worse promise than plain text.
class _TermsAgreement extends StatelessWidget {
  const _TermsAgreement({
    required this.accepted,
    required this.enabled,
    required this.onChanged,
  });

  final bool accepted;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    const TextStyle base = TextStyle(
      fontSize: 12,
      color: DeliveryColors.muted,
      height: 16 / 12,
    );
    const TextStyle emphasis = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: DeliveryColors.brand,
      height: 16 / 12,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          checked: accepted,
          label: t.authAgreeToTerms,
          child: InkWell(
            onTap: enabled ? () => onChanged(!accepted) : null,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color:
                    accepted ? DeliveryColors.brand : DeliveryColors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: accepted
                      ? DeliveryColors.brand
                      : DeliveryColors.border,
                  width: accepted ? 1 : 2,
                ),
              ),
              child: accepted
                  ? const Icon(Icons.check,
                      size: 12, color: DeliveryColors.white)
                  : null,
            ),
          ),
        ),
        const SizedBox(width: DeliverySpacing.sm),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(text: t.authTermsPrefix, style: base),
                TextSpan(text: t.authTermsOfService, style: emphasis),
                TextSpan(text: t.authTermsAnd, style: base),
                TextSpan(text: t.authPrivacyPolicy, style: emphasis),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
