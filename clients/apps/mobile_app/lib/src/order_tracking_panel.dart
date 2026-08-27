import 'dart:async';
import 'dart:math' as math;

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'order_details_screen.dart' show CustomerStatusPill;

/// Live tracking for an order in flight, drawn as the redesign's `customer-order-tracking`
/// (node 3:619): a 520px map canvas with the tracking sheet — rounded 24 at the top, lifted by the
/// heavier sheet shadow — sitting under it.
///
/// **The map canvas is a styled placeholder, deliberately.** A tile layer needs a reachable tile
/// server and an API key, and this deployment can rely on neither. More decisively, nothing in the
/// system has coordinates for a store or a delivery address: addresses are free text and
/// `stores.latitude` is null throughout. So the canvas is painted as the surface the design sizes
/// it at, marked as not-yet-live, and the rider's *actual* recorded track is drawn on top of it
/// when there is one. Everything shown is real; the three drawn map pins are not, and are not
/// reproduced. When stores and addresses gain coordinates, this is the widget that gains a
/// basemap, a destination marker and a genuine ETA.
///
/// The design's rider card — avatar, name, rating, message and call buttons — is not drawn either.
/// The wire carries a `riderId` and nothing else about the person, and inventing a name, a face or
/// a score would be fabrication. The message and call buttons are omitted outright: there is no
/// in-app chat, and putting a rider's phone number in front of a customer is a decision the owner
/// has not made. The slot carries the real fixes instead.
class OrderTrackingPanel extends StatefulWidget {
  const OrderTrackingPanel({super.key, required this.api, required this.order});

  final OrderApi api;
  final DeliveryOrder order;

  @override
  State<OrderTrackingPanel> createState() => _OrderTrackingPanelState();
}

class _OrderTrackingPanelState extends State<OrderTrackingPanel> {
  /// Matches the rider app's own ping cadence; polling faster only burns requests.
  static const Duration _pollInterval = Duration(seconds: 5);

  /// The height the design gives the map canvas.
  static const double _canvasHeight = 520;

  Timer? _poll;
  List<RiderPosition> _trail = <RiderPosition>[];
  RiderPosition? _latest;
  bool _loaded = false;

  bool get _isLive =>
      widget.order.status.wire != 'DELIVERED' && widget.order.status.wire != 'CANCELLED';

  /// True once the food has left the kitchen, which is when a position can exist at all.
  bool get _afterPickup =>
      widget.order.status.wire == 'READY' || widget.order.status.wire == 'PICKED_UP';

  @override
  void initState() {
    super.initState();
    _refresh();
    if (_isLive) {
      _poll = Timer.periodic(_pollInterval, (_) => _refresh());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
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
  }

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
        _sheet(t),
      ],
    );
  }

  // ------------------------------------------------------------------ the map slot

  Widget _mapCanvas(DeliveryStrings t) {
    return SizedBox(
      height: _canvasHeight,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: CustomPaint(
              painter: _MapSurfacePainter(),
              child: _trail.isEmpty
                  ? null
                  : CustomPaint(painter: _TrailPainter(_trail)),
            ),
          ),
          if (_trail.isEmpty)
            Positioned.fill(
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
                  ],
                ),
              ),
            ),
          // The basemap itself is the part that does not exist yet, and says so in the design's
          // own chip language rather than by drawing streets nobody can navigate by.
          PositionedDirectional(
            top: DeliverySpacing.md,
            start: DeliverySpacing.lg,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
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
                const SizedBox(width: DeliverySpacing.sm),
                YdComingSoon(label: t.custSoon, icon: Icons.schedule),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ the sheet over it

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
                    // The design's headline is an ETA. Nothing in the platform computes one — no
                    // coordinates, no route — so the headline says what is true instead: where the
                    // order has got to.
                    Text(
                      widget.order.status.labelIn(t),
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
                      _afterPickup ? t.waitingForRider : t.locationAfterPickup,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: DeliveryColors.muted,
                        height: 1.35,
                      ),
                    ),
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
        ],
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
