import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../shell/console_controls.dart';
import '../shell/shell.dart';

/// The fleet — Figma `carrier-riders` (3:3589), "Riders Management".
///
/// The design's page is one table: who rides for this company, what state they are in, where they
/// dispatch, how much they have carried, how they are rated, and when they joined. The platform
/// knows the first of those and can derive the fourth. It records no presence, no dispatch region,
/// no rating and no join date for a rider, so those columns are drawn and left honestly empty with
/// a note under the table saying which is which. Filling them with plausible-looking numbers would
/// make the page worse, not better: a company would act on them.
///
/// Two things this screen has always done keep their place under the table, because they are real,
/// they are wired, and the design has nowhere else for them: the delivery score that decides how
/// much work this company is offered, and the switch that stops it being offered any.
class CompanyScreen extends StatefulWidget {
  const CompanyScreen({super.key, required this.api, required this.orderApi});

  final DeliveryProviderApi api;

  /// The job board, read here only to count deliveries per rider and to say who is out on a job.
  /// Nothing on this screen writes through it.
  final OrderApi orderApi;

  @override
  State<CompanyScreen> createState() => _CompanyScreenState();
}

class _CompanyScreenState extends State<CompanyScreen> {
  /// The page of work the per-rider counts are drawn from. Said on screen, because a count from a
  /// window is a different claim from a lifetime total and must not be read as one.
  static const int _jobsWindow = 100;

