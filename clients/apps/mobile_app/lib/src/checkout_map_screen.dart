import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'address_sheet.dart' show OsmBasemap;
import 'delivery_address.dart' show custEtaReasonLabel;
import 'order_details_screen.dart' show CustomerStatusPill;

/// Opens the checkout map over whatever is showing — the one way every entry point reaches it, so
/// the post-checkout jump, the Orders cards and the order page all open the same screen.
Future<void> openCheckoutMap(
  BuildContext context, {
  required CheckoutTrackingApi api,
  required String checkoutId,
  int? shopCount,
  bool justPlaced = false,
  UserQueueSocket? liveSocket,
  void Function(String orderId)? onOpenOrder,
}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => CheckoutMapScreen(
      api: api,
      checkoutId: checkoutId,
      shopCount: shopCount,
      justPlaced: justPlaced,
      liveSocket: liveSocket,
      onOpenOrder: onOpenOrder,
    ),
  ));
}

/// The "Part of a N-shop order" badge made into the way in: "See all N on one map".
///
/// Drawn in the badge's own brand tint so it still reads as the same fact on the card, with a map
/// glyph and a chevron saying it now opens something. The visible pill is small; the band around
/// it answers the tap too, at the platform's minimum target height, as the neighbourhood map's
/// expand pill does. The label may wrap to a second line rather than overflow a narrow card.
class CheckoutMapBadge extends StatelessWidget {
  const CheckoutMapBadge({super.key, required this.shopCount, required this.onPressed});

  final int shopCount;
  final VoidCallback onPressed;

