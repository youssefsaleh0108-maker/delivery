import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/services_shop_bootstrap.dart';

/// Opening an approved services provider's shop on their first entry to the shop shell.
///
/// Pinned: the shop is opened exactly when an approved application says SERVICES and the merchant has
/// no shop — with the application's name, category and area, and before the shell shows anything
/// else. Nothing is opened for a goods merchant or a provider still waiting, and a merchant who owns a
/// shop is not asked about at all; an account whose application is not a services one is asked once a
/// session. A read that fails is "nothing learned", never a reason to open a shop or to give up on one
/// for good. And a shop that could not be opened is reported rather than swallowed — as something to
/// try again, or, when the server refused the category, as something no retry can change.
class _Server implements HttpClientAdapter {
  List<Map<String, dynamic>> stores = <Map<String, dynamic>>[];
  int storesStatus = 200;
  Map<String, dynamic>? application;
  int applicationStatus = 200;
  int createStatus = 201;

  final List<String> calls = <String>[];
  final List<Map<String, dynamic>> created = <Map<String, dynamic>>[];

  int get applicationReads =>
      calls.where((String c) => c == 'GET /api/onboarding/applications/mine').length;

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
        if (createStatus >= 400) {
          return _json(createStatus, <String, dynamic>{
            'title': 'Catalog rule violated',
            'detail': 'Services in PRINTING are not offered yet.',
          });
        }
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

ServicesShopBootstrap _bootstrap(_Server server,
    {ServicesProviderMemory? memory, String? account}) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = server;
  return ServicesShopBootstrap(
    stores: StoreApi(dio),
    onboarding: OnboardingApi(dio),
    memory: memory,
    account: account,
  );
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

  test('a goods merchant stays in the shop they have: nothing is opened, and Onboarding is not asked',
      () async {
    final _Server noApplication = _Server()..stores = <Map<String, dynamic>>[_grill];
    final _Server shopApplication = _Server()
      ..stores = <Map<String, dynamic>>[_grill]
      ..application = _receipt(service: null);

    for (final _Server server in <_Server>[noApplication, shopApplication]) {
      final ServicesShopOutcome outcome = await _bootstrap(server).run();

      expect(outcome, isA<NotServicesProvider>());
      expect((outcome as NotServicesProvider).storeId, 'store-grill');
      expect(server.created, isEmpty);
      expect(server.calls, <String>['GET /api/stores/mine'],
          reason: 'the answer for a merchant who owns a shop never changes, so it is not asked');
    }
  });

  // The server opens no shop for a services applicant until this bootstrap opens theirs — a first
  // product or scan is refused — so owning any shop means a shop. Asking anyway cost every goods
  // merchant a read of their application on every entry to the shell.
  test('a merchant who owns any shop is not asked about, whatever their application says', () async {
    final _Server server = _Server()
      ..stores = <Map<String, dynamic>>[_grill]
      ..application = _receipt(status: 'PROVISIONED');

    final ServicesShopOutcome outcome = await _bootstrap(server).run();

    expect(outcome, isA<NotServicesProvider>());
    expect(server.applicationReads, 0);
    expect(server.created, isEmpty);
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

  test('an account whose application is not a services one is asked once a session', () async {
    final ServicesProviderMemory memory = ServicesProviderMemory();
    final _Server noApplication = _Server();
    final _Server shopApplication = _Server()..application = _receipt(service: null);

    for (final _Server server in <_Server>[noApplication, shopApplication]) {
      final String account = 'goods-${server.hashCode}';
      final ServicesShopOutcome first =
          await _bootstrap(server, memory: memory, account: account).run();
      final ServicesShopOutcome second =
          await _bootstrap(server, memory: memory, account: account).run();

      expect(first, isA<NotServicesProvider>());
      expect(second, isA<NotServicesProvider>());
      expect(server.applicationReads, 1, reason: 'the second entry already knew the answer');
    }
  });

  test('somebody else signing in on the same phone is asked afresh', () async {
    final ServicesProviderMemory memory = ServicesProviderMemory();
    final _Server goods = _Server();
    await _bootstrap(goods, memory: memory, account: 'goods-sub').run();

    final _Server provider = _Server()..application = _receipt();
    final ServicesShopOutcome outcome =
        await _bootstrap(provider, memory: memory, account: 'provider-sub').run();

    expect(outcome, isA<ServicesShopReady>());
    expect(provider.applicationReads, 1);
  });

  test('a provider still waiting, and a read that failed, are not remembered', () async {
    final ServicesProviderMemory memory = ServicesProviderMemory();
    final _Server waiting = _Server()..application = _receipt(status: 'SUBMITTED');
    final _Server down = _Server()
      ..application = _receipt()
      ..applicationStatus = 503;

    await _bootstrap(waiting, memory: memory, account: 'waiting-sub').run();
    await _bootstrap(waiting, memory: memory, account: 'waiting-sub').run();
    expect(waiting.applicationReads, 2, reason: 'approval is what the next entry is looking for');

    expect(await _bootstrap(down, memory: memory, account: 'provider-sub').run(),
        isA<NotServicesProvider>());
    down.applicationStatus = 200;
    expect(await _bootstrap(down, memory: memory, account: 'provider-sub').run(),
        isA<ServicesShopReady>());
  });

  test('a read that fails is nothing learned: nothing is opened and the shell carries on', () async {
    final _Server storesDown = _Server()
      ..storesStatus = 500
      ..application = _receipt();
    final _Server onboardingDown = _Server()
      ..application = _receipt()
      ..applicationStatus = 503;

    final ServicesShopOutcome first = await _bootstrap(storesDown).run();
    final ServicesShopOutcome second = await _bootstrap(onboardingDown).run();

    expect(first, isA<NotServicesProvider>());
    expect((first as NotServicesProvider).storeId, isNull);
    expect(storesDown.calls, <String>['GET /api/stores/mine']);
    expect(second, isA<NotServicesProvider>());
    expect((second as NotServicesProvider).storeId, isNull);
    expect(onboardingDown.created, isEmpty);
  });

  test('a shop that could not be opened just now is reported as something to try again', () async {
    final _Server server = _Server()
      ..application = _receipt()
      ..createStatus = 500;

    expect(await _bootstrap(server).run(), isA<ServicesShopFailed>());
  });

  test('a category the server refuses (422) is reported as final, not as something to retry',
      () async {
    final _Server server = _Server()
      ..application = _receipt()
      ..createStatus = 422;

    final ServicesShopOutcome outcome = await _bootstrap(server).run();

    expect(outcome, isA<ServicesCategoryNotOffered>());
    expect(outcome, isNot(isA<ServicesShopFailed>()));
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
