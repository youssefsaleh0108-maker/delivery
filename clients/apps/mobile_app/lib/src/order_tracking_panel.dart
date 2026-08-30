import 'dart:async';
import 'dart:math' as math;

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
// `hide Path`: latlong2 ships a `Path<T>` of its own, and the trail painter below draws with
// `dart:ui`'s. Importing both unqualified turns every `Path()` in this file into the wrong one.
import 'package:latlong2/latlong.dart' hide Path;

import 'address_sheet.dart' show OsmBasemap;
import 'customer_chat_screen.dart';
import 'delivery_address.dart';
import 'order_details_screen.dart' show CustomerStatusPill;

/// Live tracking for an order in flight, drawn as the redesign's `customer-order-tracking`
/// (node 3:619): a 520px map canvas with the tracking sheet — rounded 24 at the top, lifted by the
/// heavier sheet shadow — sitting under it.
///
/// **The map canvas is a real map now.** OpenStreetMap raster tiles under the sheet, carrying the
/// rider's recorded track as a polyline, a marker on their latest fix, and a marker on the door
/// when the address the order went to still has its pin in this device's address book. The
/// remaining distance and ETA the tracking service computes are drawn over the tiles and into the
/// sheet's headline. When the server says no estimate exists, its reason is shown instead — a
/// number is never invented, and neither is a position: nothing is plotted that a fix did not put
/// there.
///
/// The styled canvas the panel used to be survives as the tile-failure surface — an unreachable
/// tile server leaves the shape of the journey drawn on the palette's own neutrals rather than a
/// grey lattice of missing squares.
///
/// The design's rider card — avatar, name, rating, call button — is still not drawn. The wire
/// carries a `riderId` and nothing else about the person, and inventing a name, a face or a
/// score would be fabrication. The *message* button is real now: it opens the customer's side of
/// the order conversation once a rider is assigned. The call button stays omitted — putting a
/// rider's phone number in front of a customer is a decision the owner has not made.
class OrderTrackingPanel extends StatefulWidget {
  const OrderTrackingPanel({
    super.key,
    required this.api,
    required this.order,
    this.trackingApi,
    this.chatApi,
  });

  final OrderApi api;
  final DeliveryOrder order;

  /// The ETA endpoint. Optional so the panel still builds where the shell has not been handed
  /// one; the headline then stays the status sentence it was. Never used to invent a number —
  /// when the server says no estimate exists, the reason is shown instead.
  final TrackingApi? trackingApi;

  /// The order conversation. Optional for the same reason; without it there is no chat entry at
  /// all rather than a dead button.
  final ChatApi? chatApi;

  @override
  State<OrderTrackingPanel> createState() => _OrderTrackingPanelState();
}

class _OrderTrackingPanelState extends State<OrderTrackingPanel> {
  /// Matches the rider app's own ping cadence; polling faster only burns requests.
  static const Duration _pollInterval = Duration(seconds: 5);

  /// The height the design gives the map canvas.
  static const double _canvasHeight = 520;

  /// Where the canvas opens before any fix exists to look at.
  ///
  /// The platform's own configured zone (`delivery.platform.zone`, `Asia/Beirut`) as a point, and
  /// only ever a viewport: it is not a position, is never labelled as one, and no marker is drawn
  /// on it. The moment a real fix or a real door coordinate exists the camera fits to that instead.
  static const LatLng _openingView = LatLng(33.8938, 35.5018);

  Timer? _poll;
  List<RiderPosition> _trail = <RiderPosition>[];
  RiderPosition? _latest;
  bool _loaded = false;

  /// The server's last answer about when the rider is expected. Null until the first answer —
  /// and always rendered exactly as sent: a number when it has one, its reason when it does not.
  OrderEta? _eta;

  // ------------------------------------------------------------------ the map

  final MapController _map = MapController();
  bool _mapReady = false;

  /// True once the customer has panned or zoomed. After that the camera is theirs: refitting it
  /// under their thumb every five seconds is the classic way to make a live map unusable.
  bool _cameraIsTheirs = false;

