/// A multi-shop checkout on one map, mirroring Order Tracking's `CheckoutView`.
///
/// Every coordinate here is one the platform holds — a shop or door pin snapshotted on the order,
/// or a rider's recorded fix — and a point it does not hold is null. The screen draws exactly this
/// and nothing it would have to guess: a missing pin is not drawn, a path is drawn as the server's
/// [RouteGeometry] says, and a stop number marked [CheckoutTrackedOrder.expected] is said to be one.
library;

import '../util/polyline.dart';
import 'order_models.dart';
import 'tracking_models.dart';

/// How the server says every path in a view is drawn, mirroring `PathGeometry`.
///
/// Decided server-side, so a routing engine switched on later turns every line into a road with
/// no app release.
enum RouteGeometry {
  /// Real roads, returned by the routing provider: draw the decoded line solid.
  road('ROAD'),

  /// Straight segments between the stops, with no knowledge of roads: draw them dashed and say
  /// they are approximate. Never a curve — a curve looks like a road.
  straight('STRAIGHT');

  const RouteGeometry(this.wire);

  final String wire;

  /// A value this build does not know reads as [straight], which the screen labels approximate —
  /// the claim it can always make honestly.
  static RouteGeometry fromWire(String? value) => RouteGeometry.values.firstWhere(
        (RouteGeometry g) => g.wire == value,
        orElse: () => RouteGeometry.straight,
      );
}

/// What a path shows, mirroring `CheckoutView.PathKind`.
enum CheckoutPathKind {
  /// Shop → door for an order nobody is on the way for yet. Drawn lighter than a live leg.
  planned('PLANNED'),

  /// From a rider's fresh fix through the stops still ahead to the door.
  riderLeg('RIDER_LEG'),

  /// A kind this build does not know. Not drawn: a line whose meaning the app cannot say is a
  /// line the customer would misread.
  unknown('UNKNOWN');

  const CheckoutPathKind(this.wire);

  final String wire;

  static CheckoutPathKind fromWire(String? value) => CheckoutPathKind.values.firstWhere(
        (CheckoutPathKind k) => k.wire == value,
        orElse: () => CheckoutPathKind.unknown,
      );
}

/// A WGS-84 point on the wire.
class GeoPin {
  const GeoPin(this.lat, this.lng);

  final double lat;
  final double lng;

  /// Null for anything that is not a pair of in-range numbers: half a coordinate is not a place,
  /// and a missing longitude read as zero would put the pin in the Gulf of Guinea.
  static GeoPin? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final Object? lat = json['lat'];
    final Object? lng = json['lng'];
    if (lat is! num || lng is! num) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return GeoPin(lat.toDouble(), lng.toDouble());
  }

  @override
  bool operator ==(Object other) => other is GeoPin && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'GeoPin($lat, $lng)';
}

/// One order of the checkout, mirroring `CheckoutView.OrderView`.
class CheckoutTrackedOrder {
  const CheckoutTrackedOrder({
    required this.orderId,
    required this.statusWire,
    this.storeName,
    this.shop,
    this.riderAssigned = false,
    this.stop,
    this.expected = false,
    this.pickedUpAt,
    this.completedAt,
    this.eta,
  });

  final String orderId;

  /// The shop's name as the order recorded it. Null for an order the projection has not heard
  /// the name of yet; the screen then says "a shop" rather than inventing one.
  final String? storeName;

  /// The server's status, kept verbatim so a status this build does not know still renders.
  final String statusWire;

  /// The shop's pin, or null when it has none — the row then says the shop is not on the map.
  final GeoPin? shop;

  /// Whether a rider has claimed it. Nothing else about the rider is on the wire.
  final bool riderAssigned;

  /// Its place in its rider's run, or null when it is not in one. Numbers exist only when one
  /// rider carries two or more of the checkout's orders.
  final int? stop;

  /// True when [stop] is the platform's expectation (nearest shop next) rather than a fact.
  final bool expected;

