import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/backoffice/dashboard_screen.dart';
import 'package:delivery_portal/src/backoffice/overview_screen.dart';
import 'package:delivery_portal/src/backoffice/service_offers_screen.dart';
import 'package:delivery_portal/src/backoffice/shops_screen.dart';
import 'package:delivery_portal/src/portal_shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The back-office rail, as the portal actually builds it.
///
/// The services back office adds two pages. Pinned: every destination the rail already had keeps its
/// position — the overview's "see all orders" jumps to index 1, and any link that counts rows stays
/// right — with the two new pages after them; and each page is handed its clients by the shell, the
/// one line that is easiest to get wrong while every test of the screen itself passes.
PortalApis _apis() {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'));
  return PortalApis(
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
}

final LocaleController _locale =
    LocaleController(read: () async => null, write: (String _) async {});

Widget _page(PortalDestination d, PortalApis apis, {void Function(int)? jump}) =>
    d.buildPage(0, apis, _locale, () async {}, jump ?? (int _) {});

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final List<PortalDestination> rail = PortalArea.backoffice_.destinations;

  PortalDestination named(String label) =>
      rail.singleWhere((PortalDestination d) => d.label(en) == label);

  test('every destination keeps its position, and the services pages come after them', () {
    expect(
      <String>[for (final PortalDestination d in rail) d.label(en)],
      <String>[
        // The rail as it stood before the services back office, position for position.
        en.navDashboard,
        en.navOrders,
        en.navCategories,
        en.navCatalog,
        en.navBanners,
        en.navOnboarding,
        en.navCarriers,
        'Riders',
        en.navAreas,
        en.navFinance,
        'Statements',
        en.navOffers,
        'Promo Codes',
        en.chatModerationTitle,
        en.navSettings,
        // Appended.
        en.svcBoOffersTitle,
        en.svcBoShopsTitle,
      ],
    );
  });

  test('the overview still jumps to the orders ledger at index 1', () {
    int? jumpedTo;
    final Widget overview = _page(rail.first, _apis(), jump: (int i) => jumpedTo = i);

    (overview as OverviewScreen).onShowOrders!();

    expect(jumpedTo, 1);
    expect(_page(rail[1], _apis()), isA<DashboardScreen>());
  });

  test("the ledger is handed the attachment client for a service order's files", () {
    final PortalApis apis = _apis();
    final DashboardScreen ledger = _page(rail[1], apis) as DashboardScreen;

    expect(ledger.api, same(apis.order));
    expect(ledger.attachmentApi, same(apis.attachments));
  });

  test('Service offers is handed the moderation client', () {
    final PortalApis apis = _apis();

    expect((_page(named(en.svcBoOffersTitle), apis) as ServiceOffersScreen).api,
        same(apis.offerModeration));
  });

  test('Shops is handed the store client, which sets the badge', () {
    final PortalApis apis = _apis();

    expect((_page(named(en.svcBoShopsTitle), apis) as ShopsScreen).api, same(apis.store));
  });

  test('the services pages are on the back-office rail and nowhere else', () {
    bool offers(PortalArea area, String label) =>
        area.destinations.any((PortalDestination d) => d.label(en) == label);

    for (final String label in <String>[en.svcBoOffersTitle, en.svcBoShopsTitle]) {
      expect(offers(PortalArea.backoffice_, label), isTrue);
      expect(offers(PortalArea.merchant_, label), isFalse);
      expect(offers(PortalArea.carrier_, label), isFalse);
    }
  });
}
