import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'one_time_code.dart';
import 'passcode_pad.dart';

/// Applying to sell or to deliver, from inside the app and before having an account.
///
/// <p>Everything else in this app assumes a signed-in person. This screen cannot: getting an
/// account is the thing being asked for. So it runs on the open endpoints — the public list of
/// companies that are hiring, and the verification pair — and the proof it collects is what stands
/// in for a token. Nobody has to create an account to apply; one is created for them if they are
/// approved.
///
/// <p><strong>The redesign's shape.</strong> Figma draws an intro (`rider-signup-intro` 22:336,
/// `merchant-signup-intro` 22:805) and then a four-step wizard with a progress bar. The steps
/// differ by kind — a rider gives vehicle and delivery zone, a merchant business type — so this is
/// no longer one form with a varying first page but two step lists sharing one engine, one
/// submission and one account creation.
///
/// <p><strong>What the design does not draw, and why it is still here.</strong> The wizard collects
/// a password on its first step and ends at "Submit Application"; the server needs a *verified*
/// address before it will take an application at all. So submitting runs the verification the
/// design omits — the one-time code, in the OTP screen's own cell style — and only then posts.
/// Dropping it would mean an application the server refuses, or an account on an address nobody
/// owns. The phone round is run the same way and only when a number was actually typed.
///
/// <p>The new answers (vehicle, zone, date of birth, national id, business type) travel in the
/// application's `details` object, which the server has carried since the form outgrew its fixed
/// columns.
enum PartnerKind {
  /// A shop. Asks the platform for terms, and names no delivery company.
  merchant,

  /// A rider. Either applies to a delivery company, or to YouDrop's own fleet when no company
  /// is chosen — see [_PartnerApplicationScreenState._company].
  rider,
}

/// What a rider drives (Figma `vehicle-grid` 22:503).
///
/// The wire token is sent rather than the label: a reviewer in the backoffice must see the same
/// value whatever language the applicant's phone was in.
enum _Vehicle {
  motorcycle('MOTORCYCLE', Icons.two_wheeler),
  car('CAR', Icons.directions_car_outlined),
  bicycle('BICYCLE', Icons.pedal_bike_outlined),
  van('VAN', Icons.local_shipping_outlined);

  const _Vehicle(this.wire, this.icon);

  final String wire;
  final IconData icon;
}

/// What a merchant sells (Figma `field-Business Type` 22:910). Same wire-token reasoning.
enum _BusinessType {
  restaurant('RESTAURANT'),
  grocery('GROCERY'),
  pharmacy('PHARMACY'),
  bakery('BAKERY'),
  retail('RETAIL'),
  other('OTHER');

  const _BusinessType(this.wire);

  final String wire;
}

/// Where the applicant is in the flow.
enum _Phase {
  /// The design's marketing page — what you get, what you need, Get Started.
  intro,

  /// The four drawn steps.
  wizard,

  /// The code that proves the address. Required by the server, not drawn by the design.
  verifyEmail,

  /// The same for a number, and only when one was typed.
  verifyPhone,

  /// Posting, creating the account and signing in.
  finishing,
}

class PartnerApplicationScreen extends StatefulWidget {
  const PartnerApplicationScreen({
    super.key,
    required this.api,
    required this.kind,
    required this.authService,
    required this.onSignedIn,
    required this.onClose,
  });

  final OnboardingApi api;
  final PartnerKind kind;

  /// Applying now ends in a session: the applicant chose a passcode on the first step and is
  /// signed straight in, so this screen needs the same two things the sign-up screen does.
  final AuthService authService;
  final void Function(AuthSession session) onSignedIn;

  final VoidCallback onClose;

  @override
  State<PartnerApplicationScreen> createState() =>
      _PartnerApplicationScreenState();
}

class _PartnerApplicationScreenState extends State<PartnerApplicationScreen> {
  // ---------------------------------------------------------------- what is being collected

  final TextEditingController _name = TextEditingController();
  final TextEditingController _business = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _emailCode = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _phoneCode = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  final TextEditingController _passcode = TextEditingController();

  // Rider-only.
  final TextEditingController _dateOfBirth = TextEditingController();
  final TextEditingController _nationalId = TextEditingController();
  final TextEditingController _vehicleModel = TextEditingController();
  final TextEditingController _plate = TextEditingController();
  final TextEditingController _vehicleYear = TextEditingController();
  final TextEditingController _preferredArea = TextEditingController();
  _Vehicle? _vehicle;

  // Merchant-only.
  _BusinessType? _businessType;

  late Future<List<HiringCompany>> _companies = widget.api.hiringCompanies();

  _Phase _phase = _Phase.intro;
  int _step = 0;

  static const int totalSteps = 4;

  /// The delivery company a rider chose, or null for YouDrop's own fleet.
  ///
  /// Null is a real answer here, not "not yet decided" — [_ridesForUs] is what separates the two,
  /// so that continuing without a company is a deliberate choice rather than a skipped step.
  HiringCompany? _company;

  /// True once a rider has picked YouDrop rather than one of the companies.
  bool _ridesForUs = false;

