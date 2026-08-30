import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// The invitee's side (Figma `friend-payment-request` 83:299 + `friend-payment` 83:627): who
/// invited you, your share in both currencies at the locked rate, the methods a connector will
/// actually carry plus cash at the door, and the two honest answers — pay, or decline.
class FriendSplitScreen extends StatefulWidget {
  const FriendSplitScreen({
    super.key,
    required this.splitApi,
    required this.transferApi,
    required this.plan,
    required this.myUsername,
  });

  final SplitApi splitApi;
  final TransferApi transferApi;
  final SplitPlan plan;
  final String myUsername;

  @override
  State<FriendSplitScreen> createState() => _FriendSplitScreenState();
}

class _FriendSplitScreenState extends State<FriendSplitScreen> {
  List<String> _walletMethods = const <String>[];
  String _method = 'CASH_AT_DOOR';
  bool _acting = false;

  SplitShare? get _myShare {
    for (final SplitShare share in widget.plan.shares) {
      if (share.username == widget.myUsername && share.status == 'PENDING') {
        return share;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadMethods();
  }

  Future<void> _loadMethods() async {
    try {
      final List<String> methods = await widget.transferApi.methods();
      if (!mounted) return;
      setState(() {
        _walletMethods =
            methods.where((String m) => m != 'CASH_ON_DELIVERY').toList();
        if (_walletMethods.contains('WHISH')) _method = 'WHISH';
      });
    } catch (_) {
      // Cash at the door remains.
    }
  }

  Future<void> _answer(bool accept) async {
    setState(() => _acting = true);
    try {
      await widget.splitApi.answer(widget.plan.id,
          accept: accept, method: accept ? _method : null);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _acting = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DeliveryStrings.of(context).somethingWentWrong)));
    }
  }

  String _lbp(double usd) {
    final int thousands = (usd * widget.plan.rateUsed / 1000).round();
    final String digits = (thousands * 1000).toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return '$out LBP';
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final SplitShare? share = _myShare;

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(
        title: t.custPayYourShare,
        onBack: () => Navigator.of(context).maybePop(),
        backSemanticLabel: t.back,
      ),
      body: share == null
          ? Center(
              child: YdEmptyState(
                icon: Icons.check_circle_outline,
                title: t.custAllSharesPaid,
                message: '',
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(DeliverySpacing.md),
              children: <Widget>[
                YdCard.bordered(
                  child: Column(
                    children: <Widget>[
                      Text(
                        t.custInvitedYouToSplit(widget.plan.hostName),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: DeliveryColors.ink,
                          height: 1.3,
                        ),
                      ),
                      if (widget.plan.storeName != null) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          widget.plan.storeName!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 13,
                              color: DeliveryColors.muted,
                              height: 1.35),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: DeliverySpacing.md),
                // The share, big and twice, on the brand-soft ground.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.lg),
                  decoration: BoxDecoration(
                    color: DeliveryColors.brandSoft,
                    borderRadius: BorderRadius.circular(DeliveryRadius.lg),
                  ),
                  child: Column(
                    children: <Widget>[
                      Text(
                        t.custYourShareToPay.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: DeliveryColors.brand,
                          letterSpacing: 0.8,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '\$${share.amountUsd.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: DeliveryColors.brand,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _lbp(share.amountUsd),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: DeliveryColors.muted,
                            height: 1.3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: DeliverySpacing.md),
                // The same locked-rate banner checkout carries.
                Container(
                  padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDF3D7),
                    borderRadius: BorderRadius.circular(DeliveryRadius.md),
                    border: Border.all(color: const Color(0xFFF2DFA4)),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.lock_rounded,
                          size: 16, color: Color(0xFFB8860B)),
                      const SizedBox(width: DeliverySpacing.sm),
                      Expanded(
                        child: Text(
                          t.custPlatformRate(_groupRate(widget.plan.rateUsed)),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: DeliveryColors.ink,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: DeliverySpacing.lg),
                Text(
                  t.custSelectPaymentMethod,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: DeliverySpacing.sm),
                if (_walletMethods.contains('WHISH'))
                  _methodRow(t.custWhishShort, 'WHISH', recommended: true),
                if (_walletMethods.contains('OMT')) _methodRow(t.custOmtShort, 'OMT'),
                if (_walletMethods.contains('BOB')) _methodRow(t.custBobShort, 'BOB'),
                _methodRow(t.custCashAtDoor, 'CASH_AT_DOOR',
                    subtitle: t.custRiderCollectsFromYou),
                const SizedBox(height: DeliverySpacing.lg),
                YdPillButton(
                  label: t.custPayMyShare('\$${share.amountUsd.toStringAsFixed(2)}'),
                  busy: _acting,
                  onPressed: _acting ? null : () => _answer(true),
                ),
                const SizedBox(height: DeliverySpacing.sm),
                Center(
                  child: TextButton(
                    onPressed: _acting ? null : () => _answer(false),
                    child: Text(
                      t.custDeclineInvitation,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: DeliveryColors.muted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: DeliverySpacing.lg),
              ],
            ),
    );
  }

  static String _groupRate(double rate) {
    final String digits = rate.round().toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  Widget _methodRow(String label, String wire,
      {String? subtitle, bool recommended = false}) {
    final bool selected = _method == wire;
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: DeliveryColors.white,
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
            onTap: () => setState(() => _method = wire),
            child: Container(
              padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
              decoration: BoxDecoration(
                border: Border.all(
                  color: selected ? DeliveryColors.brand : DeliveryColors.border,
                  width: selected ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(DeliveryRadius.md),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? DeliveryColors.ink
                                : DeliveryColors.muted,
                            height: 1.25,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle,
                            style: const TextStyle(
                                fontSize: 11.5,
                                color: DeliveryColors.faint,
                                height: 1.3),
                          ),
                      ],
                    ),
                  ),
                  if (recommended) ...<Widget>[
                    Container(
                      padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: DeliveryColors.brandSoft,
                        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
                      ),
                      child: Text(
                        t.custRecommendedChip.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: DeliveryColors.brand,
                          letterSpacing: 0.5,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: DeliverySpacing.sm),
                  ],
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected ? DeliveryColors.brand : DeliveryColors.faint,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
