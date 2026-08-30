import 'dart:async';
import 'dart:math';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'rider_butler_board.dart';
import 'rider_earnings_screen.dart';
import 'rider_job_card.dart';
import 'rider_order_detail_screen.dart';
import 'rider_settings_widgets.dart';
import 'settings_screen.dart';

/// The Delivery Rider surface — the four-tab shell of the 2026-08 Figma redesign.
///
/// Frames 3:1163 (Available), 3:1255 (Active), 3:1486 (Earnings) and 3:1591 (Settings) are one
/// app with one bottom bar, so they are one widget here: the tabs share the poll that keeps the
/// board fresh, and a job claimed on Available appears on Active without a second round trip.
///
/// While an order is PICKED_UP this screen reports the rider's position on a timer, which is what
/// feeds the customer's tracking card. That, the 5-second refresh and the action wiring are older
/// than the redesign and are carried through it unchanged — the restyle happens around them.
///
/// The design has no home for the errands board, which is a live feature: a customer can raise a
/// Butler request right now and a rider has to be able to claim it. So Available carries a
/// two-chip segmented toggle, in the design's own chip language, and Errands lives behind it
/// rather than being dropped.
class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({
    super.key,
    required this.api,
    required this.butlerApi,
    required this.session,
    required this.locale,
    this.trackingApi,
    this.moneyApi,
    this.performanceApi,
    this.statementsApi,
    this.documentsApi,
    this.chatApi,
    this.splitApi,
    this.socket,
    this.prefsApi,
    this.pendingApproval = false,
    required this.onSignOut,
  });

  final OrderApi api;
  final ButlerApi butlerApi;

  /// The presence half of the tracking service: the duty toggle and the between-jobs ping.
  ///
  /// Nullable so a shell that has not been handed one keeps the pre-wiring rendering — the duty
  /// switch stays visibly inert rather than becoming a control that silently does nothing.
  final TrackingApi? trackingApi;

  /// The accounting ledger behind the Earnings tab. Null keeps the tab on its old derived-from-
  /// orders numbers, labelled as derived.
  final RiderMoneyApi? moneyApi;

  /// The rider-performance endpoint, behind the Earnings tab's completion stat. Null leaves that
  /// one figure inert and changes nothing else.
  final RiderPerformanceApi? performanceApi;

  /// The counterparty-statements client, behind the Earnings tab's statement row. Null leaves that
  /// row undrawn and changes nothing else on the tab.
  final StatementsApi? statementsApi;

  /// The applicant documents and payout endpoints, behind the Documents and Bank Details rows in
  /// Settings. Null leaves those two rows inert.
  final DocumentsApi? documentsApi;

  /// The order chat, and the socket its live half rides on. Both null keeps the order-detail
  /// header exactly as it was — no chat button at all.
  final ChatApi? chatApi;

  /// The group-split ledger, for the cash checklist on a split order's detail. Optional.
  final SplitApi? splitApi;
  final UserQueueSocket? socket;

  /// Handed to the settings page's notification-preferences grid; null leaves the row undrawn.
  final NotificationPrefsApi? prefsApi;

  final AuthSession session;

  /// Passed through to Settings, which is a tab of its own now.
  final LocaleController locale;

  /// True while the application behind this account is still being decided.
  ///
  /// The screen works either way — the server is what refuses the committing act — but saying so
  /// up front beats letting somebody read the board and discover the refusal at the last step.
  final bool pendingApproval;
  final Future<void> Function() onSignOut;

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

