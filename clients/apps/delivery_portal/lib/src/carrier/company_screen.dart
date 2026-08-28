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
/// dispatch, how much they have carried, how they are rated, and when they joined. Most of that is
/// answerable now:
///
/// * **Status** is real presence, from the tracking service's roster — on duty, signal lost, or off
///   duty — rather than the "holding an unfinished job" approximation this screen used to draw.
/// * **Region** and **Join Date** come from the rider's own application to this company: the region
///   they said they work, and the day the company approved them.
/// * **Deliveries** is still counted from the loaded page of work, and says so.
/// * **Rating** stays empty. Nothing on this platform rates a rider, and a plausible number in that
///   column is the one a company would act on hardest.
///
/// Both row actions are live. The eye opens a drawer with everything the platform knows about one
/// rider — presence, thirty days of performance in this company's own scope, hours online, and what
/// they have delivered today — and the block suspends them, with a typed reason, through the
/// carrier-side suspension endpoints that are double-gated on actually running this company.
///
/// Two things this screen has always done keep their place under the table: the delivery score that
/// decides how much work this company is offered, and the switch that stops it being offered any.
class CompanyScreen extends StatefulWidget {
  const CompanyScreen({
    super.key,
    required this.api,
    required this.orderApi,
    this.onboardingApi,
    this.managementApi,
    this.trackingApi,
    this.performanceApi,
  });

  final DeliveryProviderApi api;

  /// The job board, read here only to count deliveries per rider. Nothing on this screen writes
  /// through it.
  final OrderApi orderApi;

  /// The company's own applications: the join date, the region a rider gave, the name to put in
  /// the first column, and the application id every suspension is addressed to.
  ///
  /// Optional only because the portal shell has not been rewired to pass it yet; without it the
  /// table falls back to rider references and the suspend action explains why it cannot act.
  final OnboardingApi? onboardingApi;

  /// The carrier-side suspend / unsuspend / standing endpoints.
  final PartnerManagementApi? managementApi;

  /// The roster and one rider's hours online.
  final TrackingApi? trackingApi;

  /// Thirty days of a rider's work for this company, and today's delivered counts.
  final RiderPerformanceApi? performanceApi;

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

    final DeliveryProviderInfo company = results[0] as DeliveryProviderInfo;
    final List<String> riders = results[2] as List<String>;

    // Everything below enriches the fleet list. A carrier whose orders or tracking endpoint is
    // briefly unhappy still gets their riders, with the derived columns showing "—".
    final List<DeliveryOrder>? jobs =
        await _tryLoad(() async => (await widget.orderApi.forCarrier(size: _jobsWindow)).content);

    final OnboardingApi? onboarding = widget.onboardingApi;
    final List<OnboardingApplication>? applications = onboarding == null
        ? null
        : await _tryLoad(() => onboarding.forCompany(company.id, all: true));

    final TrackingApi? tracking = widget.trackingApi;
    final List<RiderPresence>? roster = tracking == null
        ? null
        // Everyone, not just the on-duty half: this is a staff list, and a rider who is off duty
        // has to appear in it as off duty rather than vanish.
        : await _tryLoad(() => tracking.roster(onDutyOnly: false));

    final RiderPerformanceApi? performance = widget.performanceApi;
    final List<RiderDeliveredToday>? deliveredToday =
        performance == null ? null : await _tryLoad(performance.deliveredToday);

    final _Fleet fleet = _Fleet(
      company: company,
      score: results[1] as CarrierScore,
      riders: riders,
      jobs: jobs,
      applications: <String, OnboardingApplication>{
        if (applications != null)
          for (final OnboardingApplication a in applications)
            if (a.kind == OnboardingKind.rider && a.provisionedUserRef != null)
              a.provisionedUserRef!: a,
      },
      waiting: applications
              ?.where((OnboardingApplication a) =>
                  a.kind == OnboardingKind.rider && !a.status.isDecided)
              .toList() ??
          const <OnboardingApplication>[],
      applicationsLoaded: applications != null,
      roster: roster == null
          ? null
          : <String, RiderPresence>{
              for (final RiderPresence p in roster) p.riderId: p,
            },
      deliveredToday: deliveredToday == null
          ? null
          : <String, int>{
              for (final RiderDeliveredToday d in deliveredToday) d.riderId: d.delivered,
            },
      suspended: const <String, bool>{},
    );

