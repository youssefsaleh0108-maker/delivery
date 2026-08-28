import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/carrier/company_screen.dart';
import 'package:delivery_portal/src/shell/console_controls.dart';
import 'package:delivery_portal/src/shell/shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Riders Management — Figma `carrier-riders` (3:3589).
///
/// The design's table has seven columns and six of them can now be filled from something real:
/// presence from the tracking roster, region and join date from the rider's own application,
/// deliveries from the loaded page of work. The seventh — a rating — has no source anywhere on this
/// platform and stays empty, because a plausible number in that column is the one a company would
/// act on hardest.
///
/// Both row actions are live here: the drawer that says everything the platform knows about one
/// rider, and the suspension that stops them being offered work.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.responses, {this.failing = const <String>{}});

  /// `METHOD path-suffix` or a bare path suffix. Longest match wins, so a specific route beats the
  /// prefix it hangs off.
  final Map<String, Object> responses;
  final Set<String> failing;
  final List<String> calls = <String>[];
  final List<Object?> bodies = <Object?>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    bodies.add(options.data);

    for (final String path in failing) {
      if (options.path.contains(path)) {
        return ResponseBody.fromString('{"message":"no"}', 404);
      }
    }

    final List<String> matches = responses.keys.where((String key) {
      String suffix = key;
      final int space = key.indexOf(' ');
      if (space >= 0) {
        if (options.method != key.substring(0, space)) return false;
        suffix = key.substring(space + 1);
      }
      // A leading '=' means the path has to END there — the only way to tell a collection's route
      // from the routes that hang off it.
      if (suffix.startsWith('=')) return options.path.endsWith(suffix.substring(1));
      return options.path.contains(suffix);
    }).toList()
      ..sort((String a, String b) => b.length.compareTo(a.length));

    if (matches.isEmpty) return ResponseBody.fromString('{}', 404);
    return ResponseBody.fromString(jsonEncode(responses[matches.first]), 200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _company({
  String status = 'ACTIVE',
  bool canTakeWork = true,
}) =>
    <String, dynamic>{
      'id': 'p1',
      'slug': 'swift',
      'name': 'Swift Couriers',
      'kind': 'EXTERNAL',
      'status': status,
      'canTakeWork': canTakeWork,
      'ownerRef': null,
      'accountRef': 'ACC-CARRIER',
      'contactName': 'Cara',
      'contactPhone': '+100',
      'payoutState': 'VERIFIED',
    };

Map<String, dynamic> _score({int score = 84, bool provisional = false, double completion = 0.96}) =>
    <String, dynamic>{
      'providerId': 'p1',
      'name': 'Swift Couriers',
      'score': score,
      'orders': provisional ? 3 : 120,
      'completionRate': completion,
      'avgSecondsToClaim': 240,
      'avgSecondsOnRoad': 1080,
      'provisional': provisional,
    };

Map<String, dynamic> _job({
  required String id,
  String status = 'DELIVERED',
  String? riderId = 'rider-aaaaaaaa',
}) =>
    <String, dynamic>{
      'id': id,
      'customerId': 'c1',
      'merchantId': 'm1',
      'riderId': riderId,
      'status': status,
      'totalAmount': 50.0,
      'deliveryAddress': '12 Bliss Street',
      'deliveryFee': 5.0,
      'contactPhone': '+100',
      'notes': null,
      'items': <dynamic>[],
      'availableActions': <dynamic>[],
      'placedAt': '2026-08-16T09:00:00Z',
      'deliveredAt': status == 'DELIVERED' ? '2026-08-16T10:00:00Z' : null,
      'cancelReason': null,
    };

Map<String, dynamic> _page(List<Map<String, dynamic>> jobs) => <String, dynamic>{
      'content': jobs,
      'page': 0,
      'size': 100,
      'totalElements': jobs.length,
      'totalPages': 1,
    };

Map<String, dynamic> _application({
  required String id,
  required String name,
  String status = 'PROVISIONED',
  String? riderRef,
  Map<String, String> details = const <String, String>{},
}) =>
    <String, dynamic>{
      'id': id,
      'reference': 'REF-$id',
      'kind': 'RIDER',
      'businessName': name,
      'contactName': name,
      'contactEmail': '${name.split(' ').first.toLowerCase()}@example.com',
      'contactPhone': '+96170000000',
      'emailVerifiedAt': '2026-07-01T09:00:00Z',
      'phoneVerifiedAt': null,
      'notes': null,
      'status': status,
      'createdAt': '2026-07-01T09:00:00Z',
      'decidedAt': status == 'PROVISIONED' ? '2026-07-04T09:00:00Z' : null,
      'decidedBy': null,
      'rejectionReason': null,
      'provisionedUserRef': riderRef,
      'provisionedEntityId': null,
      'details': details,
    };

Map<String, dynamic> _presence(String riderId, {String state = 'ON_DUTY'}) => <String, dynamic>{
      'riderId': riderId,
      'carrierId': 'p1',
      'dutyState': state == 'OFF_DUTY' ? 'OFF_DUTY' : 'ON_DUTY',
      'state': state,
      'dutyChangedAt': '2026-08-16T07:00:00Z',
      'lastSeenAt': '2026-08-16T09:30:00Z',
      'lat': 33.9,
      'lng': 35.5,
      'accuracyM': 12.0,
    };

late _StubAdapter _adapter;

typedef CarrierApis = ({
  DeliveryProviderApi provider,
  OrderApi order,
  OnboardingApi onboarding,
  PartnerManagementApi management,
  TrackingApi tracking,
  RiderPerformanceApi performance,
});

CarrierApis _apis({
  Map<String, dynamic>? company,
  Map<String, dynamic>? score,
  List<String> riders = const <String>['rider-aaaaaaaa', 'rider-bbbbbbbb'],
  List<Map<String, dynamic>>? jobs,
  List<Map<String, dynamic>>? applications,
  List<Map<String, dynamic>>? roster,
  bool suspended = false,
  Set<String> failing = const <String>{},
}) {
  _adapter = _StubAdapter(
    <String, Object>{
      '/my-company/score': score ?? _score(),
      '/my-company/riders': <String, dynamic>{'providerId': 'p1', 'riders': riders},
      '/my-company/pause': _company(status: 'PAUSED', canTakeWork: false),
      '/my-company/resume': _company(),
      '/my-company': company ?? _company(),
      '/orders/carrier': _page(jobs ??
          <Map<String, dynamic>>[
            _job(id: 'aaaaaaaa11'),
            _job(id: 'bbbbbbbb22', status: 'PICKED_UP', riderId: 'rider-bbbbbbbb'),
          ]),
      'GET =/applications/for-company/p1': applications ??
          <Map<String, dynamic>>[
            _application(
              id: 'app-1',
              name: 'Nadia Haddad',
              riderRef: 'rider-aaaaaaaa',
              details: const <String, String>{'workRegion': 'Beirut'},
            ),
            _application(id: 'app-2', name: 'Karim Aoun', status: 'SUBMITTED'),
          ],
      '/suspension': <String, dynamic>{
        'suspended': suspended,
        'lastChange': suspended
            ? <String, dynamic>{
                'suspended': true,
                'reason': 'POLICY_VIOLATION',
                'reasonNote': 'Third missed shift',
                'actor': 'kc-boss',
                'at': '2026-08-15T09:00:00Z',
              }
            : null,
        'history': <dynamic>[],
      },
      '/suspend': <String, dynamic>{'suspended': true, 'lastChange': null},
      '/unsuspend': <String, dynamic>{'suspended': false, 'lastChange': null},
      '/approve': _application(id: 'app-2', name: 'Karim Aoun', riderRef: 'rider-cccccccc'),
      '/tracking/riders/roster':
          roster ?? <Map<String, dynamic>>[_presence('rider-aaaaaaaa')],
      '/duty/hours': <String, dynamic>{
        'riderId': 'rider-aaaaaaaa',
        'zone': 'UTC',
        'from': '2026-08-15',
        'to': '2026-08-16',
        'days': <Map<String, dynamic>>[
          <String, dynamic>{
            'date': '2026-08-16',
            'secondsOnline': 5400,
            'hoursOnline': 1.5,
            'sessions': 2,
          },
        ],
      },
      '/performance': <String, dynamic>{
        'riderId': 'rider-aaaaaaaa',
        'windowDays': 30,
        'claimed': 12,
        'delivered': 11,
        'cancelledAfterClaim': 1,
        'completionRate': 91.67,
      },
      '/riders/delivered-today': <Map<String, dynamic>>[
        <String, dynamic>{'riderId': 'rider-aaaaaaaa', 'delivered': 3, 'day': '2026-08-16'},
      ],
    },
    failing: failing,
  );
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = _adapter;
  return (
    provider: DeliveryProviderApi(dio),
    order: OrderApi(dio),
    onboarding: OnboardingApi(dio),
    management: PartnerManagementApi(dio),
    tracking: TrackingApi(dio),
    performance: RiderPerformanceApi(dio),
  );
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

Future<void> pump(
  WidgetTester tester,
  CarrierApis apis, {
  Locale locale = const Locale('en'),
  double width = 1180,
  /// The portal shell still builds this screen with two APIs; false mounts it that way.
  bool wired = true,
}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_wrap(
    CompanyScreen(
      api: apis.provider,
      orderApi: apis.order,
      onboardingApi: wired ? apis.onboarding : null,
      managementApi: wired ? apis.management : null,
      trackingApi: wired ? apis.tracking : null,
      performanceApi: wired ? apis.performance : null,
    ),
    locale: locale,
  ));
  await tester.pumpAndSettle();
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  testWidgets('is the design table, with all seven columns', (WidgetTester tester) async {
    await pump(tester, _apis());

    expect(find.text('Riders Management'), findsOneWidget);
    for (final String column in <String>[
      'Rider Name',
      'Status',
      'Region',
      'Deliveries',
      'Rating',
      'Join Date',
      'Actions',
    ]) {
      expect(find.text(column), findsOneWidget, reason: column);
    }
    expect(find.byType(ConsoleNameCell), findsNWidgets(2));
  });

  testWidgets('fills every column that has a source, and only those',
      (WidgetTester tester) async {
    await pump(tester, _apis());

    // Name and region and join date off the rider's own application; presence off the roster;
    // deliveries off the job board.
    expect(find.text('Nadia Haddad'), findsOneWidget);
    expect(find.text('Beirut'), findsOneWidget);
    expect(find.text('Jul 04, 2026'), findsOneWidget);
    expect(find.widgetWithText(ConsoleStatusPill, 'On duty'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    // The rider the platform attached directly has no application, so his row keeps the reference
    // and dashes what nobody recorded. Rating is dashed on both rows.
    expect(find.text('RIDER-BB'), findsWidgets);
    expect(find.textContaining('Rating is not recorded'), findsOneWidget);
  });

  testWidgets('a job board that did not load does not become a row of zeroes',
      (WidgetTester tester) async {
    await pump(tester, _apis(failing: const <String>{'/orders/carrier'}));

    expect(find.text('0'), findsNothing);
    expect(find.textContaining('could not be read just now'), findsOneWidget);
  });

  testWidgets('presence falls back to the job board when tracking cannot be read',
      (WidgetTester tester) async {
    await pump(tester, _apis(failing: const <String>{'/tracking/riders/roster'}));

    // rider-bb is out on a job that has not finished; rider-aa's is delivered.
    expect(find.widgetWithText(ConsoleStatusPill, 'On a job'), findsOneWidget);
    expect(find.widgetWithText(ConsoleStatusPill, 'On duty'), findsNothing);
  });

  testWidgets('Add New Rider approves somebody who is actually waiting',
      (WidgetTester tester) async {
    // Riders reach a fleet by applying and being approved — so the design's primary button opens
    // the people waiting for exactly that, rather than a form nothing can submit.
    await pump(tester, _apis());

    final Finder button = find.widgetWithText(ConsolePrimaryButton, 'Add New Rider');
    expect(tester.widget<ConsolePrimaryButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('Karim Aoun'), findsOneWidget);
    await tester.tap(find.widgetWithText(ConsoleButton, 'Approve'));
    await tester.pumpAndSettle();

    expect(
      _adapter.calls.any((String c) =>
          c.startsWith('POST') && c.contains('/for-company/p1/app-2/approve')),
      isTrue,
    );
    expect(find.text('On your fleet'), findsOneWidget);
  });

  testWidgets('the eye opens everything the platform knows about one rider',
      (WidgetTester tester) async {
    await pump(tester, _apis());

    await tester.tap(find.byTooltip('Rider detail').first);
    await tester.pumpAndSettle();

    // Presence, today, the thirty-day record in this company's own scope, and the week of hours.
    expect(find.text('PRESENCE'), findsOneWidget);
    expect(find.text('3'), findsWidgets); // delivered today
    expect(find.text('91.67%'), findsOneWidget);
    expect(find.text('1.50 h'), findsWidgets);
    // The endpoint sends only dates with time on them; the client draws the rest of the window.
    expect(find.text('0.00 h'), findsOneWidget);
    expect(find.textContaining('UTC zone'), findsOneWidget);
  });

  testWidgets('a rider with no claimed work shows a dash, never 0% or 100%',
      (WidgetTester tester) async {
    await pump(tester, _apis());
    _adapter.responses['/performance'] = <String, dynamic>{
      'riderId': 'rider-aaaaaaaa',
      'windowDays': 30,
      'claimed': 0,
      'delivered': 0,
      'cancelledAfterClaim': 0,
      'completionRate': null,
    };

    await tester.tap(find.byTooltip('Rider detail').first);
    await tester.pumpAndSettle();

    expect(find.text('—'), findsWidgets);
    expect(find.text('0.00%'), findsNothing);
    expect(find.text('100.00%'), findsNothing);
  });

  testWidgets('suspending a rider sends the typed reason the server insists on',
      (WidgetTester tester) async {
    await pump(tester, _apis());

    await tester.tap(find.byTooltip('Suspend this rider'));
    await tester.pumpAndSettle();

    // Dead until a reason is chosen: "suspended" with no reason is not a record anybody can act on.
    final Finder confirm = find.widgetWithText(ConsoleSoftButton, 'Suspend rider');
    expect(tester.widget<ConsoleSoftButton>(confirm).onPressed, isNull);

    await tester.tap(find.text('Choose a reason'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Policy violation').last);
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(
      _adapter.calls.any((String c) =>
          c.startsWith('POST') && c.contains('/for-company/p1/app-1/suspend')),
      isTrue,
    );
    expect(
      _adapter.bodies.any((Object? b) => b is Map && b['reason'] == 'POLICY_VIOLATION'),
      isTrue,
    );
  });

  testWidgets('a suspended rider reads as suspended and is offered reinstatement',
      (WidgetTester tester) async {
    await pump(tester, _apis(suspended: true));

    expect(find.widgetWithText(ConsoleStatusPill, 'Suspended'), findsOneWidget);
    expect(find.byTooltip('Reinstate this rider'), findsOneWidget);

    await tester.tap(find.byTooltip('Reinstate this rider'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ConsolePrimaryButton, 'Reinstate rider'));
    await tester.pumpAndSettle();

    expect(
      _adapter.calls.any((String c) =>
          c.startsWith('POST') && c.contains('/for-company/p1/app-1/unsuspend')),
      isTrue,
    );
  });

  testWidgets('a rider with no application cannot be suspended, and says why',
      (WidgetTester tester) async {
    // The endpoint is addressed to a rider's application to this company. Somebody the platform
    // attached directly has none, and a button that would 422 is worse than one that explains.
    await pump(tester, _apis());

    expect(
      find.byTooltip(
          'No application on file for this rider — the platform attached them directly'),
      findsOneWidget,
    );
  });

  testWidgets('without the new clients the page still draws its fleet',
      (WidgetTester tester) async {
    await pump(tester, _apis(), wired: false);

    expect(find.text('RIDER-AA'), findsOneWidget);
    expect(find.text('Nadia Haddad'), findsNothing);
    expect(
      tester
          .widget<ConsolePrimaryButton>(
              find.widgetWithText(ConsolePrimaryButton, 'Add New Rider'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('shows the score and what it is made of', (WidgetTester tester) async {
    await pump(tester, _apis());

    // The number alone is a verdict nobody can act on; the parts are the target.
    expect(find.text('84'), findsOneWidget);
    expect(find.text('96%'), findsOneWidget);
    expect(find.text('4m'), findsOneWidget);
    expect(find.text('18m'), findsOneWidget);
    expect(find.textContaining('decides how much work'), findsOneWidget);
  });

  testWidgets('a provisional score says so rather than looking earned',
      (WidgetTester tester) async {
    await pump(tester, _apis(score: _score(score: 70, provisional: true, completion: 1)));

    expect(find.text(en.tooEarlyToTell), findsOneWidget);
    expect(find.textContaining('benefit of the doubt'), findsOneWidget);
  });

  testWidgets('a carrier can still stop taking orders', (WidgetTester tester) async {
    await pump(tester, _apis());

    expect(find.text(en.youAreTakingOrders), findsOneWidget);
    await tester.tap(find.widgetWithText(ConsolePrimaryButton, en.pauseNewOrders));
    await tester.pumpAndSettle();

    expect(_adapter.calls.any((String c) => c.contains('POST') && c.contains('/my-company/pause')),
        isTrue);
  });

  testWidgets('a suspended carrier is not offered a button that would fail',
      (WidgetTester tester) async {
    // Suspension is the platform's decision and a carrier cannot resume out of it. A button that
    // silently fails would be worse than no button.
    await pump(tester, _apis(company: _company(status: 'SUSPENDED', canTakeWork: false)));

    expect(find.textContaining('suspended'), findsWidgets);
    expect(find.widgetWithText(ConsolePrimaryButton, en.startTakingOrders), findsNothing);
  });

  testWidgets('an empty fleet is called out, not left to be inferred',
      (WidgetTester tester) async {
    // A company with no riders looks available and can collect nothing — the most confusing way to
    // be sent no work.
    await pump(tester, _apis(riders: const <String>[]));

    expect(find.textContaining('no riders'), findsOneWidget);
  });

  testWidgets('the parts that are still translated stay translated',
      (WidgetTester tester) async {
    // The console's own chrome is English-only in this wave; the score and availability cards were
    // localised before it and stay that way.
    await pump(tester, _apis(), locale: const Locale('ar'));

    expect(find.text(ar.howYouAreDoing), findsOneWidget);
    expect(find.text(en.howYouAreDoing), findsNothing);
    expect(Directionality.of(tester.element(find.byType(CompanyScreen))), TextDirection.rtl);
  });

  // What a 1440 / 1280 / 1024 window leaves the content column once the 260px rail has its share.
  // The table scrolls sideways below its own minimum rather than compressing; the cards under it
  // stack. An overflow fails the test.
  for (final double width in <double>[1180, 1020, 764]) {
    testWidgets('lays out at a ${width.toInt()}px content column', (WidgetTester tester) async {
      await pump(tester, _apis(), width: width);
      expect(tester.takeException(), isNull);
    });
  }
}
