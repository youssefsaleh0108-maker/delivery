/// The bank step, in both of its lives — and the client half of the IBAN check.
///
/// <p>Like the documents, payout details can only reach the server once the applicant's account
/// exists (`PUT /applications/mine/payout` is resolved from the token). So the wizard's
/// [PayoutDetailsStep] collects and checks, the wizard sends after sign-in, and the pending
/// screen's [PayoutDetailsCard] reads the saved record back — masked — and lets it be corrected
/// for as long as the application is open.
///
/// <p>The mod-97 check here mirrors `com.delivery.onboarding.domain.Iban` deliberately, rule for
/// rule: normalise, bound the length, check the shape, check the registered length for known
/// countries, then the ISO 7064 checksum. The server's copy is the one that decides; this one
/// exists so a transposed digit is caught while the applicant is still looking at the field
/// rather than weeks later when the first payout bounces.
library;

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'one_time_code.dart';

// --------------------------------------------------------------------- the check

/// Registered IBAN lengths for the countries the platform pays into — the same table
/// `Iban.REGISTERED_LENGTHS` carries server-side. An unknown country falls back to the generic
/// 15–34 bounds rather than being refused, for the same reason the server does: the registry
/// gains entries, and refusing a country this map has not been updated for would be a rule about
/// this file rather than about the number.
const Map<String, int> _registeredIbanLengths = <String, int>{
  'EG': 29, 'SA': 24, 'AE': 23, 'JO': 30, 'KW': 30,
  'QA': 29, 'BH': 22, 'GB': 22, 'DE': 22, 'FR': 27,
};

/// Uppercase, no spaces or dashes — printed IBANs are grouped in fours and people paste them that
/// way, so a space is a formatting convention rather than a typo.
String normaliseIban(String raw) =>
    raw.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

/// Why a typed IBAN cannot be one, or null when every check holds.
///
/// The failure modes call for different corrections — a wrong shape means the wrong field was
/// pasted, a wrong length means a digit is missing, a failed checksum means one was mistyped — so
/// the message says which, exactly as the server's `InvalidIbanException` does.
String? ibanProblem(DeliveryStrings t, String raw) {
  final String iban = normaliseIban(raw);
  if (iban.length < 15 || iban.length > 34) {
    return t.wizPayoutIbanBounds;
  }
  if (!RegExp(r'^[A-Z]{2}[0-9]{2}[A-Z0-9]+$').hasMatch(iban)) {
    return t.wizPayoutIbanFormat;
  }
  final int? expected = _registeredIbanLengths[iban.substring(0, 2)];
  if (expected != null && iban.length != expected) {
    return t.wizPayoutIbanLength(iban.substring(0, 2), '$expected');
  }
  if (!ibanChecksumHolds(iban)) {
    return t.wizPayoutIbanInvalid;
  }
  return null;
}

/// The mod-97 check itself (ISO 7064 MOD 97-10), on an already-normalised number.
///
/// Move the first four characters to the end, replace each letter with two digits (A=10 … Z=35),
/// and the number is a valid IBAN exactly when the resulting integer leaves a remainder of 1 when
/// divided by 97. The server does this with one BigInteger; Dart's ints are 64-bit on mobile, so
/// this walks the digits keeping a running remainder — algebraically identical, because
/// `(a·10 + b) mod 97 = ((a mod 97)·10 + b) mod 97`.
bool ibanChecksumHolds(String iban) {
  final String rearranged = iban.substring(4) + iban.substring(0, 4);
  int remainder = 0;
  for (int i = 0; i < rearranged.length; i++) {
    final int code = rearranged.codeUnitAt(i);
    if (code >= 0x30 && code <= 0x39) {
      remainder = (remainder * 10 + (code - 0x30)) % 97;
    } else {
      // 'A' becomes 10 … 'Z' becomes 35 — two decimal digits, so the base shifts by 100.
      remainder = (remainder * 100 + (code - 0x41 + 10)) % 97;
    }
  }
  return remainder == 1;
}

/// The last four characters behind dots — what every surface other than the edit form shows.
/// Masked client-side for display only; the server never sent anything to "unmask".
String maskIban(String iban) {
  final String normalised = normaliseIban(iban);
  if (normalised.length <= 4) return normalised;
  return '•••• ${normalised.substring(normalised.length - 4)}';
}

