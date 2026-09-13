import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/carrier/shift_schedule_screen.dart';
import 'package:delivery_portal/src/shell/console_controls.dart';
import 'package:delivery_portal/src/shell/shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shift schedules — the part of Riders HR the attendance frame (112:945) implies but does not draw.
///
/// What is pinned: the company's shifts as they are (retired ones gone, never re-timed), each
/// rider's shift today with anything already set to start, a rider with no shift shown as the
/// freelancer they are, a retire that cannot work drawn off, a schedule for "today" sent without a
/// date so the server's Beirut today decides, and a rider's attendance opening in place.
class _Reply {
  const _Reply(this.body, [this.status = 200]);

  final Object? body;
  final int status;
}

class _Backend implements HttpClientAdapter {
  _Backend(this.route);

  final _Reply? Function(RequestOptions request) route;
  final List<RequestOptions> requests = <RequestOptions>[];

  List<RequestOptions> sent(String method, String pathSuffix) => requests
      .where((RequestOptions r) => r.method == method && r.path.endsWith(pathSuffix))
      .toList();

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

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final DateTime _today = DateUtils.dateOnly(DateTime.now());

Map<String, dynamic> _shift(
  String id,
  String name,
  String start,
  String end, {
  List<String> days = const <String>['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY'],
  int riders = 0,
  bool archived = false,
}) =>
    <String, dynamic>{
      'id': id,
      'name': name,
      'startTime': start,
      'endTime': end,
      'overnight': end.compareTo(start) <= 0,
      'days': days,
      'lateGraceMinutes': 10,
      'archived': archived,
      'riders': riders,
    };

Map<String, dynamic> _presence(String riderId) => <String, dynamic>{
      'riderId': riderId,
      'carrierId': 'p1',
      'dutyState': 'OFF_DUTY',
      'state': 'OFF_DUTY',
      'dutyChangedAt': '2026-10-01T07:00:00Z',
      'lastSeenAt': '2026-10-01T09:30:00Z',
      'lat': null,
      'lng': null,
      'accuracyM': null,
    };

Map<String, dynamic> _application(String id, String name, String riderRef) => <String, dynamic>{
      'id': id,
      'reference': 'REF-$id',
      'kind': 'RIDER',
      'businessName': name,
      'contactName': name,
      'contactEmail': 'rider@example.com',
      'contactPhone': '+96170000000',
      'emailVerifiedAt': '2026-07-01T09:00:00Z',
      'phoneVerifiedAt': null,
      'notes': null,
      'status': 'PROVISIONED',
      'createdAt': '2026-07-01T09:00:00Z',
      'decidedAt': '2026-07-04T09:00:00Z',
      'decidedBy': null,
      'rejectionReason': null,
      'provisionedUserRef': riderRef,
      'provisionedEntityId': null,
      'details': <String, String>{},
    };

Map<String, dynamic> _emptyMonth(String yearMonth) {
  final int year = int.parse(yearMonth.substring(0, 4));
  final int month = int.parse(yearMonth.substring(5, 7));
  final int length = DateTime(year, month + 1, 0).day;
  return <String, dynamic>{
    'riderId': 'rider-aaaaaaaa',
    'carrierId': 'p1',
    'zone': 'Asia/Beirut',
    'from': _iso(DateTime(year, month)),
    'to': _iso(DateTime(year, month, length)),
    'today': _iso(_today),
    'hasSchedule': false,
    'days': <Map<String, dynamic>>[
      for (int d = 1; d <= length; d++)
        <String, dynamic>{
          'date': _iso(DateTime(year, month, d)),
          'status': 'NO_DUTY',
          'derivedStatus': 'NO_DUTY',
          'onShiftNow': false,
          'worked': false,
          'workedSeconds': 0,
          'manualSeconds': 0,
          'overtimeSeconds': 0,
          'sessions': <dynamic>[],
        },
    ],
    'totals': <String, dynamic>{},
  };
}

_Backend _backend({int trackingStatus = 200}) {
  return _Backend((RequestOptions r) {
    final String path = r.path;
    if (trackingStatus != 200 && path.startsWith('/api/tracking')) {
      return _Reply(<String, dynamic>{'detail': 'refused'}, trackingStatus);
    }
    switch (r.method) {
      case 'GET':
        if (path.endsWith('/carrier/shifts')) {
          return _Reply(<Map<String, dynamic>>[
            _shift('shift-day', 'Beirut Central Day', '08:00', '18:00', riders: 1),
            _shift('shift-night', 'Night', '22:00', '06:00',
                days: <String>['FRIDAY', 'SATURDAY']),
            _shift('shift-old', 'Old', '06:00', '12:00', archived: true),
          ]);
        }
        if (path.endsWith('/carrier/shift-assignments')) {
          return _Reply(<Map<String, dynamic>>[
            <String, dynamic>{
              'riderId': 'rider-aaaaaaaa',
              'shiftId': 'shift-day',
              'shiftName': 'Beirut Central Day',
              'effectiveFrom': _iso(_today.subtract(const Duration(days: 10))),
              'effectiveTo': null,
            },
            <String, dynamic>{
              'riderId': 'rider-bbbbbbbb',
              'shiftId': 'shift-night',
              'shiftName': 'Night',
              'effectiveFrom': _iso(DateTime(_today.year, _today.month, _today.day + 5)),
              'effectiveTo': null,
            },
          ]);
        }
        if (path.endsWith('/tracking/riders/roster')) {
          return _Reply(<Map<String, dynamic>>[
            _presence('rider-aaaaaaaa'),
            _presence('rider-bbbbbbbb'),
            _presence('rider-cccccccc'),
          ]);
        }
        if (path.endsWith('/attendance')) {
          return _Reply(_emptyMonth(r.queryParameters['month'] as String));
        }
        if (path.endsWith('/my-company/riders')) {
          return const _Reply(<String, dynamic>{
            'providerId': 'p1',
            // One more than tracking knows: hired, but not yet linked to the fleet there.
            'riders': <String>['rider-aaaaaaaa', 'rider-bbbbbbbb', 'rider-cccccccc', 'rider-dddd'],
          });
        }
        if (path.endsWith('/my-company')) {
          return const _Reply(<String, dynamic>{
            'id': 'p1',
            'slug': 'libanex',
            'name': 'Libanex Express',
            'kind': 'EXTERNAL',
            'status': 'ACTIVE',
            'canTakeWork': true,
            'ownerRef': null,
            'accountRef': 'ACC-CARRIER',
            'contactName': 'Kamal',
            'contactPhone': '+100',
            'payoutState': 'VERIFIED',
          });
        }
        if (path.endsWith('/applications/for-company/p1')) {
          return _Reply(<Map<String, dynamic>>[
            _application('app-1', 'Nadia Haddad', 'rider-aaaaaaaa'),
            _application('app-2', 'Karim Aoun', 'rider-bbbbbbbb'),
          ]);
        }
      case 'POST':
        if (path.endsWith('/carrier/shifts')) {
          final Map<String, dynamic> body = r.data as Map<String, dynamic>;
          return _Reply(_shift('shift-new', body['name'] as String, body['startTime'] as String,
              body['endTime'] as String));
        }
      case 'DELETE':
        if (path.contains('/carrier/shifts/')) {
          return _Reply(_shift('shift-night', 'Night', '22:00', '06:00', archived: true));
        }
      case 'PUT':
        if (path.endsWith('/shift-assignment')) {
          return const _Reply(<dynamic>[]);
        }
    }
    return null;
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

Future<_Backend> _pump(WidgetTester tester,
    {_Backend? backend, Locale locale = const Locale('en'), double width = 1280}) async {
  tester.view.physicalSize = Size(width, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final _Backend api = backend ?? _backend();
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = api;
  await tester.pumpWidget(_wrap(
    ShiftScheduleScreen(
      api: TrackingApi(dio),
      providerApi: DeliveryProviderApi(dio),
      onboardingApi: OnboardingApi(dio),
    ),
    locale: locale,
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  testWidgets('lists the current shifts, and each rider by name with their shift today',
      (WidgetTester tester) async {
    await _pump(tester);

    expect(find.text(en.attendanceShiftsTitle), findsOneWidget);
    // Once as the shift, once as Nadia's shift today.
    expect(find.text('Beirut Central Day (08:00 - 18:00)'), findsNWidgets(2));
    expect(find.text('Night (22:00 - 06:00)'), findsOneWidget);
    // Retired shifts are history, not choices: folded away under their own heading.
    expect(find.text('Old (06:00 - 12:00)'), findsNothing);
    expect(find.text(en.attendanceRetiredShifts(1)), findsOneWidget);
    expect(find.text('MON · TUE · WED · THU · FRI'), findsOneWidget);
    expect(find.text(en.attendanceShiftOvernight), findsOneWidget);
    expect(find.text(en.attendanceShiftRiders(1)), findsOneWidget);
    expect(find.text(en.attendanceShiftRiders(0)), findsOneWidget);

    expect(find.text('Nadia Haddad'), findsOneWidget);
    expect(find.text('Karim Aoun'), findsOneWidget);
    // No application behind this one: shown by reference rather than not at all.
    expect(find.text('rider-cc'), findsOneWidget);
    // Karim's night shift has not started, so today he is a freelancer — with the change shown.
    expect(find.text(en.attendanceFreelancer), findsNWidgets(2));
    expect(find.textContaining('Night from'), findsOneWidget);
    expect(find.text(en.attendanceUnlinkedRiders(1)), findsOneWidget);

    // Past days are still judged against a retired shift, so it can still be found.
    await tester.tap(find.text(en.attendanceRetiredShifts(1)));
    await tester.pumpAndSettle();
    expect(find.text('Old (06:00 - 12:00)'), findsOneWidget);
  });

  testWidgets('a shift somebody is on cannot be retired; an empty one can',
      (WidgetTester tester) async {
    final _Backend api = await _pump(tester);

    final ConsoleRowAction blocked = tester.widget<ConsoleRowAction>(find.ancestor(
        of: find.byIcon(Icons.archive_outlined).first, matching: find.byType(ConsoleRowAction)));
    expect(blocked.tooltip, en.attendanceRetireBlocked);
    expect(blocked.onPressed, isNull);

    await tester.tap(find.byTooltip(en.attendanceRetireShift));
    await tester.pumpAndSettle();
    // The confirmation says what retiring leaves alone.
    expect(find.text(en.attendanceRetireKeepsHistory), findsOneWidget);
    await tester.tap(find.widgetWithText(ConsoleSoftButton, en.attendanceRetireShift));
    await tester.pumpAndSettle();

    expect(api.sent('DELETE', '/api/tracking/carrier/shifts/shift-night'), hasLength(1));
    expect(find.text(en.attendanceShiftRetired), findsOneWidget);
  });

  testWidgets('a new shift is sent with ISO weekday names and its grace',
      (WidgetTester tester) async {
    final _Backend api = await _pump(tester);

    await tester.tap(find.text(en.attendanceAddShift));
    await tester.pumpAndSettle();
    expect(find.text(en.attendanceShiftImmutable), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, en.attendanceShiftName), 'Night owls');
    await tester.enterText(find.widgetWithText(TextField, en.attendanceShiftStart), '22:00');
    await tester.enterText(find.widgetWithText(TextField, en.attendanceShiftEnd), '06:00');
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text(en.attendanceWeekSat)));
    await tester.pump();
    await tester.tap(find.text(en.attendanceCreateShift));
    await tester.pumpAndSettle();

    final List<RequestOptions> posts = api.sent('POST', '/api/tracking/carrier/shifts');
    expect(posts, hasLength(1));
    expect(posts.single.data, <String, dynamic>{
      'name': 'Night owls',
      'startTime': '22:00',
      'endTime': '06:00',
      'days': <String>['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY'],
      'lateGraceMinutes': 10,
    });
    expect(find.text(en.attendanceShiftCreated), findsOneWidget);
    expect(api.sent('GET', '/api/tracking/carrier/shifts'), hasLength(2));
  });

  testWidgets('a shift that starts and ends at the same time is refused before it is sent',
      (WidgetTester tester) async {
    final _Backend api = await _pump(tester);

    await tester.tap(find.text(en.attendanceAddShift));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, en.attendanceShiftName), 'Broken');
    await tester.enterText(find.widgetWithText(TextField, en.attendanceShiftStart), '08:00');
    await tester.enterText(find.widgetWithText(TextField, en.attendanceShiftEnd), '08:00');
    // enterText does not rebuild; without a frame the button would still hold the check it made
    // against 18:00, which no real click can do.
    await tester.pump();
    await tester.tap(find.text(en.attendanceCreateShift));
    await tester.pumpAndSettle();

    expect(find.text(en.attendanceShiftSameTimes), findsOneWidget);
    expect(api.sent('POST', '/api/tracking/carrier/shifts'), isEmpty);
  });

  testWidgets('a schedule starting today is sent without a date, so the server\'s today decides',
      (WidgetTester tester) async {
    final _Backend api = await _pump(tester);

    // Rows are by name: Karim Aoun first.
    await tester.tap(find.byTooltip(en.attendanceChangeShift).first);
    await tester.pumpAndSettle();
    expect(find.text(en.attendanceAssignTitle('Karim Aoun')), findsOneWidget);

    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text(en.attendanceFreelancer)));
    await tester.pumpAndSettle();
    // A retired shift is never offered.
    expect(find.text('Old (06:00 - 12:00)'), findsNothing);
    await tester.tap(find.text('Beirut Central Day (08:00 - 18:00)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.attendanceAssignSave));
    await tester.pumpAndSettle();

    final List<RequestOptions> puts =
        api.sent('PUT', '/api/tracking/riders/rider-bbbbbbbb/shift-assignment');
    expect(puts, hasLength(1));
    expect(puts.single.data, <String, dynamic>{'shiftId': 'shift-day'});
    expect(find.text(en.attendanceAssignSaved), findsOneWidget);
  });

  testWidgets('a rider\'s attendance opens in place of the page, and back returns to it',
      (WidgetTester tester) async {
    final _Backend api = await _pump(tester);

    // Karim, Nadia, rider-cc: Nadia is the second row.
    await tester.tap(find.byTooltip(en.attendanceOpenAttendance).at(1));
    await tester.pumpAndSettle();

    expect(find.text(en.attendanceTitle), findsOneWidget);
    expect(find.text('Nadia Haddad'), findsOneWidget);
    final RequestOptions read =
        api.sent('GET', '/api/tracking/riders/rider-aaaaaaaa/attendance').single;
    expect(read.queryParameters['month'], _iso(_today).substring(0, 7));

    await tester.tap(find.byTooltip(en.attendanceBackToRiders));
    await tester.pumpAndSettle();
    expect(find.text(en.attendanceShiftsTitle), findsOneWidget);
  });

  testWidgets('a carrier account in no company is told so, with nothing to retry',
      (WidgetTester tester) async {
    await _pump(tester, backend: _backend(trackingStatus: 403));

    expect(find.text(en.noCompanyYet), findsOneWidget);
    expect(find.text(en.tryAgain), findsNothing);
  });

  testWidgets('reads in Arabic at a laptop width', (WidgetTester tester) async {
    await _pump(tester, locale: const Locale('ar'), width: 1024);

    expect(find.text(ar.attendanceShiftsTitle), findsOneWidget);
    expect(find.text(ar.attendanceRidersCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
