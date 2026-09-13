import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/services_shop_bootstrap.dart';

/// Opening an approved services provider's shop on their first entry to the shop shell.
///
/// Pinned: the shop is opened exactly when an approved application says SERVICES and no services
/// shop exists — with the application's name, category and area, and before the shell shows anything
/// else. Nothing is opened for a goods merchant or a provider still waiting. A read that fails is
/// "nothing learned", never a reason to open a shop or to give up on one for good. And a shop that
/// could not be opened is reported rather than swallowed, because the shell is unusable without it.
class _Server implements HttpClientAdapter {
  List<Map<String, dynamic>> stores = <Map<String, dynamic>>[];
  int storesStatus = 200;
  Map<String, dynamic>? application;
  int applicationStatus = 200;
  int createStatus = 201;

  final List<String> calls = <String>[];
  final List<Map<String, dynamic>> created = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    final String route = '${options.method} ${options.path}';
    calls.add(route);
    switch (route) {
      case 'GET /api/stores/mine':
        return _json(storesStatus, <String, dynamic>{
          'content': stores,
          'page': 0,
          'totalElements': stores.length,
          'totalPages': 1,
        });
      case 'GET /api/onboarding/applications/mine':
        final Map<String, dynamic>? found = application;
        if (found == null) return _json(404, <String, dynamic>{'message': 'No application'});
        return _json(applicationStatus, found);
      case 'POST /api/stores':
        final Map<String, dynamic> body = options.data as Map<String, dynamic>;
        created.add(body);
        return _json(createStatus, <String, dynamic>{
          'id': 'store-opened',
          'slug': 'al-fakhry-press',
          'name': body['name'],
          'vertical': body['vertical'],
          'serviceCategory': body['serviceCategory'],
        });
    }
    return _json(500, <String, dynamic>{'message': 'not expected: $route'});
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );

Map<String, dynamic> _receipt({
  String status = 'APPROVED',
  String businessName = 'Al Fakhry Press',
  Map<String, dynamic>? service = const <String, dynamic>{
    'category': 'PRINTING',
    'zoneId': 'z-1',
    'area': 'Mar Mikhael',
  },
}) =>
    <String, dynamic>{
      'reference': 'ref-1',
      'status': status,
      'kind': 'MERCHANT',
      'businessName': businessName,
      'service': service,
    };

const Map<String, dynamic> _grill = <String, dynamic>{
  'id': 'store-grill',
  'slug': 'beirut-grill',
  'name': 'Beirut Grill',
  'vertical': 'RESTAURANT',
};

const Map<String, dynamic> _press = <String, dynamic>{
  'id': 'store-press',
  'slug': 'al-fakhry-press',
  'name': 'Al Fakhry Press',
  'vertical': 'SERVICES',
  'serviceCategory': 'PRINTING',
};

ServicesShopBootstrap _bootstrap(_Server server) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = server;
  return ServicesShopBootstrap(stores: StoreApi(dio), onboarding: OnboardingApi(dio));
}

void main() {
  test('an approved provider with no shop has it opened from the application, and is told first',
      () async {
    final _Server server = _Server()..application = _receipt();
    int opening = 0;

    final ServicesShopOutcome outcome = await _bootstrap(server).run(onOpening: () => opening++);

    expect(outcome, isA<ServicesShopReady>());
    final ServicesShopReady ready = outcome as ServicesShopReady;
    expect(ready.opened, isTrue);
    expect(ready.store.id, 'store-opened');
    expect(opening, 1);
    expect(server.calls, <String>[
      'GET /api/stores/mine',
      'GET /api/onboarding/applications/mine',
      'POST /api/stores',
    ]);
    expect(server.created.single, <String, dynamic>{
      'name': 'Al Fakhry Press',
      'vertical': 'SERVICES',
      'tags': <String>[],
      'neighborhood': 'Mar Mikhael',
      'serviceCategory': 'PRINTING',
    });
  });

  test('a provider whose services shop exists opens nothing, and Onboarding is not asked', () async {
    final _Server server = _Server()
      ..stores = <Map<String, dynamic>>[_grill, _press]
      ..application = _receipt();

    final ServicesShopOutcome outcome = await _bootstrap(server).run();

    expect(outcome, isA<ServicesShopReady>());
    expect((outcome as ServicesShopReady).opened, isFalse);
    expect(outcome.store.id, 'store-press');
    expect(server.calls, <String>['GET /api/stores/mine']);
  });

  test('a goods merchant stays in the shop they have, and nothing is opened', () async {
    final _Server noApplication = _Server()..stores = <Map<String, dynamic>>[_grill];
    final _Server shopApplication = _Server()
      ..stores = <Map<String, dynamic>>[_grill]
      ..application = _receipt(service: null);

    for (final _Server server in <_Server>[noApplication, shopApplication]) {
      final ServicesShopOutcome outcome = await _bootstrap(server).run();

      expect(outcome, isA<NotServicesProvider>());
      expect((outcome as NotServicesProvider).storeId, 'store-grill');
      expect(server.created, isEmpty);
    }
  });

  test('a provider still waiting for a decision has nothing opened yet', () async {
    for (final String waiting in <String>['SUBMITTED', 'IN_REVIEW']) {
      final _Server server = _Server()..application = _receipt(status: waiting);
      int opening = 0;

      final ServicesShopOutcome outcome =
          await _bootstrap(server).run(onOpening: () => opening++);

      expect(outcome, isA<ServicesApplicationPending>());
      expect(server.created, isEmpty);
      expect(opening, 0);
    }
  });

  test('a goods shop made by hand while waiting does not stand in for the services shop', () async {
    final _Server server = _Server()
      ..stores = <Map<String, dynamic>>[_grill]
      ..application = _receipt(status: 'PROVISIONED');

    final ServicesShopOutcome outcome = await _bootstrap(server).run();

    expect(outcome, isA<ServicesShopReady>());
    expect(server.created.single['vertical'], 'SERVICES');
  });

  test('a read that fails is nothing learned: nothing is opened and the shell carries on', () async {
    final _Server storesDown = _Server()
      ..storesStatus = 500
      ..application = _receipt();
    final _Server onboardingDown = _Server()
      ..stores = <Map<String, dynamic>>[_grill]
      ..application = _receipt()
      ..applicationStatus = 503;

    final ServicesShopOutcome first = await _bootstrap(storesDown).run();
    final ServicesShopOutcome second = await _bootstrap(onboardingDown).run();

    expect(first, isA<NotServicesProvider>());
    expect((first as NotServicesProvider).storeId, isNull);
    expect(storesDown.calls, <String>['GET /api/stores/mine']);
    expect(second, isA<NotServicesProvider>());
    expect((second as NotServicesProvider).storeId, 'store-grill');
    expect(onboardingDown.created, isEmpty);
  });

  test('a shop that could not be opened is reported, not swallowed', () async {
    final _Server server = _Server()
      ..application = _receipt()
      ..createStatus = 500;

    expect(await _bootstrap(server).run(), isA<ServicesShopFailed>());
  });

  test('a category this build cannot name is reported rather than opened under a guess', () async {
    final _Server server = _Server()
      ..application = _receipt(service: <String, dynamic>{'category': 'KNITTING', 'area': 'Hamra'});

    expect(await _bootstrap(server).run(), isA<ServicesShopFailed>());
    expect(server.created, isEmpty);
  });

  test('a business name longer than a shop may carry is trimmed, not refused', () async {
    final _Server server = _Server()..application = _receipt(businessName: 'P' * 170);

    await _bootstrap(server).run();

    expect((server.created.single['name'] as String).length, 160);
  });
}