/// The verification state in the reader's language. `checksumOnly` is the only state reachable
/// today — no payment processor is wired — and its label says what was actually checked.
String payoutStateLabel(DeliveryStrings t, PayoutVerificationState state) =>
    switch (state) {
      PayoutVerificationState.checksumOnly => t.payoutFormatChecked,
      PayoutVerificationState.verified => t.payoutVerified,
      PayoutVerificationState.failed => t.payoutFailedVerification,
    };

DeliveryAccent _payoutStateAccent(PayoutVerificationState state) => switch (state) {
      PayoutVerificationState.checksumOnly => DeliveryAccent.info,
      PayoutVerificationState.verified => DeliveryAccent.positive,
      PayoutVerificationState.failed => DeliveryAccent.critical,
    };

// --------------------------------------------------------------------- the wizard's step

/// The bank step while there is no account yet: two fields, checked as typed, sent on submit.
///
/// The controllers live in the wizard's State for the same reason the picked documents do — the
/// values must survive this step being popped and still be there two phases later.
class PayoutDetailsStep extends StatelessWidget {
  const PayoutDetailsStep({
    super.key,
    required this.accountHolder,
    required this.iban,
    required this.enabled,
  });

  final TextEditingController accountHolder;
  final TextEditingController iban;
  final bool enabled;

  /// Whether what is typed may travel. Both fields empty is a deliberate skip — the server treats
  /// the step as optional and the reviewer sees it as outstanding — but a half-answer or a number
  /// that fails its own check digits must not leave the device.
  static bool complete(DeliveryStrings t,
      {required String accountHolder, required String iban}) {
    if (accountHolder.trim().isEmpty && iban.trim().isEmpty) return true;
    return accountHolder.trim().isNotEmpty && ibanProblem(t, iban) == null;
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String typed = iban.text.trim();
    final String? problem = typed.isEmpty ? null : ibanProblem(t, typed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AuthField(
          label: t.wizPayoutAccountHolder,
          hint: t.wizPayoutAccountHolderHint,
          controller: accountHolder,
          enabled: enabled,
          borderColor: DeliveryColors.border,
          labelColor: DeliveryColors.muted,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: DeliverySpacing.md),
        AuthField(
          label: t.wizPayoutIban,
          hint: t.wizPayoutIbanHint,
          controller: iban,
          enabled: enabled,
          borderColor: problem == null
              ? DeliveryColors.border
              : DeliveryAccent.critical.color,
          labelColor: DeliveryColors.muted,
          textCapitalization: TextCapitalization.characters,
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.done,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 -]')),
            LengthLimitingTextInputFormatter(42),
          ],
        ),
        if (problem != null) ...<Widget>[
          const SizedBox(height: DeliverySpacing.sm),
          AuthErrorNote(message: problem),
        ],
        const SizedBox(height: DeliverySpacing.md),
        SoftNote(text: t.wizPayoutSentOnSubmit, icon: Icons.schedule),
      ],
    );
  }
}

// --------------------------------------------------------------------- the pending screen's card

/// The saved bank details, read back masked — and correctable while the application is open.
///
/// Three shapes: nothing saved yet (the form, straight away, because this is the rider's only
/// place to enter details at all — their wizard has no bank step), saved (holder, masked number,
/// the verification pill), and editing (the same form, prefilled with the unmasked number the
/// server returns to its owner).
class PayoutDetailsCard extends StatefulWidget {
  const PayoutDetailsCard({
    super.key,
    required this.api,
    required this.payout,
    required this.canEdit,
    required this.onChanged,
  });

  final DocumentsApi api;

  /// Null when the step has not been done yet.
  final PayoutDetails? payout;

  /// False once the application is decided.
  final bool canEdit;

  /// The record changed on the server; the owner should refetch.
  final VoidCallback onChanged;

  @override
  State<PayoutDetailsCard> createState() => _PayoutDetailsCardState();
}

