import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'application_documents_step.dart';
import 'application_refusals.dart';
import 'lebanese_phone.dart';
import 'one_time_code.dart';
import 'passcode_pad.dart';

/// Applying to offer services — a print shop, a tailor, a repairer (Figma 126:11).
///
/// One page rather than the shop wizard's four steps: the business name, the service offered, a
/// phone number and the area, then "Apply to sell services". Behind it is the same merchant
/// application every shop makes — kind MERCHANT, with `details.businessType` SERVICES plus the
/// category and the area — so it waits in the same queue, under the same auto-approval switch, for
/// the same documents (owner default 5). The server checks that the category is open and the area is
/// a live delivery zone, and the pickers can only offer what it would accept: both come from the
/// lists it checks against ([OnboardingApi.serviceOptions]).
///
/// Two ways in, as with the wizard:
///
/// - **An account that already exists** ([ServiceProviderSignupScreen.account]) — a customer from
///   the profile menu, or a Google sign-in that answered "Services". The address is the account's own
///   and already proved, so there is no email code and no passcode. The application is attached to
///   the account ([OnboardingApi.applyForMyAccount]) and the session refreshed, so the roles it
///   granted are in the token before anything routes on it.
/// - **Somebody with no account**, from the partner choice. The form also asks for their name, email
///   and a six-digit passcode: the address is proved with a code, the application recorded, and the
///   account created and signed in — the open path the wizard walks.
///
/// A phone number is optional, and proved with its own code when one is given. It is typed after a
/// fixed +961 and laid out left to right in Arabic too, as the gift checkout draws a number.
///
/// **The documents come straight after the application is recorded**, on both paths: the national ID
/// and the commercial registration every shop's application is judged on, in the rows the shop wizard
/// draws ([ApplicationDocumentsStep]). They are sent there and then — by that point the account exists
/// and the session carries its token — and the step can be skipped. There is nowhere else in the app
/// to add them later: a waiting provider is in the shop shell, whose documents row is the payout page.
/// So the last screen says whether they were sent, rather than pointing to a place that does not
/// exist. An application auto-approval has already decided takes no documents, and goes straight on.
///
/// The frame's promises that the platform cannot keep are not copied. Turnaround is set per offer, so
/// nothing says "same-day"; no customer count backs "thousands"; and the button does not say "Create
/// Service Account", because nothing sells until a reviewer or auto-approval says yes — which the
/// last screen says plainly, one way or the other.
class ServiceProviderSignupScreen extends StatefulWidget {
  const ServiceProviderSignupScreen({
    super.key,
    required this.api,
    required this.documentsApi,
    required this.authService,
    required this.onFinished,
    required this.onClose,
    this.account,
    this.pickDocument = pickApplicantDocument,
  });

  final OnboardingApi api;

  /// Sends the national ID and commercial registration once the application is in.
  final DocumentsApi documentsApi;

  /// Refreshes an existing account's session, or signs a new applicant in.
  final AuthService authService;

  /// The account applying, or null for somebody with no account yet.
  final AuthSession? account;

  /// Called from the last screen with the session that carries what applying granted: APPLICANT
  /// beside MERCHANT while the application waits, MERCHANT alone when auto-approval said yes.
  final void Function(AuthSession session) onFinished;

  /// Leaves without applying — and leaves an application that was already decided.
  final VoidCallback onClose;

  /// Opens the file dialog for one document: the platform's own, unless a test hands in another.
  final Future<PickedDocument?> Function(String groupLabel) pickDocument;

  @override
  State<ServiceProviderSignupScreen> createState() => _ServiceProviderSignupScreenState();
}

/// Where the applicant is.
enum _Phase {
  /// The frame's form.
  form,

  /// The code that proves the email address. Somebody with no account only.
  verifyEmail,

  /// The code that proves the phone number, when one was typed.
  verifyPhone,

  /// Recording the application, then the account and the session.
  sending,

  /// Recorded and waiting for a decision: the national ID and commercial registration, or skip them.
  documents,

  /// Applied: waiting for a decision, or approved.
  done,
}

class _ServiceProviderSignupScreenState extends State<ServiceProviderSignupScreen> {
  /// The longest name a shop may carry. An application allows more, but the shop is opened under
  /// this name and the server would refuse a longer one, leaving an approved provider with no shop.
  static const int _maxBusinessName = 160;

