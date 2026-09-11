import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/carrier/company_screen.dart';
import 'package:delivery_portal/src/portal_shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The carrier rail, as the portal actually builds it.
///
/// Every carrier screen takes its clients from the shell, and several of them treat a client that
/// was not passed as "not wired up in this build" rather than as an error — which is exactly how
/// the Riders page shipped with its status, region, join date, Add Rider and suspension all dead:
/// the screen was finished and tested, and the one line in the shell that builds it passed two of
/// its six clients. Nothing failed, so nothing said so. These tests build the destinations through
/// the shell's own table and check what each screen was handed.
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
  );
}

final LocaleController _locale =
    LocaleController(read: () async => null, write: (String _) async {});

Widget _build(PortalDestination d, PortalApis apis) =>
    d.build(apis, _locale, () async {}, (int _) {});

void main() {
  test('the Riders page is built with every client it reads', () {
    final PortalApis apis = _apis();
    final PortalDestination riders = PortalArea.carrier_.destinations
        .firstWhere((PortalDestination d) => _build(d, apis) is CompanyScreen);

    final CompanyScreen screen = _build(riders, apis) as CompanyScreen;

    expect(screen.api, same(apis.provider));
    expect(screen.orderApi, same(apis.order));
    // The four the shell withheld. Each is what one visible part of the page reads from.
    expect(screen.onboardingApi, same(apis.onboarding), reason: 'names, regions, Add Rider');
    expect(screen.managementApi, same(apis.partnerManagement), reason: 'suspension');
    expect(screen.trackingApi, same(apis.tracking), reason: 'presence and hours online');
    expect(screen.performanceApi, same(apis.riderPerformance), reason: 'today and 30 days');
  });
}