  /// How many points the camera was last fitted to, so a fit only happens when there is something
  /// new to fit.
  int _fittedTo = 0;

  /// The door, when this device knows where it is.
  ///
  /// The order carries the address as a line of text and nothing else — the wire has no
  /// coordinates on it — so the only honest source is the address book this customer placed the
  /// order from, where the pin they dropped is stored against that same line. No match means no
  /// destination marker; a guessed one would be a pin on somebody else's door.
  LatLng? _destination;

  bool get _isLive =>
      widget.order.status.wire != 'DELIVERED' && widget.order.status.wire != 'CANCELLED';

  /// True once the food has left the kitchen, which is when a position can exist at all.
  bool get _afterPickup =>
      widget.order.status.wire == 'READY' || widget.order.status.wire == 'PICKED_UP';

  @override
  void initState() {
    super.initState();
    _refresh();
    _resolveDestination();
    if (_isLive) {
      _poll = Timer.periodic(_pollInterval, (_) => _refresh());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _map.dispose();
    super.dispose();
  }

  /// Looks the order's address up in this customer's own address book to find the pin it was
  /// placed with.
  ///
  /// Scoped to [DeliveryOrder.customerId], which is the same Keycloak subject the store is keyed
  /// on — so one account can never read another's saved pins, and a device that never saved this
  /// address simply has no destination marker.
  Future<void> _resolveDestination() async {
    final DeliveryAddressStore book =
        DeliveryAddressStore(ownerId: widget.order.customerId);
    LatLng? found;
    try {
      await book.load();
      final String line = widget.order.deliveryAddress.trim();
      for (final DeliveryAddress a in <DeliveryAddress>[
        if (book.selected != null) book.selected!,
        ...book.recents,
      ]) {
        if (a.line.trim() != line) continue;
        final double? lat = a.latitude;
        final double? lng = a.longitude;
        if (lat == null || lng == null) continue;
        found = LatLng(lat, lng);
        break;
      }
    } catch (_) {
      // No marker. The address book is a local convenience and an unreadable one costs the map a
      // pin, not the screen.
    } finally {
      book.dispose();
    }
    if (!mounted || found == null) return;
    setState(() => _destination = found);
  }

  Future<void> _refresh() async {
    try {
      final List<RiderPosition> history = await widget.api.trackHistory(widget.order.id);
      if (!mounted) return;
      setState(() {
        _trail = history;
        _latest = history.isEmpty ? null : history.last;
        _loaded = true;
      });
    } catch (_) {
      // Tracking is supplementary. A failure leaves the last known track on screen rather than
      // replacing the order page with an error.
      if (mounted) setState(() => _loaded = true);
    }
    await _refreshEta();
  }

  Future<void> _refreshEta() async {
    final TrackingApi? api = widget.trackingApi;
    if (api == null) return;
    try {
      final OrderEta eta = await api.eta(widget.order.id);
      if (!mounted) return;
      setState(() => _eta = eta);
    } catch (_) {
      // The last answer stays on screen; the next poll replaces it. An unreachable ETA endpoint
      // must not take the tracking page down with it.
    }
  }

  /// Whole minutes to show for the remaining travel, never below one — "0 min" reads as arrived,
  /// which the server did not say.
  static int _minutesOf(int seconds) => seconds <= 0 ? 1 : (seconds / 60).ceil();

  /// Straight-line metres between two fixes, by the haversine formula.
  static double _metresBetween(RiderPosition a, RiderPosition b) {
    const double earthRadius = 6371000;
    final double dLat = (b.lat - a.lat) * math.pi / 180;
    final double dLng = (b.lng - a.lng) * math.pi / 180;
    final double lat1 = a.lat * math.pi / 180;
    final double lat2 = b.lat * math.pi / 180;
    final double h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2);
    return 2 * earthRadius * math.asin(math.min(1, math.sqrt(h)));
  }