  final TextEditingController _business = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _passcode = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _emailCode = TextEditingController();
  final TextEditingController _phoneCode = TextEditingController();

  List<TextEditingController> get _controllers => <TextEditingController>[
        _business, _name, _email, _passcode, _phone, _emailCode, _phoneCode,
      ];

  late Future<ServiceSignupOptions> _options = widget.api.serviceOptions();

  ServiceCategory? _category;
  ServiceArea? _area;

  _Phase _phase = _Phase.form;
  bool _busy = false;
  String? _error;

  // The proofs, and exactly what each one proved. Kept across a trip back to the form: the server
  // checks the services answers before it spends a proof, so a refused category costs no new code.
  String? _emailToken;
  String? _verifiedEmail;
  String? _provedEmail;
  String? _phoneToken;
  String? _verifiedPhone;
  String? _provedPhone;

  /// The recorded application's reference. Once set, a retry never records a second application.
  String? _reference;

  /// What the signed-in endpoint answered — the application, created or handed back.
  OnboardingApplication? _receipt;

  /// The open path creates the account once; a second attempt is refused, so a later failure
  /// retries the sign-in alone.
  bool _accountCreated = false;

  AuthSession? _session;

  /// The account's application was already decided, or is for something else, so applying granted
  /// nothing and sending again never will.
  bool _applicationClosed = false;

  /// Documents picked and not sent yet, one per kind. A document that is sent leaves this map, so a
  /// retry after a failure sends only what did not go through.
  final Map<ApplicantDocumentKind, PickedDocument> _pickedDocs =
      <ApplicantDocumentKind, PickedDocument>{};

  /// The kinds that reached the reviewer, for the last screen's line about them.
  final Set<ApplicantDocumentKind> _sentDocs = <ApplicantDocumentKind>{};

  bool get _forAccount => widget.account != null;

  /// Only asked when there is no name to apply in: somebody new, or an account with no name on it.
  bool get _asksName => !_forAccount || (widget.account!.name ?? '').trim().isEmpty;

  String get _contactName => _asksName ? _name.text.trim() : widget.account!.name!.trim();

  /// The number as it is sent — `+96171234567` — or null when none was typed.
  String? get _phoneNumber =>
      _phone.text.trim().isEmpty ? null : LebanesePhone.international(_phone.text);

  bool get _phoneInvalid => _phone.text.trim().isNotEmpty && _phoneNumber == null;

  bool get _recorded => _forAccount ? _receipt != null : _reference != null;

  bool get _formComplete =>
      _business.text.trim().isNotEmpty &&
      _category != null &&
      _area != null &&
      _contactName.isNotEmpty &&
      !_phoneInvalid &&
      (_forAccount ||
          (_email.text.trim().contains('@') &&
              _passcode.text.length == PasscodePad.passcodeLength));

  /// The answers that make a shop's application a services provider's.
  Map<String, dynamic> get _details => <String, dynamic>{
        'businessType': 'SERVICES',
        'serviceCategory': _category!.wireValue,
        'area': <String, String>{'zoneId': _area!.zoneId, 'label': _area!.name},
      };

  /// MERCHANT without APPLICANT: auto-approval has already said yes.
  static bool _approved(AuthSession session) =>
      session.hasRole(DeliveryRole.merchant) && !session.hasRole(DeliveryRole.applicant);

