import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// Everything a delivery company can see and do about itself.
///
/// One screen on purpose. A carrier needs three things from this platform: to know how it is doing,
/// to know who is on its fleet, and to be able to stop taking orders at closing time. Everything
/// else it does happens in the rider app, and splitting three answers across three pages would only
/// add navigation.
///
/// The score is the centrepiece rather than a statistic in a corner. It is what decides how much
/// work this company is offered, and a ranking nobody can see is a black box that appears to hand
/// out orders arbitrarily.
class CompanyScreen extends StatefulWidget {
  const CompanyScreen({
    super.key,
    required this.api,
    required this.locale,
    required this.onSignOut,
  });

  final DeliveryProviderApi api;
  final LocaleController locale;
  final Future<void> Function() onSignOut;

  @override
  State<CompanyScreen> createState() => _CompanyScreenState();
}

class _CompanyScreenState extends State<CompanyScreen> {
  late Future<_Company> _data = _load();
  bool _busy = false;

  Future<_Company> _load() async {
    // Together rather than in sequence: none depends on the others, and the page is not useful
    // until all three have arrived.
    final List<Object> results = await Future.wait(<Future<Object>>[
      widget.api.myCompany(),
      widget.api.myScore(),
      widget.api.myRiders(),
    ]);
    return _Company(
      results[0] as DeliveryProviderInfo,
      results[1] as CarrierScore,
      results[2] as List<String>,
    );
  }

  void _reload() {
    setState(() {
      _data = _load();
    });
  }

