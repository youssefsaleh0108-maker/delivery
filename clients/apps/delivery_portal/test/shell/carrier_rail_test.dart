import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/carrier/applicants_screen.dart';
import 'package:delivery_portal/src/carrier/cash_reconciliation_screen.dart';
import 'package:delivery_portal/src/carrier/dashboard_screen.dart';
import 'package:delivery_portal/src/carrier/earnings_screen.dart';
import 'package:delivery_portal/src/carrier/jobs_screen.dart';
import 'package:delivery_portal/src/carrier/payroll_screen.dart';
import 'package:delivery_portal/src/carrier/rider_attendance_screen.dart';
import 'package:delivery_portal/src/carrier/rider_profile_screen.dart';
import 'package:delivery_portal/src/carrier/riders_directory_screen.dart';
import 'package:delivery_portal/src/carrier/settings_screen.dart';
import 'package:delivery_portal/src/carrier/shift_schedule_screen.dart';
import 'package:delivery_portal/src/carrier/statement_screen.dart';
import 'package:delivery_portal/src/portal_shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The carrier rail, as the portal actually builds it.
///
/// Every carrier screen takes its clients from the shell, and the one line that builds a screen is
/// the easiest line in the app to get wrong without anything failing: the riders page shipped with
/// four of its six clients withheld, and its status, region, join date, Add Rider and suspension
/// were all dead in the deployed build while every test of the screen itself passed. So these
/// build the destinations through the shell's own table and check what each page was handed.
///
/// And because the rail was restructured onto the design's headings (Figma 112:414), they also pin
/// the promise that came with it: every page the older rail listed is still reachable, no heading
/// is drawn without a page behind it, and a row under a heading actually opens its page.
PortalApis _apis({HttpClientAdapter? adapter}) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'));
  if (adapter != null) dio.httpClientAdapter = adapter;
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
  );
}

/// Answers every request with a 404, so the pages mounted by the shell test settle into their
/// "could not load" states instead of reaching for a network.
class _NothingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
          Future<void>? cancelFuture) async =>
      ResponseBody.fromString('{"message":"no"}', 404, headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      });

  @override
  void close({bool force = false}) {}
}

final LocaleController _locale =
    LocaleController(read: () async => null, write: (String _) async {});

