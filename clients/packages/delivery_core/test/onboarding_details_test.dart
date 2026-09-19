import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// What an application's free-form answers read as, and where the list of who is hiring comes from.
///
/// The answers are shown as text — in the back office's review drawer and in a company's rider
/// roster — so a list has to read as names ("Achrafieh, Hamra"), never as Dart's "[Achrafieh, Hamra]".
/// And the rider wizard's list of companies is onboarding-service's, because only it knows the
/// regions a company with no zones registered with.
Map<String, dynamic> _application(Object? details) => <String, dynamic>{
      'id': 'app-1',
      'reference': 'REF-app-1',
      'kind': 'RIDER',
      'businessName': 'Nadia Haddad',
      'contactName': 'Nadia Haddad',
      'contactEmail': 'nadia@example.com',
      'contactPhone': null,
      'emailVerifiedAt': '2026-07-01T09:00:00Z',
      'phoneVerifiedAt': null,
      'notes': null,
      'status': 'SUBMITTED',
      'createdAt': '2026-07-01T09:00:00Z',
      'decidedAt': null,
      'decidedBy': null,
      'rejectionReason': null,
      'provisionedUserRef': null,
      'provisionedEntityId': null,
      'details': details,
    };

void main() {
  test('a list reads as its names joined with commas, not as a list', () {
    final OnboardingApplication application = OnboardingApplication.fromJson(_application(
        <String, dynamic>{
          'companyRegions': <dynamic>['Achrafieh', ' Hamra '],
          'coverage': <dynamic>['Beirut', 'Mount Lebanon'],
        }));

    expect(application.details['companyRegions'], 'Achrafieh, Hamra');
    expect(application.details['coverage'], 'Beirut, Mount Lebanon');
  });

  test('an empty list is no answer, left out like a null, and blank entries are skipped', () {
    final OnboardingApplication application = OnboardingApplication.fromJson(_application(
        <String, dynamic>{
          'companyRegions': <dynamic>[],
          'capabilities': <dynamic>['', null, 'Cold chain'],
          'workRegion': null,
          'vehicleType': 'MOTORCYCLE',
        }));

    expect(application.details.containsKey('companyRegions'), isFalse);
    expect(application.details.containsKey('workRegion'), isFalse);
    expect(application.details['capabilities'], 'Cold chain');
    expect(application.details['vehicleType'], 'MOTORCYCLE');
  });

  test('a list is also kept entry by entry, even when an entry holds a comma', () {
    final OnboardingApplication application = OnboardingApplication.fromJson(_application(
        <String, dynamic>{
          'companyRegions': <dynamic>['Mar Mikhael, Beirut', ' Hamra ', '', null],
          'emptyList': <dynamic>[],
          'vehicleType': 'MOTORCYCLE',
        }));

    expect(application.detailLists['companyRegions'], <String>['Mar Mikhael, Beirut', 'Hamra']);
    expect(application.details['companyRegions'], 'Mar Mikhael, Beirut, Hamra');
    // Only lists, and only lists with something in them.
    expect(application.detailLists.keys, <String>['companyRegions']);
    expect(OnboardingApplication.fromJson(_application(null)).detailLists, isEmpty);
  });

  test('everything else still reads as it did: false and 0 survive, and a number is its digits', () {
    final OnboardingApplication application = OnboardingApplication.fromJson(_application(
        <String, dynamic>{'agreed': false, 'fleetSize': 0, 'workLatitude': 33.89}));

    expect(application.details['agreed'], 'false');
    expect(application.details['fleetSize'], '0');
    expect(application.details['workLatitude'], '33.89');
  });

  test("the rider wizard's companies come from onboarding-service, with each region", () async {
    final _Recorder server = _Recorder(<Map<String, Object?>>[
      <String, Object?>{
        'id': 'fresh-id',
        'name': 'Fresh Fleet',
        'regions': <String>['Beirut', 'Mount Lebanon'],
      },
    ]);
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = server;

    final List<HiringCompany> companies = await OnboardingApi(dio).hiringCompanies();

    expect(server.calls, <String>['GET /api/onboarding/hiring-companies']);
    expect(server.authorization, isNull, reason: 'somebody applying has no account yet');
    expect(companies.single.name, 'Fresh Fleet');
    expect(companies.single.regions, <String>['Beirut', 'Mount Lebanon']);
  });
}

/// Answers every request with [body], and remembers what was asked.
class _Recorder implements HttpClientAdapter {
  _Recorder(this.body);

  final Object body;
  final List<String> calls = <String>[];
  Object? authorization;

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    authorization = options.headers['Authorization'];
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