  final DateTime? pickedUpAt;
  final DateTime? completedAt;

  /// What `/orders/{id}/eta` answers for this order; in a run, the run's door estimate. Null only
  /// if the server sent none.
  final OrderEta? eta;

  /// The status as this build knows it, or null for one it does not.
  OrderStatus? get status {
    for (final OrderStatus s in OrderStatus.values) {
      if (s.wire == statusWire) return s;
    }
    return null;
  }

  bool get isDelivered => statusWire == OrderStatus.delivered.wire;
  bool get isCancelled => statusWire == OrderStatus.cancelled.wire;

  /// Delivered or cancelled: tracking has closed and the map shows only the outcome.
  bool get isFinished => isDelivered || isCancelled;

  factory CheckoutTrackedOrder.fromJson(Map<String, dynamic> json) {
    final Object? eta = json['eta'];
    return CheckoutTrackedOrder(
      orderId: json['orderId'] as String,
      storeName: json['storeName'] as String?,
      statusWire: json['status'] as String? ?? 'UNKNOWN',
      shop: GeoPin.fromJson(json['shop']),
      riderAssigned: json['riderAssigned'] as bool? ?? false,
      stop: (json['stop'] as num?)?.toInt(),
      // A number the server did not send cannot be an expected one.
      expected: json['stop'] != null && (json['expected'] as bool? ?? false),
      pickedUpAt: _date(json['pickedUpAt']),
      completedAt: _date(json['completedAt']),
      eta: eta is Map<String, dynamic> ? OrderEta.fromJson(eta) : null,
    );
  }
}

/// Where a rider's phone last reported them, mirroring `CheckoutView.RiderFix`.
class CheckoutRiderFix {
  const CheckoutRiderFix({
    required this.pin,
    this.recordedAt,
    this.stale = false,
  });

  final GeoPin pin;
  final DateTime? recordedAt;

  /// Older than the platform will measure an estimate from: the marker says "last seen".
  final bool stale;

  static CheckoutRiderFix? fromJson(Object? json) {
    final GeoPin? pin = GeoPin.fromJson(json);
    if (pin == null) return null;
    final Map<String, dynamic> map = json! as Map<String, dynamic>;
    return CheckoutRiderFix(
      pin: pin,
      recordedAt: _date(map['recordedAt']),
      stale: map['stale'] as bool? ?? false,
    );
  }
}

/// One rider with a live order of the checkout, mirroring `CheckoutView.RiderView` — nothing
/// about the person beyond where their phone last was.
class CheckoutRider {
  const CheckoutRider({
    required this.orderIds,
    this.run = false,
    this.position,
    this.hasOtherDeliveries = false,
  });

  /// Their live orders of this checkout, in the order they are taken to be visited.
  final List<String> orderIds;

  /// True when they carry two or more of the checkout's orders.
  final bool run;

  /// Null before their first fix.
  final CheckoutRiderFix? position;

  /// Whether they are also carrying orders that are not this checkout's. A yes/no and nothing
  /// more; the screen says times may be longer.
  final bool hasOtherDeliveries;

  factory CheckoutRider.fromJson(Map<String, dynamic> json) => CheckoutRider(
        orderIds: _strings(json['orderIds']),
        run: json['run'] as bool? ?? false,
        position: CheckoutRiderFix.fromJson(json['position']),
        hasOtherDeliveries: json['hasOtherDeliveries'] as bool? ?? false,
      );
}

/// One expected route, mirroring `CheckoutView.PathView`.
class CheckoutRoutePath {
  const CheckoutRoutePath({
    required this.orderIds,
    required this.kind,
    required this.points,
    this.polyline6,
    this.metres,
    this.provider,
  });

  final List<String> orderIds;
  final CheckoutPathKind kind;

  /// The stops it passes, in order — the first being the rider's fix on a rider leg. What a
  /// straight path is drawn through.
  final List<GeoPin> points;

