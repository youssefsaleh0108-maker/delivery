import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

import '../shell/shell.dart';

/// Every rider on the platform, who they ride for, and — now that the tracking service reports it —
/// whether they are actually on the road.
///
/// Drawn as `backoffice-riders` (Figma 3:3088). New as a screen: riders existed only inside the
/// carriers page, as chips on a card, which meant the only way to answer "who rides for us" was to
/// open every carrier in turn.
///
/// Assembled rather than fetched. There is no rider index — the register lists carriers, and each
/// carrier lists its own roster — so this loads the register and then one roster per carrier, and
/// joins them. That is N+1 requests, bounded by the number of carriers, and it is the only path
/// there is; a joined endpoint would be the right fix and is not this screen's to write.
///
/// Presence and ratings are real now. The Status column renders what the presence roster reports —
/// on duty, signal lost, off duty — and "Unknown" only for a rider who has never declared duty at
/// all, which is a different fact from "offline". The Rating column renders the customer average
/// where one exists and "New" where nobody has rated the rider yet, never a zero. What still has no
/// source — a rider's work region and their deliveries today — stays empty and says so under the
/// table rather than being invented.
class RidersScreen extends StatefulWidget {
  const RidersScreen({
    super.key,
    required this.api,
    required this.trackingApi,
    required this.orderApi,
  });

  final DeliveryProviderApi api;

  /// The presence roster — the Online/Offline dots and the last-seen times.
  final TrackingApi trackingApi;

  /// Rider standings, one lookup per rider; there is no batch endpoint.
  final OrderApi orderApi;

  @override
  State<RidersScreen> createState() => _RidersScreenState();
}

/// One row: a rider, and the carrier whose roster they were found on.
class _RiderRow {
  const _RiderRow({required this.ref, required this.carrier});

  /// The rider's Keycloak subject, which is the only name the platform has for them.
  final String ref;
  final DeliveryProviderInfo carrier;
}

class _RidersScreenState extends State<RidersScreen> {
  /// Riders go on and off duty while the console sits open, so presence refreshes itself. Only
  /// presence: the carrier join and the ratings move on human timescales and reload on demand.
  static const Duration _presencePoll = Duration(seconds: 30);

  late Future<List<_RiderRow>> _roster = _load();
  Timer? _poll;

  /// What the tracking service last said, keyed by rider ref. Null until the first answer; a
  /// rider absent from it has never declared duty or pinged.
  Map<String, RiderPresence>? _presence;

  /// True when the roster call itself failed — every pill then reads "Unknown" honestly.
  bool _presenceDown = false;

  /// Customer standings, keyed by rider ref. A missing key means the lookup failed or has not
  /// landed; a present standing with a null average means genuinely unrated.
  Map<String, RiderStanding> _standings = <String, RiderStanding>{};

  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// The carrier the list is narrowed to, or null for all of them.
  String? _carrierId;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(_presencePoll, (_) => _refreshPresence());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// The register, then a roster per carrier — and, alongside, presence for everyone and a
  /// standing per rider found.
  ///
  /// A carrier whose roster fails to load contributes nothing rather than failing the page: one
  /// unreachable roster must not hide every other rider on the platform. The same holds for the
  /// tracking service and the ratings — each degrades to its own column, never to the table.
  Future<List<_RiderRow>> _load() async {
    // Fired first and not awaited yet: presence is one request for the whole fleet and can land
    // while the per-carrier rosters are still being joined.
    final Future<void> presenceDone = _refreshPresence();

    final Paged<DeliveryProviderInfo> page = await widget.api.all(size: 50);

    // The in-house fleet is skipped deliberately: membership in it is opt-in, so its roster is
    // empty by construction and every rider who has not been moved elsewhere belongs to it. Asking
    // for it would spend a request to learn nothing.
    final List<DeliveryProviderInfo> carriers = page.content
        .where((DeliveryProviderInfo p) => !p.isInHouse)
        .toList();

    final List<List<_RiderRow>> perCarrier = await Future.wait<List<_RiderRow>>(
      carriers.map((DeliveryProviderInfo p) async {
        try {
          final List<String> refs = await widget.api.riders(p.id);
          return refs.map((String r) => _RiderRow(ref: r, carrier: p)).toList();
        } catch (_) {
          return const <_RiderRow>[];
        }
      }),
    );

    final List<_RiderRow> rows = <_RiderRow>[
      for (final List<_RiderRow> perOne in perCarrier) ...perOne,
    ]..sort((_RiderRow a, _RiderRow b) {
        final int byCarrier = a.carrier.name.compareTo(b.carrier.name);
        return byCarrier != 0 ? byCarrier : a.ref.compareTo(b.ref);
      });

    unawaited(_loadStandings(rows));
    await presenceDone;
    return rows;
  }

