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

/// The merchant inbox answers one conversation with [unread] unread messages; everything else, an
/// empty object.
class _Gateway implements HttpClientAdapter {
  int unread = 3;
  final List<String> asked = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    asked.add(options.path);
    final String body = options.path == '/api/chat/shop-threads/inbox'
        ? '[{"id":"t1","storeId":"s1","storeName":"Abu Hassan","yourSide":"SHOP","open":true,'
            '"lastSequence":4,"unread":$unread}]'
        : '{}';
    return ResponseBody.fromString(body, 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

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
      menuInsights: MenuInsightsApi(dio),
      shopChat: ShopChatApi(dio),
      moderation: ChatModerationApi(dio),
      attachments: OrderAttachmentApi(dio),
      offerModeration: BackofficeCatalogApi(dio),
    );

/// A two-row merchant rail whose pages are blank, so what is under test is the rail alone.
PortalArea _area({required bool withMessages}) => PortalArea(
      role: DeliveryRole.merchant,
      title: (DeliveryStrings t) => t.merchantPortal,
      wordmark: 'Merchant Hub',
      accountRole: (DeliveryStrings t) => t.merchantPartner,
      logoIcon: Icons.storefront,
      destinations: <PortalDestination>[
        PortalDestination(
          icon: Icons.insights_outlined,
          selectedIcon: Icons.insights,
          label: (DeliveryStrings t) => t.navDashboard,
          build: (PortalApis a, _, __, ___) => const SizedBox(),
        ),
        if (withMessages)
          PortalDestination(
            icon: Icons.forum_outlined,
            selectedIcon: Icons.forum,
            label: (DeliveryStrings t) => t.chatShopInboxTitle,
            badge: PortalBadge.shopUnread,
            build: (PortalApis a, _, __, ___) => const SizedBox(),
          ),
      ],
    );

/// The sign on the web that a customer wrote to the shop.
///
/// The portal has no socket and there is no push, so before this a merchant working here learned of
/// a customer's message only by opening the inbox and pulling to refresh — which a mouse cannot do.
/// What is pinned: the rail row carries the unread number, the number follows the server while the
/// portal is open, and a rail without that row never asks.
void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  Finder badgeSaying(int count) => find.byWidgetPredicate(
      (Widget w) => w is Semantics && w.properties.label == en.chatShopUnreadCount(count));

  /// Pumps that move the clock: Dio finishes a request through timers, which a bare pump() — no
  /// duration, so no time passes — never runs.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));
  }

  Future<_Gateway> pumpShell(WidgetTester tester, PortalArea area) async {
    final _Gateway gateway = _Gateway();
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = gateway;
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: PortalShell(
        areas: <PortalArea>[area],
        apis: _apis(dio),
        locale: LocaleController(read: () async => 'en', write: (String _) async {}),
        session: AuthSession(
          accessToken: 'token',
          refreshToken: null,
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          roles: const <DeliveryRole>{DeliveryRole.merchant},
          subject: 'merchant-sub',
        ),
        onSignOut: () async {},
      ),
    ));
    await settle(tester);
    return gateway;
  }

  testWidgets('the merchant rail shows how many customer messages are unread, and keeps it current',
      (WidgetTester tester) async {
    final _Gateway gateway = await pumpShell(tester, _area(withMessages: true));

    expect(badgeSaying(3), findsOneWidget);
    expect(find.descendant(of: find.byType(ConsoleSidebar), matching: find.text('3')), findsOneWidget);

    gateway.unread = 1;
    await tester.pump(ShopUnreadCount.defaultInterval);
    await settle(tester);

    expect(badgeSaying(1), findsOneWidget,
        reason: 'With no socket, the number is asked again while the portal is on screen.');
    expect(badgeSaying(3), findsNothing);
  });

  testWidgets('a rail without the messages row never asks for them', (WidgetTester tester) async {
    final _Gateway gateway = await pumpShell(tester, _area(withMessages: false));
    await tester.pump(const Duration(minutes: 3));

    expect(gateway.asked, isNot(contains('/api/chat/shop-threads/inbox')));
  });

  test("the real merchant rail puts the number on its customer messages row", () {
    final List<PortalDestination> badged = PortalArea.merchant_.destinations
        .where((PortalDestination d) => d.badge == PortalBadge.shopUnread)
        .toList();

    expect(badged, hasLength(1));
    expect(badged.single.label(en), en.chatShopInboxTitle);
  });
}
