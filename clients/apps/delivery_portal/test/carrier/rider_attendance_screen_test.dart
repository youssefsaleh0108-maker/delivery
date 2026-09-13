import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/carrier/rider_attendance_screen.dart';
import 'package:delivery_portal/src/shell/console_controls.dart';
import 'package:delivery_portal/src/shell/shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rider Attendance & Shift Logs — Figma `web-carrier-rider-attendance` (112:945).
///
/// Every figure on this page can change what somebody is paid, so the tests pin the ways it could
/// mislead: colouring a freelancer's idle day as an absence, printing a time on the browser's clock
/// instead of Beirut's, adding up rounded hours, hiding that the platform (not the rider) closed a
/// shift, sending a manual entry the server would refuse, and leaving the reader stranded on a month
/// that could not be read.
class _Reply {
  const _Reply(this.body, [this.status = 200]);

  final Object? body;
  final int status;
}

class _Backend implements HttpClientAdapter {
  _Backend(this.route);

  final _Reply? Function(RequestOptions request) route;
  final List<RequestOptions> requests = <RequestOptions>[];

  List<String> monthsRead() => <String>[
        for (final RequestOptions r in requests)
          if (r.method == 'GET' &&
              r.path.endsWith('/attendance') &&
              r.queryParameters.containsKey('month'))
            r.queryParameters['month'] as String,
      ];

  List<RequestOptions> puts() =>
      requests.where((RequestOptions r) => r.method == 'PUT').toList();

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    final _Reply reply =
        route(options) ?? const _Reply(<String, dynamic>{'detail': 'no route'}, 404);
    return ResponseBody.fromString(reply.body == null ? '' : jsonEncode(reply.body), reply.status,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        });
  }

  @override
  void close({bool force = false}) {}
}

const String _rider = 'rider-aaaaaaaa';

