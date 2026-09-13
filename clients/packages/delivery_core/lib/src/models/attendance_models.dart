/// Attendance and shift models mirroring order-tracking's `AttendanceService` — the carrier's
/// Riders HR: shift schedules, the monthly attendance of one rider, and the pay-run totals.
///
/// Every date and wall-clock time here is in the server's day zone ([RiderAttendance.zone],
/// Asia/Beirut), which the server decided; keep its labels rather than shifting them by the
/// viewer's offset. The `...Local` strings exist for exactly that reason: a browser in another zone
/// would print an instant on its own clock.
library;

/// What a day came to, mirroring `AttendanceService.Status`.
enum AttendanceStatus {
  /// Scheduled, and on time.
  present('PRESENT'),

  /// Scheduled, and arrived after the shift's start plus its grace.
  late('LATE'),

  /// Scheduled, the shift is over, and nothing shows the rider was there.
  absent('ABSENT'),

  /// Scheduled today and not in yet — the shift is not over, so this is not an absence.
  pending('PENDING'),

  /// An assigned rider's day off.
  dayOff('DAY_OFF'),

  /// Worked on a day off. All of it is overtime.
  extra('EXTRA'),

  /// No schedule (a freelancer) and worked. Never judged late or absent.
  worked('WORKED'),

  /// No schedule and did not work. Never an absence.
  noDuty('NO_DUTY'),

  /// After today.
  upcoming('UPCOMING'),

  /// Late, and the office excused it.
  lateExcused('LATE_EXCUSED'),

  /// Did not work, excused by the office.
  excused('EXCUSED'),
  sick('SICK'),
  leave('LEAVE'),

  /// A status this client does not know yet. Drawn neutrally, never as a verdict.
  unknown('UNKNOWN');

  const AttendanceStatus(this.wire);

  final String wire;

  static AttendanceStatus fromWire(String? value) => AttendanceStatus.values.firstWhere(
        (AttendanceStatus s) => s.wire == value,
        orElse: () => AttendanceStatus.unknown,
      );
}

/// What the office records by hand, mirroring `AttendanceEntry.Kind`.
enum AttendanceEntryKind {
  /// Worked, though the app does not show it. The only kind that may carry clock times.
  present('PRESENT'),
  lateExcused('LATE_EXCUSED'),
  absentExcused('ABSENT_EXCUSED'),
  sick('SICK'),
  leave('LEAVE');

  const AttendanceEntryKind(this.wire);

  final String wire;

  static AttendanceEntryKind? fromWire(String? value) {
    for (final AttendanceEntryKind k in AttendanceEntryKind.values) {
      if (k.wire == value) return k;
    }
    return null;
  }
}

/// Who ended a duty session, mirroring `DutySession.EndReason`.
enum DutyEndReason {
  rider('RIDER'),
  backoffice('BACKOFFICE'),

  /// The platform closed it at the rider's last sighting after they went silent — not a tap.
  expired('EXPIRED');

  const DutyEndReason(this.wire);

  final String wire;

  static DutyEndReason? fromWire(String? value) {
    for (final DutyEndReason r in DutyEndReason.values) {
      if (r.wire == value) return r;
    }
    return null;
  }
}

