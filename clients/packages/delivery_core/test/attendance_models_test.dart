import 'package:delivery_core/delivery_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// The carrier's Riders HR models, mirroring order-tracking's attendance read.
///
/// Two properties matter more than field-by-field parsing. The `...Local` stamps are Beirut's
/// clock and must reach the screen unconverted, whatever zone the browser is in: a manager abroad
/// reading 06:05 for a rider who clocked in at 08:05 would query the wrong morning. And a status
/// this client does not know yet must degrade to something neutral, never crash the month and
/// never be read as a verdict about somebody.
void main() {
  Map<String, dynamic> lateDay() => <String, dynamic>{
        'date': '2026-10-05',
        'status': 'LATE',
        'derivedStatus': 'LATE',
        'scheduled': <String, dynamic>{
          'shiftId': 'shift-1',
          'name': 'Beirut Central Day',
          'startTime': '08:00',
          'endTime': '18:00',
          'overnight': false,
          'startsAt': '2026-10-05T05:00:00Z',
          'endsAt': '2026-10-05T15:00:00Z',
          'scheduledSeconds': 36000,
          'lateGraceMinutes': 10,
        },
        'clockIn': '2026-10-05T05:14:00Z',
        'clockOut': '2026-10-05T15:00:00Z',
        'clockInLocal': '2026-10-05T08:14',
        'clockOutLocal': '2026-10-05T18:00',
        'clockOutReason': 'EXPIRED',
        'onShiftNow': false,
        'worked': true,
        'workedSeconds': 35160,
        'workedHours': 9.77,
        'manualSeconds': 0,
        'lateBySeconds': 840,
        'overtimeSeconds': 0,
        'sessions': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'session-1',
            'startedAt': '2026-10-05T05:14:00Z',
            'endedAt': '2026-10-05T15:00:00Z',
            'endReason': 'EXPIRED',
            'open': false,
            'countedUntil': '2026-10-05T15:00:00Z',
            'countedSeconds': 35160,
            'countedHours': 9.77,
            'startedAtLocal': '2026-10-05T08:14',
            'countedUntilLocal': '2026-10-05T18:00',
          },
        ],
        'entry': <String, dynamic>{
          'id': 'entry-1',
          'date': '2026-10-05',
          'status': 'LATE_EXCUSED',
          'clockIn': null,
          'clockOut': null,
          'manualSeconds': 0,
          'note': 'Traffic at Cola',
          'recordedBy': 'dispatcher',
          'recordedAt': '2026-10-05T16:00:00Z',
        },
      };

  Map<String, dynamic> totals() => <String, dynamic>{
        'scheduledDays': 22,
        'daysWorked': 7,
        'absences': 1,
        'lates': 2,
        'excusedLates': 1,
        'excusedAbsences': 0,
        'sickDays': 1,
        'leaveDays': 0,
        'workedSeconds': 250000,
        'manualSeconds': 36000,
        'scheduledSeconds': 792000,
        'overtimeSeconds': 1500,
        'workedHours': 69.44,
        'overtimeHours': 0.42,
      };

  group('RiderAttendance', () {
    test('keeps the wall-clock stamps on the server zone clock, unconverted', () {
      final AttendanceDay day = AttendanceDay.fromJson(lateDay());

      expect(day.clockInLocal!.hour, 8);
      expect(day.clockInLocal!.minute, 14);
      expect(day.clockOutLocal!.hour, 18);
      expect(day.sessions.single.startedAtLocal!.hour, 8);
      // The instant is still an instant: 05:14Z, whatever this machine's zone prints it as.
      expect(day.sessions.single.startedAt.toUtc(), DateTime.utc(2026, 10, 5, 5, 14));
    });

    test('reads a scheduled day with its shift, sessions, close reason and entry', () {
      final AttendanceDay day = AttendanceDay.fromJson(lateDay());

      expect(day.status, AttendanceStatus.late);
      expect(day.scheduled!.name, 'Beirut Central Day');
      expect(day.scheduled!.scheduledSeconds, 36000);
      expect(day.lateBySeconds, 840);
      expect(day.clockOutReason, DutyEndReason.expired);
      expect(day.sessions.single.countedSeconds, 35160);
      expect(day.entry!.status, AttendanceEntryKind.lateExcused);
      expect(day.entry!.note, 'Traffic at Cola');
    });

    test('a month keeps every day, its zone, and evidence apart from typed hours', () {
      final RiderAttendance month = RiderAttendance.fromJson(<String, dynamic>{
        'riderId': 'rider-1',
        'carrierId': 'p1',
        'zone': 'Asia/Beirut',
        'from': '2026-10-01',
        'to': '2026-10-31',
        'today': '2026-10-12',
        'hasSchedule': true,
        'days': <Map<String, dynamic>>[lateDay()],
        'totals': totals(),
      });

      expect(month.zone, 'Asia/Beirut');
      expect(month.today, DateTime(2026, 10, 12));
      expect(month.hasSchedule, isTrue);
      expect(month.days, hasLength(1));
      expect(month.totals.workedSeconds, 250000);
      expect(month.totals.manualSeconds, 36000);
      expect(month.totals.lates, 2);
      expect(month.totals.excusedLates, 1);
    });

    test('a status or close reason this client does not know is neutral, not a verdict', () {
      final Map<String, dynamic> json = lateDay()
        ..['status'] = 'ON_BREAK'
        ..['clockOutReason'] = 'SOMETHING_NEW'
        ..['scheduled'] = null
        ..['lateBySeconds'] = null
        ..['entry'] = null;

      final AttendanceDay day = AttendanceDay.fromJson(json);

      expect(day.status, AttendanceStatus.unknown);
      expect(day.clockOutReason, isNull);
      expect(day.scheduled, isNull);
      expect(day.lateBySeconds, isNull);
      expect(day.entry, isNull);
    });

    test('an open session has no close and says so', () {
      final DutySessionView open = DutySessionView.fromJson(<String, dynamic>{
        'id': 's-2',
        'startedAt': '2026-10-12T05:00:00Z',
        'endedAt': null,
        'endReason': null,
        'open': true,
        'countedUntil': '2026-10-12T09:00:00Z',
        'countedSeconds': 14400,
        'countedHours': 4.0,
        'startedAtLocal': '2026-10-12T08:00',
        'countedUntilLocal': '2026-10-12T12:00',
      });

      expect(open.open, isTrue);
      expect(open.endedAt, isNull);
      expect(open.endReason, isNull);
    });
  });

  group('ShiftTemplate', () {
    test('reads weekday names as ISO weekdays, in week order', () {
      final ShiftTemplate shift = ShiftTemplate.fromJson(<String, dynamic>{
        'id': 'shift-2',
        'name': 'Night',
        'startTime': '22:00',
        'endTime': '06:00',
        'overnight': true,
        'days': <String>['SUNDAY', 'MONDAY', 'FRIDAY'],
        'lateGraceMinutes': 15,
        'archived': false,
        'riders': 3,
      });

      expect(shift.weekdays, <int>[DateTime.monday, DateTime.friday, DateTime.sunday]);
      expect(shift.overnight, isTrue);
      expect(shift.riders, 3);
    });
  });

  group('ShiftAssignment', () {
    test('covers its inclusive dates, and an open one covers everything after its start', () {
      final ShiftAssignment closed = ShiftAssignment.fromJson(<String, dynamic>{
        'riderId': 'rider-1',
        'shiftId': 'shift-1',
        'shiftName': 'Day',
        'effectiveFrom': '2026-10-01',
        'effectiveTo': '2026-10-07',
      });
      final ShiftAssignment open = ShiftAssignment.fromJson(<String, dynamic>{
        'riderId': 'rider-1',
        'shiftId': 'shift-2',
        'shiftName': 'Late',
        'effectiveFrom': '2026-10-08',
        'effectiveTo': null,
      });

      expect(closed.covers(DateTime(2026, 10, 1)), isTrue);
      expect(closed.covers(DateTime(2026, 10, 7, 23, 30)), isTrue);
      expect(closed.covers(DateTime(2026, 10, 8)), isFalse);
      expect(open.covers(DateTime(2026, 10, 7)), isFalse);
      expect(open.covers(DateTime(2027, 3, 1)), isTrue);
    });
  });
}
