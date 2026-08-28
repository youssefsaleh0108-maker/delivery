/// Tracking models mirroring the Order Tracking ETA and presence APIs.
library;

/// Which stretch of the journey an estimate covers, mirroring `EtaService.Leg`.
enum EtaLeg {
  /// The rider has not collected yet: the estimate spans rider → pickup → customer.
  toPickup('TO_PICKUP', 'Heading to the shop'),

  /// The rider has the goods: the estimate is the run to the customer.
  toDropoff('TO_DROPOFF', 'On the way to you');

  const EtaLeg(this.wire, this.label);

  final String wire;
  final String label;

  static EtaLeg? fromWire(String? value) {
    for (final EtaLeg leg in EtaLeg.values) {
      if (leg.wire == value) return leg;
    }
    return null;
  }
}

/// Why there is no number, mirroring `EtaService.Reason`.
///
/// Present exactly when [OrderEta.available] is false. Each reason is a different sentence on
/// screen — "waiting for the rider's first GPS fix" and "this order is already delivered" must not
/// collapse into one spinner.
enum EtaUnavailableReason {
  /// The rider has never pinged on this order.
  noFix('NO_FIX', 'Waiting for the rider\'s first GPS fix'),

  /// The last ping is older than the acceptable fix age. The rider could be anywhere.
  staleFix('STALE_FIX', 'The rider\'s position is out of date'),

  /// The order carries no coordinates to measure against.
  noDestination('NO_DESTINATION', 'No map point to measure to'),

  /// The routing provider could not answer. Transient for a real provider.
  providerUnavailable('PROVIDER_UNAVAILABLE', 'The route service did not answer'),

  /// Delivered or cancelled. Nothing is on its way.
  orderComplete('ORDER_COMPLETE', 'Nothing is on its way'),

  /// A reason this client does not know yet. Shown as unavailable, never as a number.
  unknown('UNKNOWN', 'No estimate available');

  const EtaUnavailableReason(this.wire, this.label);

  final String wire;
  final String label;

  static EtaUnavailableReason fromWire(String? value) =>
      EtaUnavailableReason.values.firstWhere(
        (EtaUnavailableReason r) => r.wire == value,
        orElse: () => EtaUnavailableReason.unknown,
      );
}

/// How far the rider still has to go and when they are expected, mirroring `EtaService.EtaResult`.
///
/// Always a body, never a 204: the interesting cases are the ones with no number in them. When
/// [available] is false every numeric field is null and [reason] says why — a screen renders the
/// reason's sentence, never a fabricated number.
class OrderEta {
  const OrderEta({
    required this.orderId,
    required this.available,
    required this.provider,
    this.reason,
    this.leg,
    this.remainingMetres,
    this.remainingSeconds,
    this.estimatedArrival,
    this.fixRecordedAt,
    this.computedAt,
  });

  final String orderId;

  /// False whenever anything is missing; the numeric fields are then null.
  final bool available;

  /// Why not — null exactly when [available] is true.
  final EtaUnavailableReason? reason;

  /// Which stretch the estimate covers. Null when unavailable.
  final EtaLeg? leg;

  /// Metres still to cover. Null when unavailable.
  final double? remainingMetres;

  /// Seconds still to travel. Null when unavailable.
  final int? remainingSeconds;

  /// When the rider is expected. Null when unavailable.
  final DateTime? estimatedArrival;

  /// Who computed it — or who would have. Always present, so a caller can tell a routed answer
  /// from a straight-line one. `HAVERSINE_DEV` is the dev straight-line estimator, and a client
  /// should show that number with rather less confidence than a routed one.
  final String provider;

  /// When the position the estimate was measured from was taken. Null when the rider has never
  /// pinged on this order.
  final DateTime? fixRecordedAt;

  final DateTime? computedAt;

  /// Whether the number on screen deserves a "roughly": true for the dev straight-line estimator,
  /// which knows nothing about roads.
  bool get isStraightLine => provider == 'HAVERSINE_DEV';