String _two(int n) => n.toString().padLeft(2, '0');
String _iso(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

const Map<String, dynamic> _dayShift = <String, dynamic>{
  'shiftId': 'shift-day',
  'name': 'Beirut Central Day',
  'startTime': '08:00',
  'endTime': '18:00',
  'overnight': false,
  'startsAt': '2026-10-01T05:00:00Z',
  'endsAt': '2026-10-01T15:00:00Z',
  'scheduledSeconds': 36000,
  'lateGraceMinutes': 10,
};

/// One judged day. [clockIn] is `HH:mm` on the day; [clockOut] a full local stamp, because after a
/// night it falls on the next date.
Map<String, dynamic> _day(
  DateTime date,
  String status, {
  Map<String, dynamic>? scheduled,
  String? clockIn,
  String? clockOut,
  String reason = 'RIDER',
  bool onShiftNow = false,
  int workedSeconds = 0,
  double? workedHours,
  int? lateBySeconds,
  int overtimeSeconds = 0,
  int manualSeconds = 0,
  Map<String, dynamic>? entry,
}) {
  final String iso = _iso(date);
  return <String, dynamic>{
    'date': iso,
    'status': status,
    'derivedStatus': status,
    'scheduled': scheduled,
    'clockInLocal': clockIn == null ? null : '${iso}T$clockIn',
    'clockOutLocal': clockOut,
    'clockOutReason': clockOut == null ? null : reason,
    'onShiftNow': onShiftNow,
    'worked': workedSeconds > 0,
    'workedSeconds': workedSeconds,
    'workedHours': workedHours ?? workedSeconds / 3600,
    'manualSeconds': manualSeconds,
    'lateBySeconds': lateBySeconds,
    'overtimeSeconds': overtimeSeconds,
    'sessions': <Map<String, dynamic>>[
      if (clockIn != null)
        <String, dynamic>{
          'id': 'session-$iso',
          'startedAt': '${iso}T05:00:00Z',
          'endedAt': onShiftNow ? null : '${iso}T15:00:00Z',
          'endReason': onShiftNow ? null : reason,
          'open': onShiftNow,
          'countedUntil': '${iso}T15:00:00Z',
          'countedSeconds': workedSeconds,
          'countedHours': workedSeconds / 3600,
          'startedAtLocal': '${iso}T$clockIn',
          'countedUntilLocal': clockOut ?? '${iso}T12:00',
        },
    ],
    'entry': entry,
  };
}

Map<String, dynamic> _month(
  int year,
  int month,
  List<Map<String, dynamic>> days, {
  required bool hasSchedule,
  Map<String, dynamic> totals = const <String, dynamic>{},
}) =>
    <String, dynamic>{
      'riderId': _rider,
      'carrierId': 'p1',
      'zone': 'Asia/Beirut',
      'from': _iso(DateTime(year, month)),
      'to': _iso(DateTime(year, month + 1, 0)),
      'today': '2026-10-12',
      'hasSchedule': hasSchedule,
      'days': days,
      'totals': totals,
    };

/// Any month with nothing in it: no schedule, no duty.
Map<String, dynamic> _quiet(String yearMonth) {
  final int year = int.parse(yearMonth.substring(0, 4));
  final int month = int.parse(yearMonth.substring(5, 7));
  final DateTime today = DateTime(2026, 10, 12);
  return _month(year, month, <Map<String, dynamic>>[
    for (int d = 1; d <= DateTime(year, month + 1, 0).day; d++)
      _day(DateTime(year, month, d),
          DateTime(year, month, d).isAfter(today) ? 'UPCOMING' : 'NO_DUTY'),
  ], hasSchedule: false);
}

/// The office's live entry for a day.
Map<String, dynamic> _entry(String iso, String status,
        {String? clockIn, String? clockOut, int manualSeconds = 0, String? note}) =>
    <String, dynamic>{
      'id': 'entry-$iso',
      'date': iso,
      'status': status,
      'clockIn': clockIn,
      'clockOut': clockOut,
      'manualSeconds': manualSeconds,
      'note': note,
      'recordedBy': 'dispatcher',
      'recordedAt': '2026-10-12T10:00:00Z',
    };

/// A one-day read — what the log dialog asks for about a day outside the month on screen.
Map<String, dynamic> _oneDay(String iso, {Map<String, dynamic>? entry}) => <String, dynamic>{
      'riderId': _rider,
      'carrierId': 'p1',
      'zone': 'Asia/Beirut',
      'from': iso,
      'to': iso,
      'today': '2026-10-12',
      'asOf': '2026-10-12T17:00:00Z',
      'hasSchedule': false,
      'days': <Map<String, dynamic>>[
        _day(DateTime.parse(iso), entry == null ? 'NO_DUTY' : entry['status'] as String,
            entry: entry),
      ],
      'totals': <String, dynamic>{},
    };

/// One roster row. [state] is what the platform believes: ON_DUTY, STALE or OFF_DUTY.
Map<String, dynamic> _presence(String riderId, String state) => <String, dynamic>{
      'riderId': riderId,
      'carrierId': 'p1',
      'dutyState': state == 'OFF_DUTY' ? 'OFF_DUTY' : 'ON_DUTY',
      'state': state,
      'dutyChangedAt': '2026-10-12T07:00:00Z',
      'lastSeenAt': '2026-10-12T09:30:00Z',
      'lat': null,
      'lng': null,
      'accuracyM': null,
    };

/// October 2026 on the design's weekday day shift, read on Monday the 12th: on time, late, absent,
/// auto-closed, overtime, days off, a shift running now, and the rest of the month still to come.
/// [typedOnTheSixth] turns the absent 6th into a day the office typed as present, 08:00-18:00.
Map<String, dynamic> _scheduledOctober({bool sickOnTheTwelfth = false, bool typedOnTheSixth = false}) {
  final List<Map<String, dynamic>> days = <Map<String, dynamic>>[];
  for (int d = 1; d <= 31; d++) {
    final DateTime date = DateTime(2026, 10, d);
    final String iso = _iso(date);
    final bool weekend = date.weekday >= DateTime.saturday;
    if (d == 12 && sickOnTheTwelfth) {
      days.add(_day(date, 'SICK', scheduled: _dayShift, entry: <String, dynamic>{
        'id': 'entry-1',
        'date': iso,
        'status': 'SICK',
        'clockIn': null,
        'clockOut': null,
        'manualSeconds': 0,
        'note': 'Flu',
        'recordedBy': 'dispatcher',
        'recordedAt': '2026-10-12T10:00:00Z',
      }));
    } else if (d > 12) {
      days.add(_day(date, 'UPCOMING', scheduled: weekend ? null : _dayShift));
    } else if (weekend) {
      days.add(_day(date, 'DAY_OFF'));
    } else if (d == 5) {
      days.add(_day(date, 'LATE',
          scheduled: _dayShift,
          clockIn: '08:14',
          clockOut: '${iso}T18:00',
          workedSeconds: 35160,
          lateBySeconds: 840));
    } else if (d == 6) {
      days.add(typedOnTheSixth
          // Nothing from the app; the office typed the day as present.
          ? _day(date, 'PRESENT',
              scheduled: _dayShift,
              manualSeconds: 36000,
              entry: _entry(iso, 'PRESENT',
                  clockIn: '08:00', clockOut: '18:00', manualSeconds: 36000))
          : _day(date, 'ABSENT', scheduled: _dayShift));
    } else if (d == 7) {
      days.add(_day(date, 'PRESENT',
          scheduled: _dayShift,
          clockIn: '07:58',
          clockOut: '${iso}T11:02',
          reason: 'EXPIRED',
          workedSeconds: 11040,
          lateBySeconds: 0));
    } else if (d == 8) {
      days.add(_day(date, 'PRESENT',
          scheduled: _dayShift,
          clockIn: '07:50',
          clockOut: '${iso}T18:20',
          workedSeconds: 37800,
          lateBySeconds: 0,
          overtimeSeconds: 1800));
    } else if (d == 12) {
      days.add(_day(date, 'PRESENT',
          scheduled: _dayShift, clockIn: '08:00', onShiftNow: true, workedSeconds: 14400));
    } else {
      days.add(_day(date, 'PRESENT',
          scheduled: _dayShift,
          clockIn: '07:56',
          clockOut: '${iso}T18:02',
          workedSeconds: 36360,
          lateBySeconds: 0));
    }
  }
  return _month(2026, 10, days, hasSchedule: true, totals: <String, dynamic>{
    'scheduledDays': 22,
    'daysWorked': 7,
    'absences': 1,
    'lates': 1,
    'excusedLates': 0,
    'excusedAbsences': 0,
    'sickDays': 0,
    'leaveDays': 0,
    'workedSeconds': 207480,
    'manualSeconds': 0,
    'scheduledSeconds': 792000,
    'overtimeSeconds': 1800,
    // Deliberately not what the seconds say: the page must never print a server-rounded figure
    // where it has the exact one.
    'workedHours': 99.99,
    'overtimeHours': 9.99,
  });
}

/// The same October for a rider with no schedule: two stints, one of them through the night.
Map<String, dynamic> _freelanceOctober() {
  final List<Map<String, dynamic>> days = <Map<String, dynamic>>[];
  for (int d = 1; d <= 31; d++) {
    final DateTime date = DateTime(2026, 10, d);
    if (d == 5) {
      days.add(_day(date, 'WORKED',
          clockIn: '11:40', clockOut: '2026-10-05T15:40', workedSeconds: 14400));
    } else if (d == 9) {
      days.add(_day(date, 'WORKED',
          clockIn: '20:30',
          clockOut: '2026-10-10T06:30',
          workedSeconds: 36000,
          // A stale rounded figure beside the exact one.
          workedHours: 3.33));
    } else {
      days.add(_day(date, d > 12 ? 'UPCOMING' : 'NO_DUTY'));
    }
  }
  return _month(2026, 10, days, hasSchedule: false, totals: <String, dynamic>{
    'daysWorked': 2,
    'workedSeconds': 50400,
    'workedHours': 1.11,
  });
}

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      theme: DeliveryTheme.light(),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    );

