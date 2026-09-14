import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// The contracts the services signup (Figma 126:11) and the provider's shop bootstrap stand on.
///
/// What is pinned is what goes wrong quietly: a category this build cannot name offered under a
/// guessed label, a receipt from any other application read as a services one, a dropped connection
/// read as "no application" — which would skip opening a provider's shop without a word — and the
/// shop opened with anything but the SERVICES vertical and its category.
class _Server implements HttpClientAdapter {
  _Server(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );

Dio _dio(_Server server) => Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = server;

void main() {
  group('the signup options', () {
    test('keep the open categories this build can name, in order, and the usable areas', () {
      final ServiceSignupOptions options = ServiceSignupOptions.fromJson(<String, dynamic>{
        'categories': <Object?>['PRINTING', 'KNITTING', 'REPAIRS', 7, null],
        'areas': <Object?>[
          <String, dynamic>{'zoneId': 'z-1', 'name': 'Mar Mikhael'},
          <String, dynamic>{'zoneId': '', 'name': 'No id'},
          <String, dynamic>{'zoneId': 'z-3'},
          'Hamra',
        ],
      });

      expect(options.categories, <ServiceCategory>[ServiceCategory.printing, ServiceCategory.repairs]);
      expect(options.areas.map((ServiceArea a) => a.name), <String>['Mar Mikhael']);
    });

    test('are read from the open onboarding endpoint', () async {
      final _Server server = _Server((_) => _json(<String, dynamic>{
            'categories': <String>['TAILORING'],
            'areas': <Map<String, String>>[
              <String, String>{'zoneId': 'z-2', 'name': 'Hamra'},
            ],
          }));

      final ServiceSignupOptions options = await OnboardingApi(_dio(server)).serviceOptions();

      expect(server.requests.single.method, 'GET');
      expect(server.requests.single.path, '/api/onboarding/service-options');
      expect(options.categories, <ServiceCategory>[ServiceCategory.tailoring]);
      expect(options.areas.single, const ServiceArea(zoneId: 'z-2', name: 'Hamra'));
    });
  });

  group('the applicant receipt', () {
    Map<String, dynamic> receipt(Object? service) => <String, dynamic>{
          'reference': 'ref-1',
          'status': 'APPROVED',
          'businessName': 'Al Fakhry Press',
          'kind': 'MERCHANT',
          'service': service,
        };

    test('carries the category and area of an application to offer services', () {
      final OnboardingApplication application = OnboardingApplication.fromJson(receipt(
          <String, dynamic>{'category': 'PRINTING', 'zoneId': 'z-1', 'area': 'Mar Mikhael'}));

      expect(application.service, isNotNull);
      expect(application.service!.category, ServiceCategory.printing);
      expect(application.service!.zoneId, 'z-1');
      expect(application.service!.area, 'Mar Mikhael');
    });

    test('carries nothing for any other application', () {
      expect(OnboardingApplication.fromJson(receipt(null)).service, isNull);
      expect(OnboardingApplication.fromJson(<String, dynamic>{'reference': 'r'}).service, isNull);
    });

    test('keeps a category this build cannot name, without naming it', () {
      final ServiceApplicationAnswers answers = OnboardingApplication.fromJson(
              receipt(<String, dynamic>{'category': 'KNITTING', 'area': 'Hamra'}))
          .service!;

      expect(answers.categoryWire, 'KNITTING');
      expect(answers.category, isNull);
    });
  });

  group('asking for my application where the answer matters', () {
    test('a 404 is no application', () async {
      final _Server server =
          _Server((_) => _json(<String, String>{'message': 'none'}, 404));

      expect(await OnboardingApi(_dio(server)).myApplication(), isNull);
    });

    test('any other failure is thrown, never read as no application', () async {
      final _Server server = _Server((_) => _json(<String, String>{'message': 'down'}, 503));

      await expectLater(OnboardingApi(_dio(server)).myApplication(), throwsA(isA<DioException>()));
    });

    test('the receipt comes back with its services answers', () async {
      final _Server server = _Server((_) => _json(<String, dynamic>{
            'reference': 'ref-9',
            'status': 'PROVISIONED',
            'kind': 'MERCHANT',
            'businessName': 'Al Fakhry Press',
            'service': <String, String>{'category': 'REPAIRS', 'area': 'Hamra'},
          }));

      final OnboardingApplication? application = await OnboardingApi(_dio(server)).myApplication();

      expect(server.requests.single.path, '/api/onboarding/applications/mine');
      expect(application!.service!.category, ServiceCategory.repairs);
    });
  });

  test('opening a services shop sends the SERVICES vertical, its category and its area', () async {
    final _Server server = _Server((_) => _json(<String, dynamic>{
          'id': 'store-1',
          'slug': 'al-fakhry-press',
          'name': 'Al Fakhry Press',
          'vertical': 'SERVICES',
          'serviceCategory': 'PRINTING',
        }, 201));

    await StoreApi(_dio(server)).create(
      name: 'Al Fakhry Press',
      vertical: StoreVertical.services,
      serviceCategory: ServiceCategory.printing,
      neighborhood: 'Mar Mikhael',
    );

    final RequestOptions sent = server.requests.single;
    expect(sent.method, 'POST');
    expect(sent.path, '/api/stores');
    expect(sent.data, <String, dynamic>{
      'name': 'Al Fakhry Press',
      'vertical': 'SERVICES',
      'tags': <String>[],
      'neighborhood': 'Mar Mikhael',
      'serviceCategory': 'PRINTING',
    });
  });

  group('the Services answer to the Google role question', () {
    test('is a seller in every way the platform checks', () {
      expect(AccountIntent.services.role, DeliveryRole.merchant);
      expect(AccountIntent.services.applicationKind, OnboardingKind.merchant);
    });

    test('proceeds for a merchant and applies for anybody else', () {
      expect(BrokerSignIn.decide(AccountIntent.services, <DeliveryRole>{DeliveryRole.merchant}),
          BrokerStep.proceed);
      expect(BrokerSignIn.decide(AccountIntent.services, <DeliveryRole>{DeliveryRole.customer}),
          BrokerStep.apply);
    });
  });
}