  @override
  void initState() {
    super.initState();
    for (final TextEditingController c in _controllers) {
      c.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------- the calls

  Future<void> _apply() async {
    setState(() => _error = null);
    final bool emailStillProved = _emailToken != null && _provedEmail == _email.text.trim();
    if (!_forAccount && !emailStillProved) {
      if (await _sendCode('EMAIL', _email.text.trim()) && mounted) {
        setState(() => _phase = _Phase.verifyEmail);
      }
      return;
    }
    await _afterEmail();
  }

  Future<void> _afterEmail() async {
    final String? phone = _phoneNumber;
    if (phone == null) {
      _phoneToken = null;
      _verifiedPhone = null;
      _provedPhone = null;
      await _send();
      return;
    }
    if (_phoneToken != null && _provedPhone == phone) {
      await _send();
      return;
    }
    if (await _sendCode('PHONE', phone) && mounted) {
      setState(() => _phase = _Phase.verifyPhone);
    }
  }

  Future<bool> _sendCode(String channel, String destination) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.requestCode(channel, destination);
      return true;
    } catch (e) {
      if (mounted) setState(() => _error = applicationServerMessage(t, e));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmEmail() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String address = _email.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ({String token, String destination}) proof =
          await widget.api.confirmCode('EMAIL', address, _emailCode.text.trim());
      // The server's spelling of the address, not the typed one: the application has to carry
      // exactly what was verified or it is refused for a reason nobody can see.
      _verifiedEmail = proof.destination;
      _emailToken = proof.token;
      _provedEmail = address;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = applicationServerMessage(t, e);
        _emailCode.clear();
      });
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _afterEmail();
  }

  Future<void> _confirmPhone() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String? phone = _phoneNumber;
    if (phone == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ({String token, String destination}) proof =
          await widget.api.confirmCode('PHONE', phone, _phoneCode.text.trim());
      _verifiedPhone = proof.destination;
      _phoneToken = proof.token;
      _provedPhone = phone;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = applicationServerMessage(t, e);
        _phoneCode.clear();
      });
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _send();
  }

  /// Carries on without the number. What was typed goes with its proof: a number left in the field
  /// unproved would be refused by the server.
  Future<void> _skipPhone() async {
    _phone.clear();
    _phoneCode.clear();
    _phoneToken = null;
    _verifiedPhone = null;
    _provedPhone = null;
    await _send();
  }

  /// Records the application, then refreshes the account — or creates it and signs in.
  Future<void> _send() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    setState(() {
      _phase = _Phase.sending;
      _busy = true;
      _error = null;
    });
    try {
      if (_forAccount) {
        // Idempotent on the server: a retry gets the same application back, not a second one.
        _receipt ??= await widget.api.applyForMyAccount(
          kind: OnboardingKind.merchant,
          name: _contactName,
          businessName: _business.text.trim(),
          phone: _verifiedPhone,
          phoneVerificationToken: _phoneToken,
          details: _details,
        );
        _reference = _receipt!.reference.isEmpty ? null : _receipt!.reference;
        // The roles changed in Keycloak, not in the token in hand. Routing on the old token would
        // put somebody back where they started.
        _session ??= await widget.authService.refresh();
      } else {
        _reference ??= await widget.api.applyAsMerchant(
          businessName: _business.text.trim(),
          contactName: _contactName,
          email: _verifiedEmail!,
          emailVerificationToken: _emailToken!,
          phone: _verifiedPhone,
          phoneVerificationToken: _phoneToken,
          details: _details,
        );
        if (!_accountCreated) {
          try {
            await widget.api.createApplicantAccount(
              reference: _reference!,
              password: _passcode.text,
            );
          } catch (e) {
            // Already made: an earlier try went through and its answer was lost. Straight on to
            // signing in with the passcode it was made with — see [isSignInExists].
            if (!isSignInExists(e)) rethrow;
          }
          _accountCreated = true;
        }
        _session ??= await widget.authService.signInWithPassword(_verifiedEmail!, _passcode.text);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (!_recorded && isServiceAnswerRefusal(e)) {
          // An answer to change, not a call to retry: back to the form, with the reason on it.
          _phase = _Phase.form;
          _error = applicationRefusal(t, e);
        } else if (!_recorded && isFinalAccountRefusal(e)) {
          // The account already has an application for something else — a shop's, say — or already
          // trades. Sending again can never change that, so the way out replaces the retry.
          _applicationClosed = true;
          _error = applicationRefusal(t, e);
        } else if (!_recorded) {
          _error = applicationRefusal(t, e);
        } else if (_forAccount) {
          _error = t.wizAccountRefreshFailed;
        } else {
          // Two different situations: retrying the account is futile once it exists.
          _error = _accountCreated
              ? '${t.accountReadySignInInstead} ${applicationServerMessage(t, e)}'
              : '${t.couldNotCreateSignIn} ${applicationServerMessage(t, e)}';
        }
      });
      return;
    }
    if (!mounted) return;
    final AuthSession session = _session!;
    if (_forAccount && !session.hasRole(DeliveryRole.merchant)) {
      // The one answer that grants nothing: this account's application was decided already, so no
      // role arrived and none will. Saying so beats a pending screen that would never change.
      setState(() {
        _busy = false;
        _applicationClosed = true;
        _error = t.accountApplicationClosed;
      });
      return;
    }
    setState(() {
      _busy = false;
      // A decided application's documents can no longer change, so an application auto-approval
      // has already said yes to goes straight to the last screen.
      _phase = _approved(session) ? _Phase.done : _Phase.documents;
    });
  }

  /// Sends what was picked, one document at a time. Each one that lands leaves [_pickedDocs], so a
  /// retry sends only what did not go through; when nothing is left, the last screen follows.
  Future<void> _sendDocuments() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    String? failure;
    for (final MapEntry<ApplicantDocumentKind, PickedDocument> entry
        in List<MapEntry<ApplicantDocumentKind, PickedDocument>>.of(_pickedDocs.entries)) {
      try {
        await widget.documentsApi.upload(
          kind: entry.key,
          bytes: entry.value.bytes,
          contentType: entry.value.contentType,
        );
        _pickedDocs.remove(entry.key);
        _sentDocs.add(entry.key);
      } on ArgumentError {
        // Refused before the transfer, against the upload ticket's limit.
        failure ??= t.wizDocTooLarge;
      } catch (_) {
        failure ??= t.wizDocUploadFailed;
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (failure == null) {
        _phase = _Phase.done;
      } else {
        _error = failure;
      }
    });
  }

  /// Carries on without the documents still picked. The application is in either way.
  void _skipDocuments() {
    setState(() {
      _pickedDocs.clear();
      _error = null;
      _phase = _Phase.done;
    });
  }

  void _back() {
    if (_busy) return;
    switch (_phase) {
      case _Phase.form:
        widget.onClose();
      case _Phase.verifyEmail || _Phase.verifyPhone:
        setState(() {
          _error = null;
          _emailCode.clear();
          _phoneCode.clear();
          _phase = _Phase.form;
        });
      case _Phase.sending:
        // Once the application is in, the form's answers can no longer change it.
        if (_recorded || _applicationClosed) {
          widget.onClose();
        } else {
          setState(() {
            _error = null;
            _phase = _Phase.form;
          });
        }
      case _Phase.documents:
        // The application is in; leaving the documents is choosing not to send them.
        _skipDocuments();
      case _Phase.done:
        widget.onFinished(_session!);
    }
  }

  // ---------------------------------------------------------------- the page

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return PopScope<Object?>(
      canPop: _phase == _Phase.form && !_busy,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: DeliveryColors.background,
        appBar: YdScreenHeader(
          title: t.svcOfferYourServices,
          onBack: _busy ? null : _back,
          backSemanticLabel: t.back,
        ),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Expanded(
                child: switch (_phase) {
                  _Phase.form => _form(t),
                  _Phase.verifyEmail || _Phase.verifyPhone => _verification(t),
                  _Phase.sending => _sending(t),
                  _Phase.documents => _documents(t),
                  _Phase.done => _done(t),
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    DeliverySpacing.lg, DeliverySpacing.sm, DeliverySpacing.lg, DeliverySpacing.lg),
                child: _bottomAction(t),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _form(DeliveryStrings t) {
    return FutureBuilder<ServiceSignupOptions>(
      future: _options,
      builder: (BuildContext context, AsyncSnapshot<ServiceSignupOptions> snapshot) {
        final List<Widget> fields;
        if (snapshot.hasError) {
          fields = <Widget>[
            YdEmptyState(
              icon: Icons.cloud_off_outlined,
              title: t.svcOptionsFailed,
              action: TextButton(
                // A block body, not an arrow: an arrow would return the Future it assigns, and
                // setState refuses a callback that returns one.
                onPressed: () => setState(() {
                  _options = widget.api.serviceOptions();
                }),
                child: Text(t.tryAgain),
              ),
            ),
          ];
        } else if (!snapshot.hasData) {
          fields = const <Widget>[
            Padding(
              padding: EdgeInsets.all(DeliverySpacing.xl),
              child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
            ),
          ];
        } else if (snapshot.data!.categories.isEmpty || snapshot.data!.areas.isEmpty) {
          // Nothing open means nothing to apply for — said, rather than drawn as a form that can
          // never be completed.
          fields = <Widget>[SoftNote(text: t.svcNoCategoriesOpen, icon: Icons.info_outline)];
        } else {
          fields = _fields(t, snapshot.data!);
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(
              DeliverySpacing.lg, DeliverySpacing.sm, DeliverySpacing.lg, DeliverySpacing.lg),
          children: <Widget>[
            Text(
              t.svcSignupTitle,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: DeliveryColors.ink,
                height: 30 / 24,
              ),
            ),
            const SizedBox(height: DeliverySpacing.xs),
            Text(
              t.svcSignupSubtitle,
              style: const TextStyle(fontSize: 14, color: DeliveryColors.muted, height: 20 / 14),
            ),
            const SizedBox(height: DeliverySpacing.lg),
            const _ServicesBanner(),
            const SizedBox(height: DeliverySpacing.lg),
            if (_error != null) ...<Widget>[
              SoftNote(text: _error!, accent: DeliveryAccent.critical, icon: Icons.error_outline),
              const SizedBox(height: DeliverySpacing.md),
            ],
            ...fields,
          ],
        );
      },
    );
  }

  List<Widget> _fields(DeliveryStrings t, ServiceSignupOptions options) {
    final bool enabled = !_busy;
    const SizedBox gap = SizedBox(height: DeliverySpacing.md);

    return <Widget>[
      AuthField(
        label: t.svcBusinessName,
        hint: t.svcBusinessNameHint,
        controller: _business,
        enabled: enabled,
        borderColor: DeliveryColors.border,
        uppercaseLabel: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        inputFormatters: <TextInputFormatter>[
          LengthLimitingTextInputFormatter(_maxBusinessName),
        ],
      ),
      gap,
      AuthPickerField(
        label: t.svcServiceCategory,
        hint: t.svcServiceCategoryHint,
        value: _category?.labelIn(t),
        options: <String>[
          for (final ServiceCategory category in options.categories) category.labelIn(t),
        ],
        enabled: enabled,
        uppercaseLabel: true,
        onSelected: (int i) => setState(() => _category = options.categories[i]),
      ),
      gap,
      // A phone number reads left to right in Arabic too, +961 first, the way the gift checkout
      // draws it: laid out right to left, "71 234 567" read back as "567 234 71". Only the number
      // and its prefix — the label above and the error below are sentences in the reader's language
      // and keep the reader's direction.
      AuthField(
        label: t.authPhoneNumber,
        hint: t.svcPhoneHint,
        controller: _phone,
        enabled: enabled,
        borderColor: DeliveryColors.border,
        uppercaseLabel: true,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.next,
        autofillHints: const <String>[AutofillHints.telephoneNumber],
        textDirection: TextDirection.ltr,
        fixedPrefix: LebanesePhone.countryCode,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(RegExp(r'[0-9 +\-]')),
          LengthLimitingTextInputFormatter(20),
        ],
      ),
      if (_phoneInvalid)
        Padding(
          padding: const EdgeInsetsDirectional.only(top: DeliverySpacing.xs),
          child: Text(
            t.svcPhoneInvalid,
            style: TextStyle(fontSize: 12, color: DeliveryAccent.critical.onTint),
          ),
        ),
      gap,
      AuthPickerField(
        label: t.svcArea,
        hint: t.svcAreaHint,
        value: _area?.name,
        options: <String>[for (final ServiceArea area in options.areas) area.name],
        enabled: enabled,
        uppercaseLabel: true,
        onSelected: (int i) => setState(() => _area = options.areas[i]),
      ),
      if (_asksName) ...<Widget>[
        gap,
        AuthField(
          label: t.authOwnerFullName,
          hint: t.authOwnerFullNameHint,
          controller: _name,
          enabled: enabled,
          borderColor: DeliveryColors.border,
          uppercaseLabel: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
        ),
      ],
      if (!_forAccount) ...<Widget>[
        gap,
        AuthField(
          label: t.authContactEmail,
          hint: t.authEmailHint,
          controller: _email,
          enabled: enabled,
          borderColor: DeliveryColors.border,
          uppercaseLabel: true,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.email],
        ),
        gap,
        AuthField(
          label: t.password,
          hint: t.authPasscodeHint,
          controller: _passcode,
          enabled: enabled,
          obscure: true,
          borderColor: DeliveryColors.border,
          uppercaseLabel: true,
          keyboardType: TextInputType.number,
          // The realm's credential is exactly six digits; a longer password here would create an
          // account the sign-in screen could never open.
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(PasscodePad.passcodeLength),
          ],
        ),
      ],
    ];
  }

  Widget _verification(DeliveryStrings t) {
    final bool email = _phase == _Phase.verifyEmail;
    final String destination = email ? _email.text.trim() : (_phoneNumber ?? _phone.text.trim());

    return ListView(
      padding: const EdgeInsets.all(DeliverySpacing.lg),
      children: <Widget>[
        _StateTile(icon: email ? Icons.mark_email_unread_outlined : Icons.smartphone_outlined),
        const SizedBox(height: DeliverySpacing.md),
        Text(email ? t.authVerifyYourEmail : t.authVerifyYourNumber, style: _titleStyle),
        const SizedBox(height: DeliverySpacing.xs),
        Text(t.codeSentTo(destination), style: _bodyStyle),
        const SizedBox(height: DeliverySpacing.lg),
        if (_error != null) ...<Widget>[
          SoftNote(text: _error!, accent: DeliveryAccent.critical, icon: Icons.error_outline),
          const SizedBox(height: DeliverySpacing.md),
        ],
        OneTimeCodeField(
          controller: email ? _emailCode : _phoneCode,
          enabled: !_busy,
          autofocus: true,
          onCompleted: email ? _confirmEmail : _confirmPhone,
        ),
        const SizedBox(height: DeliverySpacing.lg),
        Center(
          child: AuthFooterLink(
            question: t.didntGetIt,
            action: t.sendAnother,
            onTap: _busy ? null : () => _sendCode(email ? 'EMAIL' : 'PHONE', destination),
          ),
        ),
      ],
    );
  }

  Widget _sending(DeliveryStrings t) {
    return ListView(
      padding: const EdgeInsets.all(DeliverySpacing.lg),
      children: <Widget>[
        const SizedBox(height: DeliverySpacing.xxl),
        if (_error == null) ...<Widget>[
          const Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
          const SizedBox(height: DeliverySpacing.md),
          Center(child: Text(t.authSendingApplication, style: _bodyStyle)),
        ] else
          YdEmptyState(icon: Icons.error_outline, title: t.thatDidNotGoThrough, message: _error),
      ],
    );
  }

  /// The papers a shop's application is judged on, straight after it is recorded.
  Widget _documents(DeliveryStrings t) {
    return ListView(
      padding: const EdgeInsets.all(DeliverySpacing.lg),
      children: <Widget>[
        const _StateTile(icon: Icons.badge_outlined),
        const SizedBox(height: DeliverySpacing.md),
        Text(t.svcDocsTitle, style: _titleStyle),
        const SizedBox(height: DeliverySpacing.lg),
        if (_error != null) ...<Widget>[
          SoftNote(text: _error!, accent: DeliveryAccent.critical, icon: Icons.error_outline),
          const SizedBox(height: DeliverySpacing.md),
        ],
        ApplicationDocumentsStep(
          kinds: expectedDocumentKinds(rider: false),
          picked: _pickedDocs,
          enabled: !_busy,
          intro: t.svcDocsIntro,
          footnote: t.svcDocsFootnote,
          pick: widget.pickDocument,
          onPicked: (ApplicantDocumentKind kind, PickedDocument document) =>
              setState(() => _pickedDocs[kind] = document),
          onRemoved: (ApplicantDocumentKind kind) => setState(() => _pickedDocs.remove(kind)),
        ),
      ],
    );
  }

  /// Applied. Pending and approved are said as what they are: a pending provider cannot sell yet,
  /// and an approved one's shop is opened from here, on their first visit to it.
  Widget _done(DeliveryStrings t) {
    final AuthSession session = _session!;
    final bool approved = _approved(session);
    final String? email = _forAccount ? (session.email ?? widget.account!.email) : _verifiedEmail;
    final OnboardingStatus? status = _receipt?.status;

    return ListView(
      padding: const EdgeInsets.all(DeliverySpacing.lg),
      children: <Widget>[
        const SizedBox(height: DeliverySpacing.xl),
        _StateTile(icon: approved ? Icons.verified_outlined : Icons.hourglass_top_rounded),
        const SizedBox(height: DeliverySpacing.md),
        Text(approved ? t.svcApprovedTitle : t.svcPendingTitle, style: _titleStyle),
        const SizedBox(height: DeliverySpacing.sm),
        Text(
          approved
              ? t.svcApprovedBody
              : (email == null || email.isEmpty ? t.svcPendingBodyNoEmail : t.svcPendingBody(email)),
          style: _bodyStyle,
        ),
        if (!approved) ...<Widget>[
          const SizedBox(height: DeliverySpacing.lg),
          if (status == OnboardingStatus.submitted || status == OnboardingStatus.inReview) ...<Widget>[
            Text(
              status == OnboardingStatus.inReview ? t.statusInReview : t.statusSubmitted,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.ink,
              ),
            ),
            const SizedBox(height: DeliverySpacing.xs),
          ],
          if (_reference != null)
            Text(
              t.svcReference(_reference!),
              style: const TextStyle(fontSize: 13, color: DeliveryColors.muted),
            ),
          const SizedBox(height: DeliverySpacing.md),
          // What happened on the documents step, and nothing about a place to add them later: there
          // is none in the app for a waiting provider.
          SoftNote(
            text: _sentDocs.isEmpty ? t.svcDocsSkipped : t.svcDocsSent,
            icon: Icons.badge_outlined,
          ),
        ],
      ],
    );
  }

  Widget _bottomAction(DeliveryStrings t) {
    switch (_phase) {
      case _Phase.form:
        return AuthPrimaryButton(
          label: t.svcApplyCta,
          busy: _busy,
          onPressed: _busy || !_formComplete ? null : _apply,
        );
      case _Phase.verifyEmail:
        return AuthPrimaryButton(
          label: t.verify,
          busy: _busy,
          onPressed:
              _busy || _emailCode.text.length != OneTimeCodeField.length ? null : _confirmEmail,
        );
      case _Phase.verifyPhone:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AuthPrimaryButton(
              label: t.verify,
              busy: _busy,
              onPressed:
                  _busy || _phoneCode.text.length != OneTimeCodeField.length ? null : _confirmPhone,
            ),
            const SizedBox(height: DeliverySpacing.sm),
            Center(
              child: TextButton(
                onPressed: _busy ? null : _skipPhone,
                child: Text(t.skipThis),
              ),
            ),
          ],
        );
      case _Phase.sending:
        if (_error == null) return const SizedBox.shrink();
        return _applicationClosed
            ? AuthPrimaryButton(label: t.close, onPressed: widget.onClose)
            : AuthPrimaryButton(label: t.tryAgain, busy: _busy, onPressed: _busy ? null : _send);
      case _Phase.documents:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AuthPrimaryButton(
              label: t.svcDocsSend,
              busy: _busy,
              onPressed: _busy || _pickedDocs.isEmpty ? null : _sendDocuments,
            ),
            const SizedBox(height: DeliverySpacing.sm),
            Center(
              child: TextButton(
                onPressed: _busy ? null : _skipDocuments,
                child: Text(t.skipThis),
              ),
            ),
          ],
        );
      case _Phase.done:
        return AuthPrimaryButton(
          label: t.continueLabel,
          onPressed: () => widget.onFinished(_session!),
        );
    }
  }

  static const TextStyle _titleStyle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: DeliveryColors.ink,
    height: 1.25,
  );

  static const TextStyle _bodyStyle = TextStyle(
    fontSize: 14,
    color: DeliveryColors.muted,
    height: 20 / 14,
  );
}

