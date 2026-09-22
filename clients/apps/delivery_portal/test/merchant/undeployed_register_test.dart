import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:delivery_portal/src/portal_shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// PT-8: the merchant rail's POS page on an environment where pos-service does not exist.
///
/// PortalApis says the register's screens "say so calmly" while the service is not deployed, and
/// PosTerminalScreen has exactly that state — the "register is not available yet" band — but only
/// for a host that passes no client. The portal always passes one, so on dev and qa today (no
/// pos-service; Traefik answers every /api/pos path with its own plain-text 404) the merchant gets a
/// working-looking till: products to tap, and "could not load the sale" on every tap.
///
/// The backend below is dev's, as measured on 2026-09-19: product-service answers, /api/pos is
/// Traefik's 404. The test FAILS today.
class _DevLikeBackend implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    final String path = options.path;
    if (path.startsWith('/api/pos') || path.startsWith('/api/inventory')) {
      // Exactly what the edge sends for a path no router matches.
      return ResponseBody.fromString('404 page not found\n', 404, headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/plain; charset=utf-8'],
      });
    }
    Object body = <String, dynamic>{'content': <dynamic>[], 'totalElements': 0};
    if (path == '/api/stores/mine') {
      body = <String, dynamic>{
        'content': <dynamic>[
          <String, dynamic>{'id': 'store-1', 'name': 'Shop', 'status': 'ACTIVE', 'vertical': 'RESTAURANT'},
        ],
        'totalElements': 1,
      };
    } else if (path == '/api/products/mine') {
      body = <String, dynamic>{
        'content': <dynamic>[
          <String, dynamic>{
            'id': 'p1',
            'storeId': 'store-1',
            'name': 'Manoushe',
            'price': 3.5,
            'status': 'ACTIVE',
            'images': <dynamic>[],
          },
        ],
        'totalElements': 1,
      };
    } else if (path == '/api/categories') {
      body = <dynamic>[];
    }
    return ResponseBody.fromString(jsonEncode(body), 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
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

void main() {
  testWidgets('PT-8: with no pos-service behind it, the POS page says the register is not available',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final _DevLikeBackend backend = _DevLikeBackend();
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = backend;
    final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
    final PortalDestination pos = PortalArea.merchant_.destinations
        .singleWhere((PortalDestination d) => d.label(en) == en.navPos);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      locale: const Locale('en'),
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: Scaffold(
        body: pos.build(
          _apis(dio),
          LocaleController(read: () async => null, write: (String _) async {}),
          () async {},
          (int _) {},
        ),
      ),
    ));
    for (int i = 0; i < 20 && find.byType(PosTerminalScreen).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(PosTerminalScreen), findsOneWidget);
    await tester.pumpAndSettle();

    // The page asked pos-service and was told nothing is there.
    expect(backend.requests.where((RequestOptions r) => r.path.startsWith('/api/pos')), isNotEmpty);
    expect(find.text(en.posTerminalUnavailable), findsOneWidget,
        reason: 'pos-service answered 404 to everything, yet the till is drawn as if it worked');
  });
}
