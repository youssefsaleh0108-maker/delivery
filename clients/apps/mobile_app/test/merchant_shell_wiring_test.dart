import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/merchant_shell.dart';

/// That the shop can actually REACH the screens this shell owns.
///
/// Written because one of them could not. The merchant statement screen, its Arabic strings and its
/// "this figure is not a payment" notice were built, tested and exported — and shipped dead, because
/// [MerchantShell] never took a [StatementsApi] and the settings row hides itself when unwired. The
/// screen's own tests passed the whole time: they constructed it directly and wired the client
/// themselves, so nothing anywhere failed while the only real host on the phone did not pass it.
///
/// So what is pinned here is not what the screen renders. It is that the shell HANDS IT OVER — the
/// join between a finished screen and the app that is supposed to open it, which is exactly the seam
/// a green suite cannot see.
class _StubAdapter implements HttpClientAdapter {
  final List<String> calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    // Empty collections and a bare object satisfy every screen the shell builds on open — except an
    // employee's two staff lookups, which say where they work and what they may do there.
    final String body;
    if (options.path.endsWith('/staff/membership')) {
      body = '{"member":true,"storeId":"store-1"}';
    } else if (options.path.endsWith('/staff/me')) {
      body = '{"member":true,"owner":false,"permissions":["MODIFY_INVENTORY_PRICING"]}';
    } else if (options.path.contains('orders') || options.path.contains('products')) {
      body = '{"content":[],"totalElements":0}';
    } else {
      body = '{}';
    }
    return ResponseBody.fromString(body, 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Dio dio;
  late _StubAdapter adapter;

  setUp(() {
    adapter = _StubAdapter();
    dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;
  });

  /// Pumps the shell and opens one of its tabs the way a merchant does, through the shell's own
  /// bottom bar: Settings, or the shelves when [inventory].
  Future<DeliveryStrings> pumpShell(
    WidgetTester tester, {
    bool wireStatements = false,
    bool wireScan = false,
    bool wireStaff = false,
    bool inventory = false,
    bool wireChat = false,
    Set<DeliveryRole> roles = const <DeliveryRole>{DeliveryRole.merchant},
  }) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: MerchantShell(
        orderApi: OrderApi(dio),
        storeApi: StoreApi(dio),
        catalogApi: CatalogApi(dio),
        statementsApi: wireStatements ? StatementsApi(dio) : null,
        catalogScanApi: wireScan ? CatalogScanApi(dio) : null,
        staffApi: wireStaff ? StoreStaffApi(dio) : null,
        shopChatApi: wireChat ? ShopChatApi(dio) : null,
        session: AuthSession(
          accessToken: 'token',
          refreshToken: null,
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          roles: roles,
          subject: 'merchant-sub',
        ),
        locale: LocaleController(
          read: () async => 'en',
          write: (String _) async {},
        ),
        onSignOut: () async {},
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final DeliveryStrings t =
        DeliveryStrings.of(tester.element(find.byType(MerchantShell)));
    await tester.tap(find.text(inventory ? t.navInventory : t.navSettings).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return t;
  }

  testWidgets('the shop can open its own statement from Settings', (WidgetTester tester) async {
    await pumpShell(tester, wireStatements: true);

    // The row the app shipped without. Its title comes from the statement screen's own words, so
    // this also proves the two halves agree about what it is called.
    expect(find.text(MerchantStatementWords.of(
            tester.element(find.byType(MerchantShell)))
        .title), findsOneWidget);
  });

  testWidgets('and the row hides rather than dying when a host does not wire it',
      (WidgetTester tester) async {
    await pumpShell(tester, wireStatements: false);

    // The optional-client convention this shell uses throughout: no client, no row. Correct on its
    // own — it is only a problem when the real host forgets, which the test above now catches.
    expect(find.text(MerchantStatementWords.of(
            tester.element(find.byType(MerchantShell)))
        .title), findsNothing);
  });

  // Merchant Blitz (Figma 121:198) — the same seam, for a screen with two doors.

  testWidgets('the owner can build the catalogue from shelf photos, from Settings',
      (WidgetTester tester) async {
    final DeliveryStrings t = await pumpShell(tester, wireScan: true);

    await tester.tap(find.text(t.blitzSettingsRow));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(MerchantBlitzScreen), findsOneWidget);
  });

  testWidgets('and from the shelves themselves', (WidgetTester tester) async {
    final DeliveryStrings t = await pumpShell(tester, wireScan: true, inventory: true);

    await tester.tap(find.text(t.blitzEntryAction).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(MerchantBlitzScreen), findsOneWidget);
  });

  testWidgets('an employee is not offered it: the scan endpoints refuse a staff token',
      (WidgetTester tester) async {
    final DeliveryStrings t = await pumpShell(
      tester,
      wireScan: true,
      roles: const <DeliveryRole>{DeliveryRole.merchantStaff},
    );

    // On the Settings page — so the row's absence below is the gate, not an unopened tab.
    expect(find.byType(MerchantSettingsScreen), findsOneWidget);
    expect(find.text(t.blitzSettingsRow), findsNothing);
  });

  testWidgets('nor on the shelves, even for an employee the shop lets manage its stock',
      (WidgetTester tester) async {
    final DeliveryStrings t = await pumpShell(
      tester,
      wireScan: true,
      wireStaff: true,
      inventory: true,
      roles: const <DeliveryRole>{DeliveryRole.merchantStaff},
    );

    // On the shelves, which this employee may manage — so the button's absence below is the role
    // gate on the Inventory wiring, not a tab the employee was never given.
    expect(find.byType(InventoryScreen), findsOneWidget);
    expect(find.text(t.blitzEntryAction), findsNothing);
  });

  // The Demand Radar (Figma 121:8) has two doors, and the shell decides who gets them: the owner,
  // with the client wired. An employee carries a MERCHANT_STAFF token that Order Manager refuses, so
  // a door for them would open onto a 403.
  group('the Demand Radar', () {
    Future<DeliveryStrings> pumpShell(
      WidgetTester tester, {
      required bool wireDemand,
      Set<DeliveryRole> roles = const <DeliveryRole>{DeliveryRole.merchant},
    }) async {
      tester.view.physicalSize = const Size(1100, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: DeliveryTheme.light(),
        localizationsDelegates: DeliveryStrings.localizationsDelegates,
        supportedLocales: DeliveryStrings.supportedLocales,
        home: MerchantShell(
          orderApi: OrderApi(dio),
          storeApi: StoreApi(dio),
          catalogApi: CatalogApi(dio),
          demandApi: wireDemand ? DemandApi(dio) : null,
          session: AuthSession(
            accessToken: 'token',
            refreshToken: null,
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
            roles: roles,
            subject: 'merchant-sub',
          ),
          locale: LocaleController(
            read: () async => 'en',
            write: (String _) async {},
          ),
          onSignOut: () async {},
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return DeliveryStrings.of(tester.element(find.byType(MerchantShell)));
    }

    Future<void> openSettings(WidgetTester tester, DeliveryStrings t) async {
      await tester.tap(find.text(t.navSettings).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Finder settingsRow(DeliveryStrings t) => find.descendant(
        of: find.byType(MerchantSettingsScreen), matching: find.text(t.heatmapTitle));

    testWidgets('the owner reaches it from the dashboard and from Settings',
        (WidgetTester tester) async {
      final DeliveryStrings t = await pumpShell(tester, wireDemand: true);

      // The dashboard is handed its door; what the card looks like is the merchant package's test.
      expect(
        tester.widget<MerchantDashboardScreen>(find.byType(MerchantDashboardScreen)).onDemandRadar,
        isNotNull,
      );

      await openSettings(tester, t);
      await tester.tap(settingsRow(t));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(DemandRadarScreen), findsOneWidget);
    });

    testWidgets('an employee is given no door at all', (WidgetTester tester) async {
      final DeliveryStrings t = await pumpShell(
        tester,
        wireDemand: true,
        roles: const <DeliveryRole>{DeliveryRole.merchantStaff},
      );

      await openSettings(tester, t);

      expect(find.byType(MerchantSettingsScreen), findsOneWidget);
      expect(settingsRow(t), findsNothing);
      expect(find.byType(MerchantDashboardScreen), findsNothing);
    });

    testWidgets('a host that does not wire the client draws no door rather than a dead one',
        (WidgetTester tester) async {
      final DeliveryStrings t = await pumpShell(tester, wireDemand: false);

      expect(
        tester.widget<MerchantDashboardScreen>(find.byType(MerchantDashboardScreen)).onDemandRadar,
        isNull,
      );
      await openSettings(tester, t);
      expect(settingsRow(t), findsNothing);
    });
  });

  /// Customers can message a shop from its page; without this row the shop could never read them.
  testWidgets('the shop can open its customers\' messages from Settings', (WidgetTester tester) async {
    final DeliveryStrings t = await pumpShell(tester, wireChat: true);

    await tester.tap(find.text(t.chatShopInboxTitle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ShopInboxScreen), findsOneWidget);
  });

  testWidgets('and without a chat client there is no messages row to open',
      (WidgetTester tester) async {
    final DeliveryStrings t = await pumpShell(tester);

    expect(find.text(t.chatShopInboxTitle), findsNothing);
  });
}