  factory OrderEta.fromJson(Map<String, dynamic> json) {
    final bool available = json['available'] as bool? ?? false;
    return OrderEta(
      orderId: json['orderId'] as String,
      available: available,
      reason: available ? null : EtaUnavailableReason.fromWire(json['reason'] as String?),
      leg: EtaLeg.fromWire(json['leg'] as String?),
      remainingMetres: (json['remainingMetres'] as num?)?.toDouble(),
      remainingSeconds: (json['remainingSeconds'] as num?)?.toInt(),
      estimatedArrival: _date(json['estimatedArrival']),
      provider: json['provider'] as String? ?? 'UNKNOWN',
      fixRecordedAt: _date(json['fixRecordedAt']),
      computedAt: _date(json['computedAt']),
    );
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

/// What a rider has declared, mirroring `com.delivery.tracking.domain.DutyState`.
enum DutyState {
  /// The rider says they are available for work.
  onDuty('ON_DUTY', 'On duty'),

  /// The rider says they are not. Also the state every rider starts in.
  offDuty('OFF_DUTY', 'Off duty');

  const DutyState(this.wire, this.label);

  final String wire;
  final String label;

  static DutyState fromWire(String? value) => DutyState.values.firstWhere(
        (DutyState s) => s.wire == value,
        orElse: () => DutyState.offDuty,
      );
}

/// What the platform believes, mirroring `com.delivery.tracking.domain.PresenceState`.
///
/// Distinct from [DutyState] on purpose: a rider who declared duty and then went quiet is [stale],
/// and the app must say so instead of showing them as available for work they will not receive.
enum PresenceState {
  /// Declared on duty and pinged recently enough to be believed.
  onDuty('ON_DUTY', 'On duty'),

  /// Declared on duty, but the last fix is too old. Not dispatchable.
  stale('STALE', 'Signal lost'),

  /// Declared off duty.
  offDuty('OFF_DUTY', 'Off duty');

  const PresenceState(this.wire, this.label);

  final String wire;
  final String label;

  static PresenceState fromWire(String? value) => PresenceState.values.firstWhere(
        (PresenceState s) => s.wire == value,
        orElse: () => PresenceState.offDuty,
      );
}

/// One rider's duty, presence and last known fix, mirroring `PresenceService.RiderPresenceView`.
///
/// Returned by the duty endpoints, the single-rider lookup and the roster alike.
class RiderPresence {
  const RiderPresence({
    required this.riderId,
    required this.dutyState,
    required this.state,
    this.carrierId,
    this.dutyChangedAt,
    this.lastSeenAt,
    this.lat,
    this.lng,
    this.accuracyM,
  });

  final String riderId;

  /// The fleet employing them, or null for the platform's own riders.
  final String? carrierId;

  /// What the rider declared.
  final DutyState dutyState;

  /// What the platform believes — [PresenceState.stale] when the declaration and the pings
  /// disagree. This is the state to render, never [dutyState] alone.
  final PresenceState state;

  final DateTime? dutyChangedAt;

  /// When the last fix arrived. Null for a rider who has never pinged.
  final DateTime? lastSeenAt;

  /// Last known position. Null until the first fix — a roster row without one is drawn as a rider
  /// with no pin, not at (0, 0).
  final double? lat;
  final double? lng;
  final double? accuracyM;

  /// Whether there is a fix to draw on a map at all.
  bool get hasFix => lat != null && lng != null;

  factory RiderPresence.fromJson(Map<String, dynamic> json) => RiderPresence(
        riderId: json['riderId'] as String,
        carrierId: json['carrierId'] as String?,
        dutyState: DutyState.fromWire(json['dutyState'] as String?),
        state: PresenceState.fromWire(json['state'] as String?),
        dutyChangedAt: _date(json['dutyChangedAt']),
        lastSeenAt: _date(json['lastSeenAt']),
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        accuracyM: (json['accuracyM'] as num?)?.toDouble(),
      );

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

/// One date's on-duty time, mirroring the duty-hours `DayOnline` rows.
class DutyDay {
  const DutyDay({
    required this.date,
    required this.secondsOnline,
    required this.hoursOnline,
    required this.sessions,
  });

  /// A plain date in the report's zone ([HoursOnline.zone]) — the server already decided which day
  /// each shift belongs to; keep its label rather than shifting it by the viewer's offset.
  final DateTime date;

  /// The exact figure. Use THIS for any arithmetic — totals, averages, comparisons.
  final int secondsOnline;

  /// [secondsOnline] / 3600 at 2dp, computed server-side. Use for display only; adding rounded
  /// numbers up is how a week comes to 39.99 hours.
  final double hoursOnline;

  /// Distinct shifts touching this date. A shift across midnight counts on both dates.
  final int sessions;

  factory DutyDay.fromJson(Map<String, dynamic> json) => DutyDay(
        date: DateTime.parse(json['date'] as String),
        secondsOnline: (json['secondsOnline'] as num?)?.toInt() ?? 0,
        hoursOnline: (json['hoursOnline'] as num?)?.toDouble() ?? 0,
        sessions: (json['sessions'] as num?)?.toInt() ?? 0,
      );
}

/// A rider's hours-online report, mirroring the duty-hours `HoursOnline` response.
///
/// [days] carries ONLY dates with on-duty time, ascending, and is empty when there were none — the
/// client draws its own zeros across the [from]..[to] window. The opposite convention from the
/// daily trade series, which is zero-filled; read each contract's note.
///
/// The figures are live at the near edge: an open shift counts up to now while the rider is
/// pinging, and only to their last sighting once quiet — so a number can grow on refresh but never
/// shrink.
class HoursOnline {
  const HoursOnline({
    required this.riderId,
    required this.zone,
    required this.from,
    required this.to,
    required this.days,
  });

  final String riderId;

  /// The zone the days were split in, echoed so the client never guesses which midnight a
  /// 23:00–01:00 shift straddled.
  final String zone;

  /// The requested window, inclusive; [to] is today in [zone].
  final DateTime from;
  final DateTime to;

  final List<DutyDay> days;

  /// The window's total, from the exact figures.
  int get totalSecondsOnline =>
      days.fold(0, (int sum, DutyDay d) => sum + d.secondsOnline);

  factory HoursOnline.fromJson(Map<String, dynamic> json) => HoursOnline(
        riderId: json['riderId'] as String,
        zone: json['zone'] as String? ?? 'UTC',
        from: DateTime.parse(json['from'] as String),
        to: DateTime.parse(json['to'] as String),
        days: (json['days'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic d) => DutyDay.fromJson(d as Map<String, dynamic>))
            .toList(),
      );
}