  double get _distanceTravelled {
    double total = 0;
    for (int i = 1; i < _trail.length; i++) {
      total += _metresBetween(_trail[i - 1], _trail[i]);
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    // A finished or cancelled order has nothing to track, and the order page already carries the
    // five-step stepper that says where it got to.
    if (!_isLive) return const SizedBox.shrink();

    final DeliveryStrings t = DeliveryStrings.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _mapCanvas(t),
        _progressSteps(t),
        _sheet(t),
      ],
    );
  }

  /// The frame's four-step bar under the map: Confirmed, Preparing, On the Way, Delivered — a
  /// crimson bar per step reached, the border colour for the rest, the current one's label in
  /// brand. Delivered never lights here only because a delivered order has no live panel at all.
  Widget _progressSteps(DeliveryStrings t) {
    final OrderStatus status = widget.order.status;
    final int reached = switch (status) {
      OrderStatus.accepted => 1,
      OrderStatus.preparing || OrderStatus.ready => 2,
      OrderStatus.pickedUp => 3,
      OrderStatus.delivered => 4,
      _ => 0,
    };
    final List<String> labels = <String>[
      t.custTrackConfirmed,
      t.custTrackPreparing,
      t.custTrackOnTheWay,
      t.custTrackDelivered,
    ];

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
          DeliverySpacing.lg, DeliverySpacing.md, DeliverySpacing.lg, 0),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < labels.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: DeliverySpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i < reached
                          ? DeliveryColors.brand
                          : DeliveryColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: i == reached - 1
                          ? DeliveryColors.brand
                          : i < reached
                              ? DeliveryColors.ink
                              : DeliveryColors.faint,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ the map slot

  /// Everything with a real position on it: the recorded track, and the door when it is known.
  List<LatLng> get _plotted => <LatLng>[
        for (final RiderPosition p in _trail) LatLng(p.lat, p.lng),
        if (_destination != null) _destination!,
      ];

  /// Keeps the whole journey in frame while it is still the app's camera to move.
  void _fitCamera() {
    if (!_mapReady || _cameraIsTheirs) return;
    final List<LatLng> points = _plotted;
    if (points.isEmpty || points.length == _fittedTo) return;
    _fittedTo = points.length;
    _map.fitCamera(CameraFit.coordinates(
      coordinates: points,
      padding: const EdgeInsets.all(56),
      // A single fix would otherwise fit at the maximum zoom the projection allows, which is a
      // doorstep filling the screen with no street around it to place it on.
      maxZoom: 16.5,
    ));
  }

  Widget _mapCanvas(DeliveryStrings t) {
    final List<LatLng> points = _plotted;
    // Fitting inside build would move the camera during layout; this runs after the frame that
    // brought the new fix in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitCamera();
    });

    return SizedBox(
      height: _canvasHeight,
      child: OsmBasemap(
        mapController: _map,
        options: MapOptions(
          initialCenter: points.isEmpty ? _openingView : points.first,
          initialZoom: points.isEmpty ? 12 : 15,
          minZoom: 3,
          maxZoom: 18,
          backgroundColor: DeliveryColors.background,
          initialCameraFit: points.isEmpty
              ? null
              : CameraFit.coordinates(
                  coordinates: points,
                  padding: const EdgeInsets.all(56),
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
          if (_trail.length > 1)
            PolylineLayer<Object>(
              polylines: <Polyline<Object>>[
                Polyline<Object>(
                  points: <LatLng>[
                    for (final RiderPosition p in _trail) LatLng(p.lat, p.lng),
                  ],
                  color: DeliveryColors.brand.withValues(alpha: 0.75),
                  borderColor: DeliveryColors.white,
                  borderStrokeWidth: 1.5,
                  strokeWidth: 4,
                ),
              ],
            ),
          MarkerLayer(
            markers: <Marker>[
              if (_destination case final LatLng door)
                Marker(
                  point: door,
                  width: 34,
                  height: 34,
                  child: _destinationMarker(t),
                ),
              if (_latest case final RiderPosition fix)
                Marker(
                  point: LatLng(fix.lat, fix.lng),
                  width: 34,
                  height: 34,
                  child: _riderMarker(t),
                ),
            ],
          ),
        ],
        // The canvas this panel used to be, kept for exactly the case it was built for: no tiles.
        fallback: _styledSurface(),
        overlay: (bool _) => _mapOverlay(t),
      ),
    );
  }

  /// Where the door is: the brand pin, ringed in white so it reads over any tile.
  Widget _destinationMarker(DeliveryStrings t) => Semantics(
        label: t.custYourAddress,
        child: const Icon(Icons.place, size: 30, color: DeliveryColors.brand),
      );

  /// Where the rider was at their last recorded fix — never anywhere they have not pinged from.
  Widget _riderMarker(DeliveryStrings t) => Semantics(
        label: t.custTheRider,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: DeliveryColors.ink,
            shape: BoxShape.circle,
            border: Border.all(color: DeliveryColors.white, width: 2.5),
            boxShadow: YdCard.softShadow,
          ),
          child: const Icon(Icons.two_wheeler, size: 16, color: DeliveryColors.white),
        ),
      );

  /// The tile-failure surface: the page background, the faint lattice, and the journey drawn on it
  /// at its own scale — the panel's original canvas, now doing the one job it is still right for.
  Widget _styledSurface() {
    return CustomPaint(
      painter: _MapSurfacePainter(),
      child: _trail.isEmpty
          ? null
          : CustomPaint(painter: _TrailPainter(_trail)),
    );
  }

  /// Everything drawn in screen space over the canvas, in either state: the "Live map" label, the
  /// ETA chip, and the sentence that stands in for a track there is nothing to draw yet.
  Widget _mapOverlay(DeliveryStrings t) {
    return Stack(
      children: <Widget>[
        if (_trail.isEmpty && _destination == null)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: DeliveryColors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: DeliveryColors.brand, width: 2),
                      ),
                      child: const Icon(Icons.place_outlined,
                          size: 18, color: DeliveryColors.brand),
                    ),
                    const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                    Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: DeliverySpacing.lg),
                      child: Container(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: DeliverySpacing.sm + 2,
                          vertical: DeliverySpacing.xs + 2,
                        ),
                        decoration: BoxDecoration(
                          color: DeliveryColors.white,
                          borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                          boxShadow: YdCard.softShadow,
                        ),
                        child: Text(
                          _afterPickup ? t.waitingForRider : t.locationAfterPickup,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: DeliveryColors.muted,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        // The real numbers, on the map surface: how far the rider still has to go and when
        // they are expected — drawn only when the tracking service actually sent them.
        if (_eta case final OrderEta eta when eta.available)
          PositionedDirectional(
            // Above the licence notice in the opposite corner, and clear of the sheet's lip.
            bottom: DeliverySpacing.md,
            start: DeliverySpacing.lg,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: DeliverySpacing.sm + 2,
                  vertical: DeliverySpacing.xs + 2,
                ),
                decoration: BoxDecoration(
                  color: DeliveryColors.white,
                  borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                  boxShadow: YdCard.softShadow,
                ),
                child: Text(
                  <String>[
                    if (eta.remainingMetres != null)
                      eta.remainingMetres! >= 1000
                          ? t.distanceKm((eta.remainingMetres! / 1000).toStringAsFixed(1))
                          : t.distanceM(eta.remainingMetres!.round().toString()),
                    if (eta.remainingSeconds != null)
                      '${_minutesOf(eta.remainingSeconds!)} ${t.etaMinShort}',
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.ink,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
        PositionedDirectional(
          top: DeliverySpacing.md,
          start: DeliverySpacing.lg,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: DeliverySpacing.sm + 2,
                vertical: DeliverySpacing.xs + 2,
              ),
              decoration: BoxDecoration(
                color: DeliveryColors.white,
                borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                boxShadow: YdCard.softShadow,
              ),
              child: Text(
                t.custLiveMap,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DeliveryColors.muted,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ the sheet over it

  /// The big line: minutes when the server sent them, the order's status when it did not.
  String _headline(DeliveryStrings t) {
    final OrderEta? eta = _eta;
    if (eta != null && eta.available && eta.remainingSeconds != null) {
      return '${_minutesOf(eta.remainingSeconds!)} ${t.etaMinShort}';
    }
    return widget.order.status.labelIn(t);
  }

  /// The quiet line under it: the journey leg and arrival time behind a live estimate, the
  /// server's reason when there is none, and the panel's old sentence before the first answer.
  String _subline(DeliveryStrings t) {
    final OrderEta? eta = _eta;
    if (eta != null && eta.available) {
      final List<String> parts = <String>[
        if (eta.leg != null) custEtaLegLabel(t, eta.leg!),
        if (eta.estimatedArrival != null)
          '${t.etaArriving} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(eta.estimatedArrival!))}',
      ];
      if (parts.isNotEmpty) return parts.join(' · ');
    }
    if (eta != null && !eta.available && eta.reason != null) {
      return custEtaReasonLabel(t, eta.reason!);
    }
    return _afterPickup ? t.waitingForRider : t.locationAfterPickup;
  }

  Widget _sheet(DeliveryStrings t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DeliverySpacing.lg),
      decoration: BoxDecoration(
        color: DeliveryColors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(DeliveryRadius.sheet),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: DeliveryColors.ink.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: DeliveryColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // The design's headline is an ETA, and now there is one to show — when the
                    // tracking service sent a number. When it declined, the headline stays the
                    // status and the reason is said quietly underneath; a number is never
                    // invented.
                    Text(
                      _headline(t),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.ink,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subline(t),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: DeliveryColors.muted,
                        height: 1.35,
                      ),
                    ),
                    // The dev estimator knows nothing about roads; its number is shown with
                    // exactly that much confidence.
                    if (_eta?.available == true && _eta!.isStraightLine) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        t.etaStraightLineNote,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: DeliveryColors.faint,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              CustomerStatusPill(
                statusWire: widget.order.status.wire,
                label: widget.order.status.labelIn(t),
              ),
            ],
          ),
          if (_trail.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            const Divider(height: 1, thickness: 1, color: DeliveryColors.border),
            const SizedBox(height: 20),
            // The design's rider card sits here. Only the fixes are real, so only the fixes are
            // shown — see the class note.
            _stats(t),
          ] else if (_loaded) ...<Widget>[
            const SizedBox(height: 20),
            const Divider(height: 1, thickness: 1, color: DeliveryColors.border),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: DeliveryColors.background,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.two_wheeler,
                      size: 18, color: DeliveryColors.muted),
                ),
                const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
                Expanded(
                  child: Text(
                    t.locationAfterPickup,
                    style: const TextStyle(
                      fontSize: 13,
                      color: DeliveryColors.muted,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
          // The design's rider-card slot ends in a message action, and now the customer's side
          // of the conversation exists. Only with a rider to talk to: the conversation opens
          // server-side when one is assigned, so a button before that would 404.
          if (widget.chatApi != null && widget.order.riderId != null) ...<Widget>[
            const SizedBox(height: 20),
            const Divider(height: 1, thickness: 1, color: DeliveryColors.border),
            const SizedBox(height: 20),
            _chatEntry(t),
          ],
        ],
      ),
    );
  }

  /// The "Message the rider" row: the tinted 40px chat disc, the label, and the direction-aware
  /// chevron, opening the customer's side of the order conversation.
  Widget _chatEntry(DeliveryStrings t) {
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => CustomerChatScreen(
            api: widget.chatApi!,
            orderId: widget.order.id,
          ),
        )),
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: DeliveryColors.brandSoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  size: 18, color: DeliveryColors.brand),
            ),
            const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
            Expanded(
              child: Text(
                t.custChatWithRider,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: DeliveryColors.ink,
                  height: 1.25,
                ),
              ),
            ),
            Icon(
              Directionality.of(context) == TextDirection.rtl
                  ? Icons.chevron_left_rounded
                  : Icons.chevron_right_rounded,
              size: 18,
              color: DeliveryColors.muted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _stats(DeliveryStrings t) {
    final RiderPosition? latest = _latest;
    final double metres = _distanceTravelled;
    return Row(
      children: <Widget>[
        _stat(t.fixes, '${_trail.length}'),
        _stat(
            t.travelled,
            metres >= 1000
                ? t.distanceKm((metres / 1000).toStringAsFixed(1))
                : t.distanceM(metres.round().toString())),
        _stat(t.lastSeen, latest?.recordedAt == null ? '—' : _ago(t, latest!.recordedAt!)),
      ],
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: DeliveryColors.muted, height: 1.3)),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.ink,
                  height: 1.25)),
        ],
      ),
    );
  }

  /// Takes the strings rather than reading them from a context: this is static, so there is no
  /// element to look them up from.
  static String _ago(DeliveryStrings t, DateTime when) {
    final Duration since = DateTime.now().difference(when);
    if (since.inSeconds < 60) return t.secondsAgo(since.inSeconds);
    if (since.inMinutes < 60) return t.minutesAgo(since.inMinutes);
    return t.hoursAgo(since.inHours);
  }
}