class _PayoutDetailsCardState extends State<PayoutDetailsCard> {
  final TextEditingController _holder = TextEditingController();
  final TextEditingController _iban = TextEditingController();
  bool _editing = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _holder.addListener(_refresh);
    _iban.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _holder.removeListener(_refresh);
    _iban.removeListener(_refresh);
    _holder.dispose();
    _iban.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      // Prefilled with the record as the server holds it — the applicant is its owner and is
      // being asked to correct it, which a masked prefill would make impossible.
      _holder.text = widget.payout?.accountHolder ?? '';
      _iban.text = widget.payout?.iban ?? '';
      _error = null;
      _editing = true;
    });
  }

  Future<void> _save() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.setMyPayout(
        accountHolder: _holder.text.trim(),
        iban: _iban.text.trim(),
      );
      if (mounted) setState(() => _editing = false);
      widget.onChanged();
    } catch (_) {
      if (mounted) setState(() => _error = t.wizPayoutCouldNotSave);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final PayoutDetails? saved = widget.payout;
    final bool formShowing = _editing || saved == null;

    return YdCard.bordered(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  t.authBankDetails,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.2,
                  ),
                ),
              ),
              if (saved == null && !widget.canEdit)
                YdBadge(label: t.wizDocNotAddedYet, color: DeliveryColors.muted)
              else if (saved != null && !formShowing)
                YdBadge.accent(
                  label: payoutStateLabel(t, saved.verificationState),
                  accent: _payoutStateAccent(saved.verificationState),
                ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md),
          if (formShowing && widget.canEdit)
            ..._form(t)
          else if (saved != null)
            ..._saved(t, saved),
        ],
      ),
    );
  }

  List<Widget> _form(DeliveryStrings t) {
    final String typed = _iban.text.trim();
    final String? problem = typed.isEmpty ? null : ibanProblem(t, typed);
    final bool sendable = _holder.text.trim().isNotEmpty &&
        typed.isNotEmpty &&
        problem == null &&
        !_saving;

    return <Widget>[
      AuthField(
        label: t.wizPayoutAccountHolder,
        hint: t.wizPayoutAccountHolderHint,
        controller: _holder,
        enabled: !_saving,
        borderColor: DeliveryColors.border,
        labelColor: DeliveryColors.muted,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: DeliverySpacing.md),
      AuthField(
        label: t.wizPayoutIban,
        hint: t.wizPayoutIbanHint,
        controller: _iban,
        enabled: !_saving,
        borderColor: problem == null
            ? DeliveryColors.border
            : DeliveryAccent.critical.color,
        labelColor: DeliveryColors.muted,
        textCapitalization: TextCapitalization.characters,
        keyboardType: TextInputType.visiblePassword,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 -]')),
          LengthLimitingTextInputFormatter(42),
        ],
      ),
      if (problem != null) ...<Widget>[
        const SizedBox(height: DeliverySpacing.sm),
        AuthErrorNote(message: problem),
      ],
      if (_error != null) ...<Widget>[
        const SizedBox(height: DeliverySpacing.sm),
        AuthErrorNote(message: _error!),
      ],
      const SizedBox(height: DeliverySpacing.md),
      AuthPrimaryButton(
        label: t.wizPayoutSave,
        busy: _saving,
        onPressed: sendable ? _save : null,
      ),
    ];
  }

  List<Widget> _saved(DeliveryStrings t, PayoutDetails saved) => <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: DeliveryColors.brandSoft,
                borderRadius: BorderRadius.circular(DeliveryRadius.sm),
              ),
              child: const Icon(Icons.account_balance_outlined,
                  size: 16, color: DeliveryColors.brand),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    saved.accountHolder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: DeliveryColors.ink,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    maskIban(saved.iban),
                    style: const TextStyle(
                      fontSize: 12,
                      color: DeliveryColors.muted,
                      fontFamily: 'monospace',
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.canEdit) ...<Widget>[
              const SizedBox(width: DeliverySpacing.sm),
              InkWell(
                onTap: _startEditing,
                borderRadius: BorderRadius.circular(DeliveryRadius.pill),
                child: YdBadge.brand(
                    label: t.wizPayoutChange, icon: Icons.edit_outlined),
              ),
            ],
          ],
        ),
      ];
}