  /// The smallest target the platform guidelines allow.
  static const double hitHeight = 44;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final BorderRadius radius = BorderRadius.circular(DeliveryRadius.sm);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: onPressed,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: hitHeight),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: 1,
          child: Semantics(
            button: true,
            child: Material(
              color: DeliveryColors.brandSoft,
              borderRadius: radius,
              child: InkWell(
                onTap: onPressed,
                borderRadius: radius,
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: DeliverySpacing.sm,
                    vertical: DeliverySpacing.xs + 1,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.map_outlined, size: 14, color: DeliveryColors.brand),
                      const SizedBox(width: DeliverySpacing.xs),
                      Flexible(
                        child: Text(
                          t.checkoutMapSeeAll(shopCount),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: DeliveryColors.brand,
                            height: 1.25,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Directionality.of(context) == TextDirection.rtl
                            ? Icons.chevron_left_rounded
                            : Icons.chevron_right_rounded,
                        size: 16,
                        color: DeliveryColors.brand,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Every order of a multi-shop checkout on one map: the owner's "expected road map" of a basket
/// bought from several shops.
///
/// A map on top — a pin per shop, the door, a marker per rider once one is on the way, and the
/// expected routes between them — and one row per order below it. Everything drawn comes from the
/// tracking service's checkout view and nothing is guessed:
///
/// * A shop or the door without a pin is not drawn, and its row (or the list's head) says why.
/// * Lines are drawn as the server says: solid along real roads, or dashed straight segments with
///   a chip calling them approximate. The app never curves a line of its own — a curve looks like
///   a road. Planned lines (nobody on the way yet) are lighter and thinner than a rider's live leg.
/// * Stop numbers appear only when one rider carries two or more of the orders. A collected stop's
///   number is fact; the rest are the server's nearest-next expectation and say "expected".
/// * Estimates are labelled as estimates, and the straight-line one says it is rough. With no rider
///   there is no number at all — the existing rule, no fix no number.
/// * The rider is only ever "your rider": the wire carries nothing else about the person.
///
/// Delivered orders keep their pin, now ticked, and lose their line and rider; cancelled ones are
/// dimmed with a cross, and their row opens the order page, where the reason is. With every order
/// finished the map stays as a static summary and stops refreshing.
///
/// The view is polled every [pollInterval]; with the tracking socket, each live order's rider
/// position is also pushed as it is recorded, gliding the marker between polls (at most
/// [maxLiveTopics] subscriptions — a checkout holds at most three shops).
///
/// RTL: the map is a picture of the world and is never mirrored; the chip, the rows and their
/// chevrons follow the reading direction.
class CheckoutMapScreen extends StatefulWidget {
  const CheckoutMapScreen({
    super.key,
    required this.api,
    required this.checkoutId,
    this.shopCount,
    this.justPlaced = false,
    this.liveSocket,
    this.onOpenOrder,
  });

  final CheckoutTrackingApi api;
  final String checkoutId;

  /// How many shops the checkout was placed with, when the caller knows (every entry point does).
  /// Used for the title before the first answer, and to look again quickly while the tracking
  /// service is still catching up with a checkout placed a moment ago.
  final int? shopCount;

  /// Whether this checkout was placed seconds ago, which only the jump straight from checkout
  /// knows. It is the one case where "not there" is worth waiting on: the orders are on their way
  /// to the tracking service. Opened from an order instead, a checkout with no map has not got
  /// one — the orders predate the map — and the answer is given at once rather than after ten
  /// seconds of spinner.
  final bool justPlaced;

  /// The tracking service's STOMP socket, for pushed rider positions. Optional: without it the map
  /// refreshes on the poll alone.
  final UserQueueSocket? liveSocket;

  /// Opens one order's page. Null draws the rows as plain text — never a tap that goes nowhere.
  final void Function(String orderId)? onOpenOrder;

  static const Duration pollInterval = Duration(seconds: 15);

  /// How soon to look again while a just-placed checkout is still arriving at the tracking
  /// service, and how many times.
  static const Duration catchUpInterval = Duration(seconds: 2);
  static const int catchUpAttempts = 5;

  static const int maxLiveTopics = 3;

  @override
  State<CheckoutMapScreen> createState() => _CheckoutMapScreenState();
}

class _CheckoutMapScreenState extends State<CheckoutMapScreen>
    with SingleTickerProviderStateMixin {
  /// Where the camera opens when nothing has a pin: the platform's zone as a viewport, never a
  /// position — no marker is ever drawn on it.
  static const LatLng _openingView = LatLng(33.8938, 35.5018);

  /// The server's own staleness rule (`delivery.tracking.eta.max-fix-age`), applied to pushed
  /// fixes the server has not judged yet.
  static const Duration _staleAfter = Duration(minutes: 5);

  CheckoutTracking? _view;
  bool _loading = true;
  bool _notFound = false;
  int _catchUps = 0;
  Timer? _poll;
  Timer? _catchUp;

  /// Pushed fixes by order, newer than the last poll's.
  final Map<String, RiderPosition> _pushed = <String, RiderPosition>{};
  final Map<String, StreamSubscription<Map<String, dynamic>>> _live =
      <String, StreamSubscription<Map<String, dynamic>>>{};

  final MapController _map = MapController();
  bool _mapReady = false;

  /// True once the customer has moved the map; after that the camera is theirs.
  bool _cameraIsTheirs = false;
  int _fittedTo = 0;

  /// The marker glide, as on the single-order panel: a pushed fix slides rather than teleports.
  late final AnimationController _glide = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800))
    ..addListener(() => setState(() {}));
  final Map<String, LatLng> _glideFrom = <String, LatLng>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _catchUp?.cancel();
    for (final StreamSubscription<Map<String, dynamic>> s in _live.values) {
      s.cancel();
    }
    _glide.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final CheckoutTracking view = await widget.api.view(widget.checkoutId);
      if (!mounted) return;
      setState(() {
        _view = view;
        _loading = false;
        _notFound = false;
      });
      _afterAnswer(view);
    } on DioException catch (e) {
      if (!mounted) return;
      final bool missing = e.response?.statusCode == 404;
      // A checkout placed a moment ago may not have reached the tracking service yet: look again
      // shortly, a few times, before saying it is not there. Only then — an older order's
      // checkout has no map to wait for, and waiting is ten seconds of spinner before the same
      // answer.
      if (missing && widget.justPlaced && _view == null
          && _catchUps < CheckoutMapScreen.catchUpAttempts) {
        _catchUps++;
        _catchUp?.cancel();
        _catchUp = Timer(CheckoutMapScreen.catchUpInterval, _load);
        return;
      }
      // Once a map is on screen, a failed refresh leaves it there; the next poll tries again.
      if (_view != null) return;
      setState(() {
        _loading = false;
        _notFound = missing;
      });
    } catch (_) {
      if (!mounted || _view != null) return;
      setState(() {
        _loading = false;
      });
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _notFound = false;
      _catchUps = 0;
    });
    _load();
  }

  /// Keeps the refresh cadence and the live subscriptions in step with the answer on screen.
  void _afterAnswer(CheckoutTracking view) {
    if (view.allFinished) {
      // A static summary: nothing is moving, so nothing is polled or subscribed.
      _poll?.cancel();
      _poll = null;
      _syncLive(const <String>{});
      return;
    }
    _poll ??= Timer.periodic(CheckoutMapScreen.pollInterval, (_) => _load());

    // Still catching up with a checkout placed a moment ago: some of its orders are not here yet.
    final int? expected = widget.shopCount;
    if (widget.justPlaced &&
        expected != null &&
        view.orders.length < expected &&
        _catchUps < CheckoutMapScreen.catchUpAttempts) {
      _catchUps++;
      _catchUp?.cancel();
      _catchUp = Timer(CheckoutMapScreen.catchUpInterval, _load);
    }

    _syncLive(<String>{
      for (final CheckoutTrackedOrder o in view.orders)
        if (!o.isFinished && o.riderAssigned) o.orderId,
    }.take(CheckoutMapScreen.maxLiveTopics).toSet());
  }

  void _syncLive(Set<String> wanted) {
    final UserQueueSocket? socket = widget.liveSocket;
    for (final String gone in _live.keys.where((String id) => !wanted.contains(id)).toList()) {
      _live.remove(gone)?.cancel();
    }
    if (socket == null) return;
    for (final String orderId in wanted) {
      _live.putIfAbsent(
        orderId,
        () => socket
            .subscribe('/topic/orders/$orderId/position')
            .listen((Map<String, dynamic> frame) => _onPushedFix(orderId, frame)),
      );
    }
  }

  void _onPushedFix(String orderId, Map<String, dynamic> frame) {
    if (!mounted) return;
    final RiderPosition fix;
    try {
      fix = RiderPosition.fromJson(frame);
    } catch (_) {
      return; // Not a position; the next poll brings the durable copy.
    }
    final CheckoutTracking? view = _view;
    final CheckoutRider? rider = view?.riderFor(orderId);
    if (view == null || rider == null) return;
    final LatLng? from = _riderPoint(rider)?.point;
    setState(() {
      _glideFrom
        ..clear()
        ..addAll(<String, LatLng>{if (from != null) _riderKey(rider): from});
      _pushed[orderId] = fix;
    });
    if (from != null) _glide.forward(from: 0);
  }

  static String _riderKey(CheckoutRider rider) =>
      (List<String>.of(rider.orderIds)..sort()).join('|');

  /// Where to draw a rider: the newest of the server's fix and anything pushed since, for any of
  /// their orders here. The newest wins whichever arrived last, so a poll answered from a view
  /// computed a few seconds ago never drags a pushed marker back.
  ///
  /// A pushed fix counts only while it is newer than the answer on screen. The service decides who
  /// may see a rider and re-decides it on every answer — a rider who has moved on to somebody
  /// else's delivery is withheld — and a frame from before that answer has already been judged by
  /// it. Each frame the socket carries was judged as it was recorded, so a newer one stands.
  ///
  /// Staleness is re-checked here against the fix's own time, not taken from the answer alone: the
  /// server's flag was true or false when it was computed, and a refresh that cannot reach the
  /// network leaves the last answer on screen for as long as the customer watches. The marker has
  /// to go on saying "last seen" by itself.
  ({LatLng point, bool stale, DateTime? at})? _riderPoint(CheckoutRider rider) {
    ({LatLng point, bool stale, DateTime? at})? best;
    final CheckoutRiderFix? server = rider.position;
    if (server != null) {
      best = (
        point: LatLng(server.pin.lat, server.pin.lng),
        stale: server.stale || _tooOld(server.recordedAt),
        at: server.recordedAt,
      );
    }
    final DateTime? judgedAt = _view?.computedAt;
    for (final String orderId in rider.orderIds) {
      final RiderPosition? pushed = _pushed[orderId];
      final DateTime? at = pushed?.recordedAt;
      if (pushed == null || at == null) continue;
      // Already covered by the answer on screen, which decided what may be shown.
      if (judgedAt != null && !at.isAfter(judgedAt)) continue;
      if (best == null || best.at == null || at.isAfter(best.at!)) {
        best = (point: LatLng(pushed.lat, pushed.lng), stale: _tooOld(at), at: at);
      }
    }
    return best;
  }

  /// Older than the platform will measure an estimate from — the server's own rule, applied to
  /// the fix's time here so that it keeps being true while the screen is offline.
  bool _tooOld(DateTime? at) => at != null && DateTime.now().difference(at) > _staleAfter;

  LatLng _gliding(String key, LatLng to) {
    final LatLng? from = _glideFrom[key];
    if (from == null || !_glide.isAnimating) return to;
    final double u = Curves.easeInOut.transform(_glide.value);
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * u,
      from.longitude + (to.longitude - from.longitude) * u,
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final CheckoutTracking? view = _view;
    final int? count = widget.shopCount ?? view?.orders.length;

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(
        title: count != null && count > 1 ? t.checkoutMapTitle(count) : t.multiCartTitle,
        onBack: () => Navigator.of(context).maybePop(),
        backSemanticLabel: t.back,
      ),
      body: view != null
          ? _content(context, t, view)
          : _loading
              ? const Center(child: CircularProgressIndicator(color: DeliveryColors.brand))
              : YdEmptyState(
                  icon: Icons.map_outlined,
                  title: _notFound ? t.checkoutMapNotFound : t.checkoutMapLoadFailed,
                  action: YdPillButton(
                    label: t.tryAgain,
                    onPressed: _retry,
                    expand: false,
                    size: YdPillButtonSize.compact,
                  ),
                ),
    );
  }

  Widget _content(BuildContext context, DeliveryStrings t, CheckoutTracking view) {
    // The brief's clamp: 40% of the screen, never under 220 nor over 420.
    final double height = (MediaQuery.sizeOf(context).height * 0.4).clamp(220, 420).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(height: height, child: _mapCanvas(t, view)),
        Expanded(
          child: ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(
                DeliverySpacing.md, DeliverySpacing.md, DeliverySpacing.md, DeliverySpacing.lg),
            children: <Widget>[
              if (view.allFinished) _note(t.checkoutMapAllFinished, Icons.check_circle_outline),
              if (view.door == null) _note(t.checkoutMapDoorNoPin, Icons.location_off_outlined),
              for (final CheckoutTrackedOrder order in view.orders) ...<Widget>[
                _CheckoutOrderRow(
                  order: order,
                  rider: view.riderFor(order.orderId),
                  riderPoint: switch (view.riderFor(order.orderId)) {
                    final CheckoutRider r => _riderPoint(r),
                    null => null,
                  },
                  onOpen: widget.onOpenOrder == null
                      ? null
                      : () => widget.onOpenOrder!(order.orderId),
                ),
                const SizedBox(height: DeliverySpacing.sm),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _note(String text, IconData icon) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: DeliverySpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: DeliveryColors.muted),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ the map

  /// Everything with a real position: shop pins, the door, the riders.
  List<LatLng> _plotted(CheckoutTracking view) => <LatLng>[
        for (final CheckoutTrackedOrder o in view.orders)
          if (o.shop case final GeoPin pin) LatLng(pin.lat, pin.lng),
        if (view.door case final GeoPin door) LatLng(door.lat, door.lng),
        for (final CheckoutRider r in view.riders)
          if (_riderPoint(r) case final ({LatLng point, bool stale, DateTime? at}) p) p.point,
      ];

  void _fitCamera(List<LatLng> points) {
    if (!_mapReady || _cameraIsTheirs) return;
    if (points.isEmpty || points.length == _fittedTo) return;
    _fittedTo = points.length;
    _map.fitCamera(CameraFit.coordinates(
      coordinates: points,
      padding: const EdgeInsets.all(40),
      maxZoom: 16.5,
    ));
  }

  Widget _mapCanvas(DeliveryStrings t, CheckoutTracking view) {
    final List<LatLng> points = _plotted(view);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitCamera(points);
    });

    final List<CheckoutRoutePath> drawn = <CheckoutRoutePath>[
      for (final CheckoutRoutePath p in view.paths)
        if (p.kind != CheckoutPathKind.unknown && p.line.length >= 2) p,
    ];

    return OsmBasemap(
      mapController: _map,
      options: MapOptions(
        initialCenter: points.isEmpty ? _openingView : points.first,
        initialZoom: points.isEmpty ? 12 : 15,
        minZoom: 3,
        maxZoom: 18,
        backgroundColor: DeliveryColors.background,
        initialCameraFit: points.length < 2
            ? null
            : CameraFit.coordinates(
                coordinates: points,
                padding: const EdgeInsets.all(40),
                maxZoom: 16.5,
              ),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.drag |
              InteractiveFlag.pinchZoom |
              InteractiveFlag.pinchMove |
              InteractiveFlag.doubleTapZoom |
              InteractiveFlag.scrollWheelZoom,
        ),
        onMapReady: () {
          _mapReady = true;
          _fittedTo = points.length;
        },
        onPositionChanged: (MapCamera _, bool hasGesture) {
          if (hasGesture) _cameraIsTheirs = true;
        },
      ),
      layers: <Widget>[
        if (drawn.isNotEmpty)
          PolylineLayer<Object>(
            polylines: <Polyline<Object>>[
              // Planned first, so a live leg is drawn over any planned line it crosses.
              for (final CheckoutRoutePath p in drawn.where(
                  (CheckoutRoutePath p) => p.kind == CheckoutPathKind.planned))
                _line(p),
              for (final CheckoutRoutePath p in drawn.where(
                  (CheckoutRoutePath p) => p.kind == CheckoutPathKind.riderLeg))
                _line(p),
            ],
          ),
        MarkerLayer(
          markers: <Marker>[
            for (final CheckoutTrackedOrder o in view.orders)
              if (o.shop case final GeoPin pin)
                Marker(
                  point: LatLng(pin.lat, pin.lng),
                  width: CheckoutShopPin.size,
                  height: CheckoutShopPin.size,
                  child: CheckoutShopPin(
                    order: o,
                    label: _shopName(t, o),
                  ),
                ),
            if (view.door case final GeoPin door)
              Marker(
                point: LatLng(door.lat, door.lng),
                width: 36,
                height: 36,
                child: Semantics(
                  label: t.custYourAddress,
                  child: const Icon(Icons.location_on, size: 34, color: DeliveryColors.ink),
                ),
              ),
            for (final CheckoutRider r in view.riders)
              if (_riderPoint(r) case final ({LatLng point, bool stale, DateTime? at}) p)
                Marker(
                  point: _gliding(_riderKey(r), p.point),
                  width: 34,
                  height: 34,
                  child: _RiderMarker(
                    stale: p.stale,
                    label: p.stale && p.at != null
                        ? t.checkoutMapRiderMarkerLastSeen(_ago(t, p.at!))
                        : t.checkoutMapYourRider,
                  ),
                ),
          ],
        ),
      ],
      fallback: _TilesDown(message: t.checkoutMapTilesDown),
      overlay: (bool _) => Stack(
        children: <Widget>[
          // The lines are straight guesses between pins: said on the map itself, not only in a
          // footnote, because the map is what the customer is looking at.
          if (view.isStraightLine && drawn.isNotEmpty)
            PositionedDirectional(
              top: DeliverySpacing.sm,
              start: DeliverySpacing.sm,
              end: DeliverySpacing.xxl,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: _MapChip(text: t.checkoutMapApproximate, icon: Icons.straighten),
              ),
            ),
          if (points.isEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(DeliverySpacing.lg),
                    child: _MapChip(text: t.checkoutMapNothingToDraw, icon: Icons.location_off),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// A path as the server says to draw it. Road geometry is solid; a straight path is dashed,
  /// because the dashes are the honest shape of "somewhere along here". Planned lines are lighter
  /// and thinner than a live leg, so the difference survives without colour.
  Polyline<Object> _line(CheckoutRoutePath path) {
    final bool live = path.kind == CheckoutPathKind.riderLeg;
    final bool road = path.polyline6 != null;
    return Polyline<Object>(
      points: <LatLng>[for (final GeoPin p in path.line) LatLng(p.lat, p.lng)],
      color: live ? DeliveryColors.brand : DeliveryColors.brand.withValues(alpha: 0.45),
      strokeWidth: live ? 4.5 : 3,
      borderColor: live ? DeliveryColors.white : const Color(0x00000000),
      borderStrokeWidth: live ? 1.5 : 0,
      pattern: road
          ? const StrokePattern.solid()
          : StrokePattern.dashed(segments: live ? const <double>[12, 8] : const <double>[6, 8]),
    );
  }
}

/// The shop's name as the order recorded it, or "a shop" — never a name the platform does not have.
String _shopName(DeliveryStrings t, CheckoutTrackedOrder order) =>
    (order.storeName == null || order.storeName!.trim().isEmpty)
        ? t.checkoutMapUnnamedShop
        : order.storeName!;

/// "7m ago", as the single-order panel says it.
String _ago(DeliveryStrings t, DateTime when) {
  final Duration since = DateTime.now().difference(when);
  if (since.inSeconds < 60) return t.secondsAgo(since.inSeconds < 0 ? 0 : since.inSeconds);
  if (since.inMinutes < 60) return t.minutesAgo(since.inMinutes);
  return t.hoursAgo(since.inHours);
}

/// Whole minutes, never below one: "0 min" reads as arrived, which the server did not say.
int _minutesOf(int seconds) => seconds <= 0 ? 1 : (seconds / 60).ceil();

/// A shop on the checkout map: the neighbourhood map's shop pin — brand disc, storefront glyph —
/// plus what the checkout adds. A stop number in a corner badge when the order is in a run (solid
/// for a collected stop, outlined for an expected one, so the difference is not colour alone); a
/// tick once delivered; dimmed with a cross once cancelled.
class CheckoutShopPin extends StatelessWidget {
  const CheckoutShopPin({super.key, required this.order, required this.label});

  final CheckoutTrackedOrder order;

  /// The shop's name, already resolved.
  final String label;

  /// The marker's box: the 36px disc and room for the badge that overhangs it.
  static const double size = 46;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final int? stop = order.isFinished ? null : order.stop;
    final String semantics = <String>[
      stop == null ? label : t.checkoutMapShopPinStop(label, stop),
      if (stop != null && order.expected) t.checkoutMapStopExpected(stop),
      if (order.isDelivered) t.stepDelivered,
      if (order.isCancelled) t.statusCancelled,
    ].join(', ');

    return Semantics(
      label: semantics,
      child: ExcludeSemantics(
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: <Widget>[
            _PinDisc(order: order, size: 36),
            if (stop != null)
              PositionedDirectional(
                top: 0,
                end: 0,
                child: _StopBadge(number: stop, expected: order.expected),
              ),
          ],
        ),
      ),
    );
  }
}

/// The shop disc itself, on the map and at the head of its row: brand with a storefront while
/// the order is live, green with a tick once delivered, dimmed grey with a cross once cancelled —
/// the glyph repeating what the colour says.
class _PinDisc extends StatelessWidget {
  const _PinDisc({required this.order, required this.size});

  final CheckoutTrackedOrder order;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bool delivered = order.isDelivered;
    final bool cancelled = order.isCancelled;
    final Widget disc = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cancelled
            ? DeliveryColors.faint
            : delivered
                ? DeliveryAccent.positive.onTint
                : DeliveryColors.brand,
        shape: BoxShape.circle,
        border: Border.all(color: DeliveryColors.white, width: 2),
        boxShadow: YdCard.softShadow,
      ),
      alignment: Alignment.center,
      child: Icon(
        cancelled
            ? Icons.close_rounded
            : delivered
                ? Icons.check_rounded
                : Icons.storefront_rounded,
        size: size / 2,
        color: DeliveryColors.white,
      ),
    );
    return cancelled ? Opacity(opacity: 0.55, child: disc) : disc;
  }
}

