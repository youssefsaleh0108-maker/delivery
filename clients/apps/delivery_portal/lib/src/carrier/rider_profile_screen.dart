import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../shell/console_controls.dart';
import '../shell/shell.dart';
import 'fleet_roster.dart';
import 'rider_standing_dialog.dart';

/// Who a per-rider page is about, handed to every [RiderPage].
class RiderPageContext {
  const RiderPageContext({
    required this.riderId,
    required this.name,
    required this.companyId,
    this.application,
  });

  /// The rider's Keycloak subject — what every rider endpoint is addressed by.
  final String riderId;

  /// Their name from their application, or the short reference when they have none.
  final String name;

  /// The caller's own company. Carrier endpoints resolve it from the token anyway; it is here for
  /// the few onboarding routes that carry it in the path and check it server-side.
  final String companyId;

  /// Their application to this company. Null for a rider the platform attached directly.
  final OnboardingApplication? application;
}

/// A page about ONE rider, opened from their profile: the extension point for per-rider HR pages
/// such as a rider's attendance month or their pay history.
///
/// The profile draws one button per entry in its actions panel and swaps the page in place, with
/// [RiderPage.build]'s `onBack` returning to the profile — the same no-router pattern the
/// directory uses to open the profile. The list is owned by the shell
/// (`PortalArea.carrierRiderPages`), which is the one place holding every API client, so a page
/// needs no plumbing through these screens. The list is empty until such a page exists: a button
/// with nothing behind it would be a dead control.
class RiderPage {
  const RiderPage({required this.icon, required this.label, required this.build});

  final IconData icon;
  final String Function(DeliveryStrings) label;
  final Widget Function(BuildContext context, RiderPageContext rider, VoidCallback onBack) build;
}

/// One rider's HR record — Figma `web-carrier-rider-profile` (112:740), "Rider HR Profile", opened
/// from the directory's "Manage Profile".
///
/// Built on the endpoints the platform has, and only those:
///
/// * **Identity** is the rider's application to this company: name, reference (the design's badge
///   id — the platform issues no badge numbers), phone and the email they applied with. There is
///   no emergency contact anywhere on the platform, so the design's row is not drawn.
/// * **Documents** are the rider's own uploaded papers and their verdicts. The rider set is
///   national ID, driving licence and vehicle registration; the design's "vehicle insurance" and
///   its "expiring" state have no source (no document carries an expiry date).
/// * **Performance** is thirty days of this rider's work for THIS company. The design's on-time
///   rate has no definition on the platform — no order carries a promised time — so its card is
///   the completion rate; the average delivery time, rank and "city average" have no per-rider
///   source and are not drawn. The output chart is the new per-day series, zero-filled.
/// * **Employment** is the start date and what the application said. Contract type, pay rate and
///   zone assignment are recorded nowhere, and a note says so instead of printing a plausible rate
///   that nobody pays.
/// * **Actions**: suspend or reinstate (with the typed reason the server requires) while the
///   rider's standing is known, and "Terminate Contract" — the rider comes off this fleet onto no
///   fleet at all, with a reason kept on record, refused while they carry one of this company's
///   jobs. The design's "Edit Profile" has no endpoint a carrier may call, so it is not drawn.
class RiderProfileScreen extends StatefulWidget {
  const RiderProfileScreen({
    super.key,
    required this.fleet,
    required this.riderId,
    required this.providerApi,
    required this.managementApi,
    required this.trackingApi,
    required this.performanceApi,
    required this.documentsApi,
    required this.onBack,
    required this.onChanged,
    required this.onReleased,
    this.notificationApi,
    this.riderPages = const <RiderPage>[],
  });

  final CarrierFleet fleet;
  final String riderId;

  final DeliveryProviderApi providerApi;
  final PartnerManagementApi managementApi;
  final TrackingApi trackingApi;
  final RiderPerformanceApi performanceApi;
  final DocumentsApi documentsApi;
  final NotificationApi? notificationApi;
  final List<RiderPage> riderPages;

  /// Back to the directory.
  final VoidCallback onBack;

  /// Something about the rider changed (a suspension); the directory reloads its fleet.
  final VoidCallback onChanged;

