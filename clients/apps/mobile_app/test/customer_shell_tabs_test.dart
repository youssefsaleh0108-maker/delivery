import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/account_screen.dart';
import 'package:mobile_app/src/butler_screen.dart';
import 'package:mobile_app/src/cart_screen.dart';
import 'package:mobile_app/src/customer_nav_bar.dart';
import 'package:mobile_app/src/customer_shell.dart';
import 'package:mobile_app/src/my_orders_screen.dart';
import 'package:mobile_app/src/offline_banner.dart';
import 'package:mobile_app/src/services_home_screen.dart';
import 'package:mobile_app/src/store_home_screen.dart';

import 'service_fixtures.dart';
import 'widget_test.dart' show sessionWith;

/// The customer shell with its sixth destination.
///
/// `CustomerShell._tabAt` has a default branch that draws an empty box, so a destination the switch
/// forgot fails silently: a tab that opens nothing. This pins every index to a real screen, the
/// Services tab to the services home, and Orders to its new seat — and that service shops stay off
/// Home: its storefront read names no vertical, while the Services tab's names SERVICES.
void main() {
  const MethodChannel storageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (MethodCall call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
  });

  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  Future<FakeServer> pumpShell(WidgetTester tester) async {
    phone(tester, size: const Size(390, 1600));
    final FakeServer server = FakeServer()
      ..on('GET', '/api/stores', (_) => pageJson(<Map<String, dynamic>>[storeJson()]))
      ..on('GET', '/api/stores/favorites', (_) => pageJson(const <Map<String, dynamic>>[]))
      ..on('GET', '/api/banners', (_) => <dynamic>[])
      ..on('GET', '/api/categories/chips', (_) => <dynamic>[])
      ..on('GET', '/api/notifications/unread-count', (_) => <String, dynamic>{'unread': 0})
      ..on('GET', '/api/butler/mine', (_) => pageJson(const <Map<String, dynamic>>[]))
      ..on('GET', '/api/orders/mine', (_) => pageJson(const <Map<String, dynamic>>[]))
      ..on('GET', '/api/stores/service-categories', (_) => <String>['PRINTING']);
    await tester.pumpWidget(svcApp(CustomerShell(
      storeApi: StoreApi(server.dio),
      orderApi: OrderApi(server.dio),
      notificationApi: NotificationApi(server.dio),
      butlerApi: ButlerApi(server.dio),
      zoneApi: DeliveryZoneApi(server.dio),
      offerApi: OfferApi(server.dio),
      catalogApi: CatalogApi(server.dio),
      session: sessionWith(<DeliveryRole>{DeliveryRole.customer}),
      locale: LocaleController(read: () async => 'en', write: (String _) async {}),
      onSignOut: () async {},
    )));
    await tester.pumpAndSettle();
    return server;
  }

  IndexedStack tabs(WidgetTester tester) => tester.widget<IndexedStack>(
      find.descendant(of: find.byType(OfflineBanner), matching: find.byType(IndexedStack)).first);

  Future<void> open(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(of: find.byType(CustomerNavBar), matching: find.text(label)));
    await tester.pumpAndSettle();
  }

  testWidgets('every destination has a screen behind it — none is an empty box',
      (WidgetTester tester) async {
    await pumpShell(tester);
    final List<Widget> children = tabs(tester).children;

    expect(children, hasLength(CustomerNavBar.tabCount));
    for (int i = 0; i < children.length; i++) {
      expect(children[i], isNot(isA<SizedBox>()), reason: 'tab $i draws nothing');
    }
    expect(children[CustomerNavBar.homeIndex], isA<StoreHomeScreen>());
    expect(children[CustomerNavBar.butlerIndex], isA<ButlerScreen>());
    expect(children[CustomerNavBar.basketIndex], isA<CartScreen>());
    expect(children[CustomerNavBar.servicesIndex], isA<ServicesHomeScreen>());
    // Orders is the order list with the offline catalog stacked over it. Not the tab on screen, so
    // looked for offstage too.
    expect(children[CustomerNavBar.ordersIndex], isA<IndexedStack>());
    expect(
        find.descendant(
            of: find.byWidget(children[CustomerNavBar.ordersIndex], skipOffstage: false),
            matching: find.byType(MyOrdersScreen, skipOffstage: false),
            skipOffstage: false),
        findsOneWidget);
    expect(children[CustomerNavBar.accountIndex], isA<AccountScreen>());
  });

  testWidgets('Services opens the services home, which reads nothing until it is opened',
      (WidgetTester tester) async {
    final FakeServer server = await pumpShell(tester);

    expect(server.sent('GET', '/api/stores/service-categories'), isEmpty);
    // Home's storefront names no vertical, which the server answers with goods shops only.
    final List<RequestOptions> storefront = server.sent('GET', '/api/stores');
    expect(storefront, isNotEmpty);
    expect(storefront.every((RequestOptions r) => !r.queryParameters.containsKey('vertical')), isTrue);
    expect(storefront.every((RequestOptions r) => !r.queryParameters.containsKey('serviceCategory')),
        isTrue);

    await open(tester, en.svcNavServices);

    expect(tabs(tester).index, CustomerNavBar.servicesIndex);
    expect(server.sent('GET', '/api/stores/service-categories'), hasLength(1));
    expect(find.text(en.svcCategoriesTitle), findsOneWidget);
    expect(server.sent('GET', '/api/stores').last.queryParameters['vertical'], 'SERVICES');
  });

  testWidgets('Orders and Account kept their screens when they moved along a seat',
      (WidgetTester tester) async {
    await pumpShell(tester);

    await open(tester, en.navOrders);
    expect(tabs(tester).index, CustomerNavBar.ordersIndex);
    expect(tabs(tester).index, 4);
    expect(find.text(en.custYourOrders), findsOneWidget);

    await open(tester, en.navAccount);
    expect(tabs(tester).index, CustomerNavBar.accountIndex);

    await open(tester, en.navHome);
    expect(tabs(tester).index, CustomerNavBar.homeIndex);
  });
}