Widget _page(PortalDestination d, int page, PortalApis apis) =>
    d.buildPage(page, apis, _locale, () async {}, (int _) {});

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final List<PortalDestination> rail = PortalArea.carrier_.destinations;

  test('is the design\'s headings in the design\'s order, less the two with no page yet', () {
    // Figma 112:414 draws Dashboard, Orders, Fleet, Reconciliation, Riders HR, Earnings, Coverage,
    // Settings. Fleet and Coverage have no page in this portal, and a heading that opens nothing is
    // a dead control.
    expect(
      <String>[for (final PortalDestination d in rail) d.label(en)],
      <String>[
        en.navDashboard,
        en.navOrders,
        en.carrRidersNavReconciliation,
        en.carrRidersNavRidersHr,
        en.navEarnings,
        en.navSettings,
      ],
    );
  });

  test('Orders sits at index 1, where the dashboard\'s job-board link jumps', () {
    final PortalApis apis = _apis();
    int? jumpedTo;
    final Widget dashboard =
        rail.first.buildPage(0, apis, _locale, () async {}, (int i) => jumpedTo = i);

    (dashboard as CarrierDashboardScreen).onShowJobs!();

    expect(jumpedTo, 1);
    expect(_page(rail[jumpedTo!], 0, apis), isA<JobsScreen>());
  });

  test('the dashboard is built with every client it reads', () {
    final PortalApis apis = _apis();
    final CarrierDashboardScreen screen = _page(rail.first, 0, apis) as CarrierDashboardScreen;

    expect(screen.api, same(apis.order));
    expect(screen.providerApi, same(apis.provider));
    // Withheld, these two left the week-over-week lines and the fleet card's delivered-today count
    // dead in the deployed build.
    expect(screen.aggregatesApi, same(apis.aggregates), reason: 'week over week');
    expect(screen.performanceApi, same(apis.riderPerformance), reason: 'delivered today');
  });

  test('every page the older rail listed is still reachable, and each only once', () {
    final PortalApis apis = _apis();
    final List<Type> reachable = <Type>[
      for (final PortalDestination d in rail)
        for (int page = 0; page < (d.pages.isEmpty ? 1 : d.pages.length); page++)
          _page(d, page, apis).runtimeType,
    ];

    // The seven destinations of the rail this replaced: Dashboard, Jobs, Earnings, Statement, the
    // riders page (now the directory), Applicants and Settings — and Shifts & attendance, which
    // had its own destination until it was filed under Riders HR, and the rider cash
    // reconciliation and payroll, which each had their own until they were filed under
    // Reconciliation and Riders HR.
    expect(
      reachable,
      unorderedEquals(<Type>[
        CarrierDashboardScreen,
        JobsScreen,
        CarrierCashScreen,
        CarrierStatementScreen,
        RidersDirectoryScreen,
        ApplicantsScreen,
        ShiftScheduleScreen,
        CarrierPayrollScreen,
        EarningsScreen,
        CarrierSettingsScreen,
      ]),
    );
  });

  test('a heading opens its first page, and names its pages for the rows under it', () {
    final PortalApis apis = _apis();
    final PortalDestination reconciliation = rail[2];
    final PortalDestination ridersHr = rail[3];

    // The rider cash reconciliation is the page the design draws under this heading (Figma 112:9),
    // and its row is the page's title: the design's own label for it is the heading's word.
    expect(reconciliation.build(apis, _locale, () async {}, (int _) {}), isA<CarrierCashScreen>());
    expect(
      <String>[for (final PortalPage p in reconciliation.pages) p.label(en)],
      <String>[en.carrCashTitle, en.carrRidersNavStatement],
    );
    expect(ridersHr.build(apis, _locale, () async {}, (int _) {}), isA<RidersDirectoryScreen>());
    expect(
      <String>[for (final PortalPage p in ridersHr.pages) p.label(en)],
      <String>[
        en.carrRidersNavDirectory,
        en.navApplicants,
        en.attendanceNavShifts,
        en.payrollNavLabel,
      ],
    );
    // A page the heading does not have opens the first rather than throwing.
    expect(_page(ridersHr, 9, apis), isA<RidersDirectoryScreen>());
  });

  test('the rider cash reconciliation is built with every client it reads', () {
    final PortalApis apis = _apis();
    final CarrierCashScreen screen = _page(rail[2], 0, apis) as CarrierCashScreen;

    // Both optional, so withholding either still compiles and leaves part of the page dead in the
    // deployed build, the fault the riders page once shipped with.
    expect(screen.notificationApi, same(apis.notification), reason: 'the bell');
    expect(screen.orderApi, same(apis.order), reason: 'each rider\'s settlement page');
  });

  test('payroll is filed last under Riders HR, and built with the clients it reads', () {
    final PortalApis apis = _apis();
    final PortalDestination ridersHr = rail[3];

    // The design files payroll (Figma 112:1162) under Riders HR, after the shifts it pays for.
    final CarrierPayrollScreen screen =
        _page(ridersHr, ridersHr.pages.length - 1, apis) as CarrierPayrollScreen;
    expect(screen.api, isA<CarrierPayrollApi>());
    // Optional, so withholding it still compiles and leaves the page's bell dead.
    expect(screen.notificationApi, same(apis.notification), reason: 'the bell');
  });

  test('Shifts & attendance is filed under Riders HR, and built with every client it reads', () {
    final PortalApis apis = _apis();
    final PortalDestination ridersHr = rail[3];
    final int shifts =
        ridersHr.pages.indexWhere((PortalPage p) => p.label(en) == en.attendanceNavShifts);
    final int applicants =
        ridersHr.pages.indexWhere((PortalPage p) => p.label(en) == en.navApplicants);

    // Straight after the applicant queue, where the shell files pages about the whole fleet's
    // people; payroll, which pays for the shifts, follows it.
    expect(shifts, applicants + 1);
    final ShiftScheduleScreen screen = _page(ridersHr, shifts, apis) as ShiftScheduleScreen;
    expect(screen.api, same(apis.tracking), reason: 'shifts, schedules and each month');
    expect(screen.providerApi, same(apis.provider), reason: 'the company and its riders');
    expect(screen.onboardingApi, same(apis.onboarding), reason: 'the riders\' names');
  });

  testWidgets('a rider\'s profile opens their attendance month, with the way back to the profile',
      (WidgetTester tester) async {
    final PortalApis apis = _apis();
    final List<RiderPage> pages = PortalArea.carrierRiderPages(apis);
    expect(<String>[for (final RiderPage p in pages) p.label(en)],
        <String>[en.attendanceOpenAttendance]);

    Widget? built;
    bool wentBack = false;
    await tester.pumpWidget(MaterialApp(
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(builder: (BuildContext context) {
        built = pages.single.build(
          context,
          const RiderPageContext(riderId: 'rider-1', name: 'Nadia Haddad', companyId: 'p1'),
          () => wentBack = true,
        );
        return const SizedBox();
      }),
    ));

    final RiderAttendanceScreen screen = built! as RiderAttendanceScreen;
    expect(screen.api, same(apis.tracking));
    expect(screen.riderId, 'rider-1');
    expect(screen.riderName, 'Nadia Haddad');
    expect(screen.backTooltip, en.attendanceBackToProfile);
    screen.onBack!();
    expect(wentBack, isTrue);
  });

  test('the riders directory is built with every client it reads', () {
    final PortalApis apis = _apis();
    final RidersDirectoryScreen screen = _page(rail[3], 0, apis) as RidersDirectoryScreen;

    expect(screen.api, same(apis.provider));
    // Each is what one visible part of the directory or the profile behind it reads from.
    expect(screen.orderApi, same(apis.order), reason: 'ratings, and "On a job"');
    expect(screen.onboardingApi, same(apis.onboarding), reason: 'names, regions, Add Rider');
    expect(screen.managementApi, same(apis.partnerManagement), reason: 'suspension');
    expect(screen.trackingApi, same(apis.tracking), reason: 'presence and hours online');
    expect(screen.performanceApi, same(apis.riderPerformance), reason: 'today, 30 days, chart');
    expect(screen.documentsApi, same(apis.documents), reason: 'the profile\'s papers');
    expect(screen.notificationApi, same(apis.notification), reason: 'the bell');
    // The shell's own per-rider pages, which the profile draws as buttons. Compared by label: each
    // call builds fresh entries around the clients it is handed.
    expect(
      <String>[for (final RiderPage p in screen.riderPages) p.label(en)],
      <String>[for (final RiderPage p in PortalArea.carrierRiderPages(apis)) p.label(en)],
    );
    expect(screen.riderPages, isNotEmpty);
  });

  testWidgets('a row under a heading opens its page, and the heading opens the first',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: PortalShell(
        areas: <PortalArea>[PortalArea.carrier_],
        apis: _apis(adapter: _NothingAdapter()),
        locale: _locale,
        session: const AuthSession(
          accessToken: 'not-a-jwt',
          refreshToken: null,
          expiresAt: null,
          roles: <DeliveryRole>{DeliveryRole.carrier},
          subject: 'carrier-staff',
        ),
        onSignOut: () async {},
      ),
    ));
    // Settled after every move rather than pumped once: each page's first request runs on a timer,
    // and a timer left pending when the test ends fails it.
    await tester.pumpAndSettle();
    expect(find.byType(CarrierDashboardScreen), findsOneWidget);

    // Reconciliation has two pages, so both are rows beneath it and the heading opens the first:
    // the rider cash reconciliation. The statement opens from its own row.
    await tester.tap(find.text(en.carrRidersNavReconciliation));
    await tester.pumpAndSettle();
    expect(find.byType(CarrierCashScreen), findsOneWidget);
    await tester.tap(find.text(en.carrRidersNavStatement));
    await tester.pumpAndSettle();
    expect(find.byType(CarrierStatementScreen), findsOneWidget);
    expect(find.byType(CarrierCashScreen), findsNothing);

    // A heading with two draws both beneath it, and opens on the first.
    await tester.tap(find.text(en.carrRidersNavRidersHr));
    await tester.pumpAndSettle();
    expect(find.byType(RidersDirectoryScreen), findsOneWidget);
    expect(find.text(en.carrRidersNavDirectory), findsOneWidget);

    await tester.tap(find.text(en.navApplicants));
    await tester.pumpAndSettle();
    expect(find.byType(ApplicantsScreen), findsOneWidget);
    expect(find.byType(RidersDirectoryScreen), findsNothing);

    // Moving to another destination and back opens the heading on its first page again.
    await tester.tap(find.text(en.navEarnings));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.carrRidersNavRidersHr));
    await tester.pumpAndSettle();
    expect(find.byType(RidersDirectoryScreen), findsOneWidget);

    // Unmounted, so the polls the pages start end with the test, and settled so the requests
    // already on their way finish inside it.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