DateTime? _instant(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

/// A server wall-clock stamp (`yyyy-MM-ddTHH:mm`, no zone) kept as a naive DateTime: its fields
/// ARE the server zone's clock, and nothing may convert them.
DateTime? _wallClock(Object? value) => value is String ? DateTime.tryParse(value) : null;

DateTime _date(Object? value) => DateTime.parse(value as String);

int _int(Object? value) => (value as num?)?.toInt() ?? 0;

/// One duty session as the attendance log shows it, mirroring `DutySessionService.SessionView`.
class DutySessionView {
  const DutySessionView({
    required this.id,
    required this.startedAt,
    required this.open,
    required this.countedSeconds,
    this.endedAt,
    this.endReason,
    this.startedAtLocal,
    this.countedUntilLocal,
  });

  final String id;
  final DateTime startedAt;

  /// Null while the session is still open.
  final DateTime? endedAt;
  final DutyEndReason? endReason;
  final bool open;

  /// The whole session's credited time — what arithmetic uses.
  final int countedSeconds;

  /// Start and credited end on the server zone's clock.
  final DateTime? startedAtLocal;
  final DateTime? countedUntilLocal;

  factory DutySessionView.fromJson(Map<String, dynamic> json) => DutySessionView(
        id: json['id'] as String,
        startedAt: _instant(json['startedAt'])!,
        endedAt: _instant(json['endedAt']),
        endReason: DutyEndReason.fromWire(json['endReason'] as String?),
        open: json['open'] as bool? ?? false,
        countedSeconds: _int(json['countedSeconds']),
        startedAtLocal: _wallClock(json['startedAtLocal']),
        countedUntilLocal: _wallClock(json['countedUntilLocal']),
      );
}

/// The shift a day was judged against.
class ScheduledShift {
  const ScheduledShift({
    required this.shiftId,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.overnight,
    required this.scheduledSeconds,
    required this.lateGraceMinutes,
  });

  final String shiftId;
  final String name;

  /// `HH:mm` on the server zone's clock.
  final String startTime;
  final String endTime;
  final bool overnight;

  /// The window's real length that day — an hour more or less on the nights the clocks change.
  final int scheduledSeconds;
  final int lateGraceMinutes;

  factory ScheduledShift.fromJson(Map<String, dynamic> json) => ScheduledShift(
        shiftId: json['shiftId'] as String,
        name: json['name'] as String? ?? '',
        startTime: json['startTime'] as String? ?? '',
        endTime: json['endTime'] as String? ?? '',
        overnight: json['overnight'] as bool? ?? false,
        scheduledSeconds: _int(json['scheduledSeconds']),
        lateGraceMinutes: _int(json['lateGraceMinutes']),
      );
}

/// The office's live entry for a day.
class ManualAttendanceEntry {
  const ManualAttendanceEntry({
    required this.id,
    required this.date,
    required this.status,
    required this.manualSeconds,
    this.clockIn,
    this.clockOut,
    this.note,
  });

  final String id;
  final DateTime date;
  final AttendanceEntryKind status;

  /// `HH:mm`, or null when no times were typed.
  final String? clockIn;
  final String? clockOut;

  /// The typed hours. Reported as manual — never as app evidence.
  final int manualSeconds;
  final String? note;

  factory ManualAttendanceEntry.fromJson(Map<String, dynamic> json) => ManualAttendanceEntry(
        id: json['id'] as String,
        date: _date(json['date']),
        status: AttendanceEntryKind.fromWire(json['status'] as String?) ??
            AttendanceEntryKind.present,
        clockIn: json['clockIn'] as String?,
        clockOut: json['clockOut'] as String?,
        manualSeconds: _int(json['manualSeconds']),
        note: json['note'] as String?,
      );
}

/// One judged day, mirroring `AttendanceService.AttendanceDay`.
class AttendanceDay {
  const AttendanceDay({
    required this.date,
    required this.status,
    required this.derivedStatus,
    required this.onShiftNow,
    required this.worked,
    required this.workedSeconds,
    required this.manualSeconds,
    required this.overtimeSeconds,
    required this.sessions,
    this.scheduled,
    this.clockInLocal,
    this.clockOutLocal,
    this.clockOutReason,
    this.lateBySeconds,
    this.entry,
  });

  final DateTime date;

  /// The verdict, after any manual entry.
  final AttendanceStatus status;

  /// What the app and the schedule alone said — what an entry corrected.
  final AttendanceStatus derivedStatus;

  /// Null on a day off or with no schedule.
  final ScheduledShift? scheduled;

  /// First clock-in and last clock-out on the server zone's clock. The clock-out is null while the
  /// last session is open, and its date is the next day after a night shift.
  final DateTime? clockInLocal;
  final DateTime? clockOutLocal;
  final DutyEndReason? clockOutReason;

  /// A session belonging to this day is still open.
  final bool onShiftNow;

  /// Counts as a day worked: app evidence, or a manual "present".
  final bool worked;

  /// App evidence, exact. Sum THIS, never rounded hours.
  final int workedSeconds;

  /// Hours the office typed, only on a day with no app evidence.
  final int manualSeconds;

  /// Seconds between the shift start and arrival (0 when early). Null when nothing was scheduled
  /// or nobody arrived.
  final int? lateBySeconds;
  final int overtimeSeconds;
  final List<DutySessionView> sessions;
  final ManualAttendanceEntry? entry;

  factory AttendanceDay.fromJson(Map<String, dynamic> json) => AttendanceDay(
        date: _date(json['date']),
        status: AttendanceStatus.fromWire(json['status'] as String?),
        derivedStatus: AttendanceStatus.fromWire(json['derivedStatus'] as String?),
        scheduled: json['scheduled'] is Map<String, dynamic>
            ? ScheduledShift.fromJson(json['scheduled'] as Map<String, dynamic>)
            : null,
        clockInLocal: _wallClock(json['clockInLocal']),
        clockOutLocal: _wallClock(json['clockOutLocal']),
        clockOutReason: DutyEndReason.fromWire(json['clockOutReason'] as String?),
        onShiftNow: json['onShiftNow'] as bool? ?? false,
        worked: json['worked'] as bool? ?? false,
        workedSeconds: _int(json['workedSeconds']),
        manualSeconds: _int(json['manualSeconds']),
        lateBySeconds: (json['lateBySeconds'] as num?)?.toInt(),
        overtimeSeconds: _int(json['overtimeSeconds']),
        sessions: (json['sessions'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic s) => DutySessionView.fromJson(s as Map<String, dynamic>))
            .toList(),
        entry: json['entry'] is Map<String, dynamic>
            ? ManualAttendanceEntry.fromJson(json['entry'] as Map<String, dynamic>)
            : null,
      );
}

/// A period's totals — the figures a pay run consumes. Seconds are exact; evidence and manual
/// hours are never summed together here.
class AttendanceTotals {
  const AttendanceTotals({
    required this.scheduledDays,
    required this.daysWorked,
    required this.absences,
    required this.lates,
    required this.excusedLates,
    required this.excusedAbsences,
    required this.sickDays,
    required this.leaveDays,
    required this.workedSeconds,
    required this.manualSeconds,
    required this.scheduledSeconds,
    required this.overtimeSeconds,
  });

  final int scheduledDays;
  final int daysWorked;

  /// Unexcused only.
  final int absences;
  final int lates;
  final int excusedLates;
  final int excusedAbsences;
  final int sickDays;
  final int leaveDays;
  final int workedSeconds;
  final int manualSeconds;
  final int scheduledSeconds;
  final int overtimeSeconds;

  factory AttendanceTotals.fromJson(Map<String, dynamic> json) => AttendanceTotals(
        scheduledDays: _int(json['scheduledDays']),
        daysWorked: _int(json['daysWorked']),
        absences: _int(json['absences']),
        lates: _int(json['lates']),
        excusedLates: _int(json['excusedLates']),
        excusedAbsences: _int(json['excusedAbsences']),
        sickDays: _int(json['sickDays']),
        leaveDays: _int(json['leaveDays']),
        workedSeconds: _int(json['workedSeconds']),
        manualSeconds: _int(json['manualSeconds']),
        scheduledSeconds: _int(json['scheduledSeconds']),
        overtimeSeconds: _int(json['overtimeSeconds']),
      );
}

/// One rider over one period, mirroring `AttendanceService.RiderAttendance`.
class RiderAttendance {
  const RiderAttendance({
    required this.riderId,
    required this.zone,
    required this.from,
    required this.to,
    required this.today,
    required this.hasSchedule,
    required this.days,
    required this.totals,
    this.asOf,
  });

  final String riderId;

  /// The zone every date and `...Local` time is in.
  final String zone;
  final DateTime from;
  final DateTime to;

  /// Today in [zone]; days after it are [AttendanceStatus.upcoming].
  final DateTime today;

  /// When the server computed these figures. They are never final — a night shift past the
  /// period's end, an open session or a manual entry can still move them — so anything that pays
  /// from them keeps this beside what it paid. Null from a server that predates it.
  final DateTime? asOf;

  /// False: a freelancer for the whole period. Show time on duty only — no late or absent legend.
  final bool hasSchedule;

  /// Every date of the period, in order.
  final List<AttendanceDay> days;
  final AttendanceTotals totals;

  factory RiderAttendance.fromJson(Map<String, dynamic> json) => RiderAttendance(
        riderId: json['riderId'] as String,
        zone: json['zone'] as String? ?? 'UTC',
        from: _date(json['from']),
        to: _date(json['to']),
        today: _date(json['today']),
        asOf: _instant(json['asOf']),
        hasSchedule: json['hasSchedule'] as bool? ?? false,
        days: (json['days'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic d) => AttendanceDay.fromJson(d as Map<String, dynamic>))
            .toList(),
        totals: AttendanceTotals.fromJson(
            json['totals'] as Map<String, dynamic>? ?? const <String, dynamic>{}),
      );
}

/// A shift a company runs, mirroring `AttendanceService.ShiftView`.
class ShiftTemplate {
  const ShiftTemplate({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.overnight,
    required this.weekdays,
    required this.lateGraceMinutes,
    required this.archived,
    required this.riders,
  });

  final String id;
  final String name;

  /// `HH:mm` in the server's day zone.
  final String startTime;
  final String endTime;
  final bool overnight;

  /// ISO weekdays, [DateTime.monday]..[DateTime.sunday].
  final List<int> weekdays;
  final int lateGraceMinutes;

  /// Retired: kept for the history that points at it, never offered for new assignments.
  final bool archived;

  /// Riders on it today or starting it later.
  final int riders;

  static const List<String> weekdayWire = <String>[
    'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY',
  ];

  factory ShiftTemplate.fromJson(Map<String, dynamic> json) => ShiftTemplate(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        startTime: json['startTime'] as String? ?? '',
        endTime: json['endTime'] as String? ?? '',
        overnight: json['overnight'] as bool? ?? false,
        weekdays: (json['days'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic d) => weekdayWire.indexOf(d as String) + 1)
            .where((int d) => d > 0)
            .toList()
          ..sort(),
        lateGraceMinutes: _int(json['lateGraceMinutes']),
        archived: json['archived'] as bool? ?? false,
        riders: _int(json['riders']),
      );
}

/// That a rider works a shift from one date to another, mirroring `AssignmentView`.
class ShiftAssignment {
  const ShiftAssignment({
    required this.riderId,
    required this.shiftId,
    required this.effectiveFrom,
    this.shiftName,
    this.effectiveTo,
  });

  final String riderId;
  final String shiftId;
  final String? shiftName;
  final DateTime effectiveFrom;

  /// Inclusive; null while open-ended.
  final DateTime? effectiveTo;

  bool covers(DateTime day) {
    final DateTime d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(effectiveFrom) && (effectiveTo == null || !d.isAfter(effectiveTo!));
  }

  factory ShiftAssignment.fromJson(Map<String, dynamic> json) => ShiftAssignment(
        riderId: json['riderId'] as String,
        shiftId: json['shiftId'] as String,
        shiftName: json['shiftName'] as String?,
        effectiveFrom: _date(json['effectiveFrom']),
        effectiveTo: json['effectiveTo'] == null ? null : _date(json['effectiveTo']),
      );
}

/// One rider's line in a fleet's pay-run read.
class RiderAttendanceTotals {
  const RiderAttendanceTotals({
    required this.riderId,
    required this.hasSchedule,
    required this.totals,
  });

  final String riderId;
  final bool hasSchedule;
  final AttendanceTotals totals;

  factory RiderAttendanceTotals.fromJson(Map<String, dynamic> json) => RiderAttendanceTotals(
        riderId: json['riderId'] as String,
        hasSchedule: json['hasSchedule'] as bool? ?? false,
        totals: AttendanceTotals.fromJson(
            json['totals'] as Map<String, dynamic>? ?? const <String, dynamic>{}),
      );
}

/// A fleet's totals over one period — `GET /api/tracking/carrier/attendance`.
class FleetAttendance {
  const FleetAttendance({
    required this.carrierId,
    required this.zone,
    required this.from,
    required this.to,
    required this.riders,
    this.asOf,
  });

  final String carrierId;
  final String zone;
  final DateTime from;
  final DateTime to;

  /// The one instant every rider's figures were computed at — see [RiderAttendance.asOf].
  final DateTime? asOf;
  final List<RiderAttendanceTotals> riders;

  factory FleetAttendance.fromJson(Map<String, dynamic> json) => FleetAttendance(
        carrierId: json['carrierId'] as String,
        zone: json['zone'] as String? ?? 'UTC',
        from: _date(json['from']),
        to: _date(json['to']),
        asOf: _instant(json['asOf']),
        riders: (json['riders'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic r) => RiderAttendanceTotals.fromJson(r as Map<String, dynamic>))
            .toList(),
      );
}
