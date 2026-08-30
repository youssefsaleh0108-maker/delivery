import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// The host's collection screen (Figma `split-invite-sent` 83:548, with the Remind pills of
/// `split-payment-status` 83:210): the countdown, the payment progress, one row per share, Cover
/// the Rest, and — the one honest deviation — a "Continue to Checkout" button once every share is
/// in, because placing the order is still the host's tap in this build rather than a server job.
class SplitStatusScreen extends StatefulWidget {
  const SplitStatusScreen({
    super.key,
    required this.splitApi,
    required this.plan,
    required this.onReady,
  });

  final SplitApi splitApi;
  final SplitPlan plan;

  /// Called when the host taps through to checkout with every share settled.
  final VoidCallback onReady;

  @override
  State<SplitStatusScreen> createState() => _SplitStatusScreenState();
}

class _SplitStatusScreenState extends State<SplitStatusScreen> {
  static const Duration _poll = Duration(seconds: 5);

  late SplitPlan _plan = widget.plan;
  Timer? _timer;
  Timer? _tick;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_poll, (_) => _refresh());
    // A second, faster clock just to repaint the countdown.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final SplitPlan fresh = await widget.splitApi.read(_plan.id);
      if (!mounted) return;
      setState(() => _plan = fresh);
    } catch (_) {
      // Next poll tries again.
    }
  }

  Future<void> _act(Future<SplitPlan> Function() action) async {
    setState(() => _acting = true);
    try {
      final SplitPlan fresh = await action();
      if (!mounted) return;
      setState(() => _plan = fresh);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DeliveryStrings.of(context).somethingWentWrong)));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  String get _countdown {
    final DateTime? end = _plan.expiresAt;
    if (end == null) return '--:--';
    final Duration left = end.difference(DateTime.now());
    if (left.isNegative) return '0:00';
    final int m = left.inMinutes;
    final int s = left.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _lbp(double usd) {
    final int thousands = (usd * _plan.rateUsed / 1000).round();
    return '${_group(thousands * 1000)} LBP';
  }

  static String _group(int amount) {
    final String digits = amount.toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  double get _uncovered => _plan.shares
      .where((SplitShare s) => s.status == 'PENDING' || s.status == 'DECLINED')
      .fold(0, (double sum, SplitShare s) => sum + s.amountUsd);

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool collecting = _plan.status == 'COLLECTING';
    final bool ready = _plan.status == 'READY';

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(
        title: t.custSplitOrder,
        onBack: () => Navigator.of(context).maybePop(),
        backSemanticLabel: t.back,
      ),
      body: ListView(
        padding: const EdgeInsets.all(DeliverySpacing.md),
        children: <Widget>[
          Text(
            _plan.status == 'READY' ? t.custReadyToPlace : t.custWaitingGroupPayments,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ready ? DeliveryAccent.positive.color : const Color(0xFFB8860B),
              height: 1.3,
            ),
          ),
          const SizedBox(height: DeliverySpacing.md),
          // The dark countdown block, as the frame draws it.
          if (collecting)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.lg),
              decoration: BoxDecoration(
                color: DeliveryColors.ink,
                borderRadius: BorderRadius.circular(DeliveryRadius.lg),
              ),
              child: Column(
                children: <Widget>[
                  Text(
                    t.custTimeRemaining.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: DeliveryColors.white.withValues(alpha: 0.6),
                      letterSpacing: 1,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _countdown,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: DeliveryColors.white,
                      height: 1.1,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.custSplitNWays('\$${_plan.totalUsd.toStringAsFixed(2)}',
                        _plan.shares.length),
                    style: TextStyle(
                      fontSize: 12,
                      color: DeliveryColors.white.withValues(alpha: 0.6),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: DeliverySpacing.md),
          // Payment progress.
          YdCard.bordered(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        t.custPaymentProgress,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: DeliveryColors.ink,
                          height: 1.25,
                        ),
                      ),
                    ),
                    Text(
                      t.custNPaid(_plan.paidCount, _plan.shares.length),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: DeliveryAccent.positive.color,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DeliverySpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _plan.totalUsd == 0
                        ? 0
                        : (_plan.collectedUsd / _plan.totalUsd).clamp(0, 1).toDouble(),
                    minHeight: 8,
                    backgroundColor: DeliveryColors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        DeliveryAccent.positive.color),
                  ),
                ),
                const SizedBox(height: DeliverySpacing.sm),
                Text(
                  t.custCollectedOf('\$${_plan.collectedUsd.toStringAsFixed(2)}',
                      '\$${_plan.totalUsd.toStringAsFixed(2)}'),
                  style: const TextStyle(
                      fontSize: 12, color: DeliveryColors.muted, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(height: DeliverySpacing.md),
          for (final SplitShare share in _plan.shares) ...<Widget>[
            _shareRow(t, share, collecting),
            const SizedBox(height: DeliverySpacing.sm),
          ],
          const SizedBox(height: DeliverySpacing.sm),
          if (collecting && _uncovered > 0)
            YdPillButton.secondary(
              label: t.custCoverRest('\$${_uncovered.toStringAsFixed(2)}'),
              onPressed:
                  _acting ? null : () => _act(() => widget.splitApi.cover(_plan.id)),
            ),
          if (ready) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            YdPillButton(
              label: t.custContinueToCheckout,
              onPressed: () {
                Navigator.of(context).pop();
                widget.onReady();
              },
            ),
          ],
          if (collecting) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            Center(
              child: TextButton(
                onPressed: _acting
                    ? null
                    : () async {
                        final NavigatorState nav = Navigator.of(context);
                        await _act(() => widget.splitApi.cancel(_plan.id));
                        if (mounted) nav.maybePop();
                      },
                child: Text(
                  t.custCancelSplit,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.muted,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: DeliverySpacing.lg),
        ],
      ),
    );
  }

  Widget _shareRow(DeliveryStrings t, SplitShare share, bool collecting) {
    final (String label, Color color, Color bg) = switch (share.status) {
      'PAID' => (t.custPaidChip, DeliveryAccent.positive.color,
          DeliveryAccent.positive.color.withValues(alpha: 0.12)),
      'COVERED' => (t.custCoveredChip, DeliveryColors.muted, DeliveryColors.border),
      'DECLINED' => (t.custDeclinedChip, DeliveryColors.brand, DeliveryColors.brandSoft),
      _ => (t.custPendingChip, const Color(0xFFB8860B), const Color(0xFFFDF3D7)),
    };

    return YdCard.bordered(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  share.username == null
                      ? share.name
                      : '@${share.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '\$${share.amountUsd.toStringAsFixed(2)} (${_lbp(share.amountUsd)})',
                  style: const TextStyle(
                      fontSize: 12, color: DeliveryColors.muted, height: 1.3),
                ),
                if (share.method != null && share.status == 'PAID')
                  Text(
                    t.custPaidVia(share.method!),
                    style: const TextStyle(
                        fontSize: 11, color: DeliveryColors.faint, height: 1.3),
                  ),
              ],
            ),
          ),
          if (collecting && share.status == 'PENDING') ...<Widget>[
            TextButton(
              onPressed: _acting
                  ? null
                  : () => _act(() => widget.splitApi.remind(_plan.id)),
              child: Text(
                t.custRemindBtn,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.brand,
                ),
              ),
            ),
            const SizedBox(width: DeliverySpacing.xs),
          ],
          Container(
            padding:
                const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(DeliveryRadius.pill),
            ),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.4,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
