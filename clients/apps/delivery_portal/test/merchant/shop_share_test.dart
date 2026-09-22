import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:delivery_portal/src/portal_shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the merchant web finds its shop's page, its QR code and its poster.
///
/// **On My shop, and nowhere else.** A nav-rail tab for one QR code would be a tab a merchant
/// visits once and then never again, and the rail's order is load-bearing besides — the dashboard's
/// "see all orders" is `jump(2)`. So the share block sits on the page a merchant already opens to
/// look at their shop, and this pins both halves: the block is on that page, and the rail did not
/// grow a tab.
///
/// The other half is the web's own answer to Share. There is no share sheet on a desktop browser,
/// so the portal wires none and the button copies the link with a confirmation — the same widget
/// the phone mounts with a real sheet behind it.
class _Gateway implements HttpClientAdapter {
  _Gateway({this.pinned = true});

  final bool pinned;

  Map<String, dynamic> get _shop => <String, dynamic>{
        'id': 'shop-grill',
        'slug': 'beirut-grill',
        'name': 'Beirut Grill',
        'vertical': 'RESTAURANT',
        'availability': 'OPEN',
        'status': 'ACTIVE',
        'deliveryFee': 2.0,
        'minOrder': 5.0,
        'etaMinMinutes': 20,
        'etaMaxMinutes': 40,
        if (pinned) 'latitude': 33.8938,
        if (pinned) 'longitude': 35.5018,
      };

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    final Object body = options.path.endsWith('/mine')
        ? <String, dynamic>{
            'content': <Map<String, dynamic>>[_shop],
            'page': 0,
            'size': 20,
            'totalElements': 1,
            'totalPages': 1,
          }
        : options.path.endsWith('/hours')
            ? <dynamic>[]
            : _shop;
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
      shopChat: ShopChatApi(dio),
      moderation: ChatModerationApi(dio),
      attachments: OrderAttachmentApi(dio),
      offerModeration: BackofficeCatalogApi(dio),
    );

final LocaleController _locale =
    LocaleController(read: () async => null, write: (String _) async {});

/// The real My shop destination, built the way the shell builds it.
Future<List<String>> _openMyShop(
  WidgetTester tester, {
  bool pinned = true,
  Locale locale = const Locale('en'),
  Size size = const Size(1280, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final List<String> copied = <String>[];
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
    if (call.method == 'Clipboard.setData') {
      copied.add((call.arguments as Map<Object?, Object?>)['text'] as String);
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));

  final DeliveryStrings t = lookupDeliveryStrings(locale);
  final PortalDestination myShop = PortalArea.merchant_.destinations
      .singleWhere((PortalDestination d) => d.label(t) == t.navMyShop);
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))
    ..httpClientAdapter = _Gateway(pinned: pinned);

  await tester.pumpWidget(MaterialApp(
    theme: DeliveryTheme.light(),
    locale: locale,
    localizationsDelegates: const <LocalizationsDelegate<Object>>[
      DeliveryStrings.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: DeliveryStrings.supportedLocales,
    home: myShop.buildPage(0, _apis(dio), _locale, () async {}, (int _) {}),
  ));
  await tester.pumpAndSettle();
  return copied;
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  test('the rail did not grow a tab for it', () {
    final List<String> hub = <String>[
      for (final PortalDestination d in PortalArea.merchant_.destinations) d.label(en),
    ];

    expect(hub, isNot(contains(en.merchShareTitle)));
    // Still where it was: the dashboard's "see all orders" is jump(2).
    expect(hub[2], en.navOrders);
    expect(hub[6], en.navMyShop);
  });

  testWidgets('My shop carries the shop page, its QR code and the poster',
      (WidgetTester tester) async {
    await _openMyShop(tester);

    expect(find.byType(ShopShareCard), findsOneWidget);
    expect(find.text('https://www.youdrop.shop/s/beirut-grill'), findsOneWidget);
    expect(find.text(en.merchSharePrintQr), findsOneWidget);
    // And, new beside it, the table codes: the portal's only home for the share block is this
    // page, so a shop that set its tables on the phone reprints a card from the desk here.
    expect(find.text(en.merchTablesTitle), findsOneWidget);
  });

  testWidgets('with no share sheet on a desktop browser, Share copies and confirms',
      (WidgetTester tester) async {
    final List<String> copied = await _openMyShop(tester);

    await tester.tap(find.text(en.merchShareShare));
    await tester.pumpAndSettle();

    expect(copied, <String>['https://www.youdrop.shop/s/beirut-grill']);
    expect(find.text(en.merchShareLinkCopied), findsOneWidget);
  });

  testWidgets('a shop with no pin is told what fixes it instead of being shown a dead code',
      (WidgetTester tester) async {
    await _openMyShop(tester, pinned: false);

    expect(find.text(en.merchShareNoPageTitle), findsOneWidget);
    expect(find.text(en.merchShareNeedsPin), findsOneWidget);
    // The map it points at is on this very page, so the fix is a scroll and not a second screen.
    expect(find.text(en.merchSharePlaceOnMap), findsOneWidget);
  });

  testWidgets('it reads in Arabic, right to left, on a 320dp pane',
      (WidgetTester tester) async {
    await _openMyShop(tester, locale: const Locale('ar'), size: const Size(320, 2400));

    expect(Directionality.of(tester.element(find.byType(ShopShareCard))), TextDirection.rtl);
    expect(find.byTooltip(ar.merchShareCopyLink), findsOneWidget);
    expect(find.text(ar.merchSharePrintQr), findsOneWidget);
    expect(find.text(ar.merchTablesTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
