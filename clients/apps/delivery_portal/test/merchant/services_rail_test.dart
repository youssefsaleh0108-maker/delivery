import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:delivery_portal/src/portal_shell.dart';
import 'package:delivery_portal/src/shell/shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Merchant Hub for a services shop: the phone's services mode on the web.
///
/// The rail's order is load-bearing — the dashboard's "view orders" is `jump(2)` — so what is pinned
/// is that the services rail substitutes in place and never reorders (Orders is still third, Offers
/// stands where Products stood), that it leaves out exactly the till, the shelves and the shelf
/// sections, that the shell draws it for a services shop and the goods rail for everybody else, and
/// that neither is drawn before the shop has said which it is.
class _Gateway implements HttpClientAdapter {
  List<Map<String, dynamic>> stores = <Map<String, dynamic>>[];
  int storesStatus = 200;
  Completer<void>? holdStores;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    if (options.path == '/api/stores/mine') {
      await holdStores?.future;
      return _json(storesStatus, <String, dynamic>{
        'content': stores,
        'page': 0,
        'totalElements': stores.length,
        'totalPages': 1,
      });
    }
    if (options.path == '/api/chat/shop-threads/inbox') {
      return ResponseBody.fromString('[]', 200, headers: _jsonHeaders);
    }
    return _json(200, <String, dynamic>{});
  }

  @override
  void close({bool force = false}) {}
}

const Map<String, List<String>> _jsonHeaders = <String, List<String>>{
  Headers.contentTypeHeader: <String>[Headers.jsonContentType],
};

ResponseBody _json(int status, Map<String, dynamic> body) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: _jsonHeaders);

