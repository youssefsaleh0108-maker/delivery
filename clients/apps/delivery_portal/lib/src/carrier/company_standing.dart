import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import '../shell/shell.dart';
import 'fleet_roster.dart';

/// The delivery score that decides how much work a company is offered, and what it is made of —
/// one of the two things a company cannot lose that the Riders HR frame (112:413) has no place for.
/// The other is [CarrierAvailabilitySwitch], the switch that stops the work arriving.
///
/// Both sat under the old fleet table and moved to the dashboard, the page a company opens to ask
/// "how are we doing, and do we want more work tonight". The score sits at the foot of that page;
/// the switch sits in its top bar, because a brake below the fold is one nobody finds in time.
///
/// Each loads its own read rather than taking it from the dashboard, so mounting one is one line
/// and a failure in either never takes the dashboard's figures down with it. A score that cannot
/// be read draws nothing: the switch does not depend on it.
class CarrierScoreCard extends StatefulWidget {
  const CarrierScoreCard({super.key, required this.api});

  final DeliveryProviderApi api;

  @override
  State<CarrierScoreCard> createState() => _CarrierScoreCardState();
}

class _CarrierScoreCardState extends State<CarrierScoreCard> {
  CarrierScore? _score;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    CarrierScore? score;
    try {
      score = await widget.api.myScore();
    } catch (_) {
      score = null;
    }
    if (!mounted) return;
    setState(() => _score = score);
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final CarrierScore? score = _score;
    if (score == null) return const SizedBox.shrink();

    final DeliveryAccent accent = score.score >= 80
        ? DeliveryAccent.positive
        : (score.score >= 60 ? DeliveryAccent.caution : DeliveryAccent.critical);

    return ConsoleCard(
      title: t.howYouAreDoing,
      // Only when it changes what the number means: a 70 with not enough history behind it is a
      // placeholder, not a target.
      trailing: score.provisional
          ? ConsoleStatusPill(label: t.tooEarlyToTell, accent: DeliveryAccent.caution)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Wrap(
            spacing: ConsoleMetrics.kpiGap,
            runSpacing: ConsoleMetrics.kpiGap,
            children: <Widget>[
              _Figure(label: t.deliveryScore, value: '${score.score}', accent: accent),
              _Figure(
                label: t.ordersDelivered,
                value: '${(score.completionRate * 100).round()}%',
                accent: score.completionRate >= 0.95
                    ? DeliveryAccent.positive
                    : DeliveryAccent.caution,
              ),
              _Figure(
                label: t.timeToClaim,
                value: _minutes(score.timeToClaim),
                accent: DeliveryAccent.info,
              ),
              _Figure(
                label: t.timeOnTheRoad,
                value: _minutes(score.timeOnRoad),
                accent: DeliveryAccent.neutral,
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md),
          Text(
            // The whole incentive, said plainly: this number decides how much work arrives when a
            // merchant lets the platform choose.
            score.provisional ? t.scoreProvisionalBlurb : t.scoreBlurb,
            style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.4),
          ),
        ],
      ),
    );
  }

  static String _minutes(Duration? d) => d == null ? '—' : '${d.inMinutes}m';
}

/// Whether this company is being offered work, and the switch that stops or restarts it — small
/// enough for the dashboard's top bar, where it is the first thing on the page.
///
/// What pausing means is on the tooltip rather than in a paragraph beside it: the bar has room for
/// a status and a button, and the explanation is one hover away for whoever has not paused before.
/// A company the platform suspended sees its status, and why on the same tooltip, and is offered no
/// button — resuming out of a suspension is the platform's decision, and a button that silently
/// failed would be worse than none. Draws nothing when the company cannot be read; the page around
/// it already says so.
class CarrierAvailabilitySwitch extends StatefulWidget {
  const CarrierAvailabilitySwitch({super.key, required this.api});

  final DeliveryProviderApi api;

  @override
  State<CarrierAvailabilitySwitch> createState() => _CarrierAvailabilitySwitchState();
}

class _CarrierAvailabilitySwitchState extends State<CarrierAvailabilitySwitch> {
  DeliveryProviderInfo? _company;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    DeliveryProviderInfo? company;
    try {
      company = await widget.api.myCompany();
    } catch (_) {
      company = null;
    }
    if (!mounted) return;
    setState(() => _company = company);
  }

  Future<void> _toggle(DeliveryProviderInfo company) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final bool wasTaking = company.canTakeWork;
      await (wasTaking ? widget.api.pauseMyCompany() : widget.api.resumeMyCompany());
      messenger.showSnackBar(SnackBar(
        content: Text(wasTaking ? t.pausedNoNewOrders : t.resumedTakingOrders),
      ));
      await _load();
    } catch (e) {
      // The server's own sentence where it has one: it is the side that knows a suspended carrier
      // cannot resume itself, and says so.
      messenger.showSnackBar(SnackBar(content: Text(serverMessage(e, t))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final DeliveryProviderInfo? company = _company;
    if (company == null) return const SizedBox.shrink();
    final bool suspended = company.status == ProviderStatus.suspended;

    return Tooltip(
      message: suspended ? t.suspendedByPlatform : t.pauseExplanation,
      // A Wrap, so a narrow header puts the button under the status instead of overflowing.
      child: Wrap(
        spacing: DeliverySpacing.sm,
        runSpacing: DeliverySpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          ConsoleStatusPill(
            label: company.canTakeWork ? t.takingWork : company.status.label,
            accent: company.canTakeWork ? DeliveryAccent.positive : DeliveryAccent.caution,
          ),
          if (!suspended)
            ConsoleButton(
              label: company.canTakeWork ? t.pauseNewOrders : t.startTakingOrders,
              icon: company.canTakeWork ? Icons.pause_rounded : Icons.play_arrow_rounded,
              tone: company.canTakeWork ? ConsoleButtonTone.outlined : ConsoleButtonTone.tinted,
              busy: _busy,
              onPressed: _busy ? null : () => _toggle(company),
            ),
        ],
      ),
    );
  }
}

/// One of the four numbers inside the score card, in the console's KPI proportions without the
/// card chrome — these sit inside a card already.
class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, required this.accent});

  final String label;
  final String value;
  final DeliveryAccent accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: accent.color),
          ),
          const SizedBox(height: 2),
          Text(label, style: ConsoleText.kpiLabel),
        ],
      ),
    );
  }
}