/// What the Available tab is showing. Deliveries and errands are two boards, not two filters.
enum _Board { deliveries, errands }

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  static const Duration _refreshInterval = Duration(seconds: 5);

  /// Matches `delivery.tracking.rider-ping-interval-seconds` in config-repo. Every reduction here
  /// multiplies write volume on tracking_events across every active rider (Section 10).
  static const Duration _pingInterval = Duration(seconds: 10);

  Timer? _refreshTimer;
  Timer? _pingTimer;
  final Random _random = Random();

  int _tab = 0;
  _Board _board = _Board.deliveries;

  List<DeliveryOrder> _available = <DeliveryOrder>[];
  List<DeliveryOrder> _assigned = <DeliveryOrder>[];
  bool _loading = true;
  String? _busyId;

  /// The presence API's last answer, rendered by the duty toggle. Null while the server has not
  /// answered yet — which is also its honest answer for a rider who never declared duty (a 204).
  RiderPresence? _presence;

  /// True while a duty declaration is in flight; the switch refuses input meanwhile.
  bool _dutyBusy = false;

  /// The rider's own rating, on their profile card. Null while the rating service has not
  /// answered — the line is then absent rather than showing a score nobody gave.
  RiderStanding? _standing;

  /// Simulated position, walked slightly on each ping.
  ///
  /// Real GPS needs a location plugin and a runtime permission prompt, which is a Phase 5 concern.
  /// What matters now is that the tracking pipeline carries real, changing coordinates end to end.
  double _lat = 51.5074;
  double _lng = -0.1278;

  /// Where the mini-map's camera was placed, kept for the life of the tab.
  ///
  /// The camera is set once, from the first fix the platform reports. Every ping after that moves
  /// the marker and leaves the view alone — a map that re-centres itself every ten seconds cannot
  /// be looked at, because it snaps back the moment the rider drags it.
  LatLng? _mapAnchor;

  /// Tiles that came back refused, and whether the map has given up on them.
  int _tileFailures = 0;
  bool _tilesFailed = false;

  /// How many refusals before the map is replaced by the designed placeholder. More than one, so
  /// a single missing tile at the edge of a zoom level does not tear the map down.
  static const int _tileFailureLimit = 6;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _refresh(silent: true));
    _pingTimer = Timer.periodic(_pingInterval, (_) => _pingActiveDeliveries());
    unawaited(_loadPresence());
    unawaited(_loadStanding());
  }

  /// The rider's own rating, once. It never moves fast enough to be worth polling, and a rating
  /// service that is down must cost nothing but the one line it feeds.
  Future<void> _loadStanding() async {
    try {
      final RiderStanding standing = await widget.api.myRiderRating();
      if (!mounted) return;
      setState(() => _standing = standing);
    } catch (_) {
      // The profile card simply draws no rating line.
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _pingTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final List<Paged<DeliveryOrder>> results = await Future.wait(<Future<Paged<DeliveryOrder>>>[
        widget.api.available(size: 30),
        widget.api.assigned(size: 30),
      ]);
      if (!mounted) return;
      setState(() {
        _available = results[0].content;
        _assigned = results[1].content
            .where((DeliveryOrder o) => !o.status.isTerminal)
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _pingActiveDeliveries() async {
    final List<DeliveryOrder> inTransit =
        _assigned.where((DeliveryOrder o) => o.status == OrderStatus.pickedUp).toList();
    final bool onDuty = _presence?.dutyState == DutyState.onDuty;
    if (inTransit.isEmpty && !onDuty) return;

    // Drift by roughly a street's width so the customer's view visibly changes.
    _lat += (_random.nextDouble() - 0.5) * 0.002;
    _lng += (_random.nextDouble() - 0.5) * 0.002;

    for (final DeliveryOrder order in inTransit) {
      try {
        await widget.api.ping(order.id, _lat, _lng, accuracyM: 8);
      } catch (_) {
        // A dropped ping is replaced by the next one; never surface it to the rider.
      }
    }

    // The order-less ping: what keeps a rider *between* jobs believed on the roster. Only while
    // they declared duty — an off-duty rider's phone reports nothing.
    final TrackingApi? tracking = widget.trackingApi;
    if (tracking != null && onDuty) {
      try {
        await tracking.ping(_lat, _lng, accuracyM: 8);
      } catch (_) {
        // Same policy as the order ping: the next fix replaces a dropped one.
      }
    }
    // Re-ask what the platform now believes, so "last seen" moves and a STALE verdict shows up
    // without waiting for the settings tab to be reopened. Cheap for a rider who never declared
    // duty too: the server answers 204 and the toggle keeps its resting state.
    if (tracking != null) {
      await _loadPresence();
    }
  }

  // ------------------------------------------------------------------ presence

  Future<void> _loadPresence() async {
    final TrackingApi? tracking = widget.trackingApi;
    if (tracking == null) return;
    try {
      final RiderPresence? presence = await tracking.myPresence();
      if (!mounted) return;
      setState(() {
        _presence = presence;
        _anchorMap(presence);
      });
    } catch (_) {
      // The toggle keeps rendering the last answer; the next poll retries.
    }
  }

  /// Places the mini-map's camera the first time the platform reports a fix, and never again.
  ///
  /// Must be called from inside the same [setState] that stores the presence: the anchor is read
  /// during build, so changing it outside a rebuild would leave the map keyed on a stale point.
  void _anchorMap(RiderPresence? presence) {
    if (_mapAnchor != null || presence == null || !presence.hasFix) return;
    _mapAnchor = LatLng(presence.lat!, presence.lng!);
  }

  /// Declares duty and renders the *server's* answer — which can come back STALE when the phone
  /// has not produced a believable fix yet. The switch must never show a state the platform does
  /// not hold.
  Future<void> _setDuty(bool on) async {
    final TrackingApi? tracking = widget.trackingApi;
    if (tracking == null || _dutyBusy) return;
    setState(() => _dutyBusy = true);
    try {
      final RiderPresence result =
          await tracking.setDuty(on ? DutyState.onDuty : DutyState.offDuty);
      if (!mounted) return;
      setState(() {
        _presence = result;
        _anchorMap(result);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DeliveryStrings.of(context).riderDutyChangeFailed)),
      );
      // Whatever the server holds now is what the toggle should show.
      await _loadPresence();
    } finally {
      if (mounted) setState(() => _dutyBusy = false);
    }
  }

  Future<void> _act(DeliveryOrder order, OrderAction action) async {
    setState(() => _busyId = order.id);
    try {
      await widget.api.act(order.id, action);
      await _refresh(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DeliveryStrings.of(context).actionOnOrder(action.labelIn(DeliveryStrings.of(context)), order.shortId))),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      // 422 on a claim is the expected race: another rider got there first.
      final String message = switch (e.response?.statusCode) {
        422 when action == OrderAction.claim => DeliveryStrings.of(context).anotherRiderClaimedIt,
        422 => DeliveryStrings.of(context).orderAlreadyMovedOn,
        _ => DeliveryStrings.of(context).actionFailed(action.labelIn(DeliveryStrings.of(context)).toLowerCase()),
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      await _refresh(silent: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// A claim taken from Available belongs on Active, so the tab follows the job.
  Future<void> _claimAndFollow(DeliveryOrder order, OrderAction action) async {
    await _act(order, action);
    if (!mounted || action != OrderAction.claim) return;
    setState(() => _tab = 1);
  }

  void _openDetail(DeliveryOrder order) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RiderOrderDetailScreen(
        order: order,
        onAction: (OrderAction action) => _act(order, action),
        trackingApi: widget.trackingApi,
        chatApi: widget.chatApi,
        socket: widget.socket,
        splitApi: widget.splitApi,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: SafeArea(
        bottom: false,
        child: switch (_tab) {
          0 => _availableTab(t),
          1 => _activeTab(t),
          2 => RiderEarningsScreen(
              api: widget.api,
              moneyApi: widget.moneyApi,
              trackingApi: widget.trackingApi,
              performanceApi: widget.performanceApi,
              statementsApi: widget.statementsApi,
            ),
          _ => _settingsTab(t),
        },
      ),
      bottomNavigationBar: YdBottomNav(
        currentIndex: _tab,
        onTap: (int i) => setState(() => _tab = i),
        items: <YdBottomNavItem>[
          YdBottomNavItem(
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded,
            label: t.riderTabAvailable,
          ),
          YdBottomNavItem(
            icon: Icons.assignment_outlined,
            activeIcon: Icons.assignment_rounded,
            label: t.riderTabActive,
          ),
          YdBottomNavItem(
            icon: Icons.trending_up_rounded,
            label: t.riderTabEarnings,
          ),
          YdBottomNavItem(
            icon: Icons.settings_outlined,
            activeIcon: Icons.settings_rounded,
            label: t.settings,
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ available

  Widget _availableTab(DeliveryStrings t) {
    return Column(
      children: <Widget>[
        _regionBar(t),
        _mapSlot(t),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Row(
            children: <Widget>[
              YdChip(
                label: t.riderSegmentDeliveries,
                selected: _board == _Board.deliveries,
                onTap: () => setState(() => _board = _Board.deliveries),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              YdChip(
                label: t.errands,
                selected: _board == _Board.errands,
                onTap: () => setState(() => _board = _Board.errands),
              ),
            ],
          ),
        ),
        if (widget.pendingApproval)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, DeliverySpacing.md, 20, 0),
            child: SoftNote(
                icon: Icons.hourglass_top_rounded, text: t.pendingBannerRider),
          ),
        Expanded(
          child: _board == _Board.errands
              // An approved errand becomes an ordinary order and shows up in Active, so this board
              // covers only the part that is not a delivery yet: claiming, and agreeing what the
              // goods cost.
              ? RiderButlerBoard(api: widget.butlerApi)
              : _offers(t),
        ),
      ],
    );
  }

  /// The white `region-selector` bar.
  ///
  /// The design's chevron opens a zone picker, and there is still nothing for it to pick between.
  /// The platform's zone list is real, but an order does not carry the zone it was placed for —
  /// `OrderResponse` has no zone field — and a rider's account carries no zone preference, so a
  /// picker here could not filter the board by anything and could not remember an answer. What is
  /// honest is the value beside the label, and it changed: the row used to show the app's own
  /// name, and now says what is actually true of this board — every approved rider sees every
  /// ready order, everywhere.
  ///
  /// No chip beside it, either. "Coming soon" would promise a picker that no client change can
  /// deliver — it waits on an order carrying a zone and a rider carrying a preference — and the
  /// row no longer needs one: a statement of fact does not have to apologise for being true.
  Widget _regionBar(DeliveryStrings t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: DeliverySpacing.lg,
        vertical: DeliverySpacing.md - DeliverySpacing.xs,
      ),
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.place_outlined, size: 20, color: DeliveryColors.brand),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  t.riderRegionZone,
                  style: const TextStyle(
                    fontSize: 11,
                    color: DeliveryColors.faint,
                    height: 1.3,
                  ),
                ),
                Text(
                  t.riderRegionAllAreas,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The last fix the *platform* holds for this rider, or null when it holds none.
  ///
  /// Read from presence rather than from this screen's own [_lat]/[_lng] on purpose. Those two
  /// start at a hard-coded origin and are only a position once a ping has actually been sent, so
  /// centring a map on them before that would put a rider somewhere they have never been. Presence
  /// carries a fix exactly when one has been recorded — which is also the position a dispatcher is
  /// looking at, so the rider and the platform are reading the same map.
  LatLng? get _riderFix {
    final RiderPresence? presence = _presence;
    if (presence == null || !presence.hasFix) return null;
    return LatLng(presence.lat!, presence.lng!);
  }

  /// The 160px `regional-mini-map`, drawn from OpenStreetMap raster tiles.
  ///
  /// **What is on it.** The rider, at the last fix the platform holds for them. Nothing else — and
  /// that is a data fact rather than a shortcut. An order carries no coordinates anywhere in its
  /// contract (`OrderResponse` has an address string and no latitude or longitude), so there is no
  /// honest pin to drop for a job on the board. Inventing one from the address would need a
  /// geocoder call per order on a five-second refresh, and would put a rider's decision on a point
  /// a third-party guessed. The pill above the map carries the real number instead: how many
  /// orders are waiting right now.
  ///
  /// **When the tiles do not come.** The styled placeholder is painted underneath the map rather
  /// than instead of it, so a slow tile shows the designed surface and not a grey hole; and after
  /// [_tileFailureLimit] refusals the map is taken down altogether and the placeholder is all that
  /// is left. A rider on a dead connection sees the surface they saw before there were maps, never
  /// a broken grid.
  ///
  /// The OpenStreetMap attribution is on the map whenever the map is: it is the tile policy's
  /// requirement and not decoration, which is why it is not conditional on anything.
  Widget _mapSlot(DeliveryStrings t) {
    final LatLng? centre = _riderFix;

    return SizedBox(
      height: 160,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // The designed surface, always underneath: it is what a missing tile falls back to.
          Positioned.fill(
            child: CustomPaint(
              painter: _MapGridPainter(),
              child: const SizedBox.expand(),
            ),
          ),
          if (centre != null && !_tilesFailed) ...<Widget>[
            Positioned.fill(child: _map(t, centre)),
            PositionedDirectional(
              bottom: 4,
              start: 6,
              child: _attribution(),
            ),
          ] else
            Align(
              alignment: const Alignment(0, 0.55),
              child: Text(
                centre == null ? t.riderMapNoFixYet : t.riderMapUnavailable,
                style: const TextStyle(
                  fontSize: 11,
                  color: DeliveryColors.muted,
                  height: 1.3,
                ),
              ),
            ),
          Container(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: DeliverySpacing.md - DeliverySpacing.xs,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: DeliveryColors.shellDeep,
              borderRadius: BorderRadius.circular(DeliveryRadius.pill),
            ),
            child: Text(
              t.riderDeliveriesNearby(_available.length),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.white,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _map(DeliveryStrings t, LatLng centre) {
    return FlutterMap(
      // Keyed on the anchor rather than on the live fix: the camera is placed once, and every
      // later ping moves the marker instead of yanking the view out from under a rider who has
      // panned it somewhere on purpose.
      key: ValueKey<String>('rider-map-${_mapAnchor ?? centre}'),
      options: MapOptions(
        initialCenter: _mapAnchor ?? centre,
        initialZoom: 14,
        // Transparent, so the placeholder painted underneath is what shows through a tile that
        // has not arrived — flutter_map's own default is a flat grey.
        backgroundColor: Colors.transparent,
        // A 160px strip inside a scrolling column: dragging it is fine, rotating it is not, and
        // a two-finger gesture here belongs to the page.
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.drag | InteractiveFlag.doubleTapZoom,
        ),
      ),
      children: <Widget>[
        TileLayer(
          urlTemplate: riderOsmTileTemplate,
          userAgentPackageName: riderOsmUserAgent,
          maxNativeZoom: 19,
          errorTileCallback: (_, __, ___) => _noteTileFailure(),
        ),
        MarkerLayer(
          markers: <Marker>[
            Marker(
              point: centre,
              width: 28,
              height: 28,
              child: Semantics(
                label: t.riderMapYouAreHere,
                child: Container(
                  decoration: BoxDecoration(
                    color: DeliveryColors.brand,
                    shape: BoxShape.circle,
                    border: Border.all(color: DeliveryColors.white, width: 2),
                  ),
                  child: const Icon(Icons.navigation_rounded,
                      size: 14, color: DeliveryColors.white),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The credit OpenStreetMap's tile usage policy requires on every map drawn from its tiles.
  Widget _attribution() => Container(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: DeliveryColors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        ),
        child: const Text(
          riderOsmAttribution,
          style: TextStyle(
            fontSize: 9,
            color: DeliveryColors.muted,
            height: 1.2,
          ),
        ),
      );

  /// One refused tile is weather; a run of them is a rider with no usable connection.
  ///
  /// Counted rather than acted on immediately because a single 404 at the edge of a zoom level
  /// must not tear the map down. Deferred to after the frame: the callback fires from inside the
  /// tile layer's own build and paint work.
  void _noteTileFailure() {
    if (_tilesFailed) return;
    _tileFailures++;
    if (_tileFailures < _tileFailureLimit) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _tilesFailed = true);
    });
  }

  Widget _offers(DeliveryStrings t) {
    if (_loading && _available.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
    }

    return RefreshIndicator(
      onRefresh: () => _refresh(),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            t.riderOffersNearYou,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
              height: 1.3,
            ),
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          if (_available.isEmpty)
            YdEmptyState(
              icon: Icons.inbox_rounded,
              title: t.nothingWaitingForPickup,
              message: t.newJobsAppearHere,
            )
          else
            for (final DeliveryOrder order in _available)
              Padding(
                padding: const EdgeInsets.only(
                    bottom: DeliverySpacing.md - DeliverySpacing.xs),
                child: RiderJobCard(
                  order: order,
                  busy: _busyId == order.id,
                  onAction: (OrderAction a) => _claimAndFollow(order, a),
                ),
              ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------- active

  Widget _activeTab(DeliveryStrings t) {
    return Column(
      children: <Widget>[
        _screenHeader(
          title: t.riderMyActiveTasks,
          trailing: Text(
            t.riderActiveCount(_assigned.length),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.brand,
            ),
          ),
        ),
        Expanded(
          child: _loading && _assigned.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(color: DeliveryColors.brand))
              : RefreshIndicator(
                  onRefresh: () => _refresh(),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: <Widget>[
                      if (_assigned.isEmpty)
                        YdEmptyState(
                          icon: Icons.two_wheeler_rounded,
                          title: t.noActiveDeliveries,
                          message: t.claimOneToSeeItHere,
                        )
                      else
                        for (final DeliveryOrder order in _assigned)
                          Padding(
                            padding: const EdgeInsets.only(
                                bottom: DeliverySpacing.md),
                            child: RiderTaskCard(
                              order: order,
                              onOpen: () => _openDetail(order),
                            ),
                          ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------- settings

  Widget _settingsTab(DeliveryStrings t) {
    return AnimatedBuilder(
      animation: widget.locale,
      builder: (BuildContext context, _) => Column(
        children: <Widget>[
          _screenHeader(title: t.riderDriverSettings),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                RiderProfileCard(
                  name: widget.session.displayName,
                  standing: _standing,
                ),
                const SizedBox(height: DeliverySpacing.md),
                RiderDutyToggleCard(
                  presence: _presence,
                  busy: _dutyBusy,
                  // No presence service, no control: a null callback disables the switch rather
                  // than offering a toggle that would silently do nothing.
                  onChanged: widget.trackingApi == null ? null : _setDuty,
                ),
                const SizedBox(height: DeliverySpacing.md),
                // The language itself is set on the shared settings screen, which is also where
                // fingerprint unlock lives. Two places to change one setting is one too many, so
                // this row shows the answer and opens the page that owns the question.
                RiderLanguageRow(
                  value: widget.locale.isArabic ? 'العربية' : 'English',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => SettingsScreen(
                      locale: widget.locale,
                      userId: widget.session.subject,
                      prefsApi: widget.prefsApi,
                    ),
                  )),
                ),
                const SizedBox(height: DeliverySpacing.md),
                RiderPreferencesGroup(
                  rows: <RiderPreference>[
                    // The rider's own KYC file, read back from the applicant-documents endpoints:
                    // what the platform holds and what a reviewer made of each one.
                    //
                    // Both of these rows are omitted rather than drawn dead when a shell was
                    // handed no documents client. They used to render greyed with a "coming soon"
                    // chip, which described two shipped sheets as unbuilt — and, because the app
                    // itself forgot to pass the client, that is what every rider actually saw. A
                    // row that leads nowhere is not information; a shell without the client simply
                    // has no documents page, and says so by not offering one.
                    if (widget.documentsApi != null)
                      RiderPreference(
                        icon: Icons.folder_outlined,
                        label: t.riderDocuments,
                        onTap: () => showRiderSheet(
                          context,
                          (_) => RiderDocumentsSheet(api: widget.documentsApi!),
                        ),
                      ),
                    // Where the money goes. Read-only by the server's rule, not by choice — the
                    // onboarding payout endpoint refuses a change once an application is decided,
                    // and a rider signed in here has been approved.
                    if (widget.documentsApi != null)
                      RiderPreference(
                        icon: Icons.credit_card_outlined,
                        label: t.riderBankDetails,
                        onTap: () => showRiderSheet(
                          context,
                          (_) => RiderPayoutSheet(api: widget.documentsApi!),
                        ),
                      ),
                    // Notification preferences are one question with one answer per account, and
                    // the shared settings screen already owns them. This row opens that page
                    // rather than growing a second grid that could disagree with it.
                    RiderPreference(
                      icon: Icons.notifications_outlined,
                      label: t.riderNotificationPreferences,
                      onTap: () =>
                          Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => SettingsScreen(
                          locale: widget.locale,
                          userId: widget.session.subject,
                          prefsApi: widget.prefsApi,
                        ),
                      )),
                    ),
                    RiderPreference(
                      icon: Icons.help_outline_rounded,
                      label: t.riderHelpAndSupport,
                      onTap: () => showRiderSheet(
                        context,
                        (_) => RiderHelpSheet(
                          chatApi: widget.chatApi,
                          socket: widget.socket,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DeliverySpacing.md),
                RiderLogOutButton(onPressed: widget.onSignOut),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------- parts

  /// The redesign's 56px white screen header: title hard against the start edge, an optional
  /// accent-coloured fact against the end edge.
  ///
  /// Deliberately not [YdScreenHeader], which centres its title as soon as it is given a trailing
  /// widget. These rider frames keep the title left and the count right.
  Widget _screenHeader({required String title, Widget? trailing}) {
    return Container(
      height: 56,
      width: double.infinity,
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: DeliverySpacing.lg),
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: DeliveryColors.ink,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}

/// The map placeholder's ruled backdrop.
///
/// Not a decorative flourish: it is what stops a flat grey rectangle reading as a failed image
/// load. Drawn in the border token at a low contrast so it stays behind the pill overlay.
class _MapGridPainter extends CustomPainter {
  static const double _cell = 28;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = DeliveryColors.background,
    );

    final Paint line = Paint()
      ..color = DeliveryColors.border
      ..strokeWidth = 1;

    for (double x = _cell; x < size.width; x += _cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (double y = _cell; y < size.height; y += _cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(_MapGridPainter oldDelegate) => false;
}
