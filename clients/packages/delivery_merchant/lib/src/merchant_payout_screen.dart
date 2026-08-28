import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

// For `merchantMaxContentWidth` — the column width every merchant page keeps on a wide window.
import 'order_detail_screen.dart';

/// Where a shop's money goes: the bank record the platform actually holds for this account.
///
/// The Settings tab's "Payment & Bank details" row carried a "Soon" chip on the claim that no
/// payout or bank record exists anywhere on the platform. That was wrong, and it was wrong in a way
/// worth writing down, because the same mistake is easy to make again: the record does exist, it
/// is just filed under *onboarding* rather than under merchants. Every partner — shop or rider —
/// gives an account holder and an IBAN on the application wizard's bank step, and
/// `GET /api/onboarding/applications/mine/payout` reads it back. That endpoint resolves the
/// application from the caller's token and never from a role, so it answers a signed-in merchant
/// exactly as it answers a signed-in rider. Nothing needed building on the server; this page is
/// the merchant half of a screen the rider surface already had.
///
/// **Read-only, and not by choice.** The onboarding payout endpoint refuses a change once an
/// application has been decided, and a merchant signed in to a working shop has been approved. So
/// the page shows the record and offers no editor: an editor here would be a form whose Save is
/// always refused, which is a worse answer than no form. Correcting a decided account is a
/// conversation with the platform, not a text field.
///
/// **The number is masked here and unmasked in the wizard, deliberately.** In the wizard the owner
/// is being asked to check a number they have just typed, and masking it would defeat the point of
/// showing it. Here they are being reminded which account is on file, which the last four digits
/// answer — and this screen can be open on a counter in a shop with customers on the other side of
/// it.
class MerchantPayoutScreen extends StatefulWidget {
  const MerchantPayoutScreen({super.key, required this.api, this.onBack});

  final DocumentsApi api;

  /// How the host leaves. Null draws no back affordance — a host that mounted this in a rail is
  /// already showing the way out.
  final VoidCallback? onBack;

  @override
  State<MerchantPayoutScreen> createState() => _MerchantPayoutScreenState();
}

class _MerchantPayoutScreenState extends State<MerchantPayoutScreen> {
  late Future<PayoutDetails?> _payout = widget.api.myPayout();

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: Column(
        children: <Widget>[
          YdScreenHeader(
            title: t.merchbPaymentBankDetails,
            onBack: widget.onBack,
            backSemanticLabel: t.back,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(DeliverySpacing.lg),
              child: Center(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: merchantMaxContentWidth),
                  child: FutureBuilder<PayoutDetails?>(
                    future: _payout,
                    builder: (BuildContext context,
                        AsyncSnapshot<PayoutDetails?> snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.all(DeliverySpacing.xl),
                          child: Center(
                            child: CircularProgressIndicator(
                                color: DeliveryColors.brand),
                          ),
                        );
                      }
                      // A failed read says so and offers the retry. It does not fall back to
                      // "not added yet": telling a shop owner their bank details are missing
                      // because a request timed out is the one wrong answer this page can give.
                      if (snapshot.hasError) {
                        return _problem(t);
                      }
                      return _record(t, snapshot.data);
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _problem(DeliveryStrings t) => YdCard.bordered(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              t.riderPayoutCouldNotLoad,
              style: const TextStyle(
                fontSize: 14,
                color: DeliveryColors.ink,
                height: 1.4,
              ),
            ),
            const SizedBox(height: DeliverySpacing.md),
            YdPillButton(
              label: t.tryAgain,
              onPressed: () =>
                  setState(() => _payout = widget.api.myPayout()),
            ),
          ],
        ),
      );

  Widget _record(DeliveryStrings t, PayoutDetails? saved) {
    if (saved == null) {
      return YdCard.bordered(
        child: YdEmptyState(
          icon: Icons.account_balance_outlined,
          title: t.wizDocNotAddedYet,
          message: t.merchbBankNoneFiled,
        ),
      );
    }

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
              YdBadge.accent(
                label: _stateLabel(t, saved.verificationState),
                accent: _stateAccent(saved.verificationState),
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md),
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
                      _maskIban(saved.iban),
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
            ],
          ),
          const SizedBox(height: DeliverySpacing.md),
          Text(
            t.merchbBankReadOnly,
            style: const TextStyle(
              fontSize: 12,
              color: DeliveryColors.muted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  static String _stateLabel(DeliveryStrings t, PayoutVerificationState state) =>
      switch (state) {
        PayoutVerificationState.checksumOnly => t.payoutFormatChecked,
        PayoutVerificationState.verified => t.payoutVerified,
        PayoutVerificationState.failed => t.payoutFailedVerification,
      };

  static DeliveryAccent _stateAccent(PayoutVerificationState state) =>
      switch (state) {
        PayoutVerificationState.checksumOnly => DeliveryAccent.info,
        PayoutVerificationState.verified => DeliveryAccent.positive,
        PayoutVerificationState.failed => DeliveryAccent.critical,
      };

  /// The country prefix and the last four, which is what identifies an account to its owner
  /// without printing the whole number on a screen facing a shop floor.
  static String _maskIban(String iban) {
    final String flat = iban.replaceAll(' ', '');
    if (flat.length <= 8) return flat;
    return '${flat.substring(0, 2)} •••• ${flat.substring(flat.length - 4)}';
  }
}