    return fleet.withStandings(await _standings(fleet));
  }

  /// Who on this fleet is currently suspended, one call per rider the company has an application
  /// for. A fleet is human-sized, and a rider whose standing could not be read is simply absent
  /// from the map — the row then offers "Suspend rider" rather than guessing at a state.
  Future<Map<String, bool>> _standings(_Fleet fleet) async {
    final PartnerManagementApi? management = widget.managementApi;
    if (management == null || fleet.applications.isEmpty) return const <String, bool>{};

    final Map<String, bool> standings = <String, bool>{};
    await Future.wait(fleet.riders.map((String rider) async {
      final OnboardingApplication? application = fleet.applications[rider];
      if (application == null) return;
      final PartnerSuspensionRecord? record = await _tryLoad(
          () => management.riderSuspension(fleet.company.id, application.id));
      if (record != null) standings[rider] = record.suspended;
    }));
    return standings;
  }

  static Future<T?> _tryLoad<T>(Future<T> Function() load) async {
    try {
      return await load();
    } catch (_) {
      return null;
    }
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
      if (body is Map) {
        if (body['message'] is String) return body['message'] as String;
        if (body['detail'] is String) return body['detail'] as String;
      }
    }
    return t.thatDidNotWork;
  }

  void _tell(String message, {bool bad = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: bad ? DeliveryAccent.critical.color : null,
    ));
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
    final int onDuty = data.riders.where(data.isWorkingNow).length;

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
          // FINISH-WAVE NOTE: the console bell's slot. `ConsoleBell` is not exported from
          // `shell/shell.dart` yet, so this keeps the drawn control and compiles against the
          // barrel as it stands.
          const ConsoleIconAction(
            icon: Icons.notifications_none,
            tooltip: 'Notifications',
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
                // Real presence where the roster loaded, and the nearest true thing — holding an
                // unfinished job — where it did not. The label says which in the table below.
                ConsoleFilterTab(label: 'Working now', count: onDuty),
              ],
              selectedIndex: _tab,
              onSelected: (int i) => setState(() => _tab = i),
            ),
          ),
        ),
        const SizedBox(width: DeliverySpacing.md),
        // Live: riders reach a fleet by applying and being approved, so the button opens the
        // people who are waiting for exactly that and approves them in place. It is the only way a
        // rider is added, and it is now one click from the page about riders.
        Tooltip(
          message: data.applicationsLoaded
              ? 'Approve somebody who has applied to ride for you'
              : 'Riders join by applying — approve them on the Onboarding page',
          child: ConsolePrimaryButton(
            label: 'Add New Rider',
            icon: Icons.add,
            onPressed: data.applicationsLoaded ? () => _openWaiting(data) : null,
          ),
        ),
      ],
    );
  }

  Widget _table(_Fleet data, DeliveryStrings t) {
    final List<String> riders = data.riders
        .where((String r) => _tab == 0 || data.isWorkingNow(r))
        .where((String r) => _matches(data, r))
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
            onTap: () => _openRider(data, rider),
            cells: <Widget>[
              ConsoleNameCell(
                name: data.nameOf(rider),
                secondary: data.applications[rider] == null ? null : _shortRef(rider),
                leading: ConsoleAvatar(name: data.nameOf(rider), radius: DeliveryRadius.sm),
              ),
              _statusCell(data, rider),
              data.regionOf(rider) == null
                  ? const _Unknown()
                  : Text(data.regionOf(rider)!,
                      overflow: TextOverflow.ellipsis, style: ConsoleText.cellMuted),
              data.jobs == null
                  ? const _Unknown()
                  : Text('${data.deliveredBy(rider)}', style: ConsoleText.cellStrong),
              // Nothing on this platform rates a rider. A number here is the one a company would
              // act on hardest, so the column stays honestly empty.
              const _Unknown(),
              data.joinedOn(rider) == null
                  ? const _Unknown()
                  : Text(_date(data.joinedOn(rider)!), style: ConsoleText.cellMuted),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ConsoleRowAction(
                    icon: Icons.visibility_outlined,
                    tooltip: 'Rider detail',
                    onPressed: () => _openRider(data, rider),
                  ),
                  const SizedBox(width: DeliverySpacing.sm),
                  _suspendAction(data, rider),
                ],
              ),
            ],
          ),
      ],
      footer: Text(
        data.jobs == null
            ? 'Rating is not recorded on this platform. The job board could not be read just now, '
                'so the delivery counts are unavailable.'
            : 'Rating is not recorded on this platform. Region and join date come from the '
                'rider\'s own application. Deliveries are counted from this fleet\'s most recent '
                '$_jobsWindow jobs.',
        style: ConsoleText.meta,
      ),
    );
  }

  bool _matches(_Fleet data, String rider) {
    if (_query.isEmpty) return true;
    final String needle = _query.toLowerCase();
    return data.nameOf(rider).toLowerCase().contains(needle) ||
        _shortRef(rider).toLowerCase().contains(needle) ||
        (data.regionOf(rider) ?? '').toLowerCase().contains(needle);
  }

  Widget _statusCell(_Fleet data, String rider) {
    if (data.suspended[rider] == true) {
      return const ConsoleStatusPill(label: 'Suspended', accent: DeliveryAccent.critical);
    }

    final RiderPresence? presence = data.roster?[rider];
    if (presence != null) {
      return ConsoleStatusPill(
        label: presence.state.label,
        accent: switch (presence.state) {
          PresenceState.onDuty => DeliveryAccent.positive,
          PresenceState.stale => DeliveryAccent.caution,
          PresenceState.offDuty => DeliveryAccent.neutral,
        },
      );
    }
    // No presence to read: the nearest true thing, or nothing at all.
    if (data.isOnAJob(rider)) {
      return const ConsoleStatusPill(label: 'On a job', accent: DeliveryAccent.info);
    }
    return const _Unknown();
  }

  Widget _suspendAction(_Fleet data, String rider) {
    final PartnerManagementApi? management = widget.managementApi;
    final OnboardingApplication? application = data.applications[rider];
    final bool suspended = data.suspended[rider] == true;

    if (management == null || application == null) {
      return ConsoleRowAction(
        icon: Icons.block,
        tooltip: application == null
            // The endpoint is addressed to a rider's application to this company; somebody the
            // Backoffice attached directly has none, and there is nothing to suspend against.
            ? 'No application on file for this rider — the platform attached them directly'
            : 'Suspending a rider is not wired up in this build',
        destructive: true,
      );
    }

    return ConsoleRowAction(
      icon: suspended ? Icons.lock_open : Icons.block,
      tooltip: suspended ? 'Reinstate this rider' : 'Suspend this rider',
      destructive: !suspended,
      onPressed: _busy ? null : () => _flipStanding(data, rider, application, suspended),
    );
  }

  /// Suspend, with a reason the server insists on, or reinstate with an optional note.
  ///
  /// Both are idempotent server-side and both are double-gated: the caller must actually run this
  /// company, and the application must be a rider's to it.
  Future<void> _flipStanding(
    _Fleet data,
    String rider,
    OnboardingApplication application,
    bool suspended,
  ) async {
    final PartnerManagementApi management = widget.managementApi!;
    final DeliveryStrings t = DeliveryStrings.of(context);

    final _StandingAnswer? answer = await showDialog<_StandingAnswer>(
      context: context,
      builder: (BuildContext context) =>
          _StandingDialog(name: data.nameOf(rider), suspending: !suspended),
    );
    if (answer == null || !mounted) return;

    setState(() => _busy = true);
    try {
      if (suspended) {
        await management.unsuspendRider(data.company.id, application.id, note: answer.note);
      } else {
        await management.suspendRider(
            data.company.id, application.id, answer.reason!, note: answer.note);
      }
      _tell(suspended
          ? '${data.nameOf(rider)} can take work again.'
          : '${data.nameOf(rider)} is suspended and will not be offered work.');
      _reload();
    } catch (e) {
      _tell(_messageFor(e, t), bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Everything the platform knows about one rider, beside the list rather than over it.
  Future<void> _openRider(_Fleet data, String rider) async {
    final OnboardingApplication? application = data.applications[rider];

    await showConsoleDrawer<void>(
      context: context,
      title: data.nameOf(rider),
      subtitle: _shortRef(rider),
      badge: data.suspended[rider] == true
          ? const ConsoleStatusPill(label: 'Suspended', accent: DeliveryAccent.critical)
          : data.roster?[rider] == null
              ? null
              : ConsoleStatusPill(
                  label: data.roster![rider]!.state.label,
                  accent: switch (data.roster![rider]!.state) {
                    PresenceState.onDuty => DeliveryAccent.positive,
                    PresenceState.stale => DeliveryAccent.caution,
                    PresenceState.offDuty => DeliveryAccent.neutral,
                  },
                ),
      builder: (BuildContext context) => _RiderDetail(
        riderId: rider,
        presence: data.roster?[rider],
        rosterLoaded: data.roster != null,
        // Absent from the delivered-today list means nothing delivered, not missing data — the
        // contract is explicit, so the zero is drawn here rather than a dash.
        deliveredToday: data.deliveredToday == null ? null : data.deliveredToday![rider] ?? 0,
        deliveredInWindow: data.jobs == null ? null : data.deliveredBy(rider),
        jobsWindow: _jobsWindow,
        application: application,
        performanceApi: widget.performanceApi,
        trackingApi: widget.trackingApi,
      ),
    );
  }

  /// The people waiting to ride for this company, approved in place. Approving creates their
  /// account and puts them on the fleet, which is said before the button is pressed.
  Future<void> _openWaiting(_Fleet data) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool? hired = await showConsoleDrawer<bool>(
      context: context,
      title: 'Add a rider',
      subtitle: data.waiting.isEmpty
          ? 'Nobody is waiting to ride for you'
          : '${data.waiting.length} waiting to ride for you',
      builder: (BuildContext context) => _WaitingList(
        waiting: data.waiting,
        blurb: t.hiringAlsoCreatesTheirAccount,
        onHire: (OnboardingApplication a) async {
          await widget.onboardingApi!.hire(data.company.id, a.id);
        },
        onFailure: (Object e) => _messageFor(e, t),
      ),
    );

    if (hired == true) _reload();
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

  /// Riders are Keycloak subjects; the whole uuid is noise on a list, and it is only shown at all
  /// where the platform has no name to put in its place.
  static String _shortRef(String ref) =>
      ref.length <= 8 ? ref : ref.substring(0, 8).toUpperCase();
}

/// "Aug 16, 2026" — the console's own date shape.
String _date(DateTime at) {
  const List<String> months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[at.month - 1]} ${at.day.toString().padLeft(2, '0')}, ${at.year}';
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
  const _Fleet({
    required this.company,
    required this.score,
    required this.riders,
    required this.jobs,
    required this.applications,
    required this.waiting,
    required this.applicationsLoaded,
    required this.roster,
    required this.deliveredToday,
    required this.suspended,
  });

  final DeliveryProviderInfo company;
  final CarrierScore score;
  final List<String> riders;

  /// Null when the job board could not be read — which is a different state from "no jobs", and
  /// the table says so rather than printing a zero nobody can trust.
  final List<DeliveryOrder>? jobs;

  /// The rider's own application to this company, by their Keycloak subject. Empty when the
  /// onboarding endpoint was not reachable or the rider was attached by the platform directly.
  final Map<String, OnboardingApplication> applications;

  /// Undecided rider applications addressed to this company.
  final List<OnboardingApplication> waiting;

  /// Whether the applications call succeeded at all — an empty list and a failed call are
  /// different states, and only one of them means "nobody is waiting".
  final bool applicationsLoaded;

  /// Presence by rider. Null when the tracking service could not be read.
  final Map<String, RiderPresence>? roster;

  /// Deliveries today by rider. Absent riders delivered nothing; null means the call failed.
  final Map<String, int>? deliveredToday;

  /// Who is suspended. A rider missing from this map has no known standing — never a claim that
  /// they are in good standing.
  final Map<String, bool> suspended;

  _Fleet withStandings(Map<String, bool> standings) => _Fleet(
        company: company,
        score: score,
        riders: riders,
        jobs: jobs,
        applications: applications,
        waiting: waiting,
        applicationsLoaded: applicationsLoaded,
        roster: roster,
        deliveredToday: deliveredToday,
        suspended: standings,
      );

  String nameOf(String riderRef) =>
      applications[riderRef]?.contactName ?? _CompanyScreenState._shortRef(riderRef);

  /// Where the rider said they work, from their own application. Null when they were not asked or
  /// did not say — never guessed at from anything else.
  String? regionOf(String riderRef) {
    final Map<String, String> details = applications[riderRef]?.details ?? const <String, String>{};
    for (final String key in const <String>['workRegion', 'region', 'city', 'area']) {
      final String? value = details[key];
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  /// The day this company approved them, or the day they applied when the decision was not
  /// recorded.
  DateTime? joinedOn(String riderRef) {
    final OnboardingApplication? application = applications[riderRef];
    if (application == null) return null;
    return application.decidedAt ?? application.createdAt;
  }

  bool isOnAJob(String riderRef) =>
      (jobs ?? const <DeliveryOrder>[]).any((DeliveryOrder j) =>
          j.riderId == riderRef && !j.status.isTerminal);

  /// On duty by the tracking service's reckoning where there is one, and holding an unfinished job
  /// where there is not.
  bool isWorkingNow(String riderRef) {
    final RiderPresence? presence = roster?[riderRef];
    if (presence != null) return presence.state == PresenceState.onDuty;
    return isOnAJob(riderRef);
  }

  int deliveredBy(String riderRef) =>
      (jobs ?? const <DeliveryOrder>[])
          .where((DeliveryOrder j) =>
              j.riderId == riderRef && j.status == OrderStatus.delivered)
          .length;
}

// --------------------------------------------------------------------------- rider detail

/// The drawer behind the eye: presence, thirty days of performance, hours online, today.
///
/// Loads its own two endpoints rather than having the page load them for every row — a fleet of
/// forty riders would otherwise fire eighty requests to draw a table nobody has opened yet.
class _RiderDetail extends StatefulWidget {
  const _RiderDetail({
    required this.riderId,
    required this.presence,
    required this.rosterLoaded,
    required this.deliveredToday,
    required this.deliveredInWindow,
    required this.jobsWindow,
    required this.application,
    required this.performanceApi,
    required this.trackingApi,
  });

  final String riderId;
  final RiderPresence? presence;
  final bool rosterLoaded;
  final int? deliveredToday;
  final int? deliveredInWindow;
  final int jobsWindow;
  final OnboardingApplication? application;
  final RiderPerformanceApi? performanceApi;
  final TrackingApi? trackingApi;

  @override
  State<_RiderDetail> createState() => _RiderDetailState();
}

class _RiderDetailState extends State<_RiderDetail> {
  /// A week, which is what the duty-hours endpoint defaults to and what a dispatcher reads.
  static const int _hoursDays = 7;

  late final Future<RiderPerformance?>? _performance =
      widget.performanceApi == null ? null : _load(() => widget.performanceApi!.forRider(widget.riderId));
  late final Future<HoursOnline?>? _hours = widget.trackingApi == null
      ? null
      : _load(() => widget.trackingApi!.riderDutyHours(widget.riderId, days: _hoursDays));

  static Future<T?> _load<T>(Future<T> Function() load) async {
    try {
      return await load();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ConsoleDrawerSection(first: true, title: 'Presence', child: _presence()),
        ConsoleDrawerSection(title: 'Today', child: _today()),
        ConsoleDrawerSection(
          title: 'Performance, last 30 days',
          child: _performanceBlock(),
        ),
        ConsoleDrawerSection(title: 'Hours online, last $_hoursDays days', child: _hoursBlock()),
        if (widget.application != null)
          ConsoleDrawerSection(title: 'Application', child: _application(widget.application!)),
      ],
    );
  }

  Widget _presence() {
    if (!widget.rosterLoaded) {
      return const Text('Presence could not be read just now.', style: ConsoleText.body);
    }
    final RiderPresence? p = widget.presence;
    if (p == null) {
      // The roster carries riders the tracking service has ever heard from. Never having declared
      // duty is a real state and is not the same as being off duty.
      return const Text(
        'This rider has never declared duty, so the platform has no presence for them.',
        style: ConsoleText.body,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ConsoleStatusPill(
          label: p.state.label,
          accent: switch (p.state) {
            PresenceState.onDuty => DeliveryAccent.positive,
            PresenceState.stale => DeliveryAccent.caution,
            PresenceState.offDuty => DeliveryAccent.neutral,
          },
        ),
        const SizedBox(height: DeliverySpacing.sm),
        _line('Declared', p.dutyState.label),
        _line('Last seen', p.lastSeenAt == null ? 'Never' : _stamp(p.lastSeenAt!)),
        _line('Changed', p.dutyChangedAt == null ? '—' : _stamp(p.dutyChangedAt!)),
        if (p.state == PresenceState.stale)
          const Padding(
            padding: EdgeInsets.only(top: DeliverySpacing.sm),
            child: Text(
              'Declared on duty, but the last fix is too old to dispatch on.',
              style: ConsoleText.meta,
            ),
          ),
      ],
    );
  }

  Widget _today() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _line(
          'Delivered today',
          widget.deliveredToday == null ? 'Could not be read' : '${widget.deliveredToday}',
        ),
        _line(
          'Delivered in the last ${widget.jobsWindow} jobs',
          widget.deliveredInWindow == null ? 'Could not be read' : '${widget.deliveredInWindow}',
        ),
      ],
    );
  }

  Widget _performanceBlock() {
    final Future<RiderPerformance?>? future = _performance;
    if (future == null) {
      return const Text('Rider performance is not wired up in this build.',
          style: ConsoleText.body);
    }

    return FutureBuilder<RiderPerformance?>(
      future: future,
      builder: (BuildContext context, AsyncSnapshot<RiderPerformance?> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const _Loading();
        final RiderPerformance? p = snapshot.data;
        if (p == null) {
          return const Text('Could not read this rider\'s performance just now.',
              style: ConsoleText.body);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _line('Claimed', '${p.claimed}'),
            _line('Delivered', '${p.delivered}'),
            _line('Cancelled after claiming', '${p.cancelledAfterClaim}'),
            // Null exactly when nothing was claimed. A rate of 0% would read as failure and 100%
            // as an invented success; the dash is the only honest answer.
            _line('Completion', p.completionRate == null
                ? '—'
                : '${p.completionRate!.toStringAsFixed(2)}%'),
            const SizedBox(height: DeliverySpacing.sm),
            Text(
              'Counted over ${p.windowDays} days, and only for work done for this company.',
              style: ConsoleText.meta,
            ),
          ],
        );
      },
    );
  }

  Widget _hoursBlock() {
    final Future<HoursOnline?>? future = _hours;
    if (future == null) {
      return const Text('Hours online are not wired up in this build.', style: ConsoleText.body);
    }

    return FutureBuilder<HoursOnline?>(
      future: future,
      builder: (BuildContext context, AsyncSnapshot<HoursOnline?> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const _Loading();
        final HoursOnline? h = snapshot.data;
        if (h == null) {
          // A carrier's foreign rider and an unknown rider answer the identical 404 by design, so
          // this cannot say which it was without inventing the difference.
          return const Text(
            'No presence history for this rider. Nothing is backfilled before the feature '
            'existed.',
            style: ConsoleText.body,
          );
        }

        // Only dates with on-duty time arrive; the zeros across the window are the client's to
        // draw, so a quiet day is visible rather than missing.
        final Map<String, DutyDay> byDate = <String, DutyDay>{
          for (final DutyDay d in h.days) _key(d.date): d,
        };
        final List<DateTime> window = <DateTime>[];
        for (DateTime day = h.from;
            !day.isAfter(h.to);
            day = DateTime(day.year, day.month, day.day + 1)) {
          window.add(day);
        }

        final double total = h.totalSecondsOnline / 3600;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _line('Total', '${total.toStringAsFixed(2)} h'),
            const SizedBox(height: DeliverySpacing.sm),
            for (final DateTime day in window)
              _line(
                _date(day),
                byDate[_key(day)] == null
                    ? '0.00 h'
                    : '${byDate[_key(day)]!.hoursOnline.toStringAsFixed(2)} h'
                        ' · ${byDate[_key(day)]!.sessions} '
                        '${byDate[_key(day)]!.sessions == 1 ? 'shift' : 'shifts'}',
              ),
            const SizedBox(height: DeliverySpacing.sm),
            Text('Days are split in the ${h.zone} zone, as the server reports them.',
                style: ConsoleText.meta),
          ],
        );
      },
    );
  }

  Widget _application(OnboardingApplication a) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _line('Email', a.contactEmail),
        _line('Phone', a.contactPhone ?? '—'),
        _line('Applied', a.createdAt == null ? '—' : _date(a.createdAt!)),
        _line('Joined', a.decidedAt == null ? '—' : _date(a.decidedAt!)),
        for (final MapEntry<String, String> e in a.details.entries) _line(e.key, e.value),
      ],
    );
  }

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _stamp(DateTime at) =>
      '${_date(at)}, ${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  static Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: DeliverySpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(label, style: ConsoleText.body.copyWith(color: DeliveryColors.muted)),
            ),
            const SizedBox(width: DeliverySpacing.sm),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: ConsoleText.body.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: DeliverySpacing.sm),
      child: SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.brand),
      ),
    );
  }
}

