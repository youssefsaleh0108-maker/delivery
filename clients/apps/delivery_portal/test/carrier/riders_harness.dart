import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/carrier/rider_profile_screen.dart';
import 'package:delivery_portal/src/carrier/riders_directory_screen.dart';
import 'package:delivery_portal/src/shell/shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The carrier's Riders HR pages, stubbed at the HTTP edge — shared by the directory's tests and
/// the profile's.
///
/// Shared rather than copied into both files because both mount the same screen. A rider's profile
/// is only reached through the directory's "Manage Profile", so the profile's tests arrive the way
/// a dispatcher does, and one fleet fixture cannot disagree with itself about who is on it.
///
/// The stub answers only fleet-wide reads for ratings and standing: the fleet's ratings in one
/// response, and each application carrying its standing. There is no per-rider rating or standing
/// route, so a page that went back to asking once per rider would find nothing to read.
///
/// The fleet, unless a test says otherwise:
///
/// * [nadia] — Nadia Haddad, hired through her application (`app-1`, reference `REF-app-1`): she
///   gave Beirut and a motorcycle, is in good standing, is on duty, is rated 4.5 over four ratings
///   (three of them five stars), delivered three today, and has one delivered job on the board.
/// * [direct] — attached by the platform directly, so there is no application: no name, region,
///   vehicle, papers or standing. Absent from the roster, unrated, and out on a job that has not
///   finished.
/// * Waiting to be hired: Karim Aoun (`app-2`).
const String nadia = 'rider-aaaaaaaa';
const String direct = 'rider-bbbbbbbb';

final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

/// Routes by path fragment, and records what was asked.
class StubAdapter implements HttpClientAdapter {
  StubAdapter(this.responses, {this.failing = const <String, (int, Object?)>{}});

  /// `METHOD fragment` or a bare fragment, to the JSON body. Longest match wins, so a specific route
  /// beats the prefix it hangs off; a fragment starting with '=' must END the path, the only way to
  /// tell a collection's route from the routes under it.
  final Map<String, Object> responses;

  /// Routes that refuse, matched the same way and checked first: a status, and the body the screen
  /// reads from it (null sends a plain message).
  final Map<String, (int, Object?)> failing;

  final List<String> calls = <String>[];
  final List<Object?> bodies = <Object?>[];

  static const Map<String, List<String>> _json = <String, List<String>>{
    Headers.contentTypeHeader: <String>[Headers.jsonContentType],
  };

  static bool _matches(String key, RequestOptions options) {
    String fragment = key;
    final int space = key.indexOf(' ');
    if (space >= 0) {
      if (options.method != key.substring(0, space)) return false;
      fragment = key.substring(space + 1);
    }
    if (fragment.startsWith('=')) return options.path.endsWith(fragment.substring(1));
    return options.path.contains(fragment);
  }

  static String? _best(Iterable<String> keys, RequestOptions options) {
    final List<String> hits = keys.where((String k) => _matches(k, options)).toList()
      ..sort((String a, String b) => b.length.compareTo(a.length));
    return hits.isEmpty ? null : hits.first;
  }

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    bodies.add(options.data);

    final String? refusal = _best(failing.keys, options);
    if (refusal != null) {
      final (int status, Object? body) = failing[refusal]!;
      return ResponseBody.fromString(
          jsonEncode(body ?? <String, dynamic>{'message': 'no'}), status,
          headers: _json);
    }

    final String? route = _best(responses.keys, options);
    if (route == null) {
      return ResponseBody.fromString('{"message":"no route"}', 404, headers: _json);
    }
    return ResponseBody.fromString(jsonEncode(responses[route]), 200, headers: _json);
  }

  @override
  void close({bool force = false}) {}
}

// ---------------------------------------------------------------------------------- fixtures

Map<String, dynamic> companyJson({String status = 'ACTIVE', bool canTakeWork = true}) =>
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

Map<String, dynamic> scoreJson({int score = 84, bool provisional = false, double completion = 0.96}) =>
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