  /// One presence request for the whole fleet. Failure marks the column down rather than the page.
  Future<void> _refreshPresence() async {
    try {
      final List<RiderPresence> roster =
          await widget.trackingApi.roster(onDutyOnly: false);
      if (!mounted) return;
      setState(() {
        _presence = <String, RiderPresence>{
          for (final RiderPresence p in roster) p.riderId: p,
        };
        _presenceDown = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _presenceDown = true);
    }
  }

  /// One standing per rider, concurrently. A failed lookup leaves its cell empty — never a zero,
  /// and never "New", which is a claim about the rider rather than about the request.
  Future<void> _loadStandings(List<_RiderRow> rows) async {
    final List<MapEntry<String, RiderStanding>?> found =
        await Future.wait<MapEntry<String, RiderStanding>?>(
      rows.map((_RiderRow r) async {
        try {
          return MapEntry<String, RiderStanding>(
              r.ref, await widget.orderApi.riderRating(r.ref));
        } catch (_) {
          return null;
        }
      }),
    );
    if (!mounted) return;
    setState(() {
      _standings = <String, RiderStanding>{
        for (final MapEntry<String, RiderStanding>? e in found)
          if (e != null) e.key: e.value,
      };
    });
  }

  void _reload() {
    setState(() {
      _roster = _load();
      _standings = <String, RiderStanding>{};
    });
  }

  @override
  Widget build(BuildContext context) {
    return ConsolePage(
      header: ConsoleTopbar(
        title: 'Riders Control Panel',
        subtitle: 'Manage active courier performance and dispatch statuses',
        actions: <Widget>[
          const ConsoleSearchField.global(
            hintText: 'Search backoffice...',
            enabled: false,
          ),
          const ConsoleIconAction(
            icon: Icons.notifications_none,
            tooltip: 'Notifications — no feed yet',
          ),
          const ConsoleComingSoonChip(),
          ConsoleIconAction(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            onPressed: _reload,
          ),
        ],
      ),
      children: <Widget>[
        FutureBuilder<List<_RiderRow>>(
          future: _roster,
          builder: (BuildContext context, AsyncSnapshot<List<_RiderRow>> snapshot) {
            final List<_RiderRow> all = snapshot.data ?? const <_RiderRow>[];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _filters(all),
                const SizedBox(height: ConsoleMetrics.pageGap),
                if (snapshot.connectionState != ConnectionState.done)
                  const ConsoleCard(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: DeliverySpacing.xl),
                        child: CircularProgressIndicator(color: DeliveryColors.brand),
                      ),
                    ),
                  )
                else if (snapshot.hasError)
                  ConsoleCard(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.lg),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Text('Could not load the roster.',
                                style: ConsoleText.cardTitle),
                            const SizedBox(height: DeliverySpacing.xs),
                            Text('${snapshot.error}',
                                style: ConsoleText.meta, textAlign: TextAlign.center),
                            const SizedBox(height: DeliverySpacing.md),
                            ConsoleButton(label: 'Try again', onPressed: _reload),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  _table(_visible(all)),
              ],
            );
          },
        ),
      ],
    );
  }

  List<_RiderRow> _visible(List<_RiderRow> all) {
    final String q = _query.trim().toLowerCase();
    return all.where((_RiderRow r) {
      if (_carrierId != null && r.carrier.id != _carrierId) return false;
      if (q.isEmpty) return true;
      return r.ref.toLowerCase().contains(q) || r.carrier.name.toLowerCase().contains(q);
    }).toList();
  }

  // -------------------------------------------------------------------- the filter row

  Widget _filters(List<_RiderRow> all) {
    // Only carriers that actually have riders on this page. A selector that can produce an empty
    // table is a selector that lies about the shape of the fleet.
    final Map<String, DeliveryProviderInfo> carriers = <String, DeliveryProviderInfo>{
      for (final _RiderRow r in all) r.carrier.id: r.carrier,
    };

    final DeliveryProviderInfo? chosen = _carrierId == null ? null : carriers[_carrierId];

    // Figma `filters-row` (3:3142): selectors left, search right. A Wrap rather than a Row with a
    // Spacer — see the note on the merchants directory's controls row; a Row here overflows once a
    // carrier's name is long enough, which is a property of the data rather than of the window.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: DeliverySpacing.md,
      runSpacing: DeliverySpacing.md,
      children: <Widget>[
        Wrap(
          spacing: DeliverySpacing.md - DeliverySpacing.xs,
          runSpacing: DeliverySpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            ConsoleSelect(
              label: chosen?.name ?? 'All Carriers',
              icon: Icons.local_shipping_outlined,
              tooltip: 'Filter by carrier',
              options: <ConsoleOption>[
                const ConsoleOption(label: 'All Carriers', value: null),
                for (final DeliveryProviderInfo c in carriers.values)
                  ConsoleOption(label: c.name, value: c.id),
              ],
              onSelected: (String? id) => setState(() => _carrierId = id),
            ),
            // The design's second selector. Riders carry no work region on this platform — zones
            // exist, but nothing ties a rider to one — so it is drawn and dead rather than
            // filtering on a field that would have to be invented first.
            const ConsoleFilterButton(
              label: 'All regions',
              icon: Icons.public,
              trailing: ConsoleComingSoonChip(),
            ),
          ],
        ),
        ConsoleSearchField(
          hintText: 'Search riders...',
          controller: _search,
          onChanged: (String v) => setState(() => _query = v),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------- the table

  Widget _table(List<_RiderRow> rows) {
    return ConsoleTable(
      minWidth: 1000,
      columns: const <ConsoleColumn>[
        ConsoleColumn(label: 'Rider Name', flex: 1),
        ConsoleColumn(label: 'Carrier Partner', width: 180),
        ConsoleColumn(label: 'Status', width: 140),
        ConsoleColumn(label: 'Region', width: 120),
        ConsoleColumn(label: 'Deliveries Today', width: 130),
        ConsoleColumn(label: 'Rating', width: 100, alignRight: true),
      ],
      rows: <ConsoleTableRow>[
        for (final _RiderRow r in rows)
          ConsoleTableRow(
            cells: <Widget>[
              Tooltip(
                message: r.ref,
                child: ConsoleNameCell(
                  // The Keycloak subject is the only name the platform holds for a rider; there is
                  // no profile behind it. Shortened so a column of UUIDs stays scannable, with the
                  // whole of it on hover for the operator who needs to paste it somewhere.
                  name: _shortRef(r.ref),
                  secondary: r.carrier.slug,
                  leading: ConsoleInitialTile.circle(label: r.ref),
                ),
              ),
              Text(
                r.carrier.name,
                overflow: TextOverflow.ellipsis,
                style: ConsoleText.cellMuted,
              ),
              _statusCell(r),
              const ConsoleNoValue(tooltip: 'Riders carry no work region yet'),
              const ConsoleNoValue(tooltip: 'No per-rider delivery count yet'),
              _ratingCell(r),
            ],
          ),
      ],
      empty: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.pedal_bike_outlined, size: 28, color: DeliveryColors.faint),
            const SizedBox(height: DeliverySpacing.sm),
            Text(
              _query.isEmpty && _carrierId == null
                  ? 'No rider is assigned to a carrier yet.'
                  : 'No rider matches that filter.',
              style: ConsoleText.cellStrong,
            ),
            const SizedBox(height: DeliverySpacing.xs),
            const Text(
              'Riders who have never been moved to a company ride for the in-house fleet, and '
              'that roster is not enumerable.',
              textAlign: TextAlign.center,
              style: ConsoleText.meta,
            ),
          ],
        ),
      ),
      footer: const ConsoleInertNote(
        text: 'Work region and daily deliveries are not reported by any service yet. Riders '
            'shown are those assigned to a carrier; the in-house fleet is everyone else and '
            'cannot be listed.',
      ),
    );
  }

  /// The presence pill and, when there has ever been a fix, how long ago it was.
  ///
  /// Four honest states, three from the tracking service and one from its absence:
  /// * On duty (emerald) — declared on duty and pinging.
  /// * Signal lost (amber) — declared on duty, then went quiet. Exactly who a dispatcher needs to
  ///   see, which is why the roster does not hide them.
  /// * Off duty (grey) — declared off duty.
  /// * Unknown — never declared duty at all, or the tracking service did not answer. Not
  ///   "Offline": that would be a fact about the platform dressed up as a fact about the rider.
  Widget _statusCell(_RiderRow r) {
    if (_presenceDown || _presence == null) {
      return const Tooltip(
        message: 'The tracking service did not answer',
        child: ConsoleStatusPill(label: 'Unknown'),
      );
    }

    final RiderPresence? p = _presence![r.ref];
    if (p == null) {
      return const Tooltip(
        message: 'This rider has never gone on duty',
        child: ConsoleStatusPill(label: 'Unknown'),
      );
    }

    final (String label, DeliveryAccent accent) = switch (p.state) {
      PresenceState.onDuty => ('On duty', DeliveryAccent.positive),
      PresenceState.stale => ('Signal lost', DeliveryAccent.caution),
      PresenceState.offDuty => ('Off duty', DeliveryAccent.neutral),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ConsoleStatusPill(label: label, accent: accent),
        if (p.lastSeenAt != null) ...<Widget>[
          const SizedBox(height: 2),
          Text('seen ${_ago(p.lastSeenAt!)}', style: ConsoleText.meta),
        ],
      ],
    );
  }

  /// The customer average where one exists; "New" for a rider nobody has rated — never a zero,
  /// because a zero shown as a score is a lie about somebody's livelihood.
  Widget _ratingCell(_RiderRow r) {
    final RiderStanding? standing = _standings[r.ref];
    if (standing == null) {
      return const ConsoleNoValue(tooltip: 'No rating loaded for this rider');
    }
    if (!standing.isRated) {
      return const Tooltip(
        message: 'Nobody has rated this rider yet',
        child: Text('New', style: ConsoleText.cellMuted),
      );
    }
    return Tooltip(
      message: '${standing.ratings} rating${standing.ratings == 1 ? '' : 's'}',
      child: Text(
        '★ ${standing.average!.toStringAsFixed(1)}',
        style: ConsoleText.cellStrong,
      ),
    );
  }

  static String _ago(DateTime at) {
    final Duration d = DateTime.now().difference(at);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  static String _shortRef(String ref) => ref.length <= 14 ? ref : '${ref.substring(0, 12)}…';
}
