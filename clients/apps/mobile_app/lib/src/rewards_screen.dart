import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// The customer's Account tab, redrawn as the design's `customer-account` rewards screen: the
/// crimson points card, the tier ladder, the reward categories and the recent activity — all read
/// from the points ledger, which now carries a CUSTOMER balance earned on delivered orders.
///
/// What each number is, honestly: points and tiers are live (earned server-side per delivered
/// order); Cashback is what the spendable balance is WORTH at today's rate, not money paid out;
/// Free Delivery vouchers and Referral Bonus are wired to engines that do not exist yet, so they
/// read zero rather than pretending. Account management itself moved to the profile drawer.
class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key, required this.pointsApi});

  final PointsApi pointsApi;

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  PointsBalance? _balance;
  List<PointsEntry> _history = <PointsEntry>[];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _balance == null;
      _error = null;
    });
    try {
      final List<Object> results = await Future.wait(<Future<Object>>[
        widget.pointsApi.myBalance(),
        widget.pointsApi.myHistory(limit: 20),
      ]);
      if (!mounted) return;
      setState(() {
        _balance = results[0] as PointsBalance;
        _history = (results[1] as List<PointsEntry>);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  /// Points earned since the first of this month — the card's "+N pts this month" chip.
  int get _earnedThisMonth {
    final DateTime now = DateTime.now();
    final DateTime monthStart = DateTime(now.year, now.month);
    int sum = 0;
    for (final PointsEntry e in _history) {
      final DateTime? at = e.createdAt;
      if (e.points > 0 && at != null && !at.isBefore(monthStart)) {
        sum += e.points;
      }
    }
    return sum;
  }

  String _tierName(DeliveryStrings t, String wire) => switch (wire) {
        'SILVER' => t.tierSilver,
        'GOLD' => t.tierGold,
        'PLATINUM' => t.tierPlatinum,
        _ => t.tierBronze,
      };

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(title: t.custRewardsTitle),
      body: RefreshIndicator(
        color: DeliveryColors.brand,
        onRefresh: _load,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: DeliveryColors.brand))
            : _error != null && _balance == null
                ? _errorState(t)
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(DeliverySpacing.lg),
                    children: <Widget>[
                      _pointsCard(t),
                      const SizedBox(height: DeliverySpacing.lg),
                      _sectionLabel(t.custCurrentTierHeading),
                      const SizedBox(height: DeliverySpacing.sm),
                      _tierCard(t),
                      const SizedBox(height: DeliverySpacing.lg),
                      _sectionLabel(t.custRewardCategories),
                      const SizedBox(height: DeliverySpacing.sm),
                      _categories(t),
                      const SizedBox(height: DeliverySpacing.lg),
                      _sectionLabel(t.custRecentActivity),
                      const SizedBox(height: DeliverySpacing.sm),
                      _activity(t),
                      const SizedBox(height: DeliverySpacing.lg),
                    ],
                  ),
      ),
    );
  }

  Widget _errorState(DeliveryStrings t) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          const SizedBox(height: 120),
          YdEmptyState(
            icon: Icons.cloud_off_rounded,
            title: t.somethingWentWrong,
            message: t.couldNotReachTheServer,
            action: YdPillButton.secondary(
              label: t.tryAgain,
              onPressed: _load,
              size: YdPillButtonSize.compact,
              expand: false,
            ),
          ),
        ],
      );

  Widget _sectionLabel(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: DeliveryColors.faint,
          letterSpacing: 0.6,
          height: 1.2,
        ),
      );

  // -------------------------------------------------------------------- the crimson points card

  Widget _pointsCard(DeliveryStrings t) {
    final PointsBalance balance = _balance!;
    final LoyaltyStanding? loyalty = balance.loyalty;
    final int thisMonth = _earnedThisMonth;

    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.lg),
      decoration: BoxDecoration(
        // The design's card runs brand into its darker sibling, top-left to bottom-right.
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[DeliveryColors.brand, DeliveryColors.brandDark],
        ),
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      t.custTotalPoints,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DeliveryColors.white.withValues(alpha: 0.85),
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${balance.points}',
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: DeliveryColors.white,
                        height: 1.1,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (thisMonth > 0)
                Container(
                  padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: DeliveryColors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(DeliveryRadius.pill),
                  ),
                  child: Text(
                    t.custPtsThisMonth(thisMonth),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: DeliveryColors.white,
                      height: 1.2,
                    ),
                  ),
                ),
            ],
          ),
          if (loyalty != null && loyalty.nextTier != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    t.custNextTierLabel(_tierName(t, loyalty.nextTier!)),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DeliveryColors.white,
                      height: 1.2,
                    ),
                  ),
                ),
                Text(
                  t.custPtsToGo(loyalty.pointsToNextTier),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.white.withValues(alpha: 0.9),
                    height: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: DeliverySpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: loyalty.progressToNextTier,
                minHeight: 7,
                backgroundColor: DeliveryColors.white.withValues(alpha: 0.25),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(DeliveryColors.white),
              ),
            ),
          ],
          const SizedBox(height: DeliverySpacing.md),
          Text(
            t.custRewardsBlurb,
            style: TextStyle(
              fontSize: 12,
              color: DeliveryColors.white.withValues(alpha: 0.85),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------------------ tier ladder

  Widget _tierCard(DeliveryStrings t) {
    final LoyaltyStanding? loyalty = _balance!.loyalty;
    if (loyalty == null) return const SizedBox.shrink();
    final String tier = _tierName(t, loyalty.tier);

    return YdCard.bordered(
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              _tierIcon(Icons.star_rounded, DeliveryColors.brand),
              const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      t.custCurrentTierLine(tier),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.ink,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.custTierEarnedLine(
                          loyalty.lifetimeEarned, loyalty.ordersCompleted),
                      style: const TextStyle(
                          fontSize: 12,
                          color: DeliveryColors.muted,
                          height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              YdBadge.brand(label: tier, uppercase: false, fontSize: 11),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md),
          const Divider(height: 1, color: DeliveryColors.borderFaint),
          const SizedBox(height: DeliverySpacing.md),
          Row(
            children: <Widget>[
              _tierIcon(Icons.emoji_events_outlined, DeliveryColors.muted),
              const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
              Expanded(
                child: loyalty.nextTier == null
                    ? Text(
                        t.custTopTier,
                        style: const TextStyle(
                            fontSize: 13,
                            color: DeliveryColors.muted,
                            height: 1.35),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            t.custNextTierLine(
                                _tierName(t, loyalty.nextTier!)),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: DeliveryColors.ink,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t.custNextTierBlurb(loyalty.nextTierAt ?? 0),
                            style: const TextStyle(
                                fontSize: 12,
                                color: DeliveryColors.muted,
                                height: 1.35),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tierIcon(IconData icon, Color color) => Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: DeliveryColors.brandSoft,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: color),
      );

  // ------------------------------------------------------------------------ reward categories

  Widget _categories(DeliveryStrings t) {
    final LoyaltyStanding? loyalty = _balance!.loyalty;
    final String currency = loyalty?.currency ?? 'USD';
    final String cashback =
        '\$${(loyalty?.cashbackValue ?? 0).toStringAsFixed(2)}';

    return Column(
      children: <Widget>[
        // No voucher engine yet: an honest zero, not an invented count.
        _categoryRow(
          icon: Icons.local_shipping_outlined,
          title: t.custFreeDelivery,
          subtitle: t.custVouchersAvailable,
          value: '0',
        ),
        const SizedBox(height: DeliverySpacing.sm),
        // What the spendable balance is WORTH at today's point rate — display, not a payout.
        _categoryRow(
          icon: Icons.savings_outlined,
          title: t.custCashback,
          subtitle: '${t.custEarnedLabel} ($currency)',
          value: cashback,
        ),
        const SizedBox(height: DeliverySpacing.sm),
        // No referral engine yet either.
        _categoryRow(
          icon: Icons.group_add_outlined,
          title: t.custReferralBonus,
          subtitle: t.custEarnedLabel,
          value: '\$0.00',
        ),
      ],
    );
  }

  Widget _categoryRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
  }) {
    return YdCard.bordered(
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: DeliveryColors.brandSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: DeliveryColors.brand),
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                      fontSize: 12, color: DeliveryColors.muted, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: DeliveryColors.brand,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------- recent activity

  Widget _activity(DeliveryStrings t) {
    if (_history.isEmpty) {
      return YdCard.bordered(
        child: Text(
          t.custNoActivityYet,
          style: const TextStyle(
              fontSize: 13, color: DeliveryColors.muted, height: 1.4),
        ),
      );
    }
    final MaterialLocalizations dates = MaterialLocalizations.of(context);
    return YdCard.bordered(
      child: Column(
        children: <Widget>[
          for (int i = 0; i < _history.length && i < 8; i++) ...<Widget>[
            if (i > 0)
              const Divider(height: DeliverySpacing.md * 1.5, color: DeliveryColors.borderFaint),
            _activityRow(t, dates, _history[i]),
          ],
        ],
      ),
    );
  }

  Widget _activityRow(
      DeliveryStrings t, MaterialLocalizations dates, PointsEntry entry) {
    final bool positive = entry.points > 0;
    final String signed = positive ? '+${entry.points}' : '${entry.points}';
    final String? orderId = entry.orderId;
    final String label = orderId == null
        ? t.custPointsEntry(signed)
        : t.custPointsOrderEntry(
            signed, orderId.substring(0, 8).toUpperCase());

    return Row(
      children: <Widget>[
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: positive
                ? DeliveryAccent.positive.color.withValues(alpha: 0.12)
                : DeliveryColors.brandSoft,
            shape: BoxShape.circle,
          ),
          child: Icon(
            positive ? Icons.add_rounded : Icons.remove_rounded,
            size: 16,
            color:
                positive ? DeliveryAccent.positive.color : DeliveryColors.brand,
          ),
        ),
        const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.ink,
              height: 1.3,
            ),
          ),
        ),
        if (entry.createdAt != null) ...<Widget>[
          const SizedBox(width: DeliverySpacing.sm),
          Text(
            dates.formatShortDate(entry.createdAt!),
            style: const TextStyle(
                fontSize: 11, color: DeliveryColors.faint, height: 1.2),
          ),
        ],
      ],
    );
  }
}