Future<_Backend> _pump(
  WidgetTester tester, {
  Map<String, dynamic> Function(String month)? months,
  int status = 200,
  Locale locale = const Locale('en'),
  double width = 1280,
  List<Map<String, dynamic>>? roster,
  Map<String, dynamic> Function(String day)? dayRead,
}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  bool sick = false;
  final _Backend api = _Backend((RequestOptions r) {
    if (r.method == 'GET' && r.path == '/api/tracking/riders/$_rider/attendance') {
      final String? day = r.queryParameters['from'] as String?;
      if (day != null) {
        // One day outside the month on screen, read by the log dialog. Unavailable unless the
        // test says what that day holds.
        return dayRead == null
            ? const _Reply(<String, dynamic>{'detail': 'unavailable'}, 500)
            : _Reply(dayRead(day));
      }
      if (status != 200) return _Reply(<String, dynamic>{'detail': 'refused'}, status);
      final String month = r.queryParameters['month'] as String;
      if (months != null) return _Reply(months(month));
      return _Reply(month == '2026-10'
          ? _scheduledOctober(sickOnTheTwelfth: sick)
          : _quiet(month));
    }
    // Unanswered (404) unless the test gives a roster: the live badge must then stay undrawn.
    if (r.method == 'GET' && r.path == '/api/tracking/riders/roster') {
      return roster == null ? null : _Reply(roster);
    }
    if (r.method == 'DELETE' &&
        r.path.startsWith('/api/tracking/riders/$_rider/attendance/entries/')) {
      return const _Reply(<String, dynamic>{});
    }
    if (r.method == 'PUT' && r.path.startsWith('/api/tracking/riders/$_rider/attendance/entries/')) {
      final Map<String, dynamic> body = r.data as Map<String, dynamic>;
      sick = body['status'] == 'SICK';
      return _Reply(<String, dynamic>{
        'id': 'entry-1',
        'date': r.path.substring(r.path.length - 10),
        'status': body['status'],
        'clockIn': body['clockIn'],
        'clockOut': body['clockOut'],
        'manualSeconds': 0,
        'note': body['note'],
        'recordedBy': 'dispatcher',
        'recordedAt': '2026-10-12T10:00:00Z',
      });
    }
    return null;
  });
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = api;

  await tester.pumpWidget(_wrap(
    RiderAttendanceScreen(
      api: TrackingApi(dio),
      riderId: _rider,
      riderName: 'Nadia Haddad',
      initialMonth: DateTime(2026, 10),
    ),
    locale: locale,
  ));
  await tester.pumpAndSettle();
  return api;
}

