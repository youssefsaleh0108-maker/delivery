import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'split_labels.dart';

/// The end of the split flow (Figma `split-complete` 83:683): the green tick, the group summary
/// with how each share travels, the rider-collects note for every share handed over at the door,
/// and Track Order out.
///
/// The frame's headline was "All Shares Paid!", and since RECON-01 that is not true of any share
/// here: a share is COMMITTED — a promise — until a real provider carries its money, which on a
/// cash order none of them does. The rows below have always said so (a simulated wallet, "Rider
/// will collect $5.00 from Farid at delivery"), so the headline was the one line on the screen
/// contradicting the rest of it, and the only one a customer reads at a glance. It now says the
/// shares are agreed, and on a cash order a line under it says where the money is actually taken.
class SplitCompleteScreen extends StatelessWidget {
  const SplitCompleteScreen({
    super.key,
    required this.plan,
    required this.onTrack,
    this.cashOrder = true,
  });

  final SplitPlan plan;

  /// Pops the flow and lands the customer on their order.
  final VoidCallback onTrack;

  /// The order is paid in cash at the door. Then the rider collects every share there — the host's
  /// own slice and a simulated wallet share included, since neither moved any money — which is what
  /// the ledger books. On a card or wallet order nothing is collected, and no note is drawn.
  final bool cashOrder;

  static const Set<String> _wallets = <String>{'WHISH', 'OMT', 'BOB'};

  /// Who hands this share to the rider, or null when nobody does: a share a real provider carried,
  /// or one nobody has answered yet. A covered share is the host's to hand over.
  String? _handedOverBy(SplitShare share) {
    if (!cashOrder) return null;
    return switch (share.status) {
      'COMMITTED' => share.name,
      'COVERED' => plan.hostName,
      'PAID' when !(_wallets.contains(share.method) && !share.simulated) => share.name,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<(SplitShare, String)> doorNotes = <(SplitShare, String)>[
      for (final SplitShare share in plan.shares)
        if (_handedOverBy(share) case final String payer) (share, payer),
    ];

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(DeliverySpacing.lg),
                children: <Widget>[
                  const SizedBox(height: DeliverySpacing.xl),
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: DeliveryAccent.positive.color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.check_rounded,
                          size: 36, color: DeliveryAccent.positive.color),
                    ),
                  ),
                  const SizedBox(height: DeliverySpacing.md),
                  Text(
                    t.custAllSharesAgreed,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: DeliveryColors.ink,
                      height: 1.2,
                    ),
                  ),
                  // Only on a cash order, because only there does a rider collect anything. On a
                  // card or wallet order nothing is handed over at the door and no share note is
                  // drawn either, so the headline stands alone rather than promising a collection
                  // that will not happen.
                  if (cashOrder) ...<Widget>[
                    const SizedBox(height: DeliverySpacing.sm),
                    Text(
                      t.custSharesAgreedAtDoor,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: DeliveryColors.muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: DeliverySpacing.xl),
                  Text(
                    t.custGroupSplitSummary,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: DeliveryColors.ink,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: DeliverySpacing.sm),
                  YdCard.bordered(
                    child: Column(
                      children: <Widget>[
                        for (int i = 0; i < plan.shares.length; i++) ...<Widget>[
                          if (i > 0)
                            const Divider(
                                height: DeliverySpacing.md * 1.5,
                                color: DeliveryColors.borderFaint),
                          _row(t, plan.shares[i]),
                        ],
                        if (doorNotes.isNotEmpty) ...<Widget>[
                          const Divider(
                              height: DeliverySpacing.md * 1.5,
                              color: DeliveryColors.borderFaint),
                          for (final (SplitShare s, String payer) in doorNotes)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                t.custRiderCollectNote(
                                    '\$${s.amountUsd.toStringAsFixed(2)}', payer),
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: DeliveryColors.muted,
                                    height: 1.4),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(DeliverySpacing.md),
              child: YdPillButton(label: t.trackIt, onPressed: onTrack),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(DeliveryStrings t, SplitShare share) {
    final String? caption = splitShareCaption(t, share);
    return Row(
      children: <Widget>[
        Icon(Icons.check_rounded, size: 18, color: DeliveryAccent.positive.color),
        const SizedBox(width: DeliverySpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                share.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.ink,
                  height: 1.25,
                ),
              ),
              if (caption != null)
                Text(
                  caption,
                  style: const TextStyle(
                      fontSize: 11.5, color: DeliveryColors.faint, height: 1.3),
                ),
            ],
          ),
        ),
        Text(
          '\$${share.amountUsd.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: DeliveryColors.ink,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}