/// The frame's "Lebanese Merchant Services" card, with its copy made true (see the screen's doc).
///
/// The frame's illustration is an image asset; a brand tile with a storefront glyph stands in for it,
/// the way the partner cards draw their roles.
class _ServicesBanner extends StatelessWidget {
  const _ServicesBanner();

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return YdCard(
      color: DeliveryColors.brandSoft,
      radius: DeliveryRadius.lg,
      padding: const EdgeInsets.all(DeliverySpacing.md),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  t.svcSignupBannerTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.brand,
                  ),
                ),
                const SizedBox(height: DeliverySpacing.xs),
                Text(
                  t.svcSignupBannerBody,
                  style: const TextStyle(fontSize: 11, color: DeliveryColors.muted, height: 16 / 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.md),
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: DeliveryColors.brand,
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
            ),
            child: const Icon(Icons.storefront_outlined, size: 32, color: DeliveryColors.white),
          ),
        ],
      ),
    );
  }
}

/// The 64px tile that heads the code, documents, pending and approved states.
class _StateTile extends StatelessWidget {
  const _StateTile({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: DeliveryColors.brandSoft,
          borderRadius: BorderRadius.circular(DeliveryRadius.sheet),
        ),
        child: Icon(icon, size: 32, color: DeliveryColors.brand),
      ),
    );
  }
}