PortalApis _apis(Dio dio) => PortalApis(
      catalog: CatalogApi(dio),
      order: OrderApi(dio),
      store: StoreApi(dio),
      provider: DeliveryProviderApi(dio),
      zone: DeliveryZoneApi(dio),
      whatsApp: WhatsAppApi(dio),
      settings: ConnectorSettingsApi(dio),
      accounting: AccountingApi(dio),
      rate: DeliveryRateApi(dio),
      banner: BannerApi(dio),
      offer: OfferApi(dio),
      onboarding: OnboardingApi(dio),
      tracking: TrackingApi(dio),
      promo: PromoApi(dio),
      documents: DocumentsApi(dio),
      notification: NotificationApi(dio),
      aggregates: AggregatesApi(dio),
      activity: ActivityApi(dio),
      riderPerformance: RiderPerformanceApi(dio),
      partnerManagement: PartnerManagementApi(dio),
      autoApproval: AutoApprovalApi(dio),
      statements: StatementsApi(dio),
      pos: PosApi(dio),
      inventory: InventoryApi(dio),
      staff: StoreStaffApi(dio),
      reports: ReportsApi(dio),
      catalogScan: CatalogScanApi(dio),
      demand: DemandApi(dio),
      shopChat: ShopChatApi(dio),
      moderation: ChatModerationApi(dio),
      attachments: OrderAttachmentApi(dio),
      offerModeration: BackofficeCatalogApi(dio),
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
  final LocaleController locale =
      LocaleController(read: () async => null, write: (String _) async {});

  List<String> labels(PortalArea area) =>
      <String>[for (final PortalDestination d in area.destinations) d.label(en)];

  test('the services rail keeps Orders third, puts Offers where Products was, and leaves out the '
      'till, the shelves, the shelf sections and the staff roster', () {
    final List<String> goods = labels(PortalArea.merchant_);
    final List<String> services = labels(PortalArea.merchantServices_);
    final List<String> goodsOnly = <String>[
      en.navInventory,
      en.navPos,
      // The menu, for the reason the shelf sections are here: a services shop has no shelf to
      // arrange, so a menu builder there would be an empty screen with a switch that means nothing.
      en.menuBuilderTitle,
      en.navCategories,
      en.navStaff,
    ];

    expect(services.take(3), <String>[en.navDashboard, en.svcNavOffers, en.navOrders]);
    expect(goods[1], en.navProducts, reason: 'the goods rail is unchanged');
    expect(goods[2], en.navOrders);
    for (final String page in goodsOnly) {
      expect(goods, contains(page));
      expect(services, isNot(contains(page)));
    }
    // Every other goods page, in the goods rail's own order.
    expect(services.sublist(3), <String>[
      for (final String page in goods.sublist(3))
        if (!goodsOnly.contains(page)) page,
    ]);
    expect(
      PortalArea.merchantServices_.destinations
          .where((PortalDestination d) => d.badge == PortalBadge.shopUnread),
      hasLength(1),
      reason: 'customers\' messages keep their unread number',
    );
  });

  test('the services dashboard\'s View orders jumps to Orders, the services queue, and See all to Offers',
      () {
    final PortalApis apis = _apis(Dio());
    final List<PortalDestination> rail = PortalArea.merchantServices_.destinations;
    Widget page(int index, [void Function(int)? jump]) =>
        rail[index].buildPage(0, apis, locale, () async {}, jump ?? (int _) {});

    final List<int> jumps = <int>[];
    final Widget dashboard = page(0, jumps.add);
    expect(dashboard, isA<ServiceDashboardScreen>());
    (dashboard as ServiceDashboardScreen).onViewOrders!();
    dashboard.onShowOffers!();

    expect(jumps, <int>[2, 1]);
    expect(page(1), isA<ServiceOffersScreen>());
    expect(page(2), isA<ServiceOrdersScreen>());
    expect((page(2) as ServiceOrdersScreen).shopChat, isNotNull,
        reason: 'the order detail\'s Chat with customer needs the shop\'s conversations');
    expect((page(2) as ServiceOrdersScreen).files, isNotNull,
        reason: 'the order detail opens the customer\'s files');
  });

  test(
      'the rail for an owner of both kinds of shop is the goods rail unchanged, with the services '
      'shop\'s queue and offers appended', () {
    final PortalApis apis = _apis(Dio());
    final List<PortalDestination> rail = PortalArea.merchantWithServices_.destinations;
    final int goods = PortalArea.merchant_.destinations.length;
    Widget page(int index) => rail[index].buildPage(0, apis, locale, () async {}, (int _) {});

    expect(labels(PortalArea.merchantWithServices_), <String>[
      ...labels(PortalArea.merchant_),
      en.svcServiceOrdersRow,
      en.svcServiceOffersRow,
    ]);
    expect(page(goods), isA<ServiceOrdersScreen>());
    expect((page(goods) as ServiceOrdersScreen).files, isNotNull);
    expect(page(goods + 1), isA<ServiceOffersScreen>());
  });

  Future<void> pumpPortal(WidgetTester tester, _Gateway gateway,
      {bool settle = true, Future<void> Function()? onSignOut}) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = gateway;
    final AuthSession session = AuthSession(
      accessToken: 'token',
      refreshToken: null,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      roles: const <DeliveryRole>{DeliveryRole.merchant},
      subject: 'merchant-sub',
    );

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: PortalShell(
        areas: PortalArea.forSession(session),
        apis: _apis(dio),
        locale: locale,
        session: session,
        onSignOut: onSignOut ?? () async {},
      ),
    ));
    if (!settle) return;
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  List<String> railOnScreen(WidgetTester tester) => <String>[
        for (final ConsoleNavEntry entry
            in tester.widget<ConsoleSidebar>(find.byType(ConsoleSidebar)).entries)
          entry.label,
      ];

  testWidgets('a services merchant\'s portal draws the services rail and opens on its dashboard',
      (WidgetTester tester) async {
    final _Gateway gateway = _Gateway()..stores = <Map<String, dynamic>>[_printShop];
    await pumpPortal(tester, gateway);

    expect(railOnScreen(tester), labels(PortalArea.merchantServices_));
    expect(find.byType(ServiceDashboardScreen), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(ConsoleSidebar), matching: find.text(en.navOrders)));
    for (int i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(ServiceOrdersScreen), findsOneWidget);
  });

  testWidgets('a goods merchant\'s portal draws the goods rail it always had',
      (WidgetTester tester) async {
    final _Gateway gateway = _Gateway()..stores = <Map<String, dynamic>>[_grill];
    await pumpPortal(tester, gateway);

    expect(railOnScreen(tester), labels(PortalArea.merchant_));
    expect(find.byType(MerchantDashboardScreen), findsOneWidget);
    expect(find.byType(ServiceDashboardScreen), findsNothing);
  });

  testWidgets(
      'no rail is drawn until the shops are read, with sign-out in reach; a read that fails offers a '
      'retry and sign-out, never a guessed goods rail', (WidgetTester tester) async {
    int signOuts = 0;
    final _Gateway gateway = _Gateway()
      ..stores = <Map<String, dynamic>>[_printShop]
      ..holdStores = Completer<void>();
    await pumpPortal(tester, gateway, settle: false, onSignOut: () async => signOuts++);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(ConsoleSidebar), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text(en.signOut));
    expect(signOuts, 1, reason: 'a slow read is never a trap');

    gateway.holdStores!.complete();
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(railOnScreen(tester), contains(en.svcNavOffers));

    await tester.pumpWidget(const SizedBox.shrink());
    final _Gateway broken = _Gateway()
      ..stores = <Map<String, dynamic>>[_printShop]
      ..storesStatus = 500;
    await pumpPortal(tester, broken);

    expect(find.byType(ConsoleSidebar), findsNothing, reason: 'no guessed goods rail');
    expect(find.text(en.svcShopReadFailed), findsOneWidget);
    expect(find.text(en.signOut), findsOneWidget);

    broken.storesStatus = 200;
    await tester.tap(find.text(en.tryAgain));
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(railOnScreen(tester), labels(PortalArea.merchantServices_));
  });

  testWidgets(
      'an owner of a goods shop and a services shop gets the goods rail with the services shop\'s '
      'queue and offers at its end', (WidgetTester tester) async {
    final _Gateway gateway = _Gateway()..stores = <Map<String, dynamic>>[_printShop, _grill];
    await pumpPortal(tester, gateway);

    expect(railOnScreen(tester), labels(PortalArea.merchantWithServices_));
    expect(find.byType(MerchantDashboardScreen), findsOneWidget);

    final Finder entry = find.descendant(
        of: find.byType(ConsoleSidebar), matching: find.text(en.svcServiceOrdersRow));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    for (int i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(ServiceOrdersScreen), findsOneWidget);
  });
}
