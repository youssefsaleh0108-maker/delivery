import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:delivery_portal/src/portal_shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// That the merchant web portal can reach Merchant Blitz (Figma 121:198).
///
/// InventoryScreen draws "Scan shelves" only when its host hands it a scan client, and draws nothing
/// otherwise — the right behaviour for a host without one, and exactly how a finished screen ships
/// unreachable with every test green. The phone's shell has its own wiring test; this is the
/// portal's: the merchant area's real Inventory destination, built from a real [PortalApis], opens
/// the scan.
class _StubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // An empty page answers the store lookup and the shelves alike; nothing here is about contents.
    return ResponseBody.fromString('{"content":[],"totalElements":0}', 200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets("the portal's Inventory page opens Merchant Blitz", (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = _StubAdapter();
    final PortalApis apis = PortalApis(
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
    final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
    final PortalDestination inventory = PortalArea.merchant_.destinations
        .singleWhere((PortalDestination d) => d.label(en) == en.navInventory);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      locale: const Locale('en'),
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: Scaffold(
        body: inventory.build(
          apis,
          LocaleController(read: () async => null, write: (String _) async {}),
          () async {},
          (int _) {},
        ),
      ),
    ));
    // The destination waits for the store lookup before it builds the page.
    for (int i = 0; i < 20 && find.byType(InventoryScreen).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(InventoryScreen), findsOneWidget);

    await tester.tap(find.text(en.blitzEntryAction).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(MerchantBlitzScreen), findsOneWidget);
  });
}