// --------------------------------------------------------------------------- adding a rider

/// The waiting applicants, approved in place. Approving creates the account and puts them on the
/// fleet — the same call the Onboarding page makes, from the page about riders.
class _WaitingList extends StatefulWidget {
  const _WaitingList({
    required this.waiting,
    required this.blurb,
    required this.onHire,
    required this.onFailure,
  });

  final List<OnboardingApplication> waiting;
  final String blurb;
  final Future<void> Function(OnboardingApplication) onHire;
  final String Function(Object) onFailure;

  @override
  State<_WaitingList> createState() => _WaitingListState();
}

class _WaitingListState extends State<_WaitingList> {
  final Set<String> _hired = <String>{};
  String? _busyId;
  String? _error;

  Future<void> _hire(OnboardingApplication a) async {
    setState(() {
      _busyId = a.id;
      _error = null;
    });
    try {
      await widget.onHire(a);
      if (!mounted) return;
      setState(() => _hired.add(a.id));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = widget.onFailure(e));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.waiting.isEmpty) {
      return const Text(
        'Nobody has applied to ride for you. Riders reach a fleet by applying — there is no way '
        'to create one directly.',
        style: ConsoleText.body,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(widget.blurb, style: ConsoleText.meta.copyWith(height: 1.4)),
        if (_error != null) ...<Widget>[
          const SizedBox(height: DeliverySpacing.sm),
          Text(_error!,
              style: ConsoleText.body.copyWith(color: DeliveryAccent.critical.color)),
        ],
        const SizedBox(height: ConsoleMetrics.kpiGap),
        for (final OnboardingApplication a in widget.waiting)
          Padding(
            padding: const EdgeInsets.only(bottom: DeliverySpacing.md),
            child: Row(
              children: <Widget>[
                ConsoleAvatar(name: a.contactName, size: 36),
                const SizedBox(width: DeliverySpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(a.contactName,
                          overflow: TextOverflow.ellipsis, style: ConsoleText.cellStrong),
                      Text(a.contactEmail,
                          overflow: TextOverflow.ellipsis, style: ConsoleText.meta),
                    ],
                  ),
                ),
                const SizedBox(width: DeliverySpacing.sm),
                if (_hired.contains(a.id))
                  const ConsoleSmallBadge(label: 'On your fleet')
                else
                  ConsoleButton(
                    label: 'Approve',
                    tone: ConsoleButtonTone.tinted,
                    busy: _busyId == a.id,
                    onPressed: _busyId == null ? () => _hire(a) : null,
                  ),
              ],
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: ConsoleButton(
            label: 'Done',
            tone: ConsoleButtonTone.outlined,
            onPressed: () => Navigator.of(context).pop(_hired.isNotEmpty),
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------------- suspension

/// What a suspension dialog comes back with: the reason the server requires, and an optional note.
class _StandingAnswer {
  const _StandingAnswer({this.reason, this.note});

  /// Null on a reinstatement, which needs none.
  final SuspensionReason? reason;
  final String? note;
}

/// Suspending or reinstating one rider.
///
/// The reason is typed rather than free text because the server's enum is what the record is
/// searched by later; the note beside it is the free half, and is optional on both.
class _StandingDialog extends StatefulWidget {
  const _StandingDialog({required this.name, required this.suspending});

  final String name;
  final bool suspending;

  @override
  State<_StandingDialog> createState() => _StandingDialogState();
}

class _StandingDialogState extends State<_StandingDialog> {
  SuspensionReason? _reason;
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool ready = !widget.suspending || _reason != null;

    return AlertDialog(
      backgroundColor: DeliveryColors.white,
      surfaceTintColor: DeliveryColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
      ),
      title: Text(
        widget.suspending ? 'Suspend ${widget.name}' : 'Reinstate ${widget.name}',
        style: ConsoleText.cardTitle,
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.suspending
                  ? 'They keep their sign-in and their history, and stop being offered work. '
                      'You can reinstate them here at any time.'
                  : 'They can be offered work again from the moment this is saved.',
              style: ConsoleText.pageSubtitle,
            ),
            if (widget.suspending) ...<Widget>[
              const SizedBox(height: DeliverySpacing.md),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ConsoleSelect(
                  label: _reason?.label ?? 'Choose a reason',
                  icon: Icons.flag_outlined,
                  options: <ConsoleOption>[
                    for (final SuspensionReason r in SuspensionReason.values)
                      ConsoleOption(label: r.label, value: r.wire),
                  ],
                  onSelected: (String? wire) =>
                      setState(() => _reason = SuspensionReason.fromWire(wire)),
                ),
              ),
            ],
            const SizedBox(height: DeliverySpacing.md),
            TextField(
              controller: _note,
              maxLines: 3,
              maxLength: 500,
              style: ConsoleText.cell,
              cursorColor: DeliveryColors.brand,
              decoration: InputDecoration(
                hintText: 'A note for the record (optional)',
                hintStyle: const TextStyle(fontSize: 14, color: DeliveryColors.faint),
                filled: true,
                fillColor: DeliveryColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                  borderSide: const BorderSide(color: DeliveryColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                  borderSide: const BorderSide(color: DeliveryColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                  borderSide: const BorderSide(color: DeliveryColors.brand),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            t.cancel,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.muted,
            ),
          ),
        ),
        if (widget.suspending)
          ConsoleSoftButton(
            label: 'Suspend rider',
            onPressed: ready ? () => _pop(context) : null,
          )
        else
          ConsolePrimaryButton(
            label: 'Reinstate rider',
            color: DeliveryAccent.positive.color,
            onPressed: () => _pop(context),
          ),
      ],
    );
  }

  void _pop(BuildContext context) {
    final String note = _note.text.trim();
    Navigator.pop(
      context,
      _StandingAnswer(reason: _reason, note: note.isEmpty ? null : note),
    );
  }
}