/// The painted square behind a calendar day.
BoxDecoration _cell(WidgetTester tester, String day) {
  final Container box = tester.widget<Container>(
      find.ancestor(of: find.text(day), matching: find.byType(Container)).first);
  return box.decoration! as BoxDecoration;
}

Future<void> _chooseStatus(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(
      of: find.byType(AlertDialog), matching: find.byType(ConsoleSelect)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

ConsolePrimaryButton _saveButton(WidgetTester tester, DeliveryStrings t) =>
    tester.widget<ConsolePrimaryButton>(find.widgetWithText(ConsolePrimaryButton, t.attendanceLogSave));

/// Opens the log dialog's date picker from the date it shows, steps back [monthsBack] months, and
/// picks [day].
Future<void> _pickDate(WidgetTester tester,
    {required String shown, required int monthsBack, required String day}) async {
  await tester.tap(find.text(shown));
  await tester.pumpAndSettle();
  final Finder picker = find.byType(DatePickerDialog);
  for (int i = 0; i < monthsBack; i++) {
    await tester.tap(find.descendant(of: picker, matching: find.byTooltip('Previous month')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.descendant(of: picker, matching: find.text(day)));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: picker, matching: find.text('OK')));
  await tester.pumpAndSettle();
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  group('a scheduled month', () {
    testWidgets('colours each day by its verdict, and marks today', (WidgetTester tester) async {
      await _pump(tester);

      expect(find.text('Nadia Haddad'), findsOneWidget);
      expect(find.text(en.attendanceForMonth('October 2026')), findsOneWidget);
      for (final String legend in <String>[
        en.attendanceLegendPresent,
        en.attendanceLegendLate,
        en.attendanceLegendOff,
      ]) {
        expect(find.text(legend), findsOneWidget, reason: legend);
      }

      expect(_cell(tester, '1').color, DeliveryAccent.positive.tint);
      expect(_cell(tester, '5').color, DeliveryAccent.caution.tint);
      expect(_cell(tester, '6').color, DeliveryAccent.critical.tint);
      expect(_cell(tester, '3').color, DeliveryColors.borderFaint);
      // The future is left unstyled rather than predicted.
      expect(_cell(tester, '13').color, Colors.transparent);
      expect(_cell(tester, '12').border, isNotNull);
      expect(_cell(tester, '9').border, isNull);
      expect(find.text(en.attendanceZoneNote('Asia/Beirut')), findsOneWidget);
    });

    testWidgets('the figures are the server\'s totals, from exact seconds',
        (WidgetTester tester) async {
      await _pump(tester);

      expect(find.text(en.attendanceDaysCount(7)), findsOneWidget);
      // One absence and one late.
      expect(find.text(en.attendanceDaysCount(1)), findsNWidgets(2));
      expect(find.text(en.attendanceHoursValue('0.5')), findsOneWidget);
      expect(find.text(en.attendanceHoursValue('10.0')), findsNothing);
      // Nobody was excused, so the line is not drawn at all.
      expect(find.text(en.attendanceExcusedDays), findsNothing);
    });

    testWidgets('the log is the Beirut clock in 24 hours, and says who closed a shift',
        (WidgetTester tester) async {
      await _pump(tester);

      expect(find.text(en.attendanceColShift), findsOneWidget);
      expect(find.text(en.attendanceColStatus), findsOneWidget);
      // Days 1, 2, 5, 6, 7, 8, 9 and 12 — never a day off, never the future.
      expect(find.text('Beirut Central Day (08:00 - 18:00)'), findsNWidgets(8));
      expect(find.text('07:56'), findsNWidgets(3));
      expect(find.text('18:02'), findsNWidgets(3));
      expect(find.text('10.1 hrs'), findsNWidgets(3));
      expect(find.text('08:14'), findsOneWidget);
      expect(find.textContaining(en.attendanceLateBy(14)), findsOneWidget);
      expect(find.textContaining(en.attendanceAutoClosed), findsOneWidget);
      expect(find.textContaining(en.attendanceOvertimeNote(30)), findsOneWidget);
      expect(find.text(en.attendanceOnShiftNow), findsOneWidget);
      expect(find.text(en.attendanceStatusOnTime), findsNWidgets(6));
      expect(find.text(en.attendanceStatusLate), findsOneWidget);
      // The pill, and the legend beside the calendar.
      expect(find.text(en.attendanceStatusAbsent), findsNWidgets(2));
      expect(find.text('0.0 hrs'), findsOneWidget);
      expect(find.textContaining('AM'), findsNothing);
      expect(find.textContaining('PM'), findsNothing);
    });

    testWidgets('lays the figures beside the calendar when wide, under it when not',
        (WidgetTester tester) async {
      await _pump(tester, width: 1440);
      expect(tester.getTopLeft(find.text(en.attendanceAggregatesTitle)).dx,
          greaterThan(tester.getTopLeft(find.text('October 2026')).dx + 400));

      await _pump(tester, width: 1024);
      expect(tester.getTopLeft(find.text(en.attendanceAggregatesTitle)).dy,
          greaterThan(tester.getTopLeft(find.text('October 2026')).dy + 200));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the log sits inside its card, each line dated with its year',
        (WidgetTester tester) async {
      await _pump(tester);

      expect(
          find.descendant(
              of: find.byType(ConsoleTable), matching: find.text(en.attendanceLogsTitle)),
          findsOneWidget);
      expect(find.text('Oct 5, 2026'), findsOneWidget);
      expect(find.text('Mon, Oct 5'), findsNothing);
    });

    testWidgets('hours typed by hand are marked manual, with the times that were typed',
        (WidgetTester tester) async {
      await _pump(tester,
          months: (String m) =>
              m == '2026-10' ? _scheduledOctober(typedOnTheSixth: true) : _quiet(m));

      // The 6th has nothing from the app: its times and hours are the office's, and say so.
      final Finder typed = find.byTooltip(en.attendanceTypedByHand);
      expect(typed, findsNWidgets(2));
      expect(find.descendant(of: typed.first, matching: find.text('08:00')), findsOneWidget);
      expect(find.descendant(of: typed.last, matching: find.text('18:00')), findsOneWidget);
      expect(find.text(en.attendanceHoursShort('10.0')), findsOneWidget);
      expect(find.text(en.attendanceManualTag), findsOneWidget);
      // No line prints bare hours beside dashes for a day the app never saw.
      expect(find.text(en.attendanceHoursShort('0.0')), findsNothing);
    });
  });

  group('the header', () {
    testWidgets('the live badge counts riders on duty now, and the bell is drawn off',
        (WidgetTester tester) async {
      final _Backend api = await _pump(tester, roster: <Map<String, dynamic>>[
        _presence('rider-1', 'ON_DUTY'),
        _presence('rider-2', 'ON_DUTY'),
        // Declared on duty but no longer sighted: the roster keeps them for dispatch; not live.
        _presence('rider-3', 'STALE'),
      ]);

      expect(find.text(en.attendanceLiveOnDuty(2)), findsOneWidget);
      final RequestOptions roster = api.requests
          .singleWhere((RequestOptions r) => r.path == '/api/tracking/riders/roster');
      expect(roster.queryParameters['onDutyOnly'], isTrue);

      final ConsoleIconAction bell = tester.widget<ConsoleIconAction>(find.ancestor(
          of: find.byIcon(Icons.notifications_none), matching: find.byType(ConsoleIconAction)));
      expect(bell.onPressed, isNull);
      expect(bell.tooltip, en.notifications);
    });

    testWidgets('a roster that cannot be read draws no badge rather than a guess',
        (WidgetTester tester) async {
      await _pump(tester);

      expect(find.textContaining('Live:'), findsNothing);
      expect(find.byIcon(Icons.notifications_none), findsOneWidget);
    });
  });

  group('a rider with no schedule', () {
    testWidgets('shows time on duty only: no late, absent or shift anywhere',
        (WidgetTester tester) async {
      await _pump(tester, months: (_) => _freelanceOctober());

      expect(find.text(en.attendanceNoSchedule), findsOneWidget);
      expect(find.text(en.attendanceLegendOnDuty), findsOneWidget);
      for (final String absent in <String>[
        en.attendanceLegendLate,
        en.attendanceLegendAbsent,
        en.attendanceColShift,
        en.attendanceColStatus,
        en.attendanceAbsences,
        en.attendanceTimesLate,
        en.attendanceOvertime,
      ]) {
        expect(find.text(absent), findsNothing, reason: absent);
      }
      expect(find.text(en.attendanceHoursOnDuty), findsOneWidget);
      expect(find.text(en.attendanceHoursValue('14.0')), findsOneWidget);
      expect(_cell(tester, '5').color, DeliveryAccent.positive.tint);
      // An idle day is not an absence, and is not painted as one.
      expect(_cell(tester, '6').color, Colors.transparent);
    });

    testWidgets('a night is printed on the day it started, from its exact seconds',
        (WidgetTester tester) async {
      await _pump(tester, months: (_) => _freelanceOctober());

      expect(find.text('20:30'), findsOneWidget);
      expect(find.text('06:30 (+1)'), findsOneWidget);
      expect(find.text('10.0 hrs'), findsOneWidget);
      expect(find.text('3.3 hrs'), findsNothing);
    });

    testWidgets('an empty month says history is not backfilled', (WidgetTester tester) async {
      await _pump(tester, months: _quiet);

      expect(find.text(en.attendanceEmptyMonth), findsOneWidget);
    });
  });

  group('moving between months', () {
    testWidgets('the chevrons read the month they land on', (WidgetTester tester) async {
      final _Backend api = await _pump(tester);

      await tester.tap(find.byTooltip(en.attendancePrevMonth));
      await tester.pumpAndSettle();
      expect(find.text(en.attendanceForMonth('September 2026')), findsOneWidget);

      await tester.tap(find.byTooltip(en.attendanceNextMonth));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(en.attendanceNextMonth));
      await tester.pumpAndSettle();

      expect(api.monthsRead(), <String>['2026-10', '2026-09', '2026-10', '2026-11']);
      expect(find.text(en.attendanceForMonth('November 2026')), findsOneWidget);
    });

    testWidgets('a month older than the kept history says so, and can still be left',
        (WidgetTester tester) async {
      final _Backend api = await _pump(tester, status: 400);

      expect(find.text(en.attendanceHistoryLimit), findsOneWidget);
      // Retrying cannot work, so it is not offered.
      expect(find.text(en.tryAgain), findsNothing);

      await tester.tap(find.byTooltip(en.attendanceNextMonth));
      await tester.pumpAndSettle();
      expect(api.monthsRead(), <String>['2026-10', '2026-11']);
    });

    testWidgets('a failed read offers a retry that reads again', (WidgetTester tester) async {
      final _Backend api = await _pump(tester, status: 500);

      expect(find.text(en.attendanceLoadFailed), findsOneWidget);
      await tester.tap(find.text(en.tryAgain));
      await tester.pumpAndSettle();
      expect(api.monthsRead(), hasLength(2));
    });

    testWidgets('a rider not on this fleet reads as exactly that', (WidgetTester tester) async {
      await _pump(tester, status: 404);

      expect(find.text(en.attendanceNotOnFleet), findsOneWidget);
      // Nothing to log against a rider the server will not answer for.
      final ConsolePrimaryButton log =
          tester.widget(find.widgetWithText(ConsolePrimaryButton, en.attendanceManualLog));
      expect(log.onPressed, isNull);
    });

    testWidgets('a carrier account in no company is told so', (WidgetTester tester) async {
      await _pump(tester, status: 403);

      expect(find.text(en.noCompanyYet), findsOneWidget);
      expect(find.text(en.askThePlatformToAttachYou), findsOneWidget);
    });
  });

  group('the Manual Attendance Log', () {
    testWidgets('needs a status, sends the entry, and repaints the day it changed',
        (WidgetTester tester) async {
      final _Backend api = await _pump(tester);

      await tester.tap(find.text(en.attendanceManualLog));
      await tester.pumpAndSettle();
      expect(find.text(en.attendanceLogTitle('Nadia Haddad')), findsOneWidget);
      // Today, as the server counts it.
      expect(find.text('Monday, October 12, 2026'), findsOneWidget);
      expect(_saveButton(tester, en).onPressed, isNull);

      await _chooseStatus(tester, en.attendanceKindSick);
      await tester.enterText(find.widgetWithText(TextField, en.attendanceLogNote), 'Flu');
      await tester.pump();
      await tester.tap(find.text(en.attendanceLogSave));
      await tester.pumpAndSettle();

      final RequestOptions put = api.puts().single;
      expect(put.path, '/api/tracking/riders/$_rider/attendance/entries/2026-10-12');
      expect(put.data, <String, dynamic>{'status': 'SICK', 'note': 'Flu'});
      expect(find.text(en.attendanceLogSaved), findsOneWidget);
      expect(api.monthsRead(), <String>['2026-10', '2026-10']);
      expect(_cell(tester, '12').color, DeliveryAccent.info.tint);
    });

    testWidgets('a present day needs both times, and sends them as typed',
        (WidgetTester tester) async {
      final _Backend api = await _pump(tester);

      await tester.tap(find.text(en.attendanceManualLog));
      await tester.pumpAndSettle();
      await _chooseStatus(tester, en.attendanceKindPresent);
      expect(find.text(en.attendanceLogManualNote), findsOneWidget);
      expect(find.text(en.attendanceLogPresentKeepsLate), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, en.attendanceLogClockIn), '08:00');
      await tester.pump();
      expect(find.text(en.attendanceLogTimesRule), findsOneWidget);
      expect(_saveButton(tester, en).onPressed, isNull);

      await tester.enterText(find.widgetWithText(TextField, en.attendanceLogClockOut), '8pm');
      await tester.pump();
      expect(find.text(en.attendanceTimeInvalid), findsOneWidget);
      expect(_saveButton(tester, en).onPressed, isNull);

      await tester.enterText(find.widgetWithText(TextField, en.attendanceLogClockOut), '18:00');
      await tester.pump();
      await tester.tap(find.text(en.attendanceLogSave));
      await tester.pumpAndSettle();

      expect(api.puts().single.data,
          <String, dynamic>{'status': 'PRESENT', 'clockIn': '08:00', 'clockOut': '18:00'});
    });

    testWidgets('a note stops at the server\'s 500 characters', (WidgetTester tester) async {
      final _Backend api = await _pump(tester);

      await tester.tap(find.text(en.attendanceManualLog));
      await tester.pumpAndSettle();
      await _chooseStatus(tester, en.attendanceKindLeave);
      await tester.enterText(
          find.widgetWithText(TextField, en.attendanceLogNote), 'x' * 600);
      await tester.pump();
      await tester.tap(find.text(en.attendanceLogSave));
      await tester.pumpAndSettle();

      expect((api.puts().single.data as Map<String, dynamic>)['note'], 'x' * 500);
    });

    testWidgets('tapping a day opens the log for that day', (WidgetTester tester) async {
      await _pump(tester);

      await tester.tap(find.text('6'));
      await tester.pumpAndSettle();

      expect(find.text(en.attendanceLogTitle('Nadia Haddad')), findsOneWidget);
      expect(find.text('Tuesday, October 6, 2026'), findsOneWidget);
    });

    testWidgets('a day in another month is read first, so its entry is prefilled and removable',
        (WidgetTester tester) async {
      final _Backend api = await _pump(tester,
          dayRead: (String day) => _oneDay(day, entry: _entry(day, 'SICK', note: 'Flu')));

      await tester.tap(find.text(en.attendanceManualLog));
      await tester.pumpAndSettle();
      await _pickDate(tester, shown: 'Monday, October 12, 2026', monthsBack: 1, day: '30');

      expect(find.text('Wednesday, September 30, 2026'), findsOneWidget);
      final RequestOptions read = api.requests.singleWhere(
          (RequestOptions r) => r.method == 'GET' && r.queryParameters.containsKey('from'));
      expect(read.queryParameters, <String, dynamic>{'from': '2026-09-30', 'to': '2026-09-30'});
      expect(find.text(en.attendanceKindSick), findsOneWidget);
      expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, en.attendanceLogNote))
              .controller!
              .text,
          'Flu');

      await tester.tap(find.text(en.attendanceLogWithdraw));
      await tester.pumpAndSettle();

      expect(api.requests.where((RequestOptions r) => r.method == 'DELETE').single.path,
          '/api/tracking/riders/$_rider/attendance/entries/2026-09-30');
    });

    testWidgets('a day whose entry cannot be checked cannot be saved blind',
        (WidgetTester tester) async {
      final _Backend api = await _pump(tester);

      await tester.tap(find.text(en.attendanceManualLog));
      await tester.pumpAndSettle();
      await _pickDate(tester, shown: 'Monday, October 12, 2026', monthsBack: 1, day: '30');
      await _chooseStatus(tester, en.attendanceKindLeave);

      expect(find.text(en.attendanceLogCheckFailed), findsOneWidget);
      expect(_saveButton(tester, en).onPressed, isNull);
      expect(api.puts(), isEmpty);
    });
  });

  testWidgets('reads in Arabic, right to left', (WidgetTester tester) async {
    await _pump(tester, locale: const Locale('ar'), width: 1024);

    expect(find.text(ar.attendanceTitle), findsOneWidget);
    expect(find.text(ar.attendanceAggregatesTitle), findsOneWidget);
    expect(find.text(ar.attendanceLogsTitle), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(RiderAttendanceScreen))),
        TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in Arabic a clock time is still laid out left to right',
      (WidgetTester tester) async {
    await _pump(tester, months: (_) => _freelanceOctober(), locale: const Locale('ar'));

    expect(Directionality.of(tester.element(find.byType(RiderAttendanceScreen))),
        TextDirection.rtl);
    // Laid out right to left, the bidi algorithm would paint "06:30 (+1)" as "(1+) 06:30".
    for (final String time in <String>['20:30', '06:30 (+1)']) {
      expect(tester.renderObject<RenderParagraph>(find.text(time)).textDirection,
          TextDirection.ltr,
          reason: time);
    }
  });
}
