import 'dart:math' as math;

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import '../shell/console_controls.dart';
import '../shell/shell.dart';
import 'fleet_roster.dart';
import 'rider_profile_screen.dart';

/// The company's rider roster — Figma `web-carrier-riders-directory` (112:413), "Riders HR
/// Directory".
///
/// It supersedes the older "Riders Management" table (3:3589) on the same destination and keeps
/// everything that table could do: search, a working-now view (tap a presence card), "Add Rider"
/// approving somebody who is actually waiting, every rider's detail (now a full profile page
/// rather than a drawer) and suspension (on that profile). The score card and the pause switch
/// that sat under the table moved to the dashboard: the score to the foot of the page and the
/// switch to its top bar (`company_standing.dart`).
///
/// What the design draws and the platform cannot say is left out rather than faked:
///
/// * There is no **"On break"**. Presence is on duty, signal lost or off duty; the third card is
///   signal lost — declared on duty and gone quiet — which is a different fact from a break.
/// * **Zone** is the region the rider typed on their application. Nothing assigns a rider to one
///   of the company's coverage zones, and the filter's tooltip and the footnote say so.
/// * **Rating** is the order service's aggregate; an unrated rider reads "New", never 0.
/// * A figure whose source failed is a dash, and a failed roster is never "everyone offline".
///
/// Opening a rider swaps the profile in place, inside this destination, so the rail stays put and
/// "Back to riders" lands on the same filters. The portal has no router to push onto.
class RidersDirectoryScreen extends StatefulWidget {
  const RidersDirectoryScreen({
    super.key,
    required this.api,
    required this.orderApi,
    required this.onboardingApi,
    required this.managementApi,
    required this.trackingApi,
    required this.performanceApi,
    required this.documentsApi,
    this.notificationApi,
    this.riderPages = const <RiderPage>[],
  });

  final DeliveryProviderApi api;

  /// The job board (the "On a job" fallback) and each rider's rating aggregate.
  final OrderApi orderApi;

  /// The company's applications: names, references, regions, vehicles, and who is waiting.
  final OnboardingApi onboardingApi;

  /// The carrier-side suspend / reinstate / standing endpoints.
  final PartnerManagementApi managementApi;

  /// The roster and one rider's hours online.
  final TrackingApi trackingApi;

  /// Delivered today, thirty days of a rider's work for this company, and its daily series.
  final RiderPerformanceApi performanceApi;

  /// A rider's own papers, on their profile.
  final DocumentsApi documentsApi;

  /// The operator's inbox behind the topbar bell. Optional: without it the bell is not drawn.
  final NotificationApi? notificationApi;

  /// Pages opened from one rider's profile — see [RiderPage]. Empty until such a page exists.
  final List<RiderPage> riderPages;

  @override
  State<RidersDirectoryScreen> createState() => _RidersDirectoryScreenState();
}

class _RidersDirectoryScreenState extends State<RidersDirectoryScreen> {
  CarrierFleet? _fleet;
  bool _loading = true;

  final TextEditingController _search = TextEditingController();
  String _query = '';
  String? _zone;
  String? _vehicle;
  PresenceBucket? _bucket;