Map<String, dynamic> jobJson({
  required String id,
  String status = 'DELIVERED',
  String? riderId = nadia,
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

/// An application as the company's own listing sends it. [suspended] is the standing the listing
/// carries for every application; null is a listing that did not say.
Map<String, dynamic> applicationJson({
  required String id,
  required String name,
  String status = 'PROVISIONED',
  String? riderRef,
  Map<String, Object?> details = const <String, Object?>{},
  bool? suspended = false,
  bool decided = true,
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
      'decidedAt': status == 'PROVISIONED' && decided ? '2026-07-04T09:00:00Z' : null,
      'decidedBy': null,
      'rejectionReason': null,
      'provisionedUserRef': riderRef,
      'provisionedEntityId': null,
      'details': details,
      'suspended': suspended,
    };

Map<String, dynamic> presenceJson(String riderId, {String state = 'ON_DUTY'}) =>
    <String, dynamic>{
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

/// A rating aggregate as the order service sends it: every star key present, and an average only
/// when somebody has rated.
Map<String, dynamic> standingJson(String riderId, {double? average, Map<int, int> stars = const <int, int>{}}) =>
    <String, dynamic>{
      'riderId': riderId,
      'average': average,
      'ratings': stars.values.fold<int>(0, (int sum, int n) => sum + n),
      'stars': <String, int>{for (int s = 1; s <= 5; s++) '$s': stars[s] ?? 0},
    };

Map<String, dynamic> documentJson(
  String id,
  String kind,
  String status, {
  bool superseded = false,
  String? viewUrl,
}) =>
    <String, dynamic>{
      'id': id,
      'kind': kind,
      'status': status,
      'rejectionReason': status == 'REJECTED' ? 'Too blurred to read' : null,
      'reviewerNote': null,
      'uploadedAt': '2026-07-01T09:00:00Z',
      'reviewedAt': status == 'PENDING' ? null : '2026-07-02T09:00:00Z',
      'reviewedBy': null,
      'superseded': superseded,
      'viewUrl': viewUrl,
    };

Map<String, dynamic> performanceJson({
  int claimed = 12,
  int delivered = 11,
  int cancelledAfterClaim = 1,
  double? completionRate = 91.67,
}) =>
    <String, dynamic>{
      'riderId': nadia,
      'windowDays': 30,
      'claimed': claimed,
      'delivered': delivered,
      'cancelledAfterClaim': cancelledAfterClaim,
      'completionRate': completionRate,
    };

/// Thirty days, 13 August to 11 September inclusive, of which only two had a delivery — the server
/// sends no zero rows.
Map<String, dynamic> dailyJson({List<Map<String, dynamic>>? days}) => <String, dynamic>{
      'riderId': nadia,
      'zone': 'Asia/Beirut',
      'from': '2026-08-13',
      'to': '2026-09-11',
      'days': days ??
          <Map<String, dynamic>>[
            <String, dynamic>{'date': '2026-09-01', 'delivered': 4},
            <String, dynamic>{'date': '2026-09-03', 'delivered': 2},
          ],
    };

Map<String, dynamic> hoursJson() => <String, dynamic>{
      'riderId': nadia,
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
    };

// ---------------------------------------------------------------------------------- the stub

/// Every client the Riders HR pages read, on one stubbed connection.
class FleetStub {
  FleetStub({
    List<String> riders = const <String>[nadia, direct],
    List<Map<String, dynamic>>? jobs,
    List<Map<String, dynamic>>? applications,
    List<Map<String, dynamic>>? roster,
    bool? suspended = false,
    List<Map<String, dynamic>>? ratings,
    List<Map<String, dynamic>>? deliveredToday,
    List<Map<String, dynamic>>? documents,
    Map<String, dynamic>? performance,
    Map<String, dynamic>? daily,
    Map<String, dynamic>? company,
    Map<String, dynamic>? score,
    Map<String, (int, Object?)> failing = const <String, (int, Object?)>{},
  }) {
    adapter = StubAdapter(
      <String, Object>{
        '/my-company/score': score ?? scoreJson(),
        '/my-company/riders': <String, dynamic>{'providerId': 'p1', 'riders': riders},
        // The whole fleet's ratings in one response — every rider on it, the unrated included.
        '/my-company/riders/ratings': ratings ??
            <Map<String, dynamic>>[
              standingJson(nadia, average: 4.5, stars: const <int, int>{3: 1, 5: 3}),
              standingJson(direct),
            ],
        'POST /my-company/riders/': <String, dynamic>{},
        '/my-company/pause': companyJson(status: 'PAUSED', canTakeWork: false),
        '/my-company/resume': companyJson(),
        '/my-company': company ?? companyJson(),
        '/orders/carrier': <String, dynamic>{
          'content': jobs ??
              <Map<String, dynamic>>[
                jobJson(id: 'aaaaaaaa11'),
                jobJson(id: 'bbbbbbbb22', status: 'PICKED_UP', riderId: direct),
              ],
          'page': 0,
          'size': 100,
          'totalElements': 2,
          'totalPages': 1,
        },
        'GET =/applications/for-company/p1': applications ??
            <Map<String, dynamic>>[
              applicationJson(
                id: 'app-1',
                name: 'Nadia Haddad',
                riderRef: nadia,
                suspended: suspended,
                // The keys the rider wizard writes today (mobile_app partner_application_screen).
                details: const <String, String>{
                  'preferredArea': 'Beirut',
                  'vehicleType': 'MOTORCYCLE',
                  'vehicleModel': 'Honda Wave',
                  'vehicleYear': '2021',
                  'plateNumber': 'B 123456',
                  'dateOfBirth': '1998-03-14',
                  'nationalId': 'LB-000123456',
                  'ridesFor': 'Swift Couriers',
                  'workLatitude': '33.89',
                  'workLongitude': '35.5',
                },
              ),
              applicationJson(id: 'app-2', name: 'Karim Aoun', status: 'SUBMITTED'),
            ],
        '/suspend': <String, dynamic>{'suspended': true, 'lastChange': null},
        '/unsuspend': <String, dynamic>{'suspended': false, 'lastChange': null},
        '/approve': applicationJson(id: 'app-2', name: 'Karim Aoun', riderRef: 'rider-cccccccc'),
        '/tracking/riders/roster': roster ?? <Map<String, dynamic>>[presenceJson(nadia)],
        '/duty/hours': hoursJson(),
        '/performance/daily': daily ?? dailyJson(),
        '/performance': performance ?? performanceJson(),
        '/riders/delivered-today': deliveredToday ??
            <Map<String, dynamic>>[
              <String, dynamic>{'riderId': nadia, 'delivered': 3, 'day': '2026-08-16'},
            ],
        '/documents': documents ??
            <Map<String, dynamic>>[
              documentJson('d1', 'NATIONAL_ID', 'APPROVED',
                  viewUrl: 'https://files.example/national-id.jpg'),
              // Replaced by d1, and refused: shown, it would contradict the verdict on the paper
              // the rider actually rides on.
              documentJson('d0', 'NATIONAL_ID', 'REJECTED', superseded: true),
              documentJson('d2', 'DRIVING_LICENCE', 'PENDING'),
            ],
      },
      failing: failing,
    );

    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;
    providerApi = DeliveryProviderApi(dio);
    orderApi = OrderApi(dio);
    onboardingApi = OnboardingApi(dio);
    managementApi = PartnerManagementApi(dio);
    trackingApi = TrackingApi(dio);
    performanceApi = RiderPerformanceApi(dio);
    documentsApi = DocumentsApi(dio);
  }

  late final StubAdapter adapter;

  // Suffixed, because `performance` and `documents` already name fixtures a test hands in above.
  late final DeliveryProviderApi providerApi;
  late final OrderApi orderApi;
  late final OnboardingApi onboardingApi;
  late final PartnerManagementApi managementApi;
  late final TrackingApi trackingApi;
  late final RiderPerformanceApi performanceApi;
  late final DocumentsApi documentsApi;

  /// Whether a request with this method went to a path containing [fragment].
  bool called(String method, String fragment) =>
      adapter.calls.any((String c) => c.startsWith('$method ') && c.contains(fragment));
}

// ---------------------------------------------------------------------------------- mounting

Widget wrap(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
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

/// Mounts the directory at a content-column [width] — what a 1440 / 1280 / 1024 window leaves once
/// the 260px rail has its share is 1180 / 1020 / 764. Tall, because the page scrolls and a short
/// viewport makes every `findsNothing` below the fold pass for the wrong reason.
Future<void> pumpDirectory(
  WidgetTester tester,
  FleetStub stub, {
  Locale locale = const Locale('en'),
  double width = 1180,
  double height = 2400,
  List<RiderPage> riderPages = const <RiderPage>[],
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(wrap(
    RidersDirectoryScreen(
      api: stub.providerApi,
      orderApi: stub.orderApi,
      onboardingApi: stub.onboardingApi,
      managementApi: stub.managementApi,
      trackingApi: stub.trackingApi,
      performanceApi: stub.performanceApi,
      documentsApi: stub.documentsApi,
      // No notification client, so no bell: its poll would outlive every test.
      riderPages: riderPages,
    ),
    locale: locale,
  ));
  await tester.pumpAndSettle();
}

/// Opens the profile of the [index]th card on the grid through its "Manage Profile", the way a
/// dispatcher gets there.
Future<void> openProfile(WidgetTester tester, {int index = 0, DeliveryStrings? strings}) async {
  final Finder button =
      find.widgetWithText(ConsoleButton, (strings ?? en).carrRidersManageProfile).at(index);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}