  String? _emailToken;
  String? _verifiedEmail;
  String? _phoneToken;
  String? _verifiedPhone;
  bool _busy = false;
  String? _error;
  String? _reference;

  /// True once the account exists. Creating it is not retryable — the server refuses a second
  /// sign-in for one application — so a later failure must retry the sign-in alone.
  bool _accountCreated = false;

  bool get _isRider => widget.kind == PartnerKind.rider;

  List<TextEditingController> get _allControllers => <TextEditingController>[
        _name, _business, _email, _emailCode, _phone, _phoneCode, _notes,
        _passcode, _dateOfBirth, _nationalId, _vehicleModel, _plate,
        _vehicleYear, _preferredArea,
      ];

  @override
  void initState() {
    super.initState();
    for (final TextEditingController c in _allControllers) {
      c.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final TextEditingController c in _allControllers) {
      c.removeListener(_refresh);
      c.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------- moving through it

  /// Whether the current step has everything it needs.
  ///
  /// Only the first step gates: the rest collect answers the server treats as optional, and a
  /// wizard that refuses to advance over an optional field is a wizard nobody finishes.
  bool get _stepComplete {
    if (_step != 0) return true;
    final bool identity = _name.text.trim().isNotEmpty &&
        _email.text.trim().contains('@') &&
        _passcode.text.length == PasscodePad.passcodeLength;
    return _isRider ? identity : identity && _business.text.trim().isNotEmpty;
  }

  void _next() {
    if (_step + 1 < totalSteps) {
      setState(() {
        _error = null;
        _step++;
      });
    } else {
      _beginSubmit();
    }
  }

  void _back() {
    switch (_phase) {
      case _Phase.intro:
        widget.onClose();
      case _Phase.wizard:
        if (_step == 0) {
          setState(() => _phase = _Phase.intro);
        } else {
          setState(() {
            _error = null;
            _step--;
          });
        }
      case _Phase.verifyEmail:
        setState(() {
          _error = null;
          _emailCode.clear();
          _phase = _Phase.wizard;
        });
      case _Phase.verifyPhone:
        setState(() {
          _error = null;
          _phoneCode.clear();
          _phase = _Phase.verifyEmail;
        });
      case _Phase.finishing:
        // Nothing to go back to: the application is in and the account may already exist.
        break;
    }
  }

  // ---------------------------------------------------------------- the calls

  /// The server's own words where it has any — they are written to be acted on.
  String _messageFrom(Object e) {
    if (e is DioException) {
      final Object? body = e.response?.data;
      if (body is Map && body['message'] is String) return body['message'] as String;
    }
    return DeliveryStrings.of(context).thatDidNotGoThrough;
  }

  Future<void> _sendCode(String channel, String destination) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.requestCode(channel, destination);
    } catch (e) {
      if (mounted) setState(() => _error = _messageFrom(e));
      rethrow;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Leaves the wizard for the verification the server insists on.
  Future<void> _beginSubmit() async {
    try {
      await _sendCode('EMAIL', _email.text.trim());
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() => _phase = _Phase.verifyEmail);
  }

  Future<void> _confirmEmail() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ({String token, String destination}) result = await widget.api
          .confirmCode('EMAIL', _email.text.trim(), _emailCode.text.trim());
      // The server's spelling, not what was typed. The application has to carry exactly what was
      // verified or it is refused for a reason nobody can see on screen.
      _verifiedEmail = result.destination;
      _emailToken = result.token;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFrom(e);
        _emailCode.clear();
      });
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    if (_phone.text.trim().isEmpty) {
      await _send();
      return;
    }
    try {
      await _sendCode('PHONE', _phone.text.trim());
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() => _phase = _Phase.verifyPhone);
  }

  Future<void> _confirmPhone() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ({String token, String destination}) result = await widget.api
          .confirmCode('PHONE', _phone.text.trim(), _phoneCode.text.trim());
      _verifiedPhone = result.destination;
      _phoneToken = result.token;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFrom(e);
        _phoneCode.clear();
      });
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _send();
  }

  /// Carries on without the number. Anything typed is dropped along with any proof: a number left
  /// in the field but not verified would be submitted unverified and refused by the server.
  Future<void> _skipPhone() async {
    _phone.clear();
    _verifiedPhone = null;
    _phoneToken = null;
    await _send();
  }

  /// The wizard's free-form answers, flattened for a reviewer to read.
  Map<String, dynamic> get _details {
    final Map<String, dynamic> details = <String, dynamic>{};
    void put(String key, String value) {
      if (value.trim().isNotEmpty) details[key] = value.trim();
    }

    if (_isRider) {
      if (_vehicle != null) details['vehicleType'] = _vehicle!.wire;
      put('vehicleModel', _vehicleModel.text);
      put('plateNumber', _plate.text);
      put('vehicleYear', _vehicleYear.text);
      put('dateOfBirth', _dateOfBirth.text);
      put('nationalId', _nationalId.text);
      put('preferredArea', _preferredArea.text);
      details['ridesFor'] = _company == null ? 'YOUDROP' : _company!.name;
    } else {
      if (_businessType != null) {
        details['businessType'] = _businessType!.wire;
      }
    }
    return details;
  }

  /// Posts the application, then creates the account and signs in.
  Future<void> _send() async {
    setState(() {
      _phase = _Phase.finishing;
      _busy = true;
      _error = null;
    });
    try {
      _reference ??= _isRider
          ? await widget.api.applyAsRider(
              name: _name.text.trim(),
              email: _verifiedEmail!,
              emailVerificationToken: _emailToken!,
              // Null when they chose us. The server reads that as an application to YouDrop's own
              // fleet and routes it to the backoffice rather than to a company.
              companyId: _company?.id,
              phone: _verifiedPhone,
              phoneVerificationToken: _phoneToken,
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              details: _details,
            )
          : await widget.api.applyAsMerchant(
              businessName: _business.text.trim(),
              contactName: _name.text.trim(),
              email: _verifiedEmail!,
              emailVerificationToken: _emailToken!,
              phone: _verifiedPhone,
              phoneVerificationToken: _phoneToken,
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              details: _details,
            );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFrom(e);
      });
      return;
    }
    await _finishAccount();
  }

  /// Creates the applicant's account and signs them in with the passcode they chose on step one.
  ///
  /// The two halves are tracked separately. The account is created ONCE — retrying its creation
  /// fails, because the application already has a sign-in — so a failure after that point must
  /// retry only the sign-in. Without that distinction a single hiccup left somebody tapping a
  /// button against a call that could never succeed again.
  Future<void> _finishAccount() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_accountCreated) {
        await widget.api.createApplicantAccount(
          reference: _reference!,
          password: _passcode.text,
        );
        _accountCreated = true;
      }
      final AuthSession session = await widget.authService
          .signInWithPassword(_verifiedEmail!, _passcode.text);
      widget.onSignedIn(session);
    } catch (e, stack) {
      // Without this the cause never leaves the device: the screen says one sentence, and a
      // Keycloak refusal and a network failure look identical in it.
      debugPrint('APPLICANT SIGN-IN FAILED (accountCreated=$_accountCreated): $e');
      debugPrintStack(stackTrace: stack, label: 'applicant-sign-in');
      if (!mounted) return;
      setState(() {
        // Two genuinely different situations, and telling them apart is the difference between
        // "try again" and "stop typing, you already have an account".
        _error = _accountCreated
            ? '${t.accountReadySignInInstead} ${_messageFrom(e)}'
            : '${t.couldNotCreateSignIn} ${_messageFrom(e)}';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------- the screen

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    if (_phase == _Phase.intro) {
      return _Intro(
        isRider: _isRider,
        onBack: widget.onClose,
        onStart: () => setState(() => _phase = _Phase.wizard),
      );
    }

    final bool verifying =
        _phase == _Phase.verifyEmail || _phase == _Phase.verifyPhone;

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
                    padding: const EdgeInsets.all(DeliverySpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (_phase == _Phase.wizard) ...<Widget>[
                          AuthStepHeader(
                            step: _step + 1,
                            totalSteps: totalSteps,
                            stepLabel: '${t.authStep} ${_step + 1}/$totalSteps',
                            progressLabel: _isRider
                                ? null
                                : '${((_step + 1) * 100 / totalSteps).round()}% ${t.authComplete}',
                            segmented: !_isRider,
                            title: _stepTitle(t),
                            subtitle: _stepSubtitle(t),
                            onBack: _busy ? null : _back,
                            backSemanticLabel: t.back,
                          ),
                          const SizedBox(height: DeliverySpacing.lg),
                          ..._stepBody(t),
                        ] else if (verifying) ...<Widget>[
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: AuthBackButton(
                              onPressed: _busy ? null : _back,
                              semanticLabel: t.back,
                            ),
                          ),
                          const SizedBox(height: DeliverySpacing.md),
                          ..._verificationBody(t),
                        ] else
                          ..._finishingBody(t),
                        if (_error != null) ...<Widget>[
                          const SizedBox(height: DeliverySpacing.md),
                          AuthErrorNote(message: _error!),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      bottom: 20,
                      start: DeliverySpacing.lg,
                      end: DeliverySpacing.lg,
                    ),
                    child: _bottomAction(t),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomAction(DeliveryStrings t) {
    switch (_phase) {
      case _Phase.intro:
        return const SizedBox.shrink();
      case _Phase.wizard:
        return AuthPrimaryButton(
          label: _step + 1 == totalSteps ? t.authSubmitApplication : t.authNext,
          trailingIcon: _isRider || _step + 1 == totalSteps
              ? null
              : Icons.arrow_forward,
          busy: _busy,
          onPressed: _busy || !_stepComplete ? null : _next,
        );
      case _Phase.verifyEmail:
        return AuthPrimaryButton(
          label: t.verify,
          busy: _busy,
          onPressed: _busy || _emailCode.text.length != OneTimeCodeField.length
              ? null
              : _confirmEmail,
        );
      case _Phase.verifyPhone:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AuthPrimaryButton(
              label: t.verify,
              busy: _busy,
              onPressed:
                  _busy || _phoneCode.text.length != OneTimeCodeField.length
                      ? null
                      : _confirmPhone,
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
      case _Phase.finishing:
        // Only reachable after a failure — success leaves this screen entirely.
        return _error == null
            ? const SizedBox.shrink()
            : AuthPrimaryButton(
                label: t.tryAgain,
                busy: _busy,
                onPressed: _busy
                    ? null
                    : _reference == null
                        ? _send
                        : _finishAccount,
              );
    }
  }

  // ---------------------------------------------------------------- step copy

  String _stepTitle(DeliveryStrings t) {
    if (_isRider) {
      return switch (_step) {
        0 => t.authPersonalInformation,
        1 => t.authVehicleDetails,
        2 => t.authDocuments,
        _ => t.authSelectDeliveryZone,
      };
    }
    return switch (_step) {
      0 => t.authBusinessInformation,
      1 => t.authDocuments,
      2 => t.authBankDetails,
      _ => t.authReviewAndSubmit,
    };
  }

  String _stepSubtitle(DeliveryStrings t) {
    if (_isRider) {
      return switch (_step) {
        0 => t.authPersonalInformationBlurb,
        1 => t.authVehicleDetailsBlurb,
        2 => t.authDocumentsBlurb,
        _ => t.authSelectDeliveryZoneBlurb,
      };
    }
    return switch (_step) {
      0 => t.authBusinessInformationBlurb,
      1 => t.authDocumentsBlurb,
      2 => t.authBankDetailsBlurb,
      _ => t.authReviewAndSubmitBlurb,
    };
  }

  List<Widget> _stepBody(DeliveryStrings t) {
    if (_isRider) {
      return switch (_step) {
        0 => _riderPersonal(t),
        1 => _riderVehicle(t),
        2 => _documentsStep(t),
        _ => _riderZone(t),
      };
    }
    return switch (_step) {
      0 => _merchantBusiness(t),
      1 => _documentsStep(t),
      2 => _bankStep(t),
      _ => _review(t),
    };
  }

  // ---------------------------------------------------------------- rider steps

  List<Widget> _riderPersonal(DeliveryStrings t) => <Widget>[
        AuthField(
          label: t.authFullName,
          hint: t.authFullNameHint,
          controller: _name,
          icon: Icons.person_outline,
          enabled: !_busy,
          borderColor: DeliveryColors.border,
          uppercaseLabel: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.name],
        ),
        const SizedBox(height: 14),
        AuthField(
          label: t.authEmailAddress,
          hint: t.authEmailHint,
          controller: _email,
          icon: Icons.mail_outline,
          enabled: !_busy,
          borderColor: DeliveryColors.border,
          uppercaseLabel: true,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.email],
        ),
        const SizedBox(height: 14),
        AuthField(
          label: t.authPhoneNumber,
          hint: t.authPhoneHint,
          controller: _phone,
          icon: Icons.phone_outlined,
          enabled: !_busy,
          borderColor: DeliveryColors.border,
          uppercaseLabel: true,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.telephoneNumber],
        ),
        const SizedBox(height: 14),
        _passcodeField(t),
        const SizedBox(height: 14),
        AuthField(
          label: t.authDateOfBirth,
          hint: t.authDateOfBirthHint,
          controller: _dateOfBirth,
          icon: Icons.calendar_today_outlined,
          enabled: !_busy,
          borderColor: DeliveryColors.border,
          uppercaseLabel: true,
          keyboardType: TextInputType.datetime,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        AuthField(
          label: t.authNationalId,
          hint: t.authNationalIdHint,
          controller: _nationalId,
          icon: Icons.badge_outlined,
          enabled: !_busy,
          borderColor: DeliveryColors.border,
          uppercaseLabel: true,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.done,
        ),
      ];

  List<Widget> _riderVehicle(DeliveryStrings t) => <Widget>[
        AuthFieldLabel(label: t.authVehicleType, uppercase: true),
        const SizedBox(height: DeliverySpacing.sm),
        for (int row = 0; row < 2; row++) ...<Widget>[
          if (row > 0) const SizedBox(height: 10),
          Row(
            children: <Widget>[
              for (int col = 0; col < 2; col++) ...<Widget>[
                if (col > 0) const SizedBox(width: 10),
                Expanded(
                  child: _VehicleTile(
                    vehicle: _Vehicle.values[row * 2 + col],
                    label: _vehicleLabel(t, _Vehicle.values[row * 2 + col]),
                    selected: _vehicle == _Vehicle.values[row * 2 + col],
                    onTap: _busy
                        ? null
                        : () => setState(
                            () => _vehicle = _Vehicle.values[row * 2 + col]),
                  ),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: DeliverySpacing.lg),
        AuthField(
          label: t.authVehicleModel,
          hint: t.authVehicleModelHint,
          controller: _vehicleModel,
          icon: Icons.settings_outlined,
          enabled: !_busy,
          borderColor: DeliveryColors.border,
          uppercaseLabel: true,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        AuthField(
          label: t.authPlateNumber,
          hint: t.authPlateNumberHint,
          controller: _plate,
          icon: Icons.credit_card_outlined,
          enabled: !_busy,
          borderColor: DeliveryColors.border,
          uppercaseLabel: true,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        AuthField(
          label: t.authVehicleYear,
          hint: t.authVehicleYearHint,
          controller: _vehicleYear,
          icon: Icons.calendar_today_outlined,
          enabled: !_busy,
          borderColor: DeliveryColors.border,
          uppercaseLabel: true,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          textInputAction: TextInputAction.done,
        ),
      ];

  List<Widget> _riderZone(DeliveryStrings t) => <Widget>[
        AuthMapPlaceholder(label: t.authMapComingSoon),
        const SizedBox(height: DeliverySpacing.lg),
        AuthField(
          label: t.authPreferredArea,
          hint: t.authPreferredAreaHint,
          controller: _preferredArea,
          icon: Icons.near_me_outlined,
          enabled: !_busy,
          borderColor: DeliveryColors.border,
          uppercaseLabel: true,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: DeliverySpacing.lg),
        Row(
          children: <Widget>[
            AuthFieldLabel(label: t.authAvailableZones, uppercase: true),
            const SizedBox(width: DeliverySpacing.sm),
            YdComingSoon(label: t.authComingSoon, icon: Icons.schedule),
          ],
        ),
        const SizedBox(height: DeliverySpacing.sm),
        // The design lists three named city zones to tick. There is no zone service behind them —
        // no geometry, no coverage map, nothing that would make the names true — so the list is an
        // empty state rather than three plausible-looking inventions. The free-text area above is
        // the real answer until it exists.
        YdCard.bordered(
          child: YdEmptyState(
            icon: Icons.map_outlined,
            title: t.authZonesComingSoonTitle,
            message: t.authZonesComingSoonBlurb,
            padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.sm),
          ),
        ),
        const SizedBox(height: DeliverySpacing.lg),
        // Kept from the flow this replaces, because it decides who reads the application: a rider
        // who names a company is that company's to hire, and one who does not is ours.
        AuthFieldLabel(label: t.whoWillYouRideFor, uppercase: true),
        const SizedBox(height: DeliverySpacing.sm),
        _companyPicker(t),
      ];

  Widget _companyPicker(DeliveryStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ChoiceRow(
          icon: Icons.verified_outlined,
          label: t.rideForYouDrop,
          blurb: t.rideForYouDropBlurb,
          selected: _ridesForUs,
          onTap: _busy
              ? null
              : () => setState(() {
                    _ridesForUs = true;
                    _company = null;
                  }),
        ),
        const SizedBox(height: DeliverySpacing.sm + 2),
        Text(
          t.theCompanyDecidesNotUs,
          style: const TextStyle(
            fontSize: 12,
            color: DeliveryColors.muted,
            height: 1.4,
          ),
        ),
        const SizedBox(height: DeliverySpacing.sm),
        FutureBuilder<List<HiringCompany>>(
          future: _companies,
          builder: (BuildContext context,
              AsyncSnapshot<List<HiringCompany>> snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(DeliverySpacing.lg),
                child: Center(
                    child:
                        CircularProgressIndicator(color: DeliveryColors.brand)),
              );
            }
            if (snapshot.hasError) {
              // Not fatal: riding for YouDrop is still available, so this reports the companies as
              // unavailable rather than blocking the step.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(t.couldNotLoadCompanies,
                      style: const TextStyle(
                          fontSize: 13, color: DeliveryColors.muted)),
                  const SizedBox(height: DeliverySpacing.sm),
                  OutlinedButton(
                    onPressed: () => setState(
                        () => _companies = widget.api.hiringCompanies()),
                    child: Text(t.tryAgain),
                  ),
                ],
              );
            }
            final List<HiringCompany> companies =
                snapshot.data ?? <HiringCompany>[];
            if (companies.isEmpty) {
              return Text(t.nobodyIsHiringRightNow,
                  style: const TextStyle(
                      fontSize: 13, color: DeliveryColors.muted));
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final HiringCompany company in companies) ...<Widget>[
                  _ChoiceRow(
                    icon: Icons.local_shipping_outlined,
                    label: company.name,
                    selected: _company?.id == company.id,
                    onTap: _busy
                        ? null
                        : () => setState(() {
                              _company = company;
                              _ridesForUs = false;
                            }),
                  ),
                  const SizedBox(height: DeliverySpacing.sm),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- merchant steps

  List<Widget> _merchantBusiness(DeliveryStrings t) => <Widget>[
        AuthField(
          label: t.authBusinessShopName,
          hint: t.authBusinessShopNameHint,
          controller: _business,
          enabled: !_busy,
          borderColor: DeliveryColors.border,
          labelColor: DeliveryColors.muted,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: DeliverySpacing.md),
        AuthField(
          label: t.authOwnerFullName,
          hint: t.authOwnerFullNameHint,
          controller: _name,
          enabled: !_busy,
          borderColor: DeliveryColors.border,
          labelColor: DeliveryColors.muted,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: DeliverySpacing.md),
        AuthPickerField(
          label: t.authBusinessType,
          hint: t.authBusinessTypeHint,
          value: _businessType == null
              ? null
              : _businessTypeLabel(t, _businessType!),
          options: <String>[
            for (final _BusinessType b in _BusinessType.values)
              _businessTypeLabel(t, b),
          ],
          enabled: !_busy,
          labelColor: DeliveryColors.muted,
          onSelected: (int i) =>
              setState(() => _businessType = _BusinessType.values[i]),
        ),
        const SizedBox(height: DeliverySpacing.md),
        AuthField(
          label: t.authContactEmail,
          hint: t.authEmailHint,
          controller: _email,
          enabled: !_busy,
          borderColor: DeliveryColors.border,
          labelColor: DeliveryColors.muted,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.email],
        ),
        const SizedBox(height: DeliverySpacing.md),
        AuthField(
          label: t.authPhoneNumber,
          hint: t.authPhoneHint,
          controller: _phone,
          enabled: !_busy,
          borderColor: DeliveryColors.border,
          labelColor: DeliveryColors.muted,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.telephoneNumber],
        ),
        const SizedBox(height: DeliverySpacing.md),
        _passcodeField(t, labelColor: DeliveryColors.muted, uppercase: false),
        const SizedBox(height: DeliverySpacing.md),
        SoftNote(text: t.finishSettingUpInTheApp, icon: Icons.info_outline),
      ];

  /// The final merchant step: what is about to be sent, and the one free-text field that has
  /// nowhere else to live now that the flow is four drawn steps.
  List<Widget> _review(DeliveryStrings t) => <Widget>[
        YdCard.bordered(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _ReviewRow(label: t.businessName, value: _business.text.trim()),
              _ReviewRow(label: t.yourNameAsOwner, value: _name.text.trim()),
              if (_businessType != null)
                _ReviewRow(
                  label: t.authBusinessType,
                  value: _businessTypeLabel(t, _businessType!),
                ),
              _ReviewRow(label: t.authContactEmail, value: _email.text.trim()),
              if (_phone.text.trim().isNotEmpty)
                _ReviewRow(
                    label: t.authPhoneNumber, value: _phone.text.trim()),
            ],
          ),
        ),
        const SizedBox(height: DeliverySpacing.md),
        AuthField(
          label: t.anythingWeShouldKnowMerchant,
          controller: _notes,
          enabled: !_busy,
          borderColor: DeliveryColors.border,
          labelColor: DeliveryColors.muted,
          maxLines: 3,
        ),
        const SizedBox(height: DeliverySpacing.md),
        SoftNote(text: t.guestApplicationExplainer, icon: Icons.person_outline),
      ];

  // ---------------------------------------------------------------- steps with no backend yet

  List<Widget> _documentsStep(DeliveryStrings t) => <Widget>[
        YdCard.bordered(
          child: YdEmptyState(
            icon: Icons.upload_file_outlined,
            title: t.authDocumentsComingSoonTitle,
            message: t.authDocumentsComingSoonBlurb,
            action: YdComingSoon(label: t.authComingSoon, icon: Icons.schedule),
          ),
        ),
        const SizedBox(height: DeliverySpacing.lg),
        // The one real thing this step can do while the upload pipeline is being built.
        AuthField(
          label: _isRider
              ? t.anythingWeShouldKnowRider
              : t.anythingWeShouldKnowMerchant,
          controller: _notes,
          enabled: !_busy,
          borderColor: DeliveryColors.border,
          uppercaseLabel: _isRider,
          labelColor: _isRider ? DeliveryColors.ink : DeliveryColors.muted,
          maxLines: 3,
        ),
      ];

  List<Widget> _bankStep(DeliveryStrings t) => <Widget>[
        YdCard.bordered(
          child: YdEmptyState(
            icon: Icons.account_balance_outlined,
            title: t.authBankComingSoonTitle,
            message: t.authBankComingSoonBlurb,
            action: YdComingSoon(label: t.authComingSoon, icon: Icons.schedule),
          ),
        ),
      ];

  // ---------------------------------------------------------------- verification & finishing

  List<Widget> _verificationBody(DeliveryStrings t) {
    final bool email = _phase == _Phase.verifyEmail;
    return <Widget>[
      Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: DeliveryColors.brandSoft,
          borderRadius: BorderRadius.circular(DeliveryRadius.sheet),
        ),
        child: Icon(
          email ? Icons.mark_email_unread_outlined : Icons.smartphone_outlined,
          size: 32,
          color: DeliveryColors.brand,
        ),
      ),
      const SizedBox(height: DeliverySpacing.md),
      Text(
        email ? t.authVerifyYourEmail : t.authVerifyYourNumber,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: DeliveryColors.ink,
          height: 1.25,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        t.codeSentTo(
            email ? _email.text.trim() : _phone.text.trim()),
        style: const TextStyle(
          fontSize: 14,
          color: DeliveryColors.muted,
          height: 18 / 14,
        ),
      ),
      const SizedBox(height: DeliverySpacing.lg),
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
          onTap: _busy
              ? null
              : () => _sendCode(email ? 'EMAIL' : 'PHONE',
                      email ? _email.text.trim() : _phone.text.trim())
                  .catchError((Object _) {}),
        ),
      ),
    ];
  }

  List<Widget> _finishingBody(DeliveryStrings t) => <Widget>[
        const SizedBox(height: DeliverySpacing.xxl),
        if (_error == null)
          const Center(
            child: CircularProgressIndicator(color: DeliveryColors.brand),
          )
        else
          YdEmptyState(
            icon: Icons.error_outline,
            title: t.thatDidNotGoThrough,
            message: _reference == null
                ? t.authCouldNotSendApplication
                : t.couldNotCreateSignIn,
          ),
        const SizedBox(height: DeliverySpacing.md),
        if (_error == null)
          Center(
            child: Text(
              t.authSendingApplication,
              style: const TextStyle(
                fontSize: 14,
                color: DeliveryColors.muted,
                height: 1.4,
              ),
            ),
          ),
      ];

  // ---------------------------------------------------------------- small shared pieces

  Widget _passcodeField(
    DeliveryStrings t, {
    Color labelColor = DeliveryColors.ink,
    bool uppercase = true,
  }) {
    return AuthField(
      label: t.password,
      hint: t.authPasscodeHint,
      controller: _passcode,
      icon: _isRider ? Icons.lock_outline : null,
      enabled: !_busy,
      obscure: true,
      borderColor: DeliveryColors.border,
      labelColor: labelColor,
      uppercaseLabel: uppercase,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      // The realm's credential is exactly six digits — see [PasscodePad.passcodeLength]. The
      // design draws a free password field; accepting one would create an account the sign-in
      // screen could never open.
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(PasscodePad.passcodeLength),
      ],
    );
  }

  String _vehicleLabel(DeliveryStrings t, _Vehicle v) => switch (v) {
        _Vehicle.motorcycle => t.authVehicleMotorcycle,
        _Vehicle.car => t.authVehicleCar,
        _Vehicle.bicycle => t.authVehicleBicycle,
        _Vehicle.van => t.authVehicleVan,
      };

  String _businessTypeLabel(DeliveryStrings t, _BusinessType b) => switch (b) {
        _BusinessType.restaurant => t.authBusinessTypeRestaurant,
        _BusinessType.grocery => t.authBusinessTypeGrocery,
        _BusinessType.pharmacy => t.authBusinessTypePharmacy,
        _BusinessType.bakery => t.authBusinessTypeBakery,
        _BusinessType.retail => t.authBusinessTypeRetail,
        _BusinessType.other => t.authBusinessTypeOther,
      };
}

