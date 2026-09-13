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

/// One rider's deliveries day by day, mirroring `RiderPerformanceService.DailyOutput` — the bars
/// of the carrier rider profile's output chart.
///
/// Scoped server-side exactly like [RiderPerformance]: a carrier sees only the deliveries the rider
/// made for that carrier. Both count a delivery by when it was delivered, from the same local
/// midnight at the start of the window, so the thirty days of bars add up to the thirty-day
/// delivered tile above them. (The tile's "claimed" caption is still anchored on when orders were
/// placed — a claim records no time of its own.) [days] carries only dates with a delivery on them;
/// [zeroFilled] draws the quiet days between [from] and [to], the same convention as the duty-hours
/// series.
class RiderDailyOutput {
  const RiderDailyOutput({
    required this.riderId,
    required this.zone,
    required this.from,
    required this.to,
    required this.days,
  });

  final String riderId;

  /// The zone the server split days in, echoed so the screen can say so rather than let a reader
  /// in another zone assume their own midnight.
  final String zone;

  /// The first and last day of the window, both inclusive, as plain dates in [zone].
  final DateTime from;
  final DateTime to;

  /// Only the days with something delivered, oldest first.
  final List<RiderDeliveredDay> days;

  /// Every day from [from] to [to], a quiet day as zero. The server never sends zero rows, so a
  /// missing date means nothing was delivered — not that the date is unknown.
  List<RiderDeliveredDay> get zeroFilled {
    final Map<DateTime, int> byDay = <DateTime, int>{
      for (final RiderDeliveredDay d in days) _dateOnly(d.date): d.delivered,
    };
    return <RiderDeliveredDay>[
      for (DateTime day = _dateOnly(from);
          !day.isAfter(_dateOnly(to));
          day = DateTime(day.year, day.month, day.day + 1))
        RiderDeliveredDay(date: day, delivered: byDay[day] ?? 0),
    ];
  }

  /// Everything delivered across the window.
  int get total => days.fold<int>(0, (int sum, RiderDeliveredDay d) => sum + d.delivered);

  factory RiderDailyOutput.fromJson(Map<String, dynamic> json) => RiderDailyOutput(
        riderId: json['riderId'] as String? ?? '',
        zone: json['zone'] as String? ?? 'UTC',
        from: _plainDate(json['from'] as String),
        to: _plainDate(json['to'] as String),
        days: (json['days'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic d) => RiderDeliveredDay.fromJson(d as Map<String, dynamic>))
            .toList(),
      );

  /// A `YYYY-MM-DD` the server already resolved in its zone, kept as that calendar date rather
  /// than shifted by the viewer's offset.
  static DateTime _plainDate(String value) => _dateOnly(DateTime.parse(value));

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

/// One bar: a calendar day and what the rider delivered on it.
class RiderDeliveredDay {
  const RiderDeliveredDay({required this.date, required this.delivered});

  final DateTime date;
  final int delivered;

  factory RiderDeliveredDay.fromJson(Map<String, dynamic> json) => RiderDeliveredDay(
        date: RiderDailyOutput._plainDate(json['date'] as String),
        delivered: (json['delivered'] as num?)?.toInt() ?? 0,
      );
}