  Future<void> _toggleAvailability(DeliveryProviderInfo company) async {
    setState(() => _busy = true);
    final DeliveryStrings t = DeliveryStrings.of(context);
    try {
      final bool wasTaking = company.canTakeWork;
      await (wasTaking ? widget.api.pauseMyCompany() : widget.api.resumeMyCompany());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(wasTaking ? t.pausedNoNewOrders : t.resumedTakingOrders),
      ));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_messageFor(e, t))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The server's own sentence where it has one — it is the side that knows a suspended carrier
  /// cannot resume itself, and says so.
  static String _messageFor(Object error, DeliveryStrings t) {
    if (error is DioException) {
      final dynamic body = error.response?.data;
      if (body is Map && body['detail'] is String) return body['detail'] as String;
    }
    return t.thatDidNotWork;
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: AppBar(
        title: DeliveryWordmark(title: t.carrierPortal),
        actions: <Widget>[
          PopupMenuButton<String>(
            icon: const Icon(Icons.language),
            tooltip: t.language,
            initialValue: widget.locale.isArabic ? 'ar' : 'en',
            onSelected: widget.locale.setLanguage,
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'en', child: Text(t.english)),
              PopupMenuItem<String>(value: 'ar', child: Text(t.arabic)),
            ],
          ),
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: t.refresh,
          ),
          IconButton(
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout),
            tooltip: t.signOut,
          ),
        ],
      ),
      body: FutureBuilder<_Company>(
        future: _data,
        builder: (BuildContext context, AsyncSnapshot<_Company> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
          }
          if (snapshot.hasError) {
            // The likeliest cause by far: this account is not attached to a company yet, which the
            // server answers with a 404. Saying that plainly beats a raw error.
            return _centred(Icons.help_outline, t.noCompanyYet, t.askThePlatformToAttachYou);
          }

          final _Company data = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(DeliverySpacing.lg),
            children: <Widget>[
              _header(data.company, t),
              const SizedBox(height: DeliverySpacing.lg),
              SectionLabel(t.howYouAreDoing),
              const SizedBox(height: DeliverySpacing.sm),
              _scoreCard(data.score, t),
              const SizedBox(height: DeliverySpacing.lg),
              SectionLabel(t.takingOrders),
              const SizedBox(height: DeliverySpacing.sm),
              _availabilityCard(data.company, t),
              const SizedBox(height: DeliverySpacing.lg),
              SectionLabel(t.yourFleet),
              const SizedBox(height: DeliverySpacing.sm),
              _fleetCard(data.riders, t),
              const SizedBox(height: DeliverySpacing.lg),
              SectionLabel(t.gettingPaid),
              const SizedBox(height: DeliverySpacing.sm),
              _payoutCard(data.company, t),
            ],
          );
        },
      ),
    );
  }

  Widget _header(DeliveryProviderInfo company, DeliveryStrings t) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(company.name, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: DeliverySpacing.xs),
              Text(company.kind.labelIn(t), style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        StatePill(
          label: company.canTakeWork ? t.takingWork : company.status.label,
          accent: company.canTakeWork ? DeliveryAccent.positive : DeliveryAccent.caution,
        ),
      ],
    );
  }

  /// The number, and the parts a carrier can actually do something about.
  Widget _scoreCard(CarrierScore score, DeliveryStrings t) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          StatRow(tiles: <Widget>[
            StatTile(
              value: '${score.score}',
              label: t.deliveryScore,
              icon: Icons.workspace_premium_outlined,
              accent: score.score >= 80
                  ? DeliveryAccent.positive
                  : (score.score >= 60 ? DeliveryAccent.caution : DeliveryAccent.critical),
              footnote: score.provisional ? t.tooEarlyToTell : null,
            ),
            StatTile(
              value: '${(score.completionRate * 100).round()}%',
              label: t.ordersDelivered,
              icon: Icons.check_circle_outline_rounded,
              accent: score.completionRate >= 0.95
                  ? DeliveryAccent.positive
                  : DeliveryAccent.caution,
              footnote: '${score.orders}',
            ),
            StatTile(
              value: _minutes(score.timeToClaim),
              label: t.timeToClaim,
              icon: Icons.timer_outlined,
              accent: DeliveryAccent.info,
            ),
            StatTile(
              value: _minutes(score.timeOnRoad),
              label: t.timeOnTheRoad,
              icon: Icons.pedal_bike_rounded,
              accent: DeliveryAccent.neutral,
            ),
          ]),
          const SizedBox(height: DeliverySpacing.sm),
          SoftNote(
            // Said plainly because it is the whole incentive: this number decides how much work
            // arrives when a merchant lets the platform choose.
            text: score.provisional ? t.scoreProvisionalBlurb : t.scoreBlurb,
            accent: DeliveryAccent.info,
            icon: Icons.info_outline,
          ),
        ],
      ),
    );
  }

  Widget _availabilityCard(DeliveryProviderInfo company, DeliveryStrings t) {
    final bool suspended = company.status == ProviderStatus.suspended;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(company.canTakeWork ? t.youAreTakingOrders : t.youAreNotTakingOrders,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: DeliverySpacing.xs),
          Text(
            suspended ? t.suspendedByPlatform : t.pauseExplanation,
            style: const TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.35),
          ),
          const SizedBox(height: DeliverySpacing.sm),
          // A suspended carrier cannot let itself back in — that is the platform's decision, and a
          // button that silently fails would be worse than no button.
          if (!suspended)
            PrimaryAction(
              label: company.canTakeWork ? t.pauseNewOrders : t.startTakingOrders,
              icon: company.canTakeWork ? Icons.pause_rounded : Icons.play_arrow_rounded,
              busy: _busy,
              onPressed: _busy ? null : () => _toggleAvailability(company),
            ),
        ],
      ),
    );
  }

  Widget _fleetCard(List<String> riders, DeliveryStrings t) {
    if (riders.isEmpty) {
      return SoftCard(
        child: SoftNote(
          // Worth stating outright: a company with no riders looks available and can collect
          // nothing, which is the most confusing way to be sent no work.
          text: t.noRidersBlurb,
          accent: DeliveryAccent.critical,
          icon: Icons.warning_amber_rounded,
        ),
      );
    }
    return SoftCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          for (final String rider in riders)
            ListTile(
              dense: true,
              leading: const Icon(Icons.pedal_bike_outlined, color: DeliveryColors.muted),
              title: Text(_shortRef(rider)),
            ),
          Padding(
            padding: const EdgeInsets.all(DeliverySpacing.sm),
            child: SoftNote(
              text: t.ridersAddedByPlatform,
              accent: DeliveryAccent.info,
            ),
          ),
        ],
      ),
    );
  }

  Widget _payoutCard(DeliveryProviderInfo company, DeliveryStrings t) {
    final bool verified = company.payoutState == PayoutState.verified;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(verified ? Icons.verified_outlined : Icons.help_outline,
                  size: 18,
                  color: verified
                      ? DeliveryAccent.positive.color
                      : DeliveryAccent.caution.color),
              const SizedBox(width: DeliverySpacing.xs),
              Expanded(
                child: Text(
                  company.accountRef == null
                      ? t.noPayoutAccount
                      : '${company.accountRef} · ${company.payoutState.label.toLowerCase()}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (!verified) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            SoftNote(
              // A carrier whose account cannot be paid into finds out today rather than after a
              // week of deliveries.
              text: t.payoutNeedsAttentionBlurb,
              accent: DeliveryAccent.caution,
              icon: Icons.account_balance_outlined,
            ),
          ],
        ],
      ),
    );
  }

  Widget _centred(IconData icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DeliverySpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 44, color: DeliveryColors.muted),
            const SizedBox(height: DeliverySpacing.md),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: DeliverySpacing.xs),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  static String _minutes(Duration? d) => d == null ? '—' : '${d.inMinutes}m';

  /// Riders are Keycloak subjects; the whole uuid is noise on a list.
  static String _shortRef(String ref) =>
      ref.length <= 8 ? ref : ref.substring(0, 8).toUpperCase();
}

class _Company {
  const _Company(this.company, this.score, this.riders);

  final DeliveryProviderInfo company;
  final CarrierScore score;
  final List<String> riders;
}