// ------------------------------------------------------------------ the intro screens

/// `rider-signup-intro` (22:336) and `merchant-signup-intro` (22:805).
///
/// One widget for both: the frames differ in their copy, their glyphs and which tint they use for
/// the benefits card, and in nothing else. Both stray off the slate ramp onto gray-900/gray-500 and
/// onto two pinks the token layer does not carry; `tokens.dart` calls those design slips, so they
/// resolve to [DeliveryColors.ink], [DeliveryColors.muted] and [DeliveryColors.brandSoft] here.
class _Intro extends StatelessWidget {
  const _Intro({
    required this.isRider,
    required this.onBack,
    required this.onStart,
  });

  final bool isRider;
  final VoidCallback onBack;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    final List<(IconData, String)> benefits = isRider
        ? <(IconData, String)>[
            (Icons.schedule, t.authRiderBenefitHours),
            (Icons.account_balance_wallet_outlined, t.authRiderBenefitPay),
            (Icons.navigation_outlined, t.authRiderBenefitNavigation),
          ]
        : <(IconData, String)>[
            (Icons.groups_outlined, t.authMerchantBenefitReach),
            (Icons.inventory_2_outlined, t.authMerchantBenefitManage),
            (Icons.bar_chart, t.authMerchantBenefitAnalytics),
          ];