/// The run number in the pin's corner: ink-filled when the stop has been collected (a fact),
/// white with an ink ring when it is the platform's expectation.
class _StopBadge extends StatelessWidget {
  const _StopBadge({required this.number, required this.expected});

  final int number;
  final bool expected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: expected ? DeliveryColors.white : DeliveryColors.ink,
        shape: BoxShape.circle,
        border: Border.all(color: DeliveryColors.ink, width: 1.5),
      ),
      child: Text(
        '$number',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: expected ? DeliveryColors.ink : DeliveryColors.white,
          height: 1,
        ),
      ),
    );
  }
}

/// A rider's marker: the single-order panel's ink disc, or — for a fix too old to measure from — a
/// faded disc with a clock, which the row spells out as "last seen".
class _RiderMarker extends StatelessWidget {
  const _RiderMarker({required this.stale, required this.label});

  final bool stale;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: stale ? DeliveryColors.faint : DeliveryColors.ink,
          shape: BoxShape.circle,
          border: Border.all(color: DeliveryColors.white, width: 2.5),
          boxShadow: YdCard.softShadow,
        ),
        child: Icon(stale ? Icons.history : Icons.two_wheeler,
            size: 16, color: DeliveryColors.white),
      ),
    );
  }
}

/// A white label floating over the map.
class _MapChip extends StatelessWidget {
  const _MapChip({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: DeliverySpacing.sm + 2,
        vertical: DeliverySpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        boxShadow: YdCard.softShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: DeliveryColors.muted),
          const SizedBox(width: DeliverySpacing.xs + 2),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.muted,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What stands where the map would be when the tile server cannot be reached.
class _TilesDown extends StatelessWidget {
  const _TilesDown({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DeliveryColors.borderFaint,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(DeliverySpacing.lg),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.4),
      ),
    );
  }
}

