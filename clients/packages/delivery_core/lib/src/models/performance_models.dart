/// Rider performance counters mirroring the Order Manager rider-performance endpoints.
library;

/// One rider's last thirty days, mirroring `RiderPerformanceView`.
///
/// The window is fixed server-side; [windowDays] is echoed so the screen labels the period the
/// server actually counted rather than one it assumed.
class RiderPerformance {
  const RiderPerformance({
    required this.riderId,
    required this.windowDays,
    required this.claimed,
    required this.delivered,
    required this.cancelledAfterClaim,
    this.completionRate,
  });

  final String riderId;
  final int windowDays;

  /// Orders this rider took on in the window.
  final int claimed;

  /// Of those, the ones that reached a door.
  final int delivered;

  /// Claimed and then cancelled — the work that fell through after being taken on.
  final int cancelledAfterClaim;

  /// Delivered as a percent of claimed, computed server-side at 2dp.
  ///
  /// Null exactly when [claimed] is zero: a rider with no work has no rate. Render null as "—",
  /// never as 0% (which reads as failure) or 100% (which reads as an invented success).
  final double? completionRate;

  factory RiderPerformance.fromJson(Map<String, dynamic> json) => RiderPerformance(
        riderId: json['riderId'] as String,
        windowDays: (json['windowDays'] as num?)?.toInt() ?? 30,
        claimed: (json['claimed'] as num?)?.toInt() ?? 0,
        delivered: (json['delivered'] as num?)?.toInt() ?? 0,
        cancelledAfterClaim: (json['cancelledAfterClaim'] as num?)?.toInt() ?? 0,
        completionRate: (json['completionRate'] as num?)?.toDouble(),
      );
}

/// One rider's deliveries today, mirroring `RiderDeliveredTodayView`.
///
/// The list this arrives in carries only riders who delivered something: a rider with zero
/// deliveries is ABSENT, and the screen joins onto its own roster and draws the zeros itself.
class RiderDeliveredToday {
  const RiderDeliveredToday({
    required this.riderId,
    required this.delivered,
    required this.day,
  });

  final String riderId;
  final int delivered;

  /// The platform-zone date the count belongs to — a plain date the server already resolved, kept
  /// as the label it chose rather than shifted by the viewer's offset.
  final DateTime day;

  factory RiderDeliveredToday.fromJson(Map<String, dynamic> json) => RiderDeliveredToday(
        riderId: json['riderId'] as String,
        delivered: (json['delivered'] as num?)?.toInt() ?? 0,
        day: DateTime.parse(json['day'] as String),
      );
}
