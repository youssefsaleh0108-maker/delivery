import 'dart:async';
import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/merchant_shell.dart';

/// Services mode, seen through the shop shell (docs/figma-services-designs.md, "The provider app
/// experience"): a services shop's owner gets Dashboard, Orders, Offers and Settings with the services
/// screens behind them and no till or shelves; a goods shop gets exactly the five tabs it always had;
/// and neither is drawn until the shop has said which it is.
class _Gateway implements HttpClientAdapter {
  List<Map<String, dynamic>> stores = <Map<String, dynamic>>[];
  int storesStatus = 200;
  Map<String, dynamic>? application;

  /// Holds the shop list until completed.
  Completer<void>? holdStores;

  final List<String> calls = <String>[];

  /// The query of every read of the merchant's order list, in order.
  final List<String> merchantOrderQueries = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    final String route = '${options.method} ${options.path}';
    calls.add(route);
    if (route == 'GET /api/stores/mine') {
      await holdStores?.future;
      return _json(storesStatus, <String, dynamic>{
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
    if (route == 'GET /api/orders/merchant/summary') {
      return _json(200, <String, dynamic>{
        'windowDays': 7,
        'today': <String, dynamic>{'day': '2026-09-14'},
        'yesterday': <String, dynamic>{'day': '2026-09-13'},
        'window': <String, dynamic>{'orders': 4},
        'awaitingYou': 1,
      });
    }
    if (route == 'GET /api/orders/merchant') merchantOrderQueries.add(options.uri.query);
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

const Map<String, dynamic> _printShop = <String, dynamic>{
  'id': 'shop-print',
  'slug': 'al-fakhry-press',
  'name': 'Al Fakhry Press',
  'vertical': 'SERVICES',
  'serviceCategory': 'PRINTING',
};

const Map<String, dynamic> _grill = <String, dynamic>{
  'id': 'shop-grill',
  'slug': 'beirut-grill',
  'name': 'Beirut Grill',
  'vertical': 'RESTAURANT',
};

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  Future<void> pumpShell(
    WidgetTester tester,
    _Gateway gateway, {
    bool withOnboarding = true,
    bool wireNotifications = false,
    bool wireScan = false,
    bool wireChat = false,
    bool settle = true,
    Future<void> Function()? onSignOut,
  }) async {
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
        onboardingApi: withOnboarding ? OnboardingApi(dio) : null,
        notificationApi: wireNotifications ? NotificationApi(dio) : null,
        catalogScanApi: wireScan ? CatalogScanApi(dio) : null,
        shopChatApi: wireChat ? ShopChatApi(dio) : null,
        session: AuthSession(
          accessToken: 'token',
          refreshToken: null,
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          roles: const <DeliveryRole>{DeliveryRole.merchant},
          subject: 'merchant-sub',
        ),
        locale: LocaleController(read: () async => 'en', write: (String _) async {}),
        onSignOut: onSignOut ?? () async {},
      ),
    ));
    if (!settle) return;
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  List<String> navLabels(WidgetTester tester) => <String>[
        for (final YdBottomNavItem item
            in tester.widget<YdBottomNav>(find.byType(YdBottomNav)).items)
          item.label,
      ];

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(of: find.byType(YdBottomNav), matching: find.text(label)));
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a services shop gets Dashboard, Orders, Offers and Settings, and no till or shelves',
      (WidgetTester tester) async {
    final _Gateway gateway = _Gateway()..stores = <Map<String, dynamic>>[_printShop];
    await pumpShell(tester, gateway);

    expect(navLabels(tester), <String>[en.navDashboard, en.navOrders, en.svcNavOffers, en.navSettings]);
    expect(find.byType(ServiceDashboardScreen), findsOneWidget);
    expect(find.byType(MerchantDashboardScreen), findsNothing);

    await openTab(tester, en.navOrders);
    expect(find.byType(ServiceOrdersScreen), findsOneWidget);
    expect(find.byType(OrdersScreen), findsNothing);
    expect(gateway.calls.where((String c) => c == 'GET /api/orders/merchant'), isNotEmpty);

    await openTab(tester, en.svcNavOffers);
    expect(find.byType(ServiceOffersScreen), findsOneWidget);
  });

  testWidgets('a goods shop keeps exactly the five tabs it always had', (WidgetTester tester) async {
    final _Gateway gateway = _Gateway()..stores = <Map<String, dynamic>>[_grill];
    await pumpShell(tester, gateway);

    expect(navLabels(tester),
        <String>[en.navDashboard, en.navPos, en.navInventory, en.navOrders, en.navSettings]);
    expect(find.byType(MerchantDashboardScreen), findsOneWidget);
    expect(find.byType(ServiceDashboardScreen), findsNothing);

    await openTab(tester, en.navOrders);
    expect(find.byType(OrdersScreen), findsOneWidget);
    expect(find.byType(ServiceOrdersScreen), findsNothing);
  });

  testWidgets('without the onboarding client, the shop\'s own vertical still decides the mode',
      (WidgetTester tester) async {
    final _Gateway gateway = _Gateway()..stores = <Map<String, dynamic>>[_printShop];
    await pumpShell(tester, gateway, withOnboarding: false);

    expect(navLabels(tester), <String>[en.navDashboard, en.navOrders, en.svcNavOffers, en.navSettings]);
  });

  testWidgets('neither mode is drawn until the shop has said which it is, and sign-out stays in reach',
      (WidgetTester tester) async {
    int signOuts = 0;
    final _Gateway gateway = _Gateway()
      ..stores = <Map<String, dynamic>>[_printShop]
      ..holdStores = Completer<void>();
    await pumpShell(tester, gateway, settle: false, onSignOut: () async => signOuts++);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(YdBottomNav), findsNothing);
    expect(find.text(en.navPos), findsNothing, reason: 'a print shop is never shown a till');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text(en.merchbLogOutAccount));
    expect(signOuts, 1, reason: 'a slow read is never a trap');

    gateway.holdStores!.complete();
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(navLabels(tester), contains(en.svcNavOffers));
  });

  testWidgets('a services applicant still waiting for approval waits in the services shell',
      (WidgetTester tester) async {
    final _Gateway gateway = _Gateway()
      ..application = <String, dynamic>{
        'reference': 'ref-1',
        'status': 'SUBMITTED',
        'kind': 'MERCHANT',
        'businessName': 'Al Fakhry Press',
        'service': <String, dynamic>{'category': 'PRINTING', 'zoneId': 'z-1', 'area': 'Mar Mikhael'},
      };
    await pumpShell(tester, gateway);

    expect(navLabels(tester), <String>[en.navDashboard, en.navOrders, en.svcNavOffers, en.navSettings]);
    expect(find.text(en.svcNoShopYet), findsOneWidget);
  });

  testWidgets(
      'Settings in services mode leaves out the shelves\' tools and the staff roster, and keeps the '
      'messages', (WidgetTester tester) async {
    final _Gateway gateway = _Gateway()..stores = <Map<String, dynamic>>[_printShop];
    await pumpShell(tester, gateway, wireScan: true, wireChat: true);
    await openTab(tester, en.navSettings);

    final MerchantSettingsScreen settings =
        tester.widget<MerchantSettingsScreen>(find.byType(MerchantSettingsScreen));
    expect(settings.onCatalogScan, isNull, reason: 'a shelf scan cannot make a service offer');
    expect(settings.onCategories, isNull);
    expect(settings.onStockCount, isNull);
    expect(settings.onStaff, isNull, reason: 'nobody on a services shop\'s roster could work here');
    expect(settings.onServiceOrders, isNull, reason: 'the queue is a tab here');
    expect(settings.onShopMessages, isNotNull, reason: 'customers still write to a print shop');
    expect(find.text(en.chatShopInboxTitle), findsOneWidget);
  });

  testWidgets('and a goods shop\'s Settings keeps them', (WidgetTester tester) async {
    final _Gateway gateway = _Gateway()..stores = <Map<String, dynamic>>[_grill];
    await pumpShell(tester, gateway, wireScan: true);
    await openTab(tester, en.navSettings);

    final MerchantSettingsScreen settings =
        tester.widget<MerchantSettingsScreen>(find.byType(MerchantSettingsScreen));
    expect(settings.onCatalogScan, isNotNull);
    expect(settings.onCategories, isNotNull);
    expect(settings.onStaff, isNotNull);
    expect(settings.onServiceOrders, isNull, reason: 'a goods shop alone has no services queue');
  });

  testWidgets('the services dashboard gets its bell only when notifications are wired, and it opens them',
      (WidgetTester tester) async {
    final _Gateway gateway = _Gateway()..stores = <Map<String, dynamic>>[_printShop];
    await pumpShell(tester, gateway);
    expect(
      tester.widget<ServiceDashboardScreen>(find.byType(ServiceDashboardScreen)).onNotifications,
      isNull,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpShell(tester, gateway, wireNotifications: true);
    expect(
      tester.widget<ServiceDashboardScreen>(find.byType(ServiceDashboardScreen)).onNotifications,
      isNotNull,
    );

    await tester.tap(find.byTooltip(en.notifications));
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(gateway.calls, contains('GET /api/notifications/unread-count'));
    expect(find.text(en.notifications), findsWidgets);
  });

  testWidgets('the dashboard\'s View orders opens the Orders tab', (WidgetTester tester) async {
    final _Gateway gateway = _Gateway()..stores = <Map<String, dynamic>>[_printShop];
    await pumpShell(tester, gateway);

    await tester.tap(find.text(en.svcViewOrders));
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(ServiceOrdersScreen), findsOneWidget);
  });

  testWidgets('a shop list that cannot be read offers a retry and a way out, and never the goods tabs',
      (WidgetTester tester) async {
    for (final bool withOnboarding in <bool>[true, false]) {
      final _Gateway gateway = _Gateway()
        ..stores = <Map<String, dynamic>>[_printShop]
        ..storesStatus = 500;
      await pumpShell(tester, gateway, withOnboarding: withOnboarding);

      expect(find.byType(YdBottomNav), findsNothing);
      expect(find.text(en.navPos), findsNothing);
      expect(find.text(en.svcShopReadFailed), findsOneWidget);
      expect(find.text(en.merchbLogOutAccount), findsOneWidget);

      gateway.storesStatus = 200;
      await tester.tap(find.text(en.tryAgain));
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(navLabels(tester),
          <String>[en.navDashboard, en.navOrders, en.svcNavOffers, en.navSettings]);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
      'an owner of a goods shop and a services shop keeps the goods tabs and a goods-only queue, and '
      'reaches the services shop\'s orders and offers from Settings', (WidgetTester tester) async {
    final _Gateway gateway = _Gateway()..stores = <Map<String, dynamic>>[_printShop, _grill];
    await pumpShell(tester, gateway, wireChat: true);

    expect(navLabels(tester),
        <String>[en.navDashboard, en.navPos, en.navInventory, en.navOrders, en.navSettings]);

    await openTab(tester, en.navOrders);
    expect(find.byType(OrdersScreen), findsOneWidget);
    expect(gateway.merchantOrderQueries, isNotEmpty);
    expect(gateway.merchantOrderQueries, everyElement(contains('kind=CATALOG')),
        reason: 'a service order is worked in the services queue, which the goods queue cannot do');

    await openTab(tester, en.navSettings);
    final MerchantSettingsScreen settings =
        tester.widget<MerchantSettingsScreen>(find.byType(MerchantSettingsScreen));
    expect(settings.onStaff, isNotNull, reason: 'the goods shop keeps its roster');
    expect(settings.onServiceOffers, isNotNull);

    await tester.tap(find.text(en.svcServiceOrdersRow));
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(ServiceOrdersScreen), findsOneWidget);
    expect(gateway.merchantOrderQueries.last, contains('kind=SERVICE'));
  });
}