/// One order of the checkout: its shop and status, where its rider is, and when it is expected —
/// or why not.
class _CheckoutOrderRow extends StatelessWidget {
  const _CheckoutOrderRow({
    required this.order,
    required this.rider,
    required this.riderPoint,
    required this.onOpen,
  });

  final CheckoutTrackedOrder order;
  final CheckoutRider? rider;
  final ({LatLng point, bool stale, DateTime? at})? riderPoint;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final OrderStatus? status = order.status;
    final String name = _shopName(t, order);
    final List<Widget> lines = <Widget>[
      if (!order.isFinished && order.stop != null)
        _line(order.expected
            ? t.checkoutMapStopExpected(order.stop!)
            : t.checkoutMapStop(order.stop!),
            emphasis: true),
      if (_riderState(context, t) case final String state) _line(state),
      ..._eta(context, t),
      if (!order.isFinished && rider?.hasOtherDeliveries == true)
        _line(t.checkoutMapOtherDeliveries),
      if (order.shop == null && !order.isFinished) _line(t.checkoutMapShopNoPin, faint: true),
      if (order.isCancelled && onOpen != null) _line(t.checkoutMapCancelledSeeWhy, link: true),
    ];

    return YdCard(
      padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
      onTap: onOpen,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 2),
            child: _PinDisc(order: order, size: 30),
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // The name ellipsises; the pill wraps to its own line when both will not fit.
                Wrap(
                  spacing: DeliverySpacing.sm,
                  runSpacing: DeliverySpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.ink,
                        height: 1.3,
                      ),
                    ),
                    CustomerStatusPill(
                      statusWire: order.statusWire,
                      label: status?.labelIn(t) ?? order.statusWire,
                    ),
                  ],
                ),
                if (lines.isNotEmpty) const SizedBox(height: DeliverySpacing.xs),
                ...lines,
              ],
            ),
          ),
          if (onOpen != null) ...<Widget>[
            const SizedBox(width: DeliverySpacing.xs),
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 2),
              child: Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                size: 18,
                color: DeliveryColors.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Where the rider is in the order's life — status-derived, with the one thing the status
  /// cannot say: that the rider's phone has gone quiet.
  String? _riderState(BuildContext context, DeliveryStrings t) {
    if (order.isDelivered) {
      final DateTime? at = order.completedAt;
      return at == null
          ? null
          : t.checkoutMapDeliveredAt(MaterialLocalizations.of(context)
              .formatTimeOfDay(TimeOfDay.fromDateTime(at)));
    }
    if (order.isFinished) return null;
    if (!order.riderAssigned) return t.checkoutMapNoRiderYet;
    final ({LatLng point, bool stale, DateTime? at})? where = riderPoint;
    if (where != null && where.stale && where.at != null) {
      return t.checkoutMapRiderLastSeen(_ago(t, where.at!));
    }
    // No marker because the service withholds one: claims often happen at home, and the rider
    // appears once they are near the shop. Said here, so the empty map is not a mystery. (The
    // other withheld state, on somebody else's delivery, is what the estimate line says.)
    if (where == null && rider?.sighting == RiderSightingState.headingToShop) {
      return t.custRiderShownNearShop;
    }
    return order.statusWire == OrderStatus.pickedUp.wire
        ? t.checkoutMapRiderHasIt
        : t.checkoutMapRiderToShop;
  }

  /// The estimate, labelled as one — or the server's reason there is none. Nothing at all with no
  /// rider (no fix, no number, and "no rider yet" already says why) or once the order is over.
  List<Widget> _eta(BuildContext context, DeliveryStrings t) {
    final OrderEta? eta = order.eta;
    if (eta == null || order.isFinished || !order.riderAssigned) return const <Widget>[];
    if (eta.available && eta.remainingSeconds != null && eta.estimatedArrival != null) {
      return <Widget>[
        _line(t.checkoutMapEtaEstimate(
          MaterialLocalizations.of(context)
              .formatTimeOfDay(TimeOfDay.fromDateTime(eta.estimatedArrival!)),
          _minutesOf(eta.remainingSeconds!),
        )),
        // The dev estimator knows nothing about roads; its number says so.
        if (eta.isStraightLine) _line(t.etaStraightLineNote, faint: true),
      ];
    }
    final EtaUnavailableReason? reason = eta.reason;
    if (reason == null || reason == EtaUnavailableReason.orderComplete) return const <Widget>[];
    return <Widget>[_line(custEtaReasonLabel(t, reason), faint: true)];
  }

  Widget _line(String text, {bool emphasis = false, bool faint = false, bool link = false}) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: faint ? 11.5 : 12.5,
          fontWeight: emphasis || link ? FontWeight.w600 : FontWeight.w400,
          color: link
              ? DeliveryColors.brand
              : faint
                  ? DeliveryColors.faint
                  : DeliveryColors.muted,
          height: 1.35,
        ),
      ),
    );
  }
}