  /// The rider is off the fleet; the directory closes this page and says so.
  final void Function(String name) onReleased;

  @override
  State<RiderProfileScreen> createState() => _RiderProfileScreenState();
}

class _RiderProfileScreenState extends State<RiderProfileScreen> {
  /// The window the server counts performance over, and the chart's length to match.
  static const int _windowDays = 30;

  /// A week of hours online, which is what a dispatcher reads.
  static const int _hoursDays = 7;

  late final Future<RiderPerformance?> _performance =
      _try(() => widget.performanceApi.forRider(widget.riderId));
  late final Future<RiderDailyOutput?> _daily =
      _try(() => widget.performanceApi.dailyForRider(widget.riderId, days: _windowDays));
  late final Future<({HoursOnline? hours, bool notFound})> _hours = _readHours();
  late final Future<List<ReviewedDocument>?>? _documents = _application == null
      ? null
      : _try(() => widget.documentsApi
          .companyApplicantDocuments(widget.fleet.company.id, _application!.id));

  bool _busy = false;
  RiderPage? _page;

  OnboardingApplication? get _application => widget.fleet.applications[widget.riderId];
  String get _name => widget.fleet.nameOf(widget.riderId);

  static Future<T?> _try<T>(Future<T> Function() load) async {
    try {
      return await load();
    } catch (_) {
      return null;
    }
  }

