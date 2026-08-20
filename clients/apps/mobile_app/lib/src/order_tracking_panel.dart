import 'dart:async';
import 'dart:math' as math;

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// Live tracking for an order in flight: where it is in its lifecycle, and where the rider is.
///
/// **No map tiles, deliberately.** A tile layer needs a reachable tile server and an API key, and
/// this deployment cannot rely on either — the CanvasKit CDN already stalls here. More decisively,
/// nothing in the system has coordinates for a store or a delivery address: addresses are free
/// text and `stores.latitude` is null throughout. A tile map would therefore show a dot wandering
/// over a street grid with no pickup and no destination on it, which looks like tracking without
/// being it.
///
/// So this plots the rider's actual recorded track, auto-scaled to its own bounds, beside the
/// status timeline. Everything shown is real. When stores and addresses gain coordinates, this is
/// the widget that gains a destination marker and a genuine ETA.
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

  Timer? _poll;
  List<RiderPosition> _trail = <RiderPosition>[];
  RiderPosition? _latest;
  bool _loaded = false;

  /// The lifecycle, in order. The timeline renders every step so a customer can see what is still
  /// to come, not only what has happened.
  ///
  /// Wire values only. The label for each is looked up per build by [_labelFor], because a
  /// translated string is not a compile-time constant and the order the steps happen in is the part
  /// that genuinely never changes.
  static const List<String> _steps = <String>[
    'PLACED', 'ACCEPTED', 'PREPARING', 'READY', 'PICKED_UP', 'DELIVERED',
  ];

  String _labelFor(String wire) {
    return switch (wire) {
      'PLACED' => DeliveryStrings.of(context).stepPlaced,
      'ACCEPTED' => DeliveryStrings.of(context).stepAccepted,
      'PREPARING' => DeliveryStrings.of(context).stepPreparing,
      'READY' => DeliveryStrings.of(context).stepReady,
      'PICKED_UP' => DeliveryStrings.of(context).stepOnTheWay,
      // Exhaustive over _steps, and a switch rather than a map so adding a step to the list above
      // without a label here fails to compile.
      _ => DeliveryStrings.of(context).stepDelivered,
    };
  }

  bool get _isLive =>
      widget.order.status.wire != 'DELIVERED' && widget.order.status.wire != 'CANCELLED';

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

  int get _currentStep {
    final int index = _steps.indexOf(widget.order.status.wire);
    // CANCELLED is not on the line; show it as having got no further than where it stopped.
    return index < 0 ? 0 : index;
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
    if (widget.order.status.wire == 'CANCELLED') {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DeliverySpacing.md),
      decoration: BoxDecoration(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
        boxShadow: DeliveryShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(DeliveryStrings.of(context).tracking,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const Spacer(),
              if (_isLive)
                Row(
                  children: <Widget>[
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                          color: DeliveryColors.brand, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(DeliveryStrings.of(context).live,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: DeliveryColors.brand)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md),
          _timeline(),
          if (_trail.isNotEmpty) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
              child: Container(
                height: 180,
                width: double.infinity,
                color: DeliveryColors.background,
                child: CustomPaint(painter: _TrailPainter(_trail)),
              ),
            ),
            const SizedBox(height: DeliverySpacing.sm),
            _stats(),
          ] else if (_loaded && _isLive)
            Padding(
              padding: const EdgeInsets.only(top: DeliverySpacing.sm),
              child: Text(
                _currentStep >= 4
                    ? DeliveryStrings.of(context).waitingForRider
                    : DeliveryStrings.of(context).locationAfterPickup,
                style: const TextStyle(fontSize: 12.5, color: DeliveryColors.muted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _timeline() {
    final int current = _currentStep;
    return Row(
      children: <Widget>[
        for (int i = 0; i < _steps.length; i++) ...<Widget>[
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: i <= current ? DeliveryColors.brand : DeliveryColors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: i <= current ? DeliveryColors.brand : DeliveryColors.border,
                    width: 2,
                  ),
                ),
                child: i < current
                    ? const Icon(Icons.check_rounded, size: 11, color: Colors.white)
                    : null,
              ),
              const SizedBox(height: DeliverySpacing.xs),
              SizedBox(
                width: 52,
                child: Text(
                  _labelFor(_steps[i]),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.2,
                    fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                    color: i <= current ? DeliveryColors.ink : DeliveryColors.muted,
                  ),
                ),
              ),
            ],
          ),
          if (i < _steps.length - 1)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.only(bottom: 26),
                color: i < current ? DeliveryColors.brand : DeliveryColors.border,
              ),
            ),
        ],
      ],
    );
  }

  Widget _stats() {
    final RiderPosition? latest = _latest;
    final double metres = _distanceTravelled;
    final DeliveryStrings t = DeliveryStrings.of(context);
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
          Text(label, style: const TextStyle(fontSize: 11, color: DeliveryColors.muted)),
          Text(value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
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

    const double pad = 22;
    Offset project(RiderPosition p) => Offset(
          pad + (p.lng - minLng) / spanLng * (size.width - pad * 2),
          // Latitude increases northward; screen y increases downward.
          size.height - pad - (p.lat - minLat) / spanLat * (size.height - pad * 2),
        );

    // Faint grid, so the track reads as a plan rather than floating in space.
    final Paint grid = Paint()
      ..color = DeliveryColors.border
      ..strokeWidth = 1;
    for (int i = 1; i < 4; i++) {
      final double x = size.width / 4 * i;
      final double y = size.height / 4 * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

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
    canvas.drawCircle(now, 12, Paint()..color = DeliveryColors.brand.withValues(alpha: 0.18));
    canvas.drawCircle(now, 6, Paint()..color = DeliveryColors.brand);
    canvas.drawCircle(now, 6,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_TrailPainter oldDelegate) => oldDelegate.trail.length != trail.length;
}