    final List<(IconData, String)> requirements = isRider
        ? <(IconData, String)>[
            (Icons.badge_outlined, t.authNeedValidId),
            (Icons.badge_outlined, t.authNeedDriversLicence),
            (Icons.description_outlined, t.authNeedVehicleDocuments),
          ]
        : <(IconData, String)>[
            (Icons.description_outlined, t.authNeedBusinessLicence),
            (Icons.description_outlined, t.authNeedTaxCertificate),
            (Icons.credit_card_outlined, t.authNeedBankDetails),
          ];

    return Scaffold(
      backgroundColor: DeliveryColors.white,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // The design's 64px top bar: a tinted back circle, the brand mark, a balancing spacer.
            Container(
              height: 64,
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: DeliverySpacing.md),
              child: Row(
                children: <Widget>[
                  AuthBackButton(
                    onPressed: onBack,
                    semanticLabel: t.back,
                    color: DeliveryColors.brandSoft,
                    borderColor: DeliveryColors.brandSoft,
                    iconColor: DeliveryColors.brand,
                  ),
                  Expanded(
                    child: Center(
                      child: isRider
                          ? Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: DeliveryColors.brand,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(Icons.shopping_bag_outlined,
                                  size: 22, color: DeliveryColors.white),
                            )
                          : Text(
                              t.authMerchantSignUp,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: DeliveryColors.ink,
                                height: 1.2,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox.square(dimension: AuthBackButton.dimension),
                ],
              ),
            ),
            const Divider(height: 1, color: DeliveryColors.brandSoft),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(DeliverySpacing.lg),
                children: <Widget>[
                  Text(
                    isRider ? t.authRiderIntroTitle : t.authMerchantIntroTitle,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: DeliveryColors.ink,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: DeliverySpacing.sm),
                  Text(
                    isRider ? t.authRiderIntroBlurb : t.authMerchantIntroBlurb,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: DeliveryColors.muted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
                  Container(
                    padding: const EdgeInsets.all(DeliverySpacing.md),
                    decoration: BoxDecoration(
                      color: DeliveryColors.brandSoft,
                      borderRadius:
                          BorderRadius.circular(DeliveryRadius.lg),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (!isRider) ...<Widget>[
                          Text(
                            t.authWhatYouGet,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: DeliveryColors.brand,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                        ],
                        for (int i = 0; i < benefits.length; i++) ...<Widget>[
                          if (i > 0)
                            const SizedBox(
                                height: DeliverySpacing.md - DeliverySpacing.xs),
                          _IntroRow(
                            icon: benefits[i].$1,
                            label: benefits[i].$2,
                            tileColor: DeliveryColors.brand,
                            iconColor: DeliveryColors.white,
                            bold: isRider,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
                  Text(
                    isRider ? t.authWhatYouNeedToSignUp : t.authWhatYouNeed,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: DeliveryColors.ink,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                  for (int i = 0; i < requirements.length; i++) ...<Widget>[
                    if (i > 0)
                      const SizedBox(
                          height: DeliverySpacing.md - DeliverySpacing.xs),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: DeliveryColors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: DeliveryColors.brandSoft),
                      ),
                      child: _IntroRow(
                        icon: requirements[i].$1,
                        label: requirements[i].$2,
                        tileColor: DeliveryColors.brandSoft,
                        iconColor: DeliveryColors.brand,
                        bold: true,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsetsDirectional.only(
                top: DeliverySpacing.md,
                bottom: DeliverySpacing.lg,
                start: DeliverySpacing.lg,
                end: DeliverySpacing.lg,
              ),
              decoration: const BoxDecoration(
                color: DeliveryColors.white,
                border: Border(
                    top: BorderSide(color: DeliveryColors.brandSoft)),
              ),
              child: AuthPrimaryButton(
                label: t.authGetStarted,
                height: 56,
                onPressed: onStart,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of the intro's benefit or requirement lists: a small tinted tile, then the label.
class _IntroRow extends StatelessWidget {
  const _IntroRow({
    required this.icon,
    required this.label,
    required this.tileColor,
    required this.iconColor,
    required this.bold,
  });

  final IconData icon;
  final String label;
  final Color tileColor;
  final Color iconColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final double tile = bold ? 28 : 24;
    return Row(
      children: <Widget>[
        Container(
          width: tile,
          height: tile,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tileColor,
            borderRadius: BorderRadius.circular(tile / 2),
          ),
          child: Icon(icon, size: bold ? 16 : 14, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              color: DeliveryColors.ink,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ selection controls

/// One of the four vehicle tiles (Figma 22:505): a square card that turns
/// [DeliveryColors.brandSoftStrong] behind a 2px brand border when it is the chosen one.
class _VehicleTile extends StatelessWidget {
  const _VehicleTile({
    required this.vehicle,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final _Vehicle vehicle;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color tint = selected ? DeliveryColors.brand : DeliveryColors.ink;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? DeliveryColors.brandSoftStrong : DeliveryColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.lg),
          side: BorderSide(
            color: selected ? DeliveryColors.brand : DeliveryColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(DeliverySpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(vehicle.icon, size: 24, color: tint),
                const SizedBox(height: DeliverySpacing.sm),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tint,
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

/// A tickable row in the design's zone-item shape (22:628): a 1.5px brand border and a filled
/// brand checkbox when chosen, a plain hairline and an empty box when not.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.blurb,
  });

  final IconData icon;
  final String label;
  final String? blurb;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: DeliveryColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          side: BorderSide(
            color: selected ? DeliveryColors.brand : DeliveryColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                Icon(icon,
                    size: 18,
                    color:
                        selected ? DeliveryColors.brand : DeliveryColors.faint),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          color: DeliveryColors.ink,
                          height: 1.3,
                        ),
                      ),
                      if (blurb != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          blurb!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: DeliveryColors.muted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: DeliverySpacing.sm),
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        selected ? DeliveryColors.brand : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: selected
                          ? DeliveryColors.brand
                          : DeliveryColors.faint,
                      width: selected ? 1 : 2,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check,
                          size: 12, color: DeliveryColors.white)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A label/value pair on the merchant's review step.
class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: DeliveryColors.muted,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.ink,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