  /// Road geometry at 1e6 precision, or null for a straight path.
  final String? polyline6;

  final double? metres;
  final String? provider;

  /// The line to draw: the decoded road when the server sent one, else the stops themselves.
  ///
  /// A road that fails to decode is drawn as nothing — never replaced by straight segments, which
  /// would put a line on the map that no provider returned under a "roads" label.
  List<GeoPin> get line {
    final String? encoded = polyline6;
    if (encoded == null) return points;
    return decodePolyline6(encoded) ?? const <GeoPin>[];
  }

  factory CheckoutRoutePath.fromJson(Map<String, dynamic> json) => CheckoutRoutePath(
        orderIds: _strings(json['orderIds']),
        kind: CheckoutPathKind.fromWire(json['kind'] as String?),
        points: <GeoPin>[
          for (final Object? p in json['points'] as List<dynamic>? ?? const <dynamic>[])
            if (GeoPin.fromJson(p) case final GeoPin pin) pin,
        ],
        polyline6: json['polyline6'] as String?,
        metres: (json['metres'] as num?)?.toDouble(),
        provider: json['provider'] as String?,
      );
}

/// The whole map of one checkout, mirroring `CheckoutView`.
class CheckoutTracking {
  const CheckoutTracking({
    required this.checkoutId,
    required this.provider,
    required this.geometry,
    required this.orders,
    this.door,
    this.riders = const <CheckoutRider>[],
    this.paths = const <CheckoutRoutePath>[],
    this.computedAt,
  });

  final String checkoutId;

  /// Who computed every path and estimate — `HAVERSINE_DEV` is straight lines at an assumed speed.
  final String provider;

  final RouteGeometry geometry;

  /// The customer's pin, or null when the orders carry none.
  final GeoPin? door;

  final List<CheckoutTrackedOrder> orders;
  final List<CheckoutRider> riders;
  final List<CheckoutRoutePath> paths;
  final DateTime? computedAt;

  /// Whether the lines on the map are straight approximations and must be labelled so.
  bool get isStraightLine => geometry != RouteGeometry.road;

  /// Every order delivered or cancelled: the map is a static summary of pins and outcomes.
  bool get allFinished =>
      orders.isNotEmpty && orders.every((CheckoutTrackedOrder o) => o.isFinished);

  /// The rider carrying [orderId], when one with a live order is.
  CheckoutRider? riderFor(String orderId) {
    for (final CheckoutRider rider in riders) {
      if (rider.orderIds.contains(orderId)) return rider;
    }
    return null;
  }

  factory CheckoutTracking.fromJson(Map<String, dynamic> json) => CheckoutTracking(
        checkoutId: json['checkoutId'] as String,
        provider: json['provider'] as String? ?? 'UNKNOWN',
        geometry: RouteGeometry.fromWire(json['geometry'] as String?),
        door: GeoPin.fromJson(json['door']),
        orders: <CheckoutTrackedOrder>[
          for (final Object? o in json['orders'] as List<dynamic>? ?? const <dynamic>[])
            if (o is Map<String, dynamic>) CheckoutTrackedOrder.fromJson(o),
        ],
        riders: <CheckoutRider>[
          for (final Object? r in json['riders'] as List<dynamic>? ?? const <dynamic>[])
            if (r is Map<String, dynamic>) CheckoutRider.fromJson(r),
        ],
        paths: <CheckoutRoutePath>[
          for (final Object? p in json['paths'] as List<dynamic>? ?? const <dynamic>[])
            if (p is Map<String, dynamic>) CheckoutRoutePath.fromJson(p),
        ],
        computedAt: _date(json['computedAt']),
      );
}

List<String> _strings(Object? value) => <String>[
      for (final Object? v in value as List<dynamic>? ?? const <dynamic>[])
        if (v is String) v,
    ];

/// ISO-8601 text as the running service writes it; anything else reads as unknown.
DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;
