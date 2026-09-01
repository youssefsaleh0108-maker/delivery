import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'application_documents_step.dart';
import 'one_time_code.dart';
import 'passcode_pad.dart';
import 'payout_details_step.dart';
// For the OpenStreetMap tile template, user agent and attribution, which every map in this app
// draws from the same three constants — a second spelling of the tile URL is how one surface ends
// up quietly violating the tile policy the others honour.
import 'rider_job_card.dart';

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

  /// A delivery company (Figma 86:*): brings a fleet and dispatches YouDrop orders. A business
  /// applicant like the merchant — same documents, same payout — with the fleet's own step.
  carrier,
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
    required this.documentsApi,
    required this.kind,
    required this.authService,
    required this.onSignedIn,
    required this.onClose,
    this.onLogIn,
  });

  final OnboardingApi api;

  /// Where the collected documents and bank details go once the account exists. The server only
  /// takes them from a signed-in applicant, so the wizard holds everything until after
  /// [_PartnerApplicationScreenState._finishAccount] has produced a session.
  final DocumentsApi documentsApi;

  final PartnerKind kind;

  /// Applying now ends in a session: the applicant chose a passcode on the first step and is
  /// signed straight in, so this screen needs the same two things the sign-up screen does.
  final AuthService authService;
  final void Function(AuthSession session) onSignedIn;

  final VoidCallback onClose;

  /// Leaves the application flow for Sign In — the carrier intro's "Already a partner?" line
  /// (86:15). Null keeps the line off that screen.
  final VoidCallback? onLogIn;

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

  /// Where on the map the applicant said they will work, or null while they have not said.
  ///
  /// Null is the resting state and stays null unless the applicant deliberately taps the map: the
  /// wizard runs before there is an account, so there is no location permission to ask for, no
  /// stored address to read and no geocoder to call (the geocoding endpoints are authenticated).
  /// A point is therefore only ever one the applicant chose with their own finger.
  LatLng? _workPin;

  /// Tiles that came back refused, and whether the picker has given up on them.
  int _mapTileFailures = 0;
  bool _mapTilesFailed = false;

  /// How many refusals before the map is replaced by the designed placeholder.
  static const int _mapTileFailureLimit = 6;

  // Merchant-only.
  _BusinessType? _businessType;
  final TextEditingController _accountHolder = TextEditingController();
  final TextEditingController _iban = TextEditingController();

  /// Files picked on the documents step, held until the account exists — the server only takes a
  /// document from a signed-in applicant, and there is no applicant until [_finishAccount].
  final Map<ApplicantDocumentKind, PickedDocument> _pickedDocs =
      <ApplicantDocumentKind, PickedDocument>{};

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

  /// The session, from the moment sign-in succeeds. Kept rather than handed straight to
  /// [PartnerApplicationScreen.onSignedIn] because the documents and bank details still have to
  /// travel on it first — and because a failure in that last stretch needs a "carry on anyway"
  /// that can still deliver the session.
  AuthSession? _session;

  /// Which late send failed after the account existed, in the applicant's language. Null when
  /// nothing has failed. The application and account are safe by then — this only decides the
  /// wording and whether the skip action shows.
  String? _collateralError;

  /// Whether that failure is one an applicant may walk away from.
  ///
  /// Bank details are: the payout step accepts both fields empty, so failing to send them is the
  /// same position as never having typed them. **Documents are not.** Identity is asked of every
  /// applicant and a rider's licence and vehicle papers are the point of the review, so offering
  /// "skip this" beside a failed document told people a required paper was optional — and it is
  /// the retry, not the skip, that gets their application looked at.
  bool _collateralSkippable = false;

  /// True once the bank details have been PUT, so a retry does not send them twice. (The PUT is
  /// idempotent anyway; this is about not re-reporting a step that already succeeded.)
  bool _payoutSent = false;

  bool get _isRider => widget.kind == PartnerKind.rider;

  bool get _isCarrier => widget.kind == PartnerKind.carrier;

  // ---------------------------------------------------------------- carrier answers

  /// The CR number the reviewer verifies against the registry.
  final TextEditingController _crNumber = TextEditingController();

  /// Operating hours as picked ranges, not typed text (86:127 draws dropdowns). The presets
  /// cover the shapes a Lebanese fleet actually runs; a reviewer reads them as prose either way.
  String _hoursWeekdays = '08:00 AM - 11:00 PM';
  String _hoursWeekends = '09:00 AM - 01:00 AM';
  static const List<String> _weekdayHourOptions = <String>[
    '07:00 AM - 10:00 PM', '08:00 AM - 11:00 PM', '09:00 AM - 12:00 AM',
    '24 hours',
  ];
  static const List<String> _weekendHourOptions = <String>[
    '09:00 AM - 01:00 AM', '10:00 AM - 12:00 AM', '24 hours', 'Closed',
  ];

  String _companyType = 'Registered LLC';
  static const List<String> _companyTypes = <String>[
    'Registered LLC', 'SARL', 'Sole proprietorship', 'Cooperative',
  ];

  String _fleetBand = '10 - 25 riders';
  static const List<String> _fleetBands = <String>[
    '1 - 9 riders', '10 - 25 riders', '26 - 60 riders', '60+ riders',
  ];

  static const List<String> _lebanonAreas = <String>[
    'Beirut', 'Mount Lebanon', 'North', 'South', 'Bekaa',
  ];
  final Set<String> _coverage = <String>{'Beirut', 'Mount Lebanon'};

  /// Vehicle counts, per the frame's steppers.
  final Map<String, int> _vehicles = <String, int>{
    'MOTORCYCLE': 0, 'CAR': 0, 'VAN': 0, 'TRUCK': 0,
  };

  final Set<String> _capabilities = <String>{'FOOD', 'GROCERY'};

  /// The partnership agreement tick — the carrier's submit stays disabled without it.
  bool _agreed = false;

  /// How the company wants to be paid (86:295): four radio cards, Fresh USD cash selected by
  /// default. Bank details are asked for only when the answer is the bank.
  String _payoutMethod = 'CASH';

  List<TextEditingController> get _allControllers => <TextEditingController>[
        _name, _business, _email, _emailCode, _phone, _phoneCode, _notes,
        _passcode, _dateOfBirth, _nationalId, _vehicleModel, _plate,
        _vehicleYear, _preferredArea, _accountHolder, _iban,
        _crNumber,
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
  /// Only the first step gates — plus the merchant's bank step, and only when something was
  /// typed there: the rest collect answers the server treats as optional, and a wizard that
  /// refuses to advance over an optional field is a wizard nobody finishes. The bank step is
  /// different because a half-answer or an IBAN that fails its own check digits must not travel;
  /// leaving both fields empty remains a deliberate skip.
  bool get _stepComplete {
    // The bank step's own rule, wherever it sits: merchant step 2, carrier step 3 — where the
    // carrier's also carries the agreement tick, without which there is nothing to submit.
    final int bankStep = _isCarrier ? 3 : 2;
    if (!_isRider && _step == bankStep) {
      final bool payoutOk = PayoutDetailsStep.complete(
        DeliveryStrings.of(context),
        accountHolder: _accountHolder.text,
        iban: _iban.text,
      );
      if (_isCarrier) {
        // The bank fields only exist when the bank is the chosen method; the other three
        // methods need nothing typed, and the agreement arms Submit either way.
        return (_payoutMethod == 'BANK' ? payoutOk : true) && _agreed;
      }
      return payoutOk;
    }
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

    if (_isCarrier) {
      put('crNumber', _crNumber.text);
      details['companyType'] = _companyType;
      details['fleetBand'] = _fleetBand;
      details['coverage'] = _coverage.toList();
      details['vehicles'] = Map<String, int>.of(_vehicles)
        ..removeWhere((String _, int count) => count == 0);
      put('hoursWeekdays', _hoursWeekdays);
      put('hoursWeekends', _hoursWeekends);
      details['capabilities'] = _capabilities.toList();
      details['payoutMethod'] = _payoutMethod;
      return details;
    }

    if (_isRider) {
      if (_vehicle != null) details['vehicleType'] = _vehicle!.wire;
      put('vehicleModel', _vehicleModel.text);
      put('plateNumber', _plate.text);
      put('vehicleYear', _vehicleYear.text);
      put('dateOfBirth', _dateOfBirth.text);
      put('nationalId', _nationalId.text);
      put('preferredArea', _preferredArea.text);
      // The pin, when there is one. Sent as numbers rather than a formatted string so a reviewer's
      // console can put it back on a map; absent entirely when the applicant never placed one,
      // because "no answer" and "0, 0" are different answers and the second is in the Atlantic.
      if (_workPin != null) {
        details['workLatitude'] = _workPin!.latitude;
        details['workLongitude'] = _workPin!.longitude;
      }
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
          : _isCarrier
              ? await widget.api.applyAsCarrier(
                  companyName: _business.text.trim(),
                  contactName: _name.text.trim(),
                  email: _verifiedEmail!,
                  emailVerificationToken: _emailToken!,
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
      _collateralError = null;
      _collateralSkippable = false;
    });
    try {
      if (!_accountCreated) {
        await widget.api.createApplicantAccount(
          reference: _reference!,
          password: _passcode.text,
        );
        _accountCreated = true;
      }
      _session ??= await widget.authService
          .signInWithPassword(_verifiedEmail!, _passcode.text);
    } catch (e, stack) {
      // Without this the cause never leaves the device: the screen says one sentence, and a
      // Keycloak refusal and a network failure look identical in it.
      debugPrint('APPLICANT SIGN-IN FAILED (accountCreated=$_accountCreated): $e');
      debugPrintStack(stackTrace: stack, label: 'applicant-sign-in');
      if (!mounted) return;
      setState(() {
        _busy = false;
        // Two genuinely different situations, and telling them apart is the difference between
        // "try again" and "stop typing, you already have an account".
        _error = _accountCreated
            ? '${t.accountReadySignInInstead} ${_messageFrom(e)}'
            : '${t.couldNotCreateSignIn} ${_messageFrom(e)}';
      });
      return;
    }

    // Signed in: the shared Dio now carries the applicant's token, so the documents and bank
    // details collected during the wizard can finally travel. Only what succeeds is forgotten;
    // anything that fails stays queued for the retry.
    final AuthSession session = _session!;
    final _CollateralFailure? failure = await _sendCollateral(t);
    if (!mounted) return;
    if (failure != null) {
      setState(() {
        _busy = false;
        _collateralError = failure.message;
        _collateralSkippable = failure.skippable;
        _error = failure.message;
      });
      return;
    }
    setState(() => _busy = false);
    widget.onSignedIn(session);
  }

  /// Uploads the picked documents and PUTs the bank details, now that a token exists.
  ///
  /// Returns what failed, or null when everything landed. Each document that lands is removed from
  /// [_pickedDocs] and the payout marked sent, so a retry only repeats what actually failed.
  ///
  /// Neither failure blocks the session — the pending screen can upload and correct all of it — but
  /// only one of them may be walked past here. See [_collateralSkippable].
  Future<_CollateralFailure?> _sendCollateral(DeliveryStrings t) async {
    bool documentFailed = false;
    String? documentReason;
    for (final MapEntry<ApplicantDocumentKind, PickedDocument> entry
        in List<MapEntry<ApplicantDocumentKind, PickedDocument>>.of(
            _pickedDocs.entries)) {
      try {
        await widget.documentsApi.upload(
          kind: entry.key,
          bytes: entry.value.bytes,
          contentType: entry.value.contentType,
        );
        _pickedDocs.remove(entry.key);
      } catch (e, stack) {
        debugPrint('APPLICANT DOCUMENT UPLOAD FAILED (${entry.key.wire}): $e');
        debugPrintStack(stackTrace: stack, label: 'applicant-document');
        documentFailed = true;
        // Kept so the note can say WHY, not just that it failed — a server "file too large" or a
        // network refusal read identically before, which made a retry a guess.
        documentReason = _messageFrom(e);
      }
    }
    // Not skippable: these are the papers the application is judged on.
    if (documentFailed) {
      return _CollateralFailure(
        documentReason == null || documentReason == t.thatDidNotGoThrough
            ? t.wizCouldNotSendDocuments
            : '${t.wizCouldNotSendDocuments} $documentReason',
        skippable: false,
      );
    }

    final bool hasPayout = _accountHolder.text.trim().isNotEmpty &&
        _iban.text.trim().isNotEmpty;
    if (hasPayout && !_payoutSent) {
      try {
        // As typed, spaces and all — the server normalises and runs its own mod-97 check.
        await widget.documentsApi.setMyPayout(
          accountHolder: _accountHolder.text.trim(),
          iban: _iban.text.trim(),
        );
        _payoutSent = true;
      } catch (e, stack) {
        debugPrint('APPLICANT PAYOUT SAVE FAILED: $e');
        debugPrintStack(stackTrace: stack, label: 'applicant-payout');
        // Skippable: the payout step accepts both fields empty, so failing to send them leaves the
        // applicant exactly where leaving them blank would have.
        return _CollateralFailure(t.wizCouldNotSendPayout, skippable: true);
      }
    }
    return null;
  }

  // ---------------------------------------------------------------- the screen

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    if (_phase == _Phase.intro) {
      return _Intro(
        isRider: _isRider,
        isCarrier: _isCarrier,
        onBack: widget.onClose,
        onStart: () => setState(() => _phase = _Phase.wizard),
        onLogIn: widget.onLogIn,
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
                        // Suppressed when it would repeat the finishing body's own sentence —
                        // a collateral failure is already fully described up there.
                        if (_error != null && _error != _collateralError) ...<Widget>[
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
          // The carrier frames label the advance "Continue", plain (86:59-86:295).
          label: _step + 1 == totalSteps
              ? t.authSubmitApplication
              : (_isCarrier ? t.continueLabel : t.authNext),
          trailingIcon: _isRider || _isCarrier || _step + 1 == totalSteps
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
        if (_error == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AuthPrimaryButton(
              label: t.tryAgain,
              busy: _busy,
              onPressed: _busy
                  ? null
                  : _reference == null
                      ? _send
                      : _finishAccount,
            ),
            // Only for a failure the applicant may actually walk away from — the bank details,
            // which the payout step lets them leave blank anyway. A failed document does not get a
            // skip: offering one beside a required paper says it was optional. See
            // [_collateralSkippable]. Either way the account exists and the pending screen can
            // send everything again, so nobody is held hostage by a flaky upload.
            if (_collateralError != null && _collateralSkippable && _session != null) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              Center(
                child: TextButton(
                  onPressed:
                      _busy ? null : () => widget.onSignedIn(_session!),
                  child: Text(t.skipThis),
                ),
              ),
            ],
          ],
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
    if (_isCarrier) {
      return switch (_step) {
        0 => t.carrCompanyInformation,
        1 => t.carrFleetDetails,
        2 => t.carrDocsTitle,
        _ => t.carrPayoutSetup,
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
    if (_isCarrier) {
      return switch (_step) {
        0 => t.carrCompanyInformationBlurb,
        1 => t.carrFleetDetailsBlurb,
        2 => t.authDocumentsBlurb,
        _ => t.carrPayoutSetupBlurb,
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
    if (_isCarrier) {
      return switch (_step) {
        0 => _carrierCompany(t),
        1 => _carrierFleet(t),
        2 => _documentsStep(t),
        _ => _carrierPayout(t),
      };
    }
    return switch (_step) {
      0 => _merchantBusiness(t),
      1 => _documentsStep(t),
      2 => _bankStep(t),
      _ => _review(t),
    };
  }

  // ---------------------------------------------------------------- carrier steps (Figma 86:*)

  /// Step 1: who the platform is signing with. The account block (name, email, passcode) is the
  /// same one every applicant fills; the company block is the carrier's own.
  List<Widget> _carrierCompany(DeliveryStrings t) => <Widget>[
        AuthField(
          label: t.carrCompanyName,
          hint: t.carrCompanyNameHint,
          controller: _business,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: DeliverySpacing.md),
        AuthField(
          label: t.carrCrNumber,
          hint: '1004562 / B',
          controller: _crNumber,
        ),
        const SizedBox(height: DeliverySpacing.md),
        _carrierDropdown(t.carrCompanyType, _companyTypes, _companyType,
            (String v) => setState(() => _companyType = v)),
        const SizedBox(height: DeliverySpacing.md),
        _carrierDropdown(t.carrFleetSizeBand, _fleetBands, _fleetBand,
            (String v) => setState(() => _fleetBand = v)),
        const SizedBox(height: DeliverySpacing.md),
        _fieldLabel(t.carrCoverageArea),
        const SizedBox(height: DeliverySpacing.sm),
        Wrap(
          spacing: DeliverySpacing.sm,
          runSpacing: DeliverySpacing.sm,
          children: <Widget>[
            for (final String area in _lebanonAreas)
              YdChip(
                label: area,
                selected: _coverage.contains(area),
                onTap: () => setState(() => _coverage.contains(area)
                    ? _coverage.remove(area)
                    : _coverage.add(area)),
              ),
          ],
        ),
        const SizedBox(height: DeliverySpacing.md),
        AuthField(
          label: t.carrContactPerson,
          hint: t.carrContactPersonHint,
          controller: _name,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: DeliverySpacing.md),
        // Phone before email, and "Business Email" last, as 86:59 orders the form.
        AuthField(
          label: t.authPhoneNumber,
          hint: t.carrPhoneHint,
          controller: _phone,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: DeliverySpacing.md),
        AuthField(
          label: t.carrBusinessEmail,
          hint: t.carrBusinessEmailHint,
          controller: _email,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: DeliverySpacing.md),
        _passcodeField(t),
      ];

  /// Step 2: the fleet itself — counts, hours, and what it can carry.
  List<Widget> _carrierFleet(DeliveryStrings t) => <Widget>[
        _fieldLabel(t.carrActiveVehicles.toUpperCase()),
        const SizedBox(height: DeliverySpacing.sm),
        _vehicleCounter(t.carrMotorcycles, Icons.two_wheeler, 'MOTORCYCLE'),
        _vehicleCounter(t.carrCars, Icons.directions_car_outlined, 'CAR'),
        _vehicleCounter(t.carrVans, Icons.airport_shuttle_outlined, 'VAN'),
        _vehicleCounter(t.carrTrucks, Icons.local_shipping_outlined, 'TRUCK'),
        const SizedBox(height: DeliverySpacing.md),
        _fieldLabel(t.carrOperatingHours.toUpperCase()),
        const SizedBox(height: DeliverySpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _carrierDropdown(t.carrWeekdays, _weekdayHourOptions,
                  _hoursWeekdays, (String v) => setState(() => _hoursWeekdays = v)),
            ),
            const SizedBox(width: DeliverySpacing.md),
            Expanded(
              child: _carrierDropdown(t.carrWeekends, _weekendHourOptions,
                  _hoursWeekends, (String v) => setState(() => _hoursWeekends = v)),
            ),
          ],
        ),
        const SizedBox(height: DeliverySpacing.md),
        _fieldLabel(t.carrCapabilities.toUpperCase()),
        const SizedBox(height: DeliverySpacing.sm),
        // One white card with hairline dividers, as the frame draws the toggle list.
        Container(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: DeliverySpacing.md, vertical: DeliverySpacing.xs),
          decoration: BoxDecoration(
            color: DeliveryColors.white,
            border: Border.all(color: DeliveryColors.border),
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
          ),
          child: Column(
            children: <Widget>[
              _capabilityRow(t.carrCapColdChain, 'COLD_CHAIN'),
              const Divider(height: 1, color: DeliveryColors.border),
              _capabilityRow(t.carrCapFood, 'FOOD'),
              const Divider(height: 1, color: DeliveryColors.border),
              _capabilityRow(t.carrCapGrocery, 'GROCERY'),
              const Divider(height: 1, color: DeliveryColors.border),
              _capabilityRow(t.carrCapPharmacy, 'PHARMACY'),
              const Divider(height: 1, color: DeliveryColors.border),
              _capabilityRow(t.carrCapParcel, 'PARCEL'),
              const Divider(height: 1, color: DeliveryColors.border),
              _capabilityRow(t.carrCapButler, 'BUTLER'),
            ],
          ),
        ),
      ];

  /// Step 4: how the company gets paid (86:295) — four payout-method cards, the bank fields only
  /// when the bank is the answer, the commission card, and the agreement tick that arms Submit.
  List<Widget> _carrierPayout(DeliveryStrings t) => <Widget>[
        _fieldLabel(t.carrPayoutMethod.toUpperCase()),
        const SizedBox(height: DeliverySpacing.sm),
        _payoutMethodCard(t.carrPayoutCash, t.carrPayoutCashBlurb,
            Icons.payments_outlined, 'CASH'),
        _payoutMethodCard(t.carrPayoutWhish, t.carrPayoutWhishBlurb,
            Icons.account_balance_wallet_outlined, 'WHISH'),
        _payoutMethodCard(t.carrPayoutOmt, t.carrPayoutOmtBlurb,
            Icons.storefront_outlined, 'OMT'),
        _payoutMethodCard(t.carrPayoutBank, t.carrPayoutBankBlurb,
            Icons.account_balance_outlined, 'BANK'),
        if (_payoutMethod == 'BANK') ...<Widget>[
          const SizedBox(height: DeliverySpacing.md),
          ..._bankStep(t),
        ],
        const SizedBox(height: DeliverySpacing.md),
        Container(
          padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
          decoration: BoxDecoration(
            color: DeliveryColors.brandSoft,
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
          ),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(t.carrCommissionRate,
                        style: const TextStyle(
                            fontSize: 13, color: DeliveryColors.muted)),
                  ),
                  Text(
                    // The platform's standing rate; the agreement below is what makes it binding.
                    t.carrFlatFee(15),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: DeliveryColors.brand,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(t.carrPayoutSchedule,
                        style: const TextStyle(
                            fontSize: 13, color: DeliveryColors.muted)),
                  ),
                  Text(t.carrEveryMonday,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: DeliverySpacing.md),
        Semantics(
          checked: _agreed,
          child: InkWell(
            onTap: () => setState(() => _agreed = !_agreed),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Checkbox(
                  value: _agreed,
                  activeColor: DeliveryColors.brand,
                  onChanged: (bool? v) => setState(() => _agreed = v ?? false),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      t.carrAgreement,
                      style: const TextStyle(
                          fontSize: 12.5,
                          color: DeliveryColors.muted,
                          height: 1.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ];

  Widget _fieldLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: DeliveryColors.muted,
          letterSpacing: 0.3,
          height: 1.3,
        ),
      );

  Widget _carrierDropdown(String label, List<String> options, String value,
      ValueChanged<String> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _fieldLabel(label),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: value,
          items: <DropdownMenuItem<String>>[
            for (final String option in options)
              DropdownMenuItem<String>(value: option, child: Text(option)),
          ],
          onChanged: (String? v) {
            if (v != null) onChanged(v);
          },
          decoration: const InputDecoration(isDense: true),
        ),
      ],
    );
  }

  Widget _vehicleCounter(String label, IconData icon, String key) {
    final int count = _vehicles[key] ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: DeliverySpacing.md, vertical: DeliverySpacing.sm),
        decoration: BoxDecoration(
          color: DeliveryColors.white,
          border: Border.all(color: DeliveryColors.border),
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20, color: DeliveryColors.muted),
            const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            IconButton(
              onPressed: count == 0
                  ? null
                  : () => setState(() => _vehicles[key] = count - 1),
              icon: const Icon(Icons.remove, size: 18),
            ),
            SizedBox(
              width: 28,
              child: Text('$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            IconButton(
              onPressed: count >= 999
                  ? null
                  : () => setState(() => _vehicles[key] = count + 1),
              icon: const Icon(Icons.add, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  /// One of the four payout radio cards (86:295): icon in a soft-red circle, bold title, muted
  /// subtitle, radio at the end; a crimson border when it is the chosen one.
  Widget _payoutMethodCard(
      String title, String blurb, IconData icon, String key) {
    final bool selected = _payoutMethod == key;
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: DeliveryColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
            side: BorderSide(
              color: selected ? DeliveryColors.brand : DeliveryColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => setState(() => _payoutMethod = key),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: DeliverySpacing.md, vertical: DeliverySpacing.sm),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: DeliveryColors.brandSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 18, color: DeliveryColors.brand),
                  ),
                  const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(title,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(blurb,
                            style: const TextStyle(
                                fontSize: 12,
                                color: DeliveryColors.muted,
                                height: 1.3)),
                      ],
                    ),
                  ),
                  Radio<String>(
                    value: key,
                    // ignore: deprecated_member_use
                    groupValue: _payoutMethod,
                    activeColor: DeliveryColors.brand,
                    // ignore: deprecated_member_use
                    onChanged: (String? v) =>
                        setState(() => _payoutMethod = v ?? _payoutMethod),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _capabilityRow(String label, String key) {
    final bool on = _capabilities.contains(key);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(label,
              style: const TextStyle(fontSize: 13.5, height: 1.3)),
        ),
        Switch(
          value: on,
          activeThumbColor: DeliveryColors.white,
          activeTrackColor: DeliveryColors.brand,
          onChanged: (bool v) => setState(
              () => v ? _capabilities.add(key) : _capabilities.remove(key)),
        ),
      ],
    );
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
        _workAreaPicker(t),
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
        AuthFieldLabel(label: t.authAvailableZones, uppercase: true),
        const SizedBox(height: DeliverySpacing.sm),
        // The design lists three named city zones to tick, and this list stays empty. Two separate
        // reasons, and neither of them is "not built yet", which is why the chip that used to sit
        // beside the label is gone.
        //
        // The first is reach: there IS a zone service (`GET /api/delivery-zones` returns the
        // platform's areas), and this wizard cannot read it — that endpoint is open to any
        // *signed-in* user, and an applicant has no account yet, because getting one is the thing
        // being asked for. product-service declares no permit-all list, so there is no anonymous
        // route to it either.
        //
        // The second outlasts the first: even signed in, there would be nothing to save the answer
        // to. Zones describe where a *customer* is, not where a rider works — no rider record on
        // this platform carries a zone, which is the same fact the Backoffice roster's dead "All
        // regions" filter reports from the other end. So this is not a picker waiting on a
        // release. The map pin above and the free-text area carry the answer, and the card says so
        // rather than promising a list that has nothing to be a list of.
        YdCard.bordered(
          child: YdEmptyState(
            icon: Icons.map_outlined,
            title: t.authZonesNoneToPickTitle,
            message: t.authZonesNoneToPickBlurb,
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

  /// `map-canvas-container` (Figma 22:624), as a real map with a pin the applicant places.
  ///
  /// The design's 180px hairlined box keeps its exact geometry; what changed is that the grid
  /// inside it is now OpenStreetMap. Tapping drops a pin, and the pin's coordinates travel in the
  /// application's `details` object beside the free-text area — a reviewer reading "Hamra" and a
  /// reviewer reading a point on a map are answering different questions, and the second one is
  /// answerable without knowing the city.
  ///
  /// **It opens on the world, not on a guess.** There is no signed-in account at this point in the
  /// wizard, so there is no saved address to read, no location permission that has been asked for,
  /// and no geocoder to call — the geocoding endpoints are authenticated. Opening the camera over
  /// a plausible-looking city would be the app asserting where somebody lives. The applicant
  /// navigates to their own area, which is a few gestures, and nothing is recorded until they tap.
  ///
  /// Tiles that will not come degrade to the same styled placeholder the step had before there was
  /// a map, so a rider applying on a bad connection never sees a broken grid.
  Widget _workAreaPicker(DeliveryStrings t) {
    if (_mapTilesFailed) {
      return AuthMapPlaceholder(label: t.authMapUnavailable);
    }

    final LatLng? pin = _workPin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: DeliveryColors.background,
            borderRadius: BorderRadius.circular(DeliveryRadius.lg),
            border: Border.all(color: DeliveryColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: FlutterMap(
                  options: MapOptions(
                    // A world view: the app knows nothing about this person yet and says nothing.
                    initialCenter: const LatLng(25, 15),
                    initialZoom: 1.5,
                    backgroundColor: DeliveryColors.background,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.drag |
                          InteractiveFlag.pinchZoom |
                          InteractiveFlag.pinchMove |
                          InteractiveFlag.doubleTapZoom,
                    ),
                    onTap: _busy
                        ? null
                        : (TapPosition _, LatLng point) =>
                            setState(() => _workPin = point),
                  ),
                  children: <Widget>[
                    TileLayer(
                      urlTemplate: riderOsmTileTemplate,
                      userAgentPackageName: riderOsmUserAgent,
                      maxNativeZoom: 19,
                      errorTileCallback: (_, __, ___) => _noteMapTileFailure(),
                    ),
                    if (pin != null)
                      MarkerLayer(
                        markers: <Marker>[
                          Marker(
                            point: pin,
                            width: 32,
                            height: 32,
                            child: const Icon(Icons.place,
                                size: 32, color: DeliveryColors.brand),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              // Required by the OpenStreetMap tile policy on every map that draws its tiles.
              PositionedDirectional(
                bottom: 4,
                start: 6,
                child: Container(
                  padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: DeliveryColors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                  ),
                  child: const Text(
                    riderOsmAttribution,
                    style: TextStyle(
                      fontSize: 9,
                      color: DeliveryColors.muted,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: DeliverySpacing.sm),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                pin == null
                    ? t.authPinYourArea
                    : t.authPinnedAt(
                        pin.latitude.toStringAsFixed(4),
                        pin.longitude.toStringAsFixed(4),
                      ),
                style: const TextStyle(
                  fontSize: 12,
                  color: DeliveryColors.muted,
                  height: 1.4,
                ),
              ),
            ),
            if (pin != null)
              TextButton(
                onPressed: _busy ? null : () => setState(() => _workPin = null),
                style: TextButton.styleFrom(
                  foregroundColor: DeliveryColors.brand,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(t.authPinClear),
              ),
          ],
        ),
      ],
    );
  }

  /// One refused tile is weather; a run of them is an applicant with no usable connection.
  void _noteMapTileFailure() {
    if (_mapTilesFailed) return;
    _mapTileFailures++;
    if (_mapTileFailures < _mapTileFailureLimit) return;
    // The callback fires from inside the tile layer's own build and paint work.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _mapTilesFailed = true);
    });
  }

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

  // ---------------------------------------------------------------- documents and bank

  List<Widget> _documentsStep(DeliveryStrings t) => <Widget>[
        ApplicationDocumentsStep(
          kinds: expectedDocumentKinds(rider: _isRider, carrier: _isCarrier),
          picked: _pickedDocs,
          enabled: !_busy,
          onPicked: (ApplicantDocumentKind kind, PickedDocument document) =>
              setState(() => _pickedDocs[kind] = document),
          onRemoved: (ApplicantDocumentKind kind) =>
              setState(() => _pickedDocs.remove(kind)),
        ),
        // The frame's amber verification note: who reads the papers and how long it takes.
        if (_isCarrier) ...<Widget>[
          const SizedBox(height: DeliverySpacing.md),
          Container(
            padding: const EdgeInsets.all(DeliverySpacing.md),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E6),
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
              border: Border.all(color: const Color(0xFFF2DDAE)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.info_outline,
                    size: 18, color: Color(0xFFB07B0F)),
                const SizedBox(width: DeliverySpacing.sm),
                Expanded(
                  child: Text(
                    t.carrVerificationNote,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF7A5A12),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: DeliverySpacing.lg),
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
        PayoutDetailsStep(
          accountHolder: _accountHolder,
          iban: _iban,
          enabled: !_busy,
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
            message: _collateralError ??
                (_reference == null
                    ? t.authCouldNotSendApplication
                    : t.couldNotCreateSignIn),
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
    this.isCarrier = false,
    required this.onBack,
    required this.onStart,
    this.onLogIn,
  });

  final bool isRider;

  /// The third kind rides the business branch with its own words.
  final bool isCarrier;
  final VoidCallback onBack;
  final VoidCallback onStart;

  /// "Already a partner? Sign In" (86:15). Null leaves the line off — only the carrier frame
  /// draws it, and a link that silently went nowhere would be worse than none.
  final VoidCallback? onLogIn;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    final List<(IconData, String)> benefits = isRider
        ? <(IconData, String)>[
            (Icons.schedule, t.authRiderBenefitHours),
            (Icons.account_balance_wallet_outlined, t.authRiderBenefitPay),
            (Icons.navigation_outlined, t.authRiderBenefitNavigation),
          ]
        : isCarrier
            ? <(IconData, String)>[
                (Icons.markunread_mailbox_outlined, t.carrBenefitOrders),
                (Icons.location_on_outlined, t.carrBenefitTracking),
                (Icons.payments_outlined, t.carrBenefitPayouts),
              ]
            : <(IconData, String)>[
                (Icons.groups_outlined, t.authMerchantBenefitReach),
                (Icons.inventory_2_outlined, t.authMerchantBenefitManage),
                (Icons.bar_chart, t.authMerchantBenefitAnalytics),
              ];

    // The carrier frame gives each benefit a one-line description under its title; the rider and
    // merchant frames do not.
    final List<String> benefitBlurbs = isCarrier
        ? <String>[
            t.carrBenefitOrdersBlurb,
            t.carrBenefitTrackingBlurb,
            t.carrBenefitPayoutsBlurb,
          ]
        : const <String>[];

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
                      child: isRider || isCarrier
                          ? Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: DeliveryColors.brand,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Icon(
                                  isCarrier
                                      ? Icons.local_shipping_outlined
                                      : Icons.shopping_bag_outlined,
                                  size: 22,
                                  color: DeliveryColors.white),
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
                  // The frame's dark FOR CARRIERS pill, identifying the flow above the headline.
                  if (isCarrier) ...<Widget>[
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                        padding: const EdgeInsetsDirectional.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: DeliveryColors.ink,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          t.carrForCarriers.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: DeliveryColors.white,
                            letterSpacing: 1,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: DeliverySpacing.md),
                  ],
                  Text(
                    isCarrier ? t.carrPartnerTitle : (isRider ? t.authRiderIntroTitle : t.authMerchantIntroTitle),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: DeliveryColors.ink,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: DeliverySpacing.sm),
                  Text(
                    isCarrier ? t.carrPartnerBlurb : (isRider ? t.authRiderIntroBlurb : t.authMerchantIntroBlurb),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: DeliveryColors.muted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
                  // The carrier frame lays its three benefits straight on the white page, each a
                  // soft-pink tile with a red icon and a one-line description; the rider and
                  // merchant frames keep the pink card.
                  if (isCarrier)
                    for (int i = 0; i < benefits.length; i++) ...<Widget>[
                      if (i > 0) const SizedBox(height: DeliverySpacing.md),
                      _IntroRow(
                        icon: benefits[i].$1,
                        label: benefits[i].$2,
                        blurb: benefitBlurbs[i],
                        tileColor: DeliveryColors.brandSoft,
                        iconColor: DeliveryColors.brand,
                        bold: true,
                      ),
                    ]
                  else
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
                  // No "what you'll need" on the carrier frame — it goes straight to the CTA.
                  if (!isCarrier) ...<Widget>[
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  AuthPrimaryButton(
                    label: isCarrier ? t.carrRegisterCompany : t.authGetStarted,
                    height: 56,
                    onPressed: onStart,
                  ),
                  if (isCarrier && onLogIn != null) ...<Widget>[
                    const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                    Center(
                      child: AuthFooterLink(
                        question: t.carrAlreadyPartner,
                        action: t.authLogIn,
                        onTap: onLogIn,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of the intro's benefit or requirement lists: a small tinted tile, then the label —
/// and, on the carrier frame, a muted one-line description under it.
class _IntroRow extends StatelessWidget {
  const _IntroRow({
    required this.icon,
    required this.label,
    this.blurb,
    required this.tileColor,
    required this.iconColor,
    required this.bold,
  });

  final IconData icon;
  final String label;
  final String? blurb;
  final Color tileColor;
  final Color iconColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    // The two-line form gets the frame's larger rounded-square tile; the one-liner keeps its dot.
    final double tile = blurb != null ? 44 : (bold ? 28 : 24);
    return Row(
      crossAxisAlignment: blurb != null
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          width: tile,
          height: tile,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tileColor,
            borderRadius:
                BorderRadius.circular(blurb != null ? 14 : tile / 2),
          ),
          child: Icon(icon,
              size: blurb != null ? 20 : (bold ? 16 : 14), color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: blurb == null
              ? Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                    color: DeliveryColors.ink,
                    height: 1.5,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.ink,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      blurb!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: DeliveryColors.muted,
                        height: 18 / 13,
                      ),
                    ),
                  ],
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

/// A late send that failed after the account already existed, and whether it may be walked past.
///
/// The distinction is the whole reason this type exists rather than a bare string: both failures
/// leave the applicant signed in with an application on file, but only one of them is genuinely
/// optional. Bank details may be left blank at the payout step, so failing to send them is no
/// worse than never typing them. A document is what the application is judged on.
class _CollateralFailure {
  const _CollateralFailure(this.message, {required this.skippable});

  /// The sentence to show, already in the applicant's language.
  final String message;

  /// Whether to offer "skip this" beside the retry.
  final bool skippable;
}