  /// A week of hours, and whether the tracking service answered "not found". The two failures read
  /// differently: a 404 is the service declining to show this company the rider's hours — nothing
  /// recorded for them here, or a rider it no longer counts as this company's, which it will not
  /// tell apart from one that does not exist — while anything else is a read that did not work.
  Future<({HoursOnline? hours, bool notFound})> _readHours() async {
    try {
      final HoursOnline hours =
          await widget.trackingApi.riderDutyHours(widget.riderId, days: _hoursDays);
      return (hours: hours, notFound: false);
    } on DioException catch (e) {
      return (hours: null, notFound: e.response?.statusCode == 404);
    } catch (_) {
      return (hours: null, notFound: false);
    }
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

    final RiderPage? page = _page;
    if (page != null) {
      return page.build(
        context,
        RiderPageContext(
          riderId: widget.riderId,
          name: _name,
          companyId: widget.fleet.company.id,
          application: _application,
        ),
        () => setState(() => _page = null),
      );
    }

    return ConsolePage(
      header: ConsoleTopbar(
        title: t.carrRidersProfileTitle,
        subtitle: t.carrRidersProfileSubtitle,
        actions: <Widget>[
          // The design draws no way back; a page swapped in place without one is a dead end.
          ConsoleButton(
            label: t.carrRidersBackToDirectory,
            icon: Icons.arrow_back,
            tone: ConsoleButtonTone.outlined,
            onPressed: widget.onBack,
          ),
          if (widget.notificationApi != null) ConsoleBell(api: widget.notificationApi),
        ],
      ),
      children: <Widget>[
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Widget identity = _identity(t);
            final Widget documents = _documentsCard(t);
            final Widget kpis = _kpis(t);
            final Widget chart = _chart(t);
            final Widget hours = _hoursCard(t);
            final Widget employment = _employment(t);
            final Widget actions = _actions(t);

            // The design's three columns (360 / flex / 320) where they fit, two below that, and
            // one stack on a narrow window.
            if (constraints.maxWidth >= 1100) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(width: 340, child: _column(<Widget>[identity, documents])),
                  const SizedBox(width: ConsoleMetrics.pageGap),
                  Expanded(child: _column(<Widget>[kpis, chart, hours])),
                  const SizedBox(width: ConsoleMetrics.pageGap),
                  SizedBox(width: 300, child: _column(<Widget>[employment, actions])),
                ],
              );
            }
            if (constraints.maxWidth >= 760) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 320,
                    child: _column(<Widget>[identity, actions, employment, documents]),
                  ),
                  const SizedBox(width: ConsoleMetrics.pageGap),
                  Expanded(child: _column(<Widget>[kpis, chart, hours])),
                ],
              );
            }
            return _column(
                <Widget>[identity, actions, kpis, chart, hours, employment, documents]);
          },
        ),
      ],
    );
  }

  static Widget _column(List<Widget> blocks) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < blocks.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: ConsoleMetrics.pageGap),
            blocks[i],
          ],
        ],
      );

  // ------------------------------------------------------------------ identity

  Widget _identity(DeliveryStrings t) {
    final CarrierFleet fleet = widget.fleet;
    final OnboardingApplication? application = _application;
    final Widget? badge = riderStatusPill(t, fleet.statusOf(widget.riderId));
    final RiderPresence? presence = fleet.roster?[widget.riderId];

    // A dash when the roster could not be read, or when they declared duty and never sent a fix.
    final String? lastSeen = fleet.roster == null
        ? null
        : presence == null
            // Missing from this company's roster, which says nothing about their duty — see
            // [CarrierFleet.bucketOf] — so it is said as exactly that.
            ? t.carrRidersNoPresenceYet
            : presence.lastSeenAt == null
                ? null
                : _stamp(presence.lastSeenAt!);

    return Container(
      padding: const EdgeInsets.all(ConsoleMetrics.cardPadding),
      decoration: ConsoleSurface.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Center(child: ConsoleAvatar(name: _name, size: 80)),
          const SizedBox(height: DeliverySpacing.md),
          Text(_name, textAlign: TextAlign.center, style: ConsoleText.cardTitle),
          const SizedBox(height: DeliverySpacing.xs),
          Text(
            // Isolated, so an Arabic sentence keeps the reference's letters, hyphen and digits in
            // their own order.
            t.carrRidersBadgeId(ltrIsolate(fleet.referenceOf(widget.riderId))),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.faint,
            ),
          ),
          if (badge != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Center(child: badge),
          ],
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: DeliverySpacing.lg - DeliverySpacing.xs),
            color: DeliveryColors.borderFaint,
          ),
          if (application == null)
            Padding(
              padding: const EdgeInsets.only(bottom: DeliverySpacing.md - DeliverySpacing.xs),
              // "Attached directly" is only known when the applications were read. When they were
              // not, the page cannot tell, and says that rather than a reason it made up.
              child: Text(
                  fleet.applicationsLoaded ? t.carrRidersNoApplication : t.carrRidersCouldNotRead,
                  style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.4)),
            )
          else ...<Widget>[
            _fact(t.carrRidersPhone, application.contactPhone),
            _fact(t.carrRidersEmail, application.contactEmail),
            // The national ID to its last three characters: enough to tell riders apart or match a
            // paper in hand, and the whole number is on the verified document in the card below.
            // No date of birth at all — that document carries it too, and a birth date in plain
            // text on an office screen is personal data dispatching a rider does not need.
            _fact(
              t.carrRidersNationalIdNumber,
              switch (application.details['nationalId']?.trim()) {
                null || '' => null,
                final String id => ltrIsolate(maskedNationalId(id)),
              },
            ),
          ],
          _fact(t.carrRidersLastSeen, lastSeen),
          // When they last went on or off duty — "on duty since seven" is how a dispatcher reads
          // a shift, and the old rider drawer said it.
          if (presence?.dutyChangedAt != null)
            _fact(t.carrRidersDutyChanged, _stamp(presence!.dutyChangedAt!)),
          if (presence?.state == PresenceState.stale)
            Text(t.carrRidersStaleNote, style: ConsoleText.meta.copyWith(height: 1.4)),
          if (fleet.roster != null && presence == null)
            Text(t.carrRidersNoPresenceNote, style: ConsoleText.meta.copyWith(height: 1.4)),
        ],
      ),
    );
  }

  String _stamp(DateTime at) {
    final MaterialLocalizations l = MaterialLocalizations.of(context);
    return '${consoleDate(context, at)}, '
        '${l.formatTimeOfDay(TimeOfDay.fromDateTime(at), alwaysUse24HourFormat: true)}';
  }

  /// A label over its value, the design's bio and employment rows. A value the platform does not
  /// have is the faint dash, never an empty line that reads as "blank on purpose".
  static Widget _fact(String label, String? value) => Padding(
        padding: const EdgeInsets.only(bottom: DeliverySpacing.md - DeliverySpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: DeliveryColors.faint,
              ),
            ),
            const SizedBox(height: 2),
            if (value == null || value.trim().isEmpty)
              const FleetUnknown()
            else
              Text(value, style: ConsoleText.cell),
          ],
        ),
      );

  // ------------------------------------------------------------------ documents

  /// The papers a rider is asked for, in the order the rider wizard asks for them.
  static const List<ApplicantDocumentKind> _riderPapers = <ApplicantDocumentKind>[
    ApplicantDocumentKind.nationalId,
    ApplicantDocumentKind.drivingLicence,
    ApplicantDocumentKind.vehicleRegistration,
  ];

  String _kindLabel(DeliveryStrings t, ReviewedDocument doc) => switch (doc.kind) {
        ApplicantDocumentKind.nationalId => t.carrRidersDocNationalId,
        ApplicantDocumentKind.drivingLicence => t.carrRidersDocDrivingLicence,
        ApplicantDocumentKind.vehicleRegistration => t.carrRidersDocVehicleRegistration,
        final ApplicantDocumentKind other => other.label,
        null => doc.kindWire,
      };

  String _paperLabel(DeliveryStrings t, ApplicantDocumentKind kind) => switch (kind) {
        ApplicantDocumentKind.nationalId => t.carrRidersDocNationalId,
        ApplicantDocumentKind.drivingLicence => t.carrRidersDocDrivingLicence,
        ApplicantDocumentKind.vehicleRegistration => t.carrRidersDocVehicleRegistration,
        _ => kind.label,
      };

  Widget _documentsCard(DeliveryStrings t) {
    final Future<List<ReviewedDocument>?>? documents = _documents;

    return ConsoleCard(
      title: t.carrRidersDocumentsTitle,
      child: documents == null
          // "Attached directly" only when the applications were read; otherwise the page does not
          // know why there are no papers to ask for, and says only that it could not read them.
          ? Text(
              widget.fleet.applicationsLoaded
                  ? t.carrRidersNoApplication
                  : t.carrRidersCouldNotRead,
              style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.4))
          : FutureBuilder<List<ReviewedDocument>?>(
              future: documents,
              builder: (BuildContext context, AsyncSnapshot<List<ReviewedDocument>?> snapshot) {
                if (snapshot.connectionState != ConnectionState.done) return const _Loading();
                final List<ReviewedDocument>? docs = snapshot.data;
                if (docs == null) {
                  return Text(t.carrRidersCouldNotRead,
                      style: ConsoleText.body.copyWith(color: DeliveryColors.muted));
                }

                // A replaced upload keeps its verdict on the record, but it is not the paper the
                // rider rides on; only the current one of each kind is shown.
                final List<ReviewedDocument> current =
                    docs.where((ReviewedDocument d) => !d.superseded).toList();
                ReviewedDocument? currentOf(ApplicantDocumentKind kind) {
                  for (final ReviewedDocument d in current) {
                    if (d.kind == kind) return d;
                  }
                  return null;
                }

                final List<Widget> rows = <Widget>[
                  for (final ApplicantDocumentKind kind in _riderPapers)
                    if (currentOf(kind) case final ReviewedDocument doc)
                      _documentRow(t, _kindLabel(t, doc), doc)
                    else
                      _documentRow(t, _paperLabel(t, kind), null),
                  for (final ReviewedDocument doc in current)
                    if (!_riderPapers.contains(doc.kind)) _documentRow(t, _kindLabel(t, doc), doc),
                ];
                return Column(mainAxisSize: MainAxisSize.min, children: rows);
              },
            ),
    );
  }

  Widget _documentRow(DeliveryStrings t, String label, ReviewedDocument? doc) {
    final Widget badge = doc == null
        ? ConsoleStatusPill.quiet(label: t.carrRidersDocNotUploaded)
        : switch (doc.status) {
            ApplicantDocumentStatus.approved =>
              ConsoleStatusPill(label: t.carrRidersDocVerified, accent: DeliveryAccent.positive),
            ApplicantDocumentStatus.pending =>
              ConsoleStatusPill(label: t.carrRidersDocWaiting, accent: DeliveryAccent.caution),
            ApplicantDocumentStatus.rejected =>
              ConsoleStatusPill(label: t.carrRidersDocRefused, accent: DeliveryAccent.critical),
          };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: DeliveryColors.muted)),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          badge,
          // The paper itself, in a new tab. Absent when storage could not sign a URL — a dead
          // button would promise a file this card cannot show.
          if (doc?.viewUrl != null) ...<Widget>[
            const SizedBox(width: DeliverySpacing.xs),
            ConsoleRowAction(
              icon: Icons.open_in_new,
              tooltip: t.carrRidersDocOpen,
              onPressed: () => openExternalLink(doc!.viewUrl!),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ performance

  static Widget _note(String text) =>
      Text(text, style: const TextStyle(fontSize: 13, color: DeliveryColors.faint));

  /// Four- and five-star ratings as a share of all of them. Only called when there are ratings.
  static int _happy(RiderStanding s) =>
      (((s.stars[4] ?? 0) + (s.stars[5] ?? 0)) * 100 / s.ratings).round();

  Widget _kpis(DeliveryStrings t) {
    final RiderStanding? standing = widget.fleet.ratings[widget.riderId];
    final int? today = widget.fleet.deliveredTodayBy(widget.riderId);

    return FutureBuilder<RiderPerformance?>(
      future: _performance,
      builder: (BuildContext context, AsyncSnapshot<RiderPerformance?> snapshot) {
        final bool loading = snapshot.connectionState != ConnectionState.done;
        final RiderPerformance? p = snapshot.data;
        String figure(String Function(RiderPerformance) read) =>
            loading ? '…' : (p == null ? '—' : read(p));

        return ConsoleKpiRow(
          minCardWidth: 200,
          cards: <Widget>[
            ConsoleKpiCard(
              label: t.carrRidersAvgRating,
              value: standing == null
                  ? '—'
                  : standing.isRated
                      ? '${standing.average!.toStringAsFixed(1)} ★'
                      // Unrated is new, never zero.
                      : t.carrRidersRatingNew,
              icon: Icons.star_outline_rounded,
              footnote: _note(standing == null
                  ? t.carrRidersCouldNotRead
                  : standing.isRated && standing.ratings > 0
                      ? t.carrRidersHappyCustomers(_happy(standing))
                      : t.carrRidersNoRatingsYet),
            ),
            ConsoleKpiCard(
              // The server's rolling window, labelled as the window it counted — not "this month".
              label: t.carrRidersDeliveriesWindow(p?.windowDays ?? _windowDays),
              value: figure((RiderPerformance p) => '${p.delivered}'),
              icon: Icons.local_shipping_outlined,
              footnote: loading
                  ? null
                  : _note(p == null
                      ? t.carrRidersCouldNotRead
                      : t.carrRidersClaimedCaption(p.claimed, p.cancelledAfterClaim)),
            ),
            ConsoleKpiCard(
              // In the design's "on-time rate" slot: nothing on the platform says when a delivery
              // was due, so on-time cannot be counted. Completion can, and is what this is.
              label: t.carrRidersCompletionRate,
              // Null exactly when nothing was claimed: 0% would read as failure and 100% as an
              // invented success, so the dash is the only honest answer.
              value: figure((RiderPerformance p) => p.completionRate == null
                  ? '—'
                  : '${p.completionRate!.toStringAsFixed(1)}%'),
              icon: Icons.task_alt_rounded,
              footnote: p == null
                  ? null
                  : _note(p.completionRate == null
                      ? t.carrRidersNothingClaimed
                      : t.carrRidersCompletionCaption),
            ),
            ConsoleKpiCard(
              label: t.carrRidersDeliveredTodayLabel,
              value: today?.toString() ?? '—',
              icon: Icons.today_outlined,
              footnote: _note(
                  today == null ? t.carrRidersCouldNotRead : t.carrRidersDeliveredTodayCaption),
            ),
          ],
        );
      },
    );
  }

  Widget _chart(DeliveryStrings t) {
    return ConsoleCard(
      title: t.carrRidersOutputTitle(_windowDays),
      child: FutureBuilder<RiderDailyOutput?>(
        future: _daily,
        builder: (BuildContext context, AsyncSnapshot<RiderDailyOutput?> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const _Loading();
          final RiderDailyOutput? output = snapshot.data;
          if (output == null) {
            return Text(t.carrRidersCouldNotRead,
                style: ConsoleText.body.copyWith(color: DeliveryColors.muted));
          }

          // Every day of the window, a quiet one as a hairline: the server sends only the days
          // with work, and a chart that skipped the rest would squeeze a month into a fortnight.
          final List<RiderDeliveredDay> days = output.zeroFilled;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ConsoleBarChart(
                barWidth: 8,
                gap: DeliverySpacing.xs,
                emptyLabel: t.carrRidersOutputEmpty,
                bars: <ConsoleBar>[
                  for (int i = 0; i < days.length; i++)
                    ConsoleBar(
                      // A caption every fifth day and on the last: thirty two-digit captions under
                      // eight-pixel bars would run into each other.
                      label: i % 5 == 0 || i == days.length - 1 ? '${days[i].date.day}' : '',
                      value: days[i].delivered,
                      tooltip: '${consoleDate(context, days[i].date)}: ${days[i].delivered}',
                    ),
                ],
              ),
              const SizedBox(height: DeliverySpacing.sm),
              Text(t.carrRidersOutputNote(output.zone),
                  style: ConsoleText.meta.copyWith(height: 1.4)),
            ],
          );
        },
      ),
    );
  }

  Widget _hoursCard(DeliveryStrings t) {
    return ConsoleCard(
      title: t.carrRidersHoursTitle(_hoursDays),
      child: FutureBuilder<({HoursOnline? hours, bool notFound})>(
        future: _hours,
        builder: (BuildContext context,
            AsyncSnapshot<({HoursOnline? hours, bool notFound})> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const _Loading();
          final HoursOnline? hours = snapshot.data?.hours;
          if (hours == null) {
            // A 404 is the tracking service declining to show this company the rider's hours: a
            // foreign rider, one it no longer counts as this company's and an unknown one answer it
            // identically by design, so the page says only that there is nothing to show. Any other
            // failure is a read that did not work, and is said as exactly that.
            return Text(
                (snapshot.data?.notFound ?? false)
                    ? t.carrRidersHoursNone
                    : t.carrRidersCouldNotRead,
                style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.4));
          }

          // Only dates with time on duty arrive; the rest of the window is the client's to draw.
          final Map<String, DutyDay> byDate = <String, DutyDay>{
            for (final DutyDay d in hours.days) _key(d.date): d,
          };
          final List<DateTime> window = <DateTime>[
            for (DateTime day = hours.from;
                !day.isAfter(hours.to);
                day = DateTime(day.year, day.month, day.day + 1))
              day,
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                t.carrRidersHoursTotal((hours.totalSecondsOnline / 3600).toStringAsFixed(2)),
                style: ConsoleText.cellStrong,
              ),
              const SizedBox(height: DeliverySpacing.sm),
              for (final DateTime day in window)
                _line(
                  consoleDate(context, day),
                  byDate[_key(day)] == null
                      ? t.carrRidersHoursValue('0.00')
                      : '${t.carrRidersHoursValue(byDate[_key(day)]!.hoursOnline.toStringAsFixed(2))}'
                          ' · ${t.carrRidersShifts(byDate[_key(day)]!.sessions)}',
                ),
              const SizedBox(height: DeliverySpacing.sm),
              Text(t.carrRidersHoursZone(hours.zone), style: ConsoleText.meta),
            ],
          );
        },
      ),
    );
  }

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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

  // ------------------------------------------------------------------ employment

  Widget _employment(DeliveryStrings t) {
    final CarrierFleet fleet = widget.fleet;
    final OnboardingApplication? application = _application;
    final DateTime? joined = fleet.joinedOn(widget.riderId);
    final String? vehicle = fleet.vehicleOf(widget.riderId);

    final Map<String, String> details = application?.details ?? const <String, String>{};

    return ConsoleCard(
      title: t.carrRidersEmploymentTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _fact(t.carrRidersStartDate, joined == null ? null : consoleDate(context, joined)),
          _fact(
            t.carrRidersApplied,
            application?.createdAt == null ? null : consoleDate(context, application!.createdAt!),
          ),
          _fact(t.carrRidersRegion, fleet.regionOf(widget.riderId)),
          _fact(t.carrRidersVehicle, vehicle == null ? null : vehicleLabel(t, vehicle)),
          // The rest of what the rider wizard asked about the vehicle, named in the reader's own
          // language. Nothing else from the application's map is printed: what is left is the
          // wizard's plumbing — a map pin's coordinates, who they applied to ride for — and a raw
          // key on a card is a Latin word on an Arabic page with nothing behind it to act on.
          _fact(t.carrRidersVehicleModel, details['vehicleModel']),
          _fact(t.carrRidersVehicleYear, details['vehicleYear']),
          _fact(t.carrRidersPlateNumber, details['plateNumber']),
          // Said rather than drawn as empty rows: a "Base rate" line would look like pay, and the
          // platform pays riders from its own ledger, not from anything entered here.
          Text(t.carrRidersEmploymentNote, style: ConsoleText.meta.copyWith(height: 1.4)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ actions

  Widget _actions(DeliveryStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final RiderPage page in widget.riderPages) ...<Widget>[
          ConsoleButton(
            label: page.label(t),
            icon: page.icon,
            tone: ConsoleButtonTone.outlined,
            onPressed: () => setState(() => _page = page),
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        ],
        switch ((widget.fleet.suspensionOf(widget.riderId), _application)) {
          // Neither control while the standing is unknown. "Suspend" on a rider who may already be
          // suspended, or "Reinstate" on one who may not be, is a guess dressed as a button.
          (RiderSuspension.unknown, _) =>
            Text(t.carrRidersStandingUnknownNote, style: ConsoleText.meta.copyWith(height: 1.4)),
          (RiderSuspension.suspended, final OnboardingApplication a) => ConsoleSoftButton(
              label: t.carrRidersReinstateRider,
              icon: Icons.lock_open_rounded,
              accent: DeliveryAccent.positive,
              busy: _busy,
              onPressed: _busy ? null : () => _flipStanding(a, suspended: true),
            ),
          (RiderSuspension.active, final OnboardingApplication a) => ConsoleSoftButton(
              label: t.carrRidersSuspendRider,
              icon: Icons.block_rounded,
              accent: DeliveryAccent.caution,
              busy: _busy,
              onPressed: _busy ? null : () => _flipStanding(a, suspended: false),
            ),
          // The suspension endpoints are addressed to a rider's application to this company, and
          // somebody the platform attached directly has none. Said instead of a button that 404s.
          _ =>
            Text(t.carrRidersSuspendUnavailable, style: ConsoleText.meta.copyWith(height: 1.4)),
        },
        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        ConsoleSoftButton(
          label: t.carrRidersTerminate,
          icon: Icons.delete_outline_rounded,
          accent: DeliveryAccent.critical,
          busy: _busy,
          onPressed: _busy ? null : _terminate,
        ),
      ],
    );
  }

  /// Suspend, with the reason the server insists on, or reinstate with an optional note. Both are
  /// idempotent server-side and double-gated there: the caller must run this company, and the
  /// application must be a rider's to it.
  Future<void> _flipStanding(OnboardingApplication application, {required bool suspended}) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final RiderStandingAnswer? answer =
        await RiderStandingDialog.show(context, name: _name, suspending: !suspended);
    if (answer == null || !mounted) return;

    setState(() => _busy = true);
    try {
      if (suspended) {
        await widget.managementApi
            .unsuspendRider(widget.fleet.company.id, application.id, note: answer.note);
      } else {
        await widget.managementApi.suspendRider(
            widget.fleet.company.id, application.id, answer.reason!, note: answer.note);
      }
      _tell(suspended ? t.carrRidersReinstatedToast(_name) : t.carrRidersSuspendedToast(_name));
      widget.onChanged();
    } catch (e) {
      _tell(serverMessage(e, t), bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Ends the rider's contract with this company, after a dialog that says exactly what that does —
  /// including to a job they are carrying right now, which is the server's reason to refuse — and
  /// takes the reason the release is recorded with.
  Future<void> _terminate() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    // The reason, or null when nothing should be sent.
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _TerminateDialog(name: _name),
    );
    if (reason == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.providerApi.releaseMyRider(widget.riderId, reason: reason);
      if (!mounted) return;
      widget.onReleased(_name);
    } on DioException catch (e) {
      final dynamic body = e.response?.data;
      switch (e.response?.statusCode) {
        case 409:
          // Said in the reader's language rather than as the server's English sentence; the count
          // is the server's.
          final int jobs = body is Map && body['jobs'] is num ? (body['jobs'] as num).toInt() : 1;
          _tell(t.carrRidersTerminateCarrying(jobs), bad: true);
        case 404:
          // Already gone — released elsewhere, or by Backoffice. The fleet reloads to match.
          _tell(t.carrRidersNotOnFleet, bad: true);
          widget.onChanged();
        default:
          _tell(serverMessage(e, t), bad: true);
      }
    } catch (e) {
      _tell(serverMessage(e, t), bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// "End this rider's contract?" — where the rider goes (no fleet at all, not YouDrop's), what
/// happens to a job they are carrying, that their door cash is the company's to collect first, and
/// the reason the release is kept on record with.
///
/// Pops with the reason, trimmed, or with nothing: the confirm button stays dead until there is a
/// reason to record.
class _TerminateDialog extends StatefulWidget {
  const _TerminateDialog({required this.name});

  final String name;

  @override
  State<_TerminateDialog> createState() => _TerminateDialogState();
}

class _TerminateDialogState extends State<_TerminateDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  static OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        borderSide: BorderSide(color: color),
      );

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String reason = _reason.text.trim();

    Widget paragraph(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: DeliverySpacing.md - DeliverySpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 16, color: DeliveryColors.muted),
              const SizedBox(width: DeliverySpacing.sm),
              Expanded(
                child: Text(text, style: ConsoleText.body.copyWith(height: 1.45)),
              ),
            ],
          ),
        );

    return AlertDialog(
      backgroundColor: DeliveryColors.white,
      surfaceTintColor: DeliveryColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
      title: Text(t.carrRidersTerminateTitle(widget.name), style: ConsoleText.cardTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              paragraph(Icons.person_remove_outlined, t.carrRidersTerminateBody(widget.name)),
              paragraph(Icons.local_shipping_outlined, t.carrRidersTerminateJobs),
              paragraph(Icons.payments_outlined, t.carrRidersTerminateMoney),
              paragraph(Icons.undo_rounded, t.carrRidersTerminateUndo),
              const SizedBox(height: DeliverySpacing.xs),
              Text(t.carrRidersTerminateReason, style: ConsoleText.cellStrong),
              const SizedBox(height: DeliverySpacing.xs),
              TextField(
                controller: _reason,
                maxLines: 3,
                // What the record holds; the server refuses a longer reason rather than cut it.
                maxLength: 500,
                style: ConsoleText.cell,
                cursorColor: DeliveryColors.brand,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: t.carrRidersTerminateReasonHint,
                  hintStyle: const TextStyle(fontSize: 14, color: DeliveryColors.faint),
                  filled: true,
                  fillColor: DeliveryColors.background,
                  border: _border(DeliveryColors.border),
                  enabledBorder: _border(DeliveryColors.border),
                  focusedBorder: _border(DeliveryColors.brand),
                ),
              ),
            ],
          ),
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
        // Solid and red: this ends somebody's work with the company, and must not read like the
        // soft buttons beside it on the profile.
        ConsolePrimaryButton(
          label: t.carrRidersTerminateConfirm,
          icon: Icons.delete_outline_rounded,
          color: DeliveryAccent.critical.color,
          onPressed: reason.isEmpty ? null : () => Navigator.pop(context, reason),
        ),
      ],
    );
  }
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
