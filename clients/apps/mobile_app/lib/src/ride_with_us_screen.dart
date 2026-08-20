import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// Applying to ride for a delivery company, from inside the app and before having an account.
///
/// Everything else in this app assumes a signed-in person. This screen cannot: getting an account
/// is the thing being asked for. So it runs on the open endpoints — the public list of companies
/// that are hiring, and the verification pair — and the proof it collects is what stands in for a
/// token.
///
/// Steps rather than one long form, for the same reason the website has them: verifying an address
/// means leaving the app to fetch a code, and a form that asks for that has to hold its place while
/// somebody does.
class RideWithUsScreen extends StatefulWidget {
  const RideWithUsScreen({super.key, required this.api, required this.onClose});

  final OnboardingApi api;
  final VoidCallback onClose;

  @override
  State<RideWithUsScreen> createState() => _RideWithUsScreenState();
}

class _RideWithUsScreenState extends State<RideWithUsScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _emailCode = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _phoneCode = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  late Future<List<HiringCompany>> _companies = widget.api.hiringCompanies();

  int _step = 0;
  HiringCompany? _company;
  String? _emailToken;
  String? _verifiedEmail;
  String? _phoneToken;
  String? _verifiedPhone;
  bool _emailCodeSent = false;
  bool _phoneCodeSent = false;
  bool _busy = false;
  String? _error;
  String? _reference;

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _name, _email, _emailCode, _phone, _phoneCode, _notes
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.rideWithUs),
        leading: IconButton(
          onPressed: widget.onClose,
          icon: const Icon(Icons.close),
          tooltip: t.cancel,
        ),
      ),
      body: _reference != null
          ? _done(t)
          : ListView(
              padding: const EdgeInsets.all(DeliverySpacing.lg),
              children: <Widget>[
                _stepDots(),
                const SizedBox(height: DeliverySpacing.lg),
                switch (_step) {
                  0 => _chooseCompany(t),
                  1 => _aboutYou(t),
                  2 => _verifyEmail(t),
                  _ => _verifyPhone(t),
                },
                if (_error != null) ...<Widget>[
                  const SizedBox(height: DeliverySpacing.md),
                  SoftNote(text: _error!, accent: DeliveryAccent.critical,
                      icon: Icons.error_outline),
                ],
              ],
            ),
    );
  }

  Widget _stepDots() {
    return Row(
      children: <Widget>[
        for (int i = 0; i < 4; i++) ...<Widget>[
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i <= _step ? DeliveryColors.brand : DeliveryColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (i < 3) const SizedBox(width: 6),
        ],
      ],
    );
  }

  // ------------------------------------------------------------------ 1. company

  Widget _chooseCompany(DeliveryStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(t.whoWouldYouRideFor, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: DeliverySpacing.xs),
        // Said plainly at the start, because it is the thing most likely to be misunderstood: the
        // platform is not the employer here, and waiting on the wrong party is a bad surprise.
        Text(t.theCompanyDecidesNotUs, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: DeliverySpacing.lg),
        FutureBuilder<List<HiringCompany>>(
          future: _companies,
          builder: (BuildContext context, AsyncSnapshot<List<HiringCompany>> snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                  child: Padding(
                padding: EdgeInsets.all(DeliverySpacing.xl),
                child: CircularProgressIndicator(color: DeliveryColors.brand),
              ));
            }
            if (snapshot.hasError) {
              return Column(
                children: <Widget>[
                  Text(t.couldNotLoadCompanies, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: DeliverySpacing.sm),
                  OutlinedButton(
                    onPressed: () =>
                        setState(() => _companies = widget.api.hiringCompanies()),
                    child: Text(t.tryAgain),
                  ),
                ],
              );
            }
            final List<HiringCompany> companies = snapshot.data ?? <HiringCompany>[];
            if (companies.isEmpty) {
              return Text(t.nobodyIsHiringRightNow,
                  style: Theme.of(context).textTheme.bodyMedium);
            }
            return Column(
              children: <Widget>[
                for (final HiringCompany company in companies)
                  Padding(
                    padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
                    child: SoftCard(
                      selected: _company?.id == company.id,
                      onTap: () => setState(() => _company = company),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.local_shipping_outlined,
                              color: DeliveryColors.brand),
                          const SizedBox(width: DeliverySpacing.sm),
                          Expanded(
                            child: Text(company.name,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          if (_company?.id == company.id)
                            const Icon(Icons.check_circle, color: DeliveryColors.brand),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: DeliverySpacing.md),
        PrimaryAction(
          label: t.continueLabel,
          onPressed: _company == null ? null : () => setState(() => _step = 1),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ 2. you

  Widget _aboutYou(DeliveryStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(t.aboutYou, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: DeliverySpacing.lg),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: t.yourName),
        ),
        const SizedBox(height: DeliverySpacing.md),
        TextField(
          controller: _notes,
          maxLines: 3,
          decoration: InputDecoration(labelText: t.anythingWeShouldKnowRider),
        ),
        const SizedBox(height: DeliverySpacing.lg),
        Row(
          children: <Widget>[
            OutlinedButton(
                onPressed: () => setState(() => _step = 0), child: Text(t.back)),
            const SizedBox(width: DeliverySpacing.sm),
            Expanded(
              child: PrimaryAction(
                label: t.continueLabel,
                onPressed: _name.text.trim().isEmpty
                    ? null
                    : () => setState(() {
                          _error = null;
                          _step = 2;
                        }),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ 3 & 4. proving

  Widget _verifyEmail(DeliveryStrings t) => _verification(
        t,
        title: t.yourEmail,
        blurb: t.weSendACodeToCheckItReachesYou,
        field: _email,
        codeField: _emailCode,
        sent: _emailCodeSent,
        verified: _verifiedEmail != null,
        keyboard: TextInputType.emailAddress,
        onSend: () => _sendCode('EMAIL', _email, () => _emailCodeSent = true),
        onConfirm: () => _confirmCode('EMAIL', _email, _emailCode, (String d, String tok) {
          _verifiedEmail = d;
          _emailToken = tok;
        }),
        onBack: () => setState(() => _step = 1),
        onNext: _verifiedEmail == null ? null : () => setState(() => _step = 3),
      );

  Widget _verifyPhone(DeliveryStrings t) => _verification(
        t,
        title: t.yourPhoneOptional,
        blurb: t.aNumberHelpsWhenAnOrderNeedsSorting,
        field: _phone,
        codeField: _phoneCode,
        sent: _phoneCodeSent,
        verified: _verifiedPhone != null,
        keyboard: TextInputType.phone,
        onSend: () => _sendCode('PHONE', _phone, () => _phoneCodeSent = true),
        onConfirm: () => _confirmCode('PHONE', _phone, _phoneCode, (String d, String tok) {
          _verifiedPhone = d;
          _phoneToken = tok;
        }),
        onBack: () => setState(() => _step = 2),
        onNext: _verifiedPhone == null ? null : _submit,
        // Skipping clears anything typed as well as any proof: a number left in the field but not
        // verified would be submitted unverified and refused by the server.
        onSkip: () {
          _phone.clear();
          _verifiedPhone = null;
          _phoneToken = null;
          _submit();
        },
        submitLabel: t.sendApplication,
      );

  Widget _verification(
    DeliveryStrings t, {
    required String title,
    required String blurb,
    required TextEditingController field,
    required TextEditingController codeField,
    required bool sent,
    required bool verified,
    required TextInputType keyboard,
    required VoidCallback onSend,
    required VoidCallback onConfirm,
    required VoidCallback onBack,
    VoidCallback? onNext,
    VoidCallback? onSkip,
    String? submitLabel,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: DeliverySpacing.xs),
        Text(blurb, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: DeliverySpacing.lg),
        TextField(
          controller: field,
          keyboardType: keyboard,
          readOnly: verified,
          decoration: InputDecoration(
            labelText: title,
            suffixIcon: verified
                ? const Icon(Icons.verified_rounded, color: Color(0xFF25834B))
                : null,
          ),
        ),
        if (!verified) ...<Widget>[
          const SizedBox(height: DeliverySpacing.sm),
          OutlinedButton(
            onPressed: _busy ? null : onSend,
            child: Text(sent ? t.sendAnother : t.sendCode),
          ),
        ],
        if (sent && !verified) ...<Widget>[
          const SizedBox(height: DeliverySpacing.md),
          TextField(
            controller: codeField,
            keyboardType: TextInputType.number,
            autofillHints: const <String>[AutofillHints.oneTimeCode],
            maxLength: 6,
            decoration: InputDecoration(labelText: t.theCodeWeSent),
          ),
          PrimaryAction(label: t.verify, onPressed: _busy ? null : onConfirm, busy: _busy),
        ],
        const SizedBox(height: DeliverySpacing.lg),
        Row(
          children: <Widget>[
            OutlinedButton(onPressed: onBack, child: Text(t.back)),
            const SizedBox(width: DeliverySpacing.sm),
            if (onSkip != null) ...<Widget>[
              TextButton(onPressed: _busy ? null : onSkip, child: Text(t.skipThis)),
              const SizedBox(width: DeliverySpacing.sm),
            ],
            Expanded(
              child: PrimaryAction(
                label: submitLabel ?? t.continueLabel,
                onPressed: onNext,
                busy: _busy && onNext != null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ the calls

  Future<void> _sendCode(
      String channel, TextEditingController field, VoidCallback onSent) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.requestCode(channel, field.text.trim());
      setState(onSent);
    } catch (e) {
      setState(() => _error = _messageFrom(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmCode(String channel, TextEditingController field,
      TextEditingController codeField, void Function(String, String) onVerified) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ({String token, String destination}) result = await widget.api
          .confirmCode(channel, field.text.trim(), codeField.text.trim());
      setState(() {
        // The server's spelling, not what was typed. The application has to carry exactly what was
        // verified or it is refused for a reason nobody can see on screen.
        field.text = result.destination;
        onVerified(result.destination, result.token);
      });
    } catch (e) {
      setState(() => _error = _messageFrom(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final String reference = await widget.api.applyAsRider(
        name: _name.text.trim(),
        email: _verifiedEmail!,
        emailVerificationToken: _emailToken!,
        companyId: _company!.id,
        phone: _verifiedPhone,
        phoneVerificationToken: _phoneToken,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      setState(() => _reference = reference);
    } catch (e) {
      setState(() => _error = _messageFrom(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The server's own words where it has any — they are written to be acted on.
  String _messageFrom(Object e) {
    if (e is DioException) {
      final Object? body = e.response?.data;
      if (body is Map && body['message'] is String) return body['message'] as String;
    }
    return DeliveryStrings.of(context).thatDidNotGoThrough;
  }

  // ------------------------------------------------------------------ receipt

  Widget _done(DeliveryStrings t) {
    return ListView(
      padding: const EdgeInsets.all(DeliverySpacing.lg),
      children: <Widget>[
        const SizedBox(height: DeliverySpacing.xl),
        const Icon(Icons.check_circle, size: 56, color: Color(0xFF25834B)),
        const SizedBox(height: DeliverySpacing.md),
        Text(t.applicationSent, textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: DeliverySpacing.sm),
        Text(t.companyWillBeInTouch(_company!.name), textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: DeliverySpacing.lg),
        SoftCard(
          child: Column(
            children: <Widget>[
              Text(t.keepThisReference, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: DeliverySpacing.xs),
              SelectableText(_reference!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        const SizedBox(height: DeliverySpacing.lg),
        PrimaryAction(label: t.done, onPressed: widget.onClose),
      ],
    );
  }
}