/// The map slot itself: the page background with a faint grid over it.
///
/// Not a basemap and not pretending to be one — it is the surface the design sizes at 520px, drawn
/// in the palette's own neutrals so the real track laid over it reads as a plan rather than as a
/// line floating in space.
class _MapSurfacePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = DeliveryColors.background,
    );

    final Paint grid = Paint()
      ..color = DeliveryColors.border
      ..strokeWidth = 1;
    const double cell = 48;
    for (double x = cell; x < size.width; x += cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = cell; y < size.height; y += cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  @override
  bool shouldRepaint(_MapSurfacePainter oldDelegate) => false;
}

/// Draws the recorded track, auto-scaled to its own bounds.
///
/// Auto-scaling rather than a fixed zoom because there is no basemap to stay registered with: the
/// only thing worth showing is the shape and extent of the journey, and a fixed scale would render
/// most trips as a single dot.
class _TrailPainter extends CustomPainter {
  _TrailPainter(this.trail);

  final List<RiderPosition> trail;

  @override
  void paint(Canvas canvas, Size size) {
    if (trail.isEmpty) return;

    double minLat = trail.first.lat, maxLat = trail.first.lat;
    double minLng = trail.first.lng, maxLng = trail.first.lng;
    for (final RiderPosition p in trail) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLng = math.min(minLng, p.lng);
      maxLng = math.max(maxLng, p.lng);
    }
    // A degenerate span (one fix, or a stationary rider) would divide by zero and then by an
    // arbitrarily tiny number, magnifying GPS jitter into a scribble.
    final double spanLat = math.max(maxLat - minLat, 0.0005);
    final double spanLng = math.max(maxLng - minLng, 0.0005);

    const double pad = 48;
    Offset project(RiderPosition p) => Offset(
          pad + (p.lng - minLng) / spanLng * (size.width - pad * 2),
          // Latitude increases northward; screen y increases downward.
          size.height - pad - (p.lat - minLat) / spanLat * (size.height - pad * 2),
        );

    final Path path = Path();
    for (int i = 0; i < trail.length; i++) {
      final Offset o = project(trail[i]);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = DeliveryColors.brand.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Where the rider started.
    canvas.drawCircle(project(trail.first), 5,
        Paint()..color = DeliveryColors.muted.withValues(alpha: 0.8));

    // Where they are now, with a halo so it reads at a glance.
    final Offset now = project(trail.last);
    canvas.drawCircle(now, 14, Paint()..color = DeliveryColors.brand.withValues(alpha: 0.18));
    canvas.drawCircle(now, 7, Paint()..color = DeliveryColors.brand);
    canvas.drawCircle(
        now,
        7,
        Paint()
          ..color = DeliveryColors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_TrailPainter oldDelegate) => oldDelegate.trail.length != trail.length;
}