  late Future<_Fleet> _data = _load();
  final TextEditingController _search = TextEditingController();
  String _query = '';
  int _tab = 0;
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<_Fleet> _load() async {
    // Together rather than in sequence: none depends on the others, and the page is not useful
    // until the first three have arrived.
    final List<Object> results = await Future.wait(<Future<Object>>[
      widget.api.myCompany(),
      widget.api.myScore(),
      widget.api.myRiders(),
    ]);

    // The job board is an enrichment, not the page. A carrier whose orders endpoint is briefly
    // unhappy still gets their fleet list, with the derived columns showing "—".
    List<DeliveryOrder>? jobs;
    try {
      jobs = (await widget.orderApi.forCarrier(size: _jobsWindow)).content;
    } catch (_) {
      jobs = null;
    }

    return _Fleet(
      results[0] as DeliveryProviderInfo,
      results[1] as CarrierScore,
      results[2] as List<String>,
      jobs,
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

    return FutureBuilder<_Fleet>(
      future: _data,
      builder: (BuildContext context, AsyncSnapshot<_Fleet> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            color: DeliveryColors.background,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(color: DeliveryColors.brand),
          );
        }
        if (snapshot.hasError) {
          // The likeliest cause by far: this account is not attached to a company yet, which the
          // server answers with a 404. Saying that plainly beats a raw error.
          return _centred(Icons.help_outline, t.noCompanyYet, t.askThePlatformToAttachYou);
        }

        return _page(snapshot.data!, t);
      },
    );
  }

  Widget _page(_Fleet data, DeliveryStrings t) {
    final int onDuty = data.riders.where(data.isOnAJob).length;

    return ConsolePage(
      header: ConsoleTopbar(
        title: 'Riders Management',
        subtitle: 'Manage your delivery team, dispatch regions, and rider status',
        actions: <Widget>[
          ConsoleSearchField.global(
            hintText: 'Search riders...',
            controller: _search,
            onChanged: (String value) => setState(() => _query = value.trim()),
          ),
          ConsoleIconAction(
            icon: Icons.refresh,
            tooltip: t.refresh,
            onPressed: _reload,
          ),
          const ConsoleIconAction(
            icon: Icons.notifications_none,
            tooltip: 'Notifications — coming soon',
          ),
        ],
      ),
      children: <Widget>[
        _controls(data, onDuty),
        _table(data, t),
        _standing(data, t),
      ],
    );
  }

  /// The design's `controls-row` (3:3632): the segmented population switch on the left, the primary
  /// action on the right.
  Widget _controls(_Fleet data, int onDuty) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Flexible(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConsoleFilterTabs(
              tabs: <ConsoleFilterTab>[
                ConsoleFilterTab(label: 'All Delivery Riders', count: data.riders.length),
                // A real count. The design's is presence; this one is "holding a job that has not
                // finished", which is the nearest true thing and is what the tab now says.
                ConsoleFilterTab(label: 'On a job', count: onDuty),
              ],
              selectedIndex: _tab,
              onSelected: (int i) => setState(() => _tab = i),
            ),
          ),
        ),
        const SizedBox(width: DeliverySpacing.md),
        const ConsoleComingSoonChip(),
        const SizedBox(width: DeliverySpacing.sm),
        // Drawn, greyed, and explained. Riders reach a fleet by applying and being approved on the
        // Onboarding page — there is no endpoint that creates one directly, and a button that
        // opened a form nothing could submit would be worse than a button that says so.
        const Tooltip(
          message: 'Riders join by applying — approve them on the Onboarding page',
          child: ConsolePrimaryButton(label: 'Add New Rider', icon: Icons.add),
        ),
      ],
    );
  }

  Widget _table(_Fleet data, DeliveryStrings t) {
    final List<String> riders = data.riders
        .where((String r) => _tab == 0 || data.isOnAJob(r))
        .where((String r) =>
            _query.isEmpty || _shortRef(r).toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return ConsoleTable(
      minWidth: 1000,
      columns: const <ConsoleColumn>[
        ConsoleColumn(label: 'Rider Name', flex: 1),
        ConsoleColumn(label: 'Status', width: 120),
        ConsoleColumn(label: 'Region', width: 140),
        ConsoleColumn(label: 'Deliveries', width: 100),
        ConsoleColumn(label: 'Rating', width: 80),
        ConsoleColumn(label: 'Join Date', width: 120),
        ConsoleColumn(label: 'Actions', width: 140, alignRight: true),
      ],
      empty: Text(
        data.riders.isEmpty
            // Worth stating outright: a company with no riders looks available and can collect
            // nothing, which is the most confusing way to be sent no work.
            ? t.noRidersBlurb
            : 'No rider matches that.',
        style: ConsoleText.pageSubtitle,
      ),
      rows: <ConsoleTableRow>[
        for (final String rider in riders)
          ConsoleTableRow(
            cells: <Widget>[
              ConsoleNameCell(
                name: _shortRef(rider),
                leading: ConsoleAvatar(name: _shortRef(rider), radius: DeliveryRadius.sm),
              ),
              if (data.isOnAJob(rider))
                const ConsoleStatusPill(label: 'On a job', accent: DeliveryAccent.info)
              else
                const _Unknown(),
              const _Unknown(),
              data.jobs == null
                  ? const _Unknown()
                  : Text('${data.deliveredBy(rider)}', style: ConsoleText.cellStrong),
              const _Unknown(),
              const _Unknown(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: const <Widget>[
                  ConsoleRowAction(icon: Icons.visibility_outlined, tooltip: 'Rider detail — coming soon'),
                  SizedBox(width: DeliverySpacing.sm),
                  ConsoleRowAction(
                    icon: Icons.block,
                    tooltip: 'Suspending a rider — coming soon',
                    destructive: true,
                  ),
                ],
              ),
            ],
          ),
      ],
      footer: Row(
        children: <Widget>[
          const ConsoleComingSoonChip(),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              data.jobs == null
                  ? 'Presence, region, rating and join date are not recorded for a rider yet, and '
                      'the job board could not be read just now.'
                  : 'Presence, dispatch region, rating and join date are not recorded for a rider '
                      'yet. Deliveries are counted from this fleet\'s most recent $_jobsWindow jobs.',
              style: ConsoleText.meta,
            ),
          ),
        ],
      ),
    );
  }

  /// What the design has no place for and the product cannot lose: the score that decides how much
  /// work arrives, and the switch that stops it arriving.
  Widget _standing(_Fleet data, DeliveryStrings t) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Widget score = _scoreCard(data.score, t);
        final Widget availability = _availabilityCard(data.company, t);

        if (constraints.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              score,
              const SizedBox(height: ConsoleMetrics.pageGap),
              availability,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: score),
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
      // Only when it changes what the number means. A pill on every card is chrome; a pill that
      // says "there is not enough history for this yet" is the difference between a 70 to work on
      // and a 70 that is a placeholder.
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
            // Said plainly because it is the whole incentive: this number decides how much work
            // arrives when a merchant lets the platform choose.
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
              alignment: Alignment.centerLeft,
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

  Widget _centred(IconData icon, String title, String subtitle) {
    return Container(
      color: DeliveryColors.background,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(DeliverySpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 44, color: DeliveryColors.faint),
            const SizedBox(height: DeliverySpacing.md),
            Text(title, style: ConsoleText.cardTitle),
            const SizedBox(height: DeliverySpacing.xs),
            Text(subtitle, textAlign: TextAlign.center, style: ConsoleText.pageSubtitle),
          ],
        ),
      ),
    );
  }

  static String _minutes(Duration? d) => d == null ? '—' : '${d.inMinutes}m';

  /// Riders are Keycloak subjects; the whole uuid is noise on a list, and there is no display name
  /// on this endpoint to put in its place.
  static String _shortRef(String ref) =>
      ref.length <= 8 ? ref : ref.substring(0, 8).toUpperCase();
}

/// A cell for something the platform does not record. Faint, and the same glyph everywhere, so a
/// reader learns in one row that a dash means "not tracked" rather than "zero".
class _Unknown extends StatelessWidget {
  const _Unknown();

  @override
  Widget build(BuildContext context) {
    return const Text('—', style: TextStyle(fontSize: 14, color: DeliveryColors.faint));
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

class _Fleet {
  const _Fleet(this.company, this.score, this.riders, this.jobs);

  final DeliveryProviderInfo company;
  final CarrierScore score;
  final List<String> riders;

  /// Null when the job board could not be read — which is a different state from "no jobs", and
  /// the table says so rather than printing a zero nobody can trust.
  final List<DeliveryOrder>? jobs;

  bool isOnAJob(String riderRef) =>
      (jobs ?? const <DeliveryOrder>[]).any((DeliveryOrder j) =>
          j.riderId == riderRef && !j.status.isTerminal);

  int deliveredBy(String riderRef) =>
      (jobs ?? const <DeliveryOrder>[])
          .where((DeliveryOrder j) =>
              j.riderId == riderRef && j.status == OrderStatus.delivered)
          .length;
}