  /// The rider whose profile is open, or null for the directory itself.
  String? _open;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final CarrierFleet fleet = await CarrierFleet.load(
        provider: widget.api,
        order: widget.orderApi,
        onboarding: widget.onboardingApi,
        tracking: widget.trackingApi,
        performance: widget.performanceApi,
      );
      if (!mounted) return;
      setState(() {
        _fleet = fleet;
        _loading = false;
        // A rider who has left the fleet has no profile here to stay on.
        if (_open != null && !fleet.riders.contains(_open)) _open = null;
      });
    } catch (_) {
      if (!mounted) return;
      // A reload that fails leaves the last good fleet on screen; only a first load that fails is
      // the "no company" page.
      setState(() => _loading = false);
    }
  }

  void _reload() {
    setState(() => _loading = true);
    _load();
  }

  void _tell(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final CarrierFleet? fleet = _fleet;

    if (fleet == null) {
      if (_loading) {
        return Container(
          color: DeliveryColors.background,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(color: DeliveryColors.brand),
        );
      }
      // By far the likeliest cause: this account is attached to no company, which the server
      // answers with a 404. Saying that plainly beats a raw error.
      return _centred(Icons.help_outline, t.noCompanyYet, t.askThePlatformToAttachYou);
    }

    final String? open = _open;
    if (open != null) {
      return RiderProfileScreen(
        fleet: fleet,
        riderId: open,
        providerApi: widget.api,
        managementApi: widget.managementApi,
        trackingApi: widget.trackingApi,
        performanceApi: widget.performanceApi,
        documentsApi: widget.documentsApi,
        notificationApi: widget.notificationApi,
        riderPages: widget.riderPages,
        onBack: () => setState(() => _open = null),
        onChanged: _reload,
        onReleased: (String name) {
          setState(() => _open = null);
          _tell(t.carrRidersTerminated(name));
          _reload();
        },
      );
    }

    return ConsolePage(
      header: ConsoleTopbar(
        title: t.carrRidersTitle,
        subtitle: t.carrRidersSubtitle,
        actions: <Widget>[
          ConsoleIconAction(icon: Icons.refresh, tooltip: t.refresh, onPressed: _reload),
          if (widget.notificationApi != null) ConsoleBell(api: widget.notificationApi),
        ],
      ),
      children: <Widget>[
        ConsoleKpiRow(cards: _stats(fleet, t)),
        _filters(fleet, t),
        _grid(fleet, t),
        Text(t.carrRidersDirectoryFootnote, style: ConsoleText.meta.copyWith(height: 1.4)),
      ],
    );
  }

  // ------------------------------------------------------------------ stat cards

  /// The design's four cards. The three presence cards filter the grid when tapped — the old
  /// table's "Working now" tab, one tap away as before — and go inert when presence could not be
  /// read, because a filter over an unknown is a list of guesses.
  List<Widget> _stats(CarrierFleet fleet, DeliveryStrings t) {
    final bool presence = fleet.roster != null;

    Widget card(PresenceBucket bucket, String label, String note, IconData icon) =>
        ConsoleKpiCard(
          label: label,
          value: fleet.countIn(bucket)?.toString() ?? '—',
          icon: icon,
          footnote: _note(presence ? note : t.carrRidersPresenceUnknown),
          onTap: presence
              ? () => setState(() => _bucket = _bucket == bucket ? null : bucket)
              : null,
        );

    return <Widget>[
      ConsoleKpiCard(
        label: t.carrRidersStatTotal,
        value: '${fleet.riders.length}',
        icon: Icons.groups_outlined,
        footnote: _note(t.carrRidersStatTotalNote),
        onTap: _bucket == null ? null : () => setState(() => _bucket = null),
      ),
      card(PresenceBucket.onDuty, t.carrRidersStatOnDuty, t.carrRidersStatOnDutyNote,
          Icons.near_me_outlined),
      card(PresenceBucket.signalLost, t.carrRidersStatSignalLost,
          t.carrRidersStatSignalLostNote, Icons.wifi_off_rounded),
      // Off duty by their own declaration. A rider the roster says nothing about is in none of the
      // three presence cards (see [CarrierFleet.bucketOf]), and this card is where a reader would
      // otherwise assume they are, so their number is said here instead of being folded in.
      card(
        PresenceBucket.offline,
        t.carrRidersStatOffline,
        (fleet.withoutPresence ?? 0) > 0
            ? t.carrRidersNoPresenceCount(fleet.withoutPresence!)
            : t.carrRidersStatOfflineNote,
        Icons.bedtime_outlined,
      ),
    ];
  }

  static Widget _note(String text) =>
      Text(text, style: const TextStyle(fontSize: 13, color: DeliveryColors.faint));

  String _bucketLabel(DeliveryStrings t, PresenceBucket bucket) => switch (bucket) {
        PresenceBucket.onDuty => t.carrRidersStatOnDuty,
        PresenceBucket.signalLost => t.carrRidersStatSignalLost,
        PresenceBucket.offline => t.carrRidersStatOffline,
      };

  // ------------------------------------------------------------------ filters

  Widget _filters(CarrierFleet fleet, DeliveryStrings t) {
    // Only values somebody actually has: a filter option that can only ever produce an empty grid
    // is a control that cannot work.
    // One entry per region, so a company rider working in "Achrafieh, Hamra" is found under each.
    final List<String> zones = <String>{
      for (final String r in fleet.riders) ...fleet.regionsOf(r),
    }.toList()
      ..sort();
    final List<String> vehicles = <String>{
      for (final String r in fleet.riders)
        if (fleet.vehicleOf(r) != null) fleet.vehicleOf(r)!,
    }.toList()
      ..sort();

    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.lg - DeliverySpacing.xs),
      decoration: ConsoleSurface.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Wrap(
                  spacing: DeliverySpacing.md - DeliverySpacing.xs,
                  runSpacing: DeliverySpacing.md - DeliverySpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    ConsoleSearchField(
                      hintText: t.carrRidersSearchHint,
                      controller: _search,
                      width: 260,
                      onChanged: (String value) => setState(() => _query = value.trim()),
                    ),
                    ConsoleSelect(
                      label: _zone == null ? t.carrRidersZoneAll : t.carrRidersZoneValue(_zone!),
                      icon: Icons.place_outlined,
                      tooltip: t.carrRidersZoneTooltip,
                      options: <ConsoleOption>[
                        ConsoleOption(label: t.carrRidersZoneAll, value: null),
                        for (final String zone in zones) ConsoleOption(label: zone, value: zone),
                      ],
                      onSelected: (String? zone) => setState(() => _zone = zone),
                    ),
                    ConsoleSelect(
                      label: _vehicle == null
                          ? t.carrRidersVehicleAll
                          : t.carrRidersVehicleValue(vehicleLabel(t, _vehicle!)),
                      icon: Icons.two_wheeler_outlined,
                      options: <ConsoleOption>[
                        ConsoleOption(label: t.carrRidersVehicleAll, value: null),
                        for (final String wire in vehicles)
                          ConsoleOption(label: vehicleLabel(t, wire), value: wire),
                      ],
                      onSelected: (String? wire) => setState(() => _vehicle = wire),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DeliverySpacing.md),
              // Riders reach a fleet by applying and being approved, so the design's "Add Rider"
              // opens the people waiting for exactly that and approves them in place. When the
              // applications could not be read there is nobody to show, and the tooltip says so.
              Tooltip(
                message: fleet.applicationsLoaded
                    ? t.carrRidersAddRiderTooltip
                    : t.carrRidersAddRiderUnavailable,
                child: ConsolePrimaryButton(
                  label: t.carrRidersAddRider,
                  icon: Icons.add,
                  onPressed: fleet.applicationsLoaded ? () => _openWaiting(fleet) : null,
                ),
              ),
            ],
          ),
          if (_bucket != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: DeliverySpacing.sm,
              children: <Widget>[
                Text(t.carrRidersShowingOnly(_bucketLabel(t, _bucket!)),
                    style: ConsoleText.body.copyWith(color: DeliveryColors.muted)),
                ConsoleTintButton(
                  label: t.carrRidersShowEveryone,
                  onPressed: () => setState(() => _bucket = null),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  bool _matches(CarrierFleet fleet, String rider) {
    if (_bucket != null && fleet.bucketOf(rider) != _bucket) return false;
    if (_zone != null && !fleet.regionsOf(rider).contains(_zone)) return false;
    if (_vehicle != null && fleet.vehicleOf(rider) != _vehicle) return false;
    if (_query.isEmpty) return true;
    final String needle = _query.toLowerCase();
    return fleet.nameOf(rider).toLowerCase().contains(needle) ||
        fleet.referenceOf(rider).toLowerCase().contains(needle) ||
        shortRiderRef(rider).toLowerCase().contains(needle) ||
        (fleet.regionOf(rider) ?? '').toLowerCase().contains(needle);
  }

  // ------------------------------------------------------------------ the grid

  Widget _grid(CarrierFleet fleet, DeliveryStrings t) {
    final List<String> riders =
        fleet.riders.where((String r) => _matches(fleet, r)).toList();

    if (riders.isEmpty) {
      return ConsoleCard(
        child: Text(
          // Worth stating outright: a company with no riders looks available and can collect
          // nothing, which is the most confusing way to be sent no work.
          fleet.riders.isEmpty ? t.noRidersBlurb : t.carrRidersNoMatch,
          style: ConsoleText.pageSubtitle,
        ),
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // The design's 268px cards, as many across as fit, stretched to fill the row rather than
        // leaving a ragged gap on the end.
        const double gap = DeliverySpacing.md;
        const double minCard = 268;
        final int columns =
            math.max(1, ((constraints.maxWidth + gap) / (minCard + gap)).floor());
        final double width =
            ((constraints.maxWidth - gap * (columns - 1)) / columns).floorToDouble();

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final String rider in riders)
              SizedBox(
                width: width,
                child: _RiderCard(
                  fleet: fleet,
                  rider: rider,
                  onOpen: () => setState(() => _open = rider),
                ),
              ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------------ adding a rider

  /// The people waiting to ride for this company, approved in place. Approving creates their
  /// account and puts them on the fleet, which is said before the button is pressed.
  Future<void> _openWaiting(CarrierFleet fleet) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool? hired = await showConsoleDrawer<bool>(
      context: context,
      title: t.carrRidersWaitingTitle,
      subtitle: t.carrRidersWaitingCount(fleet.waiting.length),
      builder: (BuildContext context) => _WaitingList(
        waiting: fleet.waiting,
        onHire: (OnboardingApplication a) => widget.onboardingApi.hire(fleet.company.id, a.id),
      ),
    );
    if (hired == true) _reload();
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
}

/// One rider, as the design's card draws them: reference and badge, avatar, name, rating and
/// today's count, then region and vehicle, then "Manage Profile". The whole card opens the
/// profile too, the way a console table row opens its drawer.
class _RiderCard extends StatelessWidget {
  const _RiderCard({required this.fleet, required this.rider, required this.onOpen});

  final CarrierFleet fleet;
  final String rider;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final Widget? badge = riderStatusPill(t, fleet.statusOf(rider));
    final RiderStanding? standing = fleet.ratings[rider];
    final int? today = fleet.deliveredTodayBy(rider);
    final String? vehicle = fleet.vehicleOf(rider);

    final String rating = standing == null
        ? '—'
        : standing.isRated
            ? standing.average!.toStringAsFixed(1)
            // Unrated is new, not terrible. A zero here would be a lie about someone's living.
            : t.carrRidersRatingNew;

    return Container(
      decoration: ConsoleSurface.card(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(DeliveryRadius.lg),
          child: Padding(
            padding: const EdgeInsets.all(DeliverySpacing.lg - DeliverySpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      // Left to right on an Arabic card too, still at the card's start edge:
                      // "REF-884#" is not the reference anybody quotes.
                      child: FleetCode(
                        '#${fleet.referenceOf(rider)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: DeliveryColors.faint,
                        ),
                      ),
                    ),
                    if (badge != null) badge,
                  ],
                ),
                const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                Row(
                  children: <Widget>[
                    ConsoleAvatar(name: fleet.nameOf(rider), size: 48),
                    const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            fleet.nameOf(rider),
                            overflow: TextOverflow.ellipsis,
                            style: ConsoleText.cellStrong.copyWith(fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: <Widget>[
                              Icon(Icons.star_rounded, size: 14, color: DeliveryAccent.caution.color),
                              const SizedBox(width: DeliverySpacing.xs),
                              Text(
                                rating,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: DeliveryColors.ink,
                                ),
                              ),
                              // Absent when the count could not be read: a "(0 today)" there
                              // would be a number the platform does not have.
                              if (today != null) ...<Widget>[
                                const SizedBox(width: DeliverySpacing.xs),
                                Flexible(
                                  child: Text(
                                    t.carrRidersDeliveredToday(today),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12, color: DeliveryColors.faint),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(vertical: DeliverySpacing.md),
                  color: DeliveryColors.borderFaint,
                ),
                _line(Icons.place_outlined, fleet.regionOf(rider)),
                const SizedBox(height: DeliverySpacing.xs + 2),
                _line(Icons.near_me_outlined, vehicle == null ? null : vehicleLabel(t, vehicle)),
                const SizedBox(height: DeliverySpacing.md),
                ConsoleButton(
                  label: t.carrRidersManageProfile,
                  tone: ConsoleButtonTone.outlined,
                  onPressed: onOpen,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _line(IconData icon, String? value) => Row(
        children: <Widget>[
          Icon(icon, size: 14, color: DeliveryColors.faint),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              value ?? '—',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: value == null ? DeliveryColors.faint : DeliveryColors.muted,
              ),
            ),
          ),
        ],
      );
}

/// The waiting applicants, approved in place — the same call the Applicants page makes, from the
/// page about riders. Moved from the old fleet table unchanged, and localised.
class _WaitingList extends StatefulWidget {
  const _WaitingList({required this.waiting, required this.onHire});

  final List<OnboardingApplication> waiting;
  final Future<void> Function(OnboardingApplication) onHire;

  @override
  State<_WaitingList> createState() => _WaitingListState();
}

class _WaitingListState extends State<_WaitingList> {
  final Set<String> _hired = <String>{};
  String? _busyId;
  String? _error;

  Future<void> _hire(OnboardingApplication a) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
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
      setState(() => _error = serverMessage(e, t));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    if (widget.waiting.isEmpty) {
      return Text(t.carrRidersWaitingEmpty, style: ConsoleText.body);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Irreversible, so it is said before the button rather than after.
        Text(t.hiringAlsoCreatesTheirAccount, style: ConsoleText.meta.copyWith(height: 1.4)),
        if (_error != null) ...<Widget>[
          const SizedBox(height: DeliverySpacing.sm),
          Text(_error!, style: ConsoleText.body.copyWith(color: DeliveryAccent.critical.color)),
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
                  ConsoleSmallBadge(label: t.carrRidersOnYourFleet)
                else
                  ConsoleButton(
                    label: t.carrRidersApprove,
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
            label: t.done,
            tone: ConsoleButtonTone.outlined,
            onPressed: () => Navigator.of(context).pop(_hired.isNotEmpty),
          ),
        ),
      ],
    );
  }
}
