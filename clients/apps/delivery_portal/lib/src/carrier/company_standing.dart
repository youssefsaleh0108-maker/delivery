import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import '../shell/console_controls.dart';
import '../shell/shell.dart';
import 'fleet_roster.dart';

/// The two things a delivery company cannot lose and the Riders HR frame (112:413) has no place
/// for: the delivery score that decides how much work arrives, and the switch that stops it
/// arriving.
///
/// They sat under the old fleet table because that page was the company's page. The riders page
/// is an HR directory now, so they moved here, onto the dashboard — the page a company opens to
/// ask "how are we doing, and do we want more work tonight". Behaviour is unchanged: the score
/// says when it is provisional, and a company the platform suspended is not offered a resume
/// button that would fail.
///
/// Loads its own two reads rather than taking them from the dashboard, so mounting it is one line
/// and a failure here never takes the dashboard's figures down with it. Each read may fail alone:
/// no score still leaves the switch, and no company leaves nothing to draw at all.
class CarrierStandingCards extends StatefulWidget {
  const CarrierStandingCards({super.key, required this.api});

  final DeliveryProviderApi api;

  @override
  State<CarrierStandingCards> createState() => _CarrierStandingCardsState();
}

class _CarrierStandingCardsState extends State<CarrierStandingCards> {
  DeliveryProviderInfo? _company;
  CarrierScore? _score;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<Object?> both = await Future.wait(<Future<Object?>>[
      _tryLoad(widget.api.myCompany),
      _tryLoad(widget.api.myScore),
    ]);
    if (!mounted) return;
    setState(() {
      _company = both[0] as DeliveryProviderInfo?;
      _score = both[1] as CarrierScore?;
    });
  }

  static Future<T?> _tryLoad<T>(Future<T> Function() load) async {
    try {
      return await load();
    } catch (_) {
      return null;
    }
  }

  Future<void> _toggleAvailability(DeliveryProviderInfo company) async {
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
    final CarrierScore? score = _score;
    if (company == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Widget availability = _availabilityCard(company, t);
        if (score == null) return availability;
        final Widget scoreCard = _scoreCard(score, t);

        if (constraints.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              scoreCard,
              const SizedBox(height: ConsoleMetrics.pageGap),
              availability,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: scoreCard),
            const SizedBox(width: ConsoleMetrics.pageGap),
            SizedBox(width: 380, child: availability),
          ],
        );
      },
    );
  }

  Widget _scoreCard(CarrierScore score, DeliveryStrings t) {
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

  Widget _availabilityCard(DeliveryProviderInfo company, DeliveryStrings t) {
    final bool suspended = company.status == ProviderStatus.suspended;

    return ConsoleCard(
      title: t.takingOrders,
      trailing: ConsoleStatusPill(
        label: company.canTakeWork ? t.takingWork : company.status.label,
        accent: company.canTakeWork ? DeliveryAccent.positive : DeliveryAccent.caution,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            company.canTakeWork ? t.youAreTakingOrders : t.youAreNotTakingOrders,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
            ),
          ),
          const SizedBox(height: DeliverySpacing.xs),
          Text(
            suspended ? t.suspendedByPlatform : t.pauseExplanation,
            style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.4),
          ),
          // A suspended carrier cannot let itself back in — that is the platform's decision, and a
          // button that silently fails would be worse than no button.
          if (!suspended) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ConsolePrimaryButton(
                label: company.canTakeWork ? t.pauseNewOrders : t.startTakingOrders,
                icon: company.canTakeWork ? Icons.pause_rounded : Icons.play_arrow_rounded,
                busy: _busy,
                onPressed: _busy ? null : () => _toggleAvailability(company),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _minutes(Duration? d) => d == null ? '—' : '${d.inMinutes}m';
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
