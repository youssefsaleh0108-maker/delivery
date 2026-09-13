import 'dart:async';
import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/merchant_shell.dart';

/// The shop shell opening an approved services provider's shop, seen through the shell itself.
///
/// `services_shop_bootstrap_test.dart` pins what is decided. This pins what the provider sees: nothing
/// but "Opening your services shop…" until the shop exists, because every tab needs it; a plain
/// statement and a retry that works when it could not be opened; and, for a goods merchant, their
/// shop straight away with nothing opened — the shell they had before services existed.
class _Gateway implements HttpClientAdapter {
  List<Map<String, dynamic>> stores = <Map<String, dynamic>>[];
  Map<String, dynamic>? application;
  int createStatus = 201;

  /// Holds the shop's opening until completed, so the screen shown meanwhile can be read.
  Completer<void>? holdCreate;

  final List<String> calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    final String route = '${options.method} ${options.path}';
    calls.add(route);
    if (route == 'GET /api/stores/mine') {
      return _json(200, <String, dynamic>{
        'content': stores,
        'page': 0,
        'totalElements': stores.length,
        'totalPages': 1,
      });
    }
    if (route == 'GET /api/onboarding/applications/mine') {
      final Map<String, dynamic>? found = application;
      return found == null ? _json(404, <String, dynamic>{'message': 'none'}) : _json(200, found);
    }
    if (route == 'POST /api/stores') {
      await holdCreate?.future;
      if (createStatus >= 400) return _json(createStatus, <String, dynamic>{'title': 'down'});
      final Map<String, dynamic> body = options.data as Map<String, dynamic>;
      return _json(201, <String, dynamic>{
        'id': 'store-opened',
        'slug': 'al-fakhry-press',
        'name': body['name'],
        'vertical': body['vertical'],
        'serviceCategory': body['serviceCategory'],
      });
    }
    // Empty collections and a bare object satisfy every screen the shell builds on open.
    if (options.path.contains('orders') || options.path.contains('products')) {
      return _json(200, <String, dynamic>{'content': <Object>[], 'totalElements': 0});
    }
    return _json(200, <String, dynamic>{});
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Map<String, dynamic> body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );

const Map<String, dynamic> _approvedPrintShop = <String, dynamic>{
  'reference': 'ref-1',
  'status': 'APPROVED',
  'kind': 'MERCHANT',
  'businessName': 'Al Fakhry Press',
  'service': <String, dynamic>{'category': 'PRINTING', 'zoneId': 'z-1', 'area': 'Mar Mikhael'},
};

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  Future<void> pumpShell(WidgetTester tester, _Gateway gateway) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = gateway;

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: MerchantShell(
        orderApi: OrderApi(dio),
        storeApi: StoreApi(dio),
        catalogApi: CatalogApi(dio),
        onboardingApi: OnboardingApi(dio),
        session: AuthSession(
          accessToken: 'token',
          refreshToken: null,
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          roles: const <DeliveryRole>{DeliveryRole.merchant},
          subject: 'provider-sub',
        ),
        locale: LocaleController(read: () async => 'en', write: (String _) async {}),
        onSignOut: () async {},
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> settle(WidgetTester tester) async {
    // The spinner animates for ever, so pump rather than settle — several frames, so the reads the
    // shop's own screens start once it exists have been answered before the test ends.
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('an approved provider sees only the opening of their shop, then the shop',
      (WidgetTester tester) async {
    final _Gateway gateway = _Gateway()
      ..application = _approvedPrintShop
      ..holdCreate = Completer<void>();
    await pumpShell(tester, gateway);

    expect(find.text(en.svcOpeningShop), findsOneWidget);
    expect(find.byType(YdBottomNav), findsNothing, reason: 'every tab needs the shop');

    gateway.holdCreate!.complete();
    await settle(tester);

    expect(find.text(en.svcOpeningShop), findsNothing);
    expect(find.byType(YdBottomNav), findsOneWidget);
    expect(gateway.calls.where((String c) => c == 'POST /api/stores'), hasLength(1));
  });

  testWidgets('a shop that could not be opened is said plainly, with a retry that works',
      (WidgetTester tester) async {
    final _Gateway gateway = _Gateway()
      ..application = _approvedPrintShop
      ..createStatus = 500;
    await pumpShell(tester, gateway);
    await settle(tester);

    expect(find.text(en.svcOpeningShopFailed), findsOneWidget);
    expect(find.byType(YdBottomNav), findsNothing);

    gateway.createStatus = 201;
    await tester.tap(find.text(en.tryAgain));
    await settle(tester);

    expect(find.text(en.svcOpeningShopFailed), findsNothing);
    expect(find.byType(YdBottomNav), findsOneWidget);
    expect(gateway.calls.where((String c) => c == 'POST /api/stores'), hasLength(2));
  });

  testWidgets('a goods merchant goes straight to their shop, and nothing is opened',
      (WidgetTester tester) async {
    final _Gateway gateway = _Gateway()
      ..stores = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'store-grill',
          'slug': 'beirut-grill',
          'name': 'Beirut Grill',
          'vertical': 'RESTAURANT',
        },
      ];
    await pumpShell(tester, gateway);
    await settle(tester);

    expect(find.text(en.svcOpeningShop), findsNothing);
    expect(find.byType(YdBottomNav), findsOneWidget);
    expect(gateway.calls, isNot(contains('POST /api/stores')));
  });
}
