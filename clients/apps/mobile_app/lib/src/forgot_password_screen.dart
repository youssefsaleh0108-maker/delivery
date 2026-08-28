import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'one_time_code.dart';
import 'passcode_pad.dart';
// The auth surface's brand lockup lives with the screen that first drew it, as the other shared
// auth parts live in one_time_code.dart. The import is mutual — sign-in pushes this screen — which
// Dart handles fine and which is preferable to a third file holding one widget.
import 'sign_in_screen.dart' show AuthBrandRow;

/// The API base the reset endpoints live behind.
///
/// Read from the same `--dart-define` `main.dart` reads, with the same default, because this
/// screen has to be able to build its own client: the password-reset pair is **open** — no bearer,
/// no session, that is the entire premise — and the screens that open it (the sign-in form, which
/// is drawn before any session exists) are not handed one. Reading the same define means a build
/// that points the app at a different box points this at the same box, with no second switch to
/// forget.
///
/// A caller that already has a wired client should pass [ForgotPasswordScreen.api] instead; this is
/// the fallback, not the intent.
const String _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://192.168.10.24:8100',
);

/// Which of the three steps is showing.
enum _Step { address, code, done }

/// Setting a new passcode without being able to sign in — and changing one while signed in.
///
/// <p>Figma has no frame for this: the sign-in screen draws a "Forgot password?" link and stops.
/// So it is drawn in the auth surface's own established language — the back button, the brand
/// lockup, the labelled fields, the six OTP cells, the full-width primary button and the error
/// note — because that is what every other step of this flow already looks like and a customer
/// arriving here from sign-in should not feel they have left the app.
///
/// <p><strong>What the server will and will not tell us, and what this screen therefore says.</strong>
/// Asking for a code answers 202 for every well-formed address, known or unknown — it is
/// deliberately not a directory of who has an account. So this screen never claims a message was
/// sent: it says a code is on its way *if that address has an account*. The same holds at the far
/// end: a correct code for an address with no account is refused with the same wording as a wrong
/// code, and this screen passes that wording through rather than trying to be cleverer than the
/// endpoint that is protecting somebody's privacy.
///
/// <p>The 502 case matters and is not a dead end: the code was right and the identity server
/// refused the new passcode, its consumption rolled back, and the same code is still live. The
/// server's own sentence says to try again, and the code cells keep what was typed.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    super.key,
    this.api,
    this.initialEmail,
    this.emailFixed = false,
    this.signedIn = false,
  });

  /// The reset client. Optional: when absent one is built against [_apiBaseUrl], because the
  /// endpoints are open and the sign-in screen has nothing wired to hand over.
  final PasswordResetApi? api;

  /// Prefills the address — the account's own when opened from the Account tab, and the username
  /// already typed when opened from sign-in.
  final String? initialEmail;

  /// Locks the address field. True when the account is known: letting somebody signed in as one
  /// person send a reset code to another address is not "editing a field", it is a way to spam
  /// strangers from inside a session.
  final bool emailFixed;

  /// Changes the wording from "reset" to "change" and the closing button from "Sign in" to
  /// "Done" — the same three calls either way, but somebody who is already signed in is not
  /// locked out and should not be told they are.
  final bool signedIn;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  _Step _step = _Step.address;

  final TextEditingController _email = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _passcode = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _busy = false;
  String? _error;

  /// True when the last refusal was about the code, so the cells can be painted as refused rather
  /// than only the note under them saying so.
  bool _codeRefused = false;

  /// The address the code was actually requested for, which is the one the confirm call must use.
  /// Editing the field after the code was sent and confirming against the new text would spend the
  /// code on the wrong account.
  String _requestedFor = '';

  late final PasswordResetApi _api = widget.api ??
      PasswordResetApi(Dio(BaseOptions(
        baseUrl: _apiBaseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
        contentType: Headers.jsonContentType,
      )));

  @override
  void initState() {
    super.initState();
    _email.text = widget.initialEmail?.trim() ?? '';
    for (final TextEditingController c in <TextEditingController>[
      _email, _code, _passcode, _confirm
    ]) {
      c.addListener(_refresh);
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _email, _code, _passcode, _confirm
    ]) {
      c.removeListener(_refresh);
      c.dispose();
    }
    super.dispose();
  }

  /// Shows the server's own sentence where it sent one.
  ///
  /// It is the useful half on every refusal this flow can produce: "wait before asking for another
  /// code", "that code is wrong or has expired", "we could not set your passcode, try again". Only
  /// the unreachable case is translated, because there is nothing from the server to show.
  void _fail(Object e) {
    if (!mounted) return;
    final DeliveryStrings t = DeliveryStrings.of(context);
    setState(() {
      _busy = false;
      final Object? data = e is DioException ? e.response?.data : null;
      _error = data is Map<String, dynamic>
          ? (data['message'] as String? ?? data['detail'] as String? ?? t.somethingWentWrong)
          : (e is DioException && e.response != null
              ? t.somethingWentWrong
              : t.couldNotReachTheServer);
    });
  }

  bool get _addressLooksRight => _email.text.trim().contains('@');

  bool get _newPasscodeReady =>
      _code.text.length == OneTimeCodeField.length &&
      _passcode.text.length == PasscodePad.passcodeLength &&
      _confirm.text.length == PasscodePad.passcodeLength;

  /// Step 1 → 2. Never says a message was sent, because the server never says so either.
  Future<void> _requestCode() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String address = _email.text.trim();
    if (!_addressLooksRight) {
      setState(() => _error = t.enterAValidEmail);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.request(address);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _requestedFor = address;
        _codeRefused = false;
        _step = _Step.code;
      });
    } catch (e) {
      _fail(e);
    }
  }

  /// Asks for another code for the SAME address. The cooldown is the server's to enforce and its
  /// 429 sentence is what appears if it is still running.
  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.request(_requestedFor);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _codeRefused = false;
        _code.clear();
      });
    } catch (e) {
      _fail(e);
    }
  }

  /// Step 2 → 3. One code, one reset — the server consumes it transactionally.
  Future<void> _confirmReset() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    if (_passcode.text.length != PasscodePad.passcodeLength) {
      setState(() => _error = t.passcodeMustBeSixDigits);
      return;
    }
    if (_passcode.text != _confirm.text) {
      setState(() {
        _error = t.passcodesDoNotMatch;
        // Only the confirmation is cleared: the first entry was almost certainly right.
        _confirm.clear();
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _codeRefused = false;
    });
    try {
      await _api.confirm(
        email: _requestedFor,
        code: _code.text.trim(),
        newPassword: _passcode.text,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = _Step.done;
      });
    } on DioException catch (e) {
      // 422 is the code being refused — wrong, expired, spent, or one guess too many. 502 is the
      // identity server refusing the new passcode with the code still live, so the cells keep what
      // was typed and the button is the retry.
      if (mounted && e.response?.statusCode == 422) {
        setState(() {
          _codeRefused = true;
          _code.clear();
        });
      }
      _fail(e);
    } catch (e) {
      _fail(e);
    }
  }

  void _back() {
    if (_step == _Step.address || _step == _Step.done) {
      Navigator.of(context).pop();
      return;
    }
    // Back walks the steps. Leaving the flow to fix a typo in an address would mean waiting out
    // the resend cooldown for a code that is already in somebody's inbox.
    setState(() {
      _error = null;
      _codeRefused = false;
      _code.clear();
      _step = _Step.address;
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
                        const SizedBox(height: DeliverySpacing.md),
                        const AuthBrandRow(),
                        const SizedBox(height: DeliverySpacing.md),
                        ...switch (_step) {
                          _Step.address => _addressStep(t),
                          _Step.code => _codeStep(t),
                          _Step.done => _doneStep(t),
                        },
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
                    child: _primary(t),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _primary(DeliveryStrings t) {
    return switch (_step) {
      _Step.address => AuthPrimaryButton(
          label: t.sendCode,
          busy: _busy,
          onPressed: _busy || !_addressLooksRight ? null : _requestCode,
        ),
      _Step.code => AuthPrimaryButton(
          label: t.authSetNewPasscode,
          busy: _busy,
          onPressed: _busy || !_newPasscodeReady ? null : _confirmReset,
        ),
      _Step.done => AuthPrimaryButton(
          label: widget.signedIn ? t.done : t.signIn,
          busy: false,
          onPressed: () => Navigator.of(context).pop(true),
        ),
    };
  }

  // ------------------------------------------------------------------ 1. which account

  List<Widget> _addressStep(DeliveryStrings t) => <Widget>[
        Text(
          widget.signedIn ? t.authChangeYourPasscode : t.authResetYourPasscode,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.emailFixed ? t.authResetToYourAddress : t.authResetAskForAddress,
          style: const TextStyle(
            fontSize: 14,
            color: DeliveryColors.muted,
            height: 1.4,
          ),
        ),
        const SizedBox(height: DeliverySpacing.lg),
        AuthField(
          label: t.authEmailAddress,
          hint: t.authEmailHint,
          controller: _email,
          // Locked rather than hidden when the account is known: somebody should be able to see
          // which address the code is going to before they ask for it.
          enabled: !_busy && !widget.emailFixed,
          readOnly: widget.emailFixed,
          autofocus: !widget.emailFixed,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.none,
          autofillHints: const <String>[AutofillHints.email],
          onSubmitted: (_) => _requestCode(),
        ),
      ];

  // ------------------------------------------------------------------ 2. the code and the new one

  List<Widget> _codeStep(DeliveryStrings t) => <Widget>[
        Center(
          child: Container(
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
        // Not "we sent you a code". The endpoint answers the same way for an address with no
        // account, so promising a message would be promising something nobody checked.
        Text(
          t.authResetCodeMaybeSent(_requestedFor),
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
          hasError: _codeRefused,
          // The button below is the way through here, not the last digit: there is a new passcode
          // to choose underneath before anything can be sent.
          onCompleted: () {},
        ),
        const SizedBox(height: DeliverySpacing.lg),
        AuthField(
          label: t.chooseAPasscode,
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
        const SizedBox(height: 14),
        AuthField(
          label: t.confirmYourPasscode,
          hint: t.authPasscodeHint,
          controller: _confirm,
          enabled: !_busy,
          obscure: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(PasscodePad.passcodeLength),
          ],
          onSubmitted: (_) => _newPasscodeReady ? _confirmReset() : null,
        ),
        const SizedBox(height: DeliverySpacing.lg),
        Center(
          child: AuthFooterLink(
            question: t.didntGetIt,
            action: t.sendAnother,
            onTap: _busy ? null : _resend,
          ),
        ),
      ];

  // ------------------------------------------------------------------ 3. it is changed

  List<Widget> _doneStep(DeliveryStrings t) => <Widget>[
        Center(
          child: Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: DeliveryAccent.positive.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(DeliveryRadius.sheet),
            ),
            child: Icon(Icons.check_rounded,
                size: 32, color: DeliveryAccent.positive.color),
          ),
        ),
        const SizedBox(height: DeliverySpacing.md),
        Text(
          t.authPasscodeChanged,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.signedIn ? t.authPasscodeChangedSignedIn : t.authPasscodeChangedSignIn,
          style: const TextStyle(
            fontSize: 14,
            color: DeliveryColors.muted,
            height: 1.4,
          ),
        ),
      ];
}
