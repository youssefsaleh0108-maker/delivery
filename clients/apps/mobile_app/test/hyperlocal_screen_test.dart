import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart' show ShopThreadScreen;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile_app/src/address_sheet.dart' show OsmBasemap;
import 'package:mobile_app/src/cart.dart';
import 'package:mobile_app/src/cart_screen.dart' show CartScreen;
import 'package:mobile_app/src/customer_shell.dart';
import 'package:mobile_app/src/delivery_address.dart';
import 'package:mobile_app/src/hyperlocal_screen.dart';
import 'package:mobile_app/src/neighbourhood_chat_screen.dart';
import 'package:mobile_app/src/neighbourhood_map_screen.dart';
import 'package:mobile_app/src/store_page_screen.dart';
import 'package:mobile_app/src/store_power_chip.dart' show DekkanePowerPill, DekkaneStatePill;

import 'widget_test.dart' show sessionWith;

/// The neighbourhood browse (Figma 112:1941).
///
/// It was built and then never opened — the surface checklist listed it as UNREACHABLE — so the
/// first thing pinned here is the road to it from Home, through the real shell, and the road back:
/// a shop opened from it hands the shell's own basket callback to its basket bar. The rest pins what
/// the redesign asks of it on real data: the list is measured from the customer's pinned address,
/// every chip is a question the server answers (and the frame's "Has generator" is asked as what it
/// can truthfully be — "on generator now"), and nothing is drawn that the data does not have: no
/// distance, chips or map without a point, no neighbourhood title over the whole storefront, no
/// trust badge Backoffice did not grant, no power badge for a shop that never declared or whose
/// declaration no longer counts as now, and no open-looking card for a shop that is shut.
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
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  /// Mar Mikhael, pinned — the address every distance below is measured from.
  const DeliveryAddress pinned = DeliveryAddress(
    line: 'Armenia Street',
    zoneId: 'z-mar-mikhael',
    zoneName: 'Mar Mikhael',
    latitude: 33.8969,
    longitude: 35.5236,
  );

  /// The same street typed by hand: an area, but no point on the map.
  const DeliveryAddress typed = DeliveryAddress(
    line: 'Armenia Street',
    zoneId: 'z-mar-mikhael',
    zoneName: 'Mar Mikhael',
  );

  /// When the fixtures' merchants declared their power: two hours ago, still current. Long enough
  /// ago that the "updated" line reads in hours and cannot tick over while the tests run.
  final DateTime declaredAt = DateTime.now().toUtc().subtract(const Duration(hours: 2));

  Map<String, dynamic> card(
    String id,
    String name, {
    String? tagline,
    bool verified = false,
    String power = 'UNKNOWN',
    bool current = true,
    String availability = 'OPEN',
    double? rating = 4.6,
  }) =>
      <String, dynamic>{
        'id': id,
        'slug': id,
        'name': name,
        'vertical': 'GROCERY',
        'availability': availability,
        'tagline': tagline,
        'rating': rating,
        'ratingCount': 12,
        'verifiedLocal': verified,
        'powerStatus': power,
        if (power != 'UNKNOWN') 'powerUpdatedAt': declaredAt.toIso8601String(),
        'powerCurrent': power != 'UNKNOWN' && current,
      };

  Map<String, dynamic> near(Map<String, dynamic> store, int metres,
          {double latitude = 33.8975, double longitude = 35.5241}) =>
      <String, dynamic>{
        'store': store,
        'latitude': latitude,
        'longitude': longitude,
        'distanceMetres': metres,
      };

  Map<String, dynamic> page(List<Map<String, dynamic>> content) => <String, dynamic>{
        'content': content,
        'page': 0,
        'totalElements': content.length,
        'totalPages': 1,
      };

  final Map<String, dynamic> abuHassan = card('s1', 'Abu Hassan Mini Market',
      tagline: 'Fresh fruits, vegetables, bread & propane', verified: true, power: 'GENERATOR');
  final Map<String, dynamic> haddad = card('s2', 'Boulangerie Haddad',
      tagline: "Traditional hot man'oushe", rating: null);
  final Map<String, dynamic> mains = card('s3', 'Mains Mart', power: 'MAINS');
  final Map<String, dynamic> dark = card('s4', 'Dark Corner Shop', power: 'DARK');

  late List<Map<String, dynamic>> nearbyShops;
  late List<Map<String, dynamic>> browseShops;
  late bool nearbyTruncated;
  late int failNearby;
  late List<RequestOptions> requests;

  setUp(() {
    nearbyShops = <Map<String, dynamic>>[
      near(abuHassan, 350),
      near(haddad, 1234),
      near(mains, 1500),
      near(dark, 1800),
    ];
    browseShops = <Map<String, dynamic>>[abuHassan, haddad];
    nearbyTruncated = false;
    failNearby = 0;
    requests = <RequestOptions>[];
  });

  List<Map<String, dynamic>> nearbyQueries() => requests
      .where((RequestOptions r) => r.path == '/api/stores/nearby')
      .map((RequestOptions r) => r.queryParameters)
      .toList();

  Object? answer(RequestOptions options) {
    if (options.path.startsWith('/api/orders')) return page(const <Map<String, dynamic>>[]);
    return switch (options.path) {
      '/api/stores/nearby' => <String, dynamic>{
          ...page(nearbyShops),
          'truncated': nearbyTruncated,
          'candidateLimit': 500,
        },
      '/api/stores' => page(browseShops),
      '/api/delivery-zones' => <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'z-mar-mikhael',
            'name': 'Mar Mikhael',
            'region': 'Beirut',
            'sortOrder': 1,
            'active': true,
          },
        ],
      '/api/stores/favorites' => page(const <Map<String, dynamic>>[]),
      '/api/banners' => const <dynamic>[],
      '/api/categories/chips' => const <dynamic>[],
      '/api/stores/s1' => abuHassan,
      '/api/stores/s1/products' => page(const <Map<String, dynamic>>[]),
      '/api/stores/s1/aisles' => const <dynamic>[],
      '/api/stores/s1/offers' => page(const <Map<String, dynamic>>[]),
      '/api/notifications/unread-count' => const <String, dynamic>{'unread': 0},
      '/api/butler/mine' => page(const <Map<String, dynamic>>[]),
      _ => null,
    };
  }

  Dio fakeServer() {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        requests.add(options);
        final bool failing = options.path == '/api/stores/nearby' && failNearby > 0;
        if (failing) failNearby--;
        final Object? body = options.method == 'GET' && !failing ? answer(options) : null;
        if (body == null) {
          handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
                requestOptions: options, statusCode: failing ? 500 : 404),
          ));
          return;
        }
        handler.resolve(Response<dynamic>(requestOptions: options, statusCode: 200, data: body));
      },
    ));
    return dio;
  }

  Widget app(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
        theme: DeliveryTheme.light(),
        locale: locale,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          DeliveryStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: LocaleController.supported,
        home: home,
      );

  Future<void> pumpBrowse(
    WidgetTester tester, {
    DeliveryAddress? address = pinned,
    Locale locale = const Locale('en'),
    Size size = const Size(1000, 3000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final DeliveryAddressStore addresses = DeliveryAddressStore(ownerId: 'user-1');
    if (address != null) await addresses.select(address);
    final Dio dio = fakeServer();

    await tester.pumpWidget(app(
      HyperlocalScreen(
        storeApi: StoreApi(dio),
        orderApi: OrderApi(dio),
        cart: Cart(),
        addresses: addresses,
        zoneApi: DeliveryZoneApi(dio),
        onOpenBasket: () {},
      ),
      locale: locale,
    ));
    await tester.pumpAndSettle();
  }

  Finder cardOf(String name) => find.widgetWithText(DekkaneShopCard, name);

  group('the road to it', () {
    Future<void> pumpShell(WidgetTester tester,
        {Locale locale = const Locale('en'), bool withChat = false}) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final Dio dio = fakeServer();
      await tester.pumpWidget(app(
        CustomerShell(
          storeApi: StoreApi(dio),
          orderApi: OrderApi(dio),
          notificationApi: NotificationApi(dio),
          butlerApi: ButlerApi(dio),
          zoneApi: DeliveryZoneApi(dio),
          offerApi: OfferApi(dio),
          neighbourhoodChatApi: withChat ? NeighbourhoodChatApi(dio) : null,
          shopChatApi: withChat ? ShopChatApi(dio) : null,
          session: sessionWith(<DeliveryRole>{DeliveryRole.customer}),
          locale: LocaleController(
              read: () async => locale.languageCode, write: (String _) async {}),
          onSignOut: () async {},
        ),
        locale: locale,
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('in Arabic the way in still points the way it opens', (WidgetTester tester) async {
      await pumpShell(tester, locale: const Locale('ar'));

      final Finder entry =
          find.ancestor(of: find.text(ar.dekkaneBrowseTitle), matching: find.byType(YdCard));
      final Finder chevron =
          find.descendant(of: entry, matching: find.byIcon(Icons.chevron_right));
      expect(chevron, findsOneWidget);
      // chevron_right is declared with matchTextDirection, so Icon mirrors it in right-to-left -
      // exactly once. Choosing chevron_left for Arabic flips it a second time, and the card points
      // back the way the customer came.
      final Iterable<Transform> flips = tester
          .widgetList<Transform>(find.descendant(of: chevron, matching: find.byType(Transform)));
      expect(flips, hasLength(1));
      expect(flips.single.transform.storage[0], -1);
    });

    /// The dekkane shop page left a slot for a shop chat; this is the whole road to it being filled:
    /// the shell builds the pill from its chat client, Home hands it to the browse, and the browse
    /// hands it to the shop — and without a chat client nothing is drawn at all.
    testWidgets('a shop opened from the neighbourhood offers a chat with that shop, which opens it',
        (WidgetTester tester) async {
      await pumpShell(tester, withChat: true);
      await tester.tap(find.text(en.dekkaneBrowseTitle));
      await tester.pumpAndSettle();

      expect(tester.widget<HyperlocalScreen>(find.byType(HyperlocalScreen)).shopChatAction, isNotNull);

      await tester.tap(find.text('Abu Hassan Mini Market'));
      await tester.pumpAndSettle();
      final Finder pill = find.text(en.chatShopWith('Abu Hassan Mini Market'));
      expect(pill, findsOneWidget);

      await tester.tap(pill);
      await tester.pumpAndSettle();
      expect(find.byType(ShopThreadScreen), findsOneWidget);
      expect(
          requests.where((RequestOptions r) =>
              r.method == 'POST' && r.path == '/api/chat/stores/s1/thread'),
          hasLength(1),
          reason: 'The pill asks for the conversation with the shop it is on, when tapped.');
    });

    testWidgets('without a chat client, a shop page offers no chat and Home no room',
        (WidgetTester tester) async {
      await pumpShell(tester);
      expect(find.text(en.chatRoomEntryTitle), findsNothing);

      await tester.tap(find.text(en.dekkaneBrowseTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abu Hassan Mini Market'));
      await tester.pumpAndSettle();

      expect(find.text(en.chatShopWith('Abu Hassan Mini Market')), findsNothing);
    });

    testWidgets('Home has a way into the neighbourhood chat, under the browse',
        (WidgetTester tester) async {
      await pumpShell(tester, withChat: true);

      await tester.tap(find.text(en.chatRoomEntryTitle));
      await tester.pumpAndSettle();

      expect(find.byType(NeighbourhoodChatScreen), findsOneWidget);
    });

    testWidgets('Home has a way in, and it opens the neighbourhood browse over the shell',
        (WidgetTester tester) async {
      await pumpShell(tester);

      expect(find.byType(HyperlocalScreen), findsNothing);
      await tester.tap(find.text(en.dekkaneBrowseTitle));
      await tester.pumpAndSettle();

      expect(find.byType(HyperlocalScreen), findsOneWidget,
          reason: 'The Home entry must push the neighbourhood browse — it had no road in.');
    });

    testWidgets("a shop opened from it is handed the shell's own way to the basket",
        (WidgetTester tester) async {
      await pumpShell(tester);
      await tester.tap(find.text(en.dekkaneBrowseTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abu Hassan Mini Market'));
      await tester.pumpAndSettle();

      // What the shop's basket bar calls. The shell's callback pops back to the shell and opens the
      // Basket tab; a stand-in — the `() {}` these tests hand the browse directly — would leave the
      // customer standing in the shop.
      tester.widget<StorePageScreen>(find.byType(StorePageScreen)).onOpenBasket();
      await tester.pumpAndSettle();

      expect(find.byType(StorePageScreen), findsNothing);
      expect(find.byType(HyperlocalScreen), findsNothing);
      expect(find.byType(CartScreen), findsOneWidget);
    });
  });

  group('with a pinned address', () {
    testWidgets('asks for the shops around that point and says how far each one is',
        (WidgetTester tester) async {
      await pumpBrowse(tester);

      final List<Map<String, dynamic>> queries = nearbyQueries();
      expect(queries, hasLength(1));
      expect(queries.single['latitude'], pinned.latitude);
      expect(queries.single['longitude'], pinned.longitude);
      expect(queries.single['radiusMetres'], HyperlocalScreen.radiusMetres);
      // "All" is no filter at all, not four filters set to false.
      expect(queries.single.keys,
          isNot(anyOf(contains('openNow'), contains('powerStatus'), contains('newSinceDays'))));
      expect(requests.where((RequestOptions r) => r.path == '/api/stores'), isEmpty);

      expect(find.text('350 m away'), findsOneWidget);
      expect(find.text('1.2 km away'), findsOneWidget);
      // The area and its region, from the address and the zone list.
      expect(find.text(en.dekkaneAreaInRegion('Mar Mikhael', 'Beirut')), findsOneWidget);
      expect(find.text(en.dekkaneBrowseSubRegion('Beirut')), findsOneWidget);
      expect(find.text(en.dekkaneBrowseTitle), findsOneWidget);
    });

    testWidgets('Trusted local appears only on the shop Backoffice vouched for',
        (WidgetTester tester) async {
      await pumpBrowse(tester);

      expect(find.text(en.dekkaneTrustedLocal), findsOneWidget);
      expect(
          find.descendant(
              of: cardOf('Abu Hassan Mini Market'), matching: find.text(en.dekkaneTrustedLocal)),
          findsOneWidget);
    });

    testWidgets('the generator pill is on the GENERATOR shop only — nothing for mains or unknown',
        (WidgetTester tester) async {
      await pumpBrowse(tester);

      expect(find.text(en.dekkaneGeneratorActive), findsOneWidget);
      expect(
          find.descendant(
              of: cardOf('Abu Hassan Mini Market'),
              matching: find.text(en.dekkaneGeneratorActive)),
          findsOneWidget);
      for (final String quiet in <String>['Boulangerie Haddad', 'Mains Mart']) {
        expect(
            find.descendant(of: cardOf(quiet), matching: find.text(en.dekkaneGeneratorActive)),
            findsNothing);
        expect(find.descendant(of: cardOf(quiet), matching: find.text(en.custPowerDark)),
            findsNothing);
      }
    });

    testWidgets('a power badge says how long ago it was declared, and an old one is not drawn',
        (WidgetTester tester) async {
      nearbyShops = <Map<String, dynamic>>[
        near(abuHassan, 350),
        near(card('s7', 'Said So Yesterday', power: 'GENERATOR', current: false), 600),
        near(card('s8', 'Dark Last Week', power: 'DARK', current: false), 900),
      ];
      await pumpBrowse(tester);

      expect(
          find.descendant(
              of: cardOf('Abu Hassan Mini Market'),
              matching: find.text(en.dekkanePowerUpdatedHours(2))),
          findsOneWidget);
      // "Generator active" and "Currently dark" are claims about now, and the server says these
      // declarations no longer are — so no badge, and no dimming on the strength of one.
      expect(
          find.descendant(
              of: cardOf('Said So Yesterday'), matching: find.text(en.dekkaneGeneratorActive)),
          findsNothing);
      expect(find.descendant(of: cardOf('Dark Last Week'), matching: find.text(en.custPowerDark)),
          findsNothing);
      expect(find.descendant(of: cardOf('Dark Last Week'), matching: find.byType(Opacity)),
          findsNothing);
    });

    testWidgets('a dark shop is dimmed, not removed', (WidgetTester tester) async {
      await pumpBrowse(tester);

      expect(cardOf('Dark Corner Shop'), findsOneWidget);
      // The card dims itself, so the Opacity is inside it rather than around it.
      final Opacity dimmed = tester.widget<Opacity>(
          find.descendant(of: cardOf('Dark Corner Shop'), matching: find.byType(Opacity)));
      expect(dimmed.opacity, 0.55);
      expect(find.descendant(of: cardOf('Mains Mart'), matching: find.byType(Opacity)),
          findsNothing);
    });

    testWidgets('a shop that is not open says so on its cover, and a closed one is dimmed',
        (WidgetTester tester) async {
      nearbyShops = <Map<String, dynamic>>[
        near(abuHassan, 350),
        near(card('s5', 'Shut Till Morning', availability: 'CLOSED'), 600),
        near(card('s6', 'Closing Bakery', availability: 'CLOSING_SOON'), 900),
      ];
      await pumpBrowse(tester);

      // Under "All" a shut shop is still listed, and says so before anyone opens it to a shelf
      // with nothing to add.
      final Finder shut = cardOf('Shut Till Morning');
      expect(
          find.descendant(of: shut, matching: find.text(StoreAvailability.closed.labelIn(en))),
          findsOneWidget);
      expect(tester.widget<Opacity>(find.descendant(of: shut, matching: find.byType(Opacity))).opacity,
          0.55);

      // Closing soon still takes orders: said, not dimmed.
      final Finder closing = cardOf('Closing Bakery');
      expect(
          find.descendant(
              of: closing, matching: find.text(StoreAvailability.closingSoon.labelIn(en))),
          findsOneWidget);
      expect(find.descendant(of: closing, matching: find.byType(Opacity)), findsNothing);

      // An open shop wears no state pill, as the frame draws it.
      expect(
          find.descendant(
              of: cardOf('Abu Hassan Mini Market'), matching: find.byType(DekkaneStatePill)),
          findsNothing);
    });

    testWidgets('an unrated shop says New instead of inventing a rating',
        (WidgetTester tester) async {
      await pumpBrowse(tester);

      expect(find.descendant(of: cardOf('Boulangerie Haddad'), matching: find.text(en.ratingNew)),
          findsOneWidget);
      expect(find.descendant(of: cardOf('Abu Hassan Mini Market'), matching: find.text('4.6')),
          findsOneWidget);
    });

    testWidgets('each chip is a question the server answers, and All asks none',
        (WidgetTester tester) async {
      await pumpBrowse(tester);

      await tester.tap(find.text(en.dekkaneFilterOpenNow));
      await tester.pumpAndSettle();
      expect(nearbyQueries().last['openNow'], isTrue);

      await tester.tap(find.text(en.dekkaneFilterOnGenerator));
      await tester.pumpAndSettle();
      // Asked as what the data is: what the lights are doing now.
      expect(nearbyQueries().last['powerStatus'], 'GENERATOR');
      expect(nearbyQueries().last.containsKey('openNow'), isFalse);

      await tester.tap(find.text(en.dekkaneFilterNew));
      await tester.pumpAndSettle();
      expect(nearbyQueries().last['newSinceDays'], HyperlocalScreen.joinedWithinDays);

      await tester.tap(find.text(en.all));
      await tester.pumpAndSettle();
      expect(nearbyQueries().last.keys,
          isNot(anyOf(contains('openNow'), contains('powerStatus'), contains('newSinceDays'))));
    });

    testWidgets('the frame\'s "Has generator" and "Delivers" chips are not drawn',
        (WidgetTester tester) async {
      await pumpBrowse(tester);

      // Nothing the platform knows says which shops OWN a generator, and nobody has decided what
      // "delivers" would filter on — so neither is offered as if it could.
      expect(find.textContaining('Has generator', findRichText: true), findsNothing);
      expect(find.text('Delivers'), findsNothing);
      expect(find.byType(YdChip), findsNWidgets(4));
    });

    testWidgets('a filter that matches nothing says so, and offers to clear it',
        (WidgetTester tester) async {
      await pumpBrowse(tester);
      nearbyShops = <Map<String, dynamic>>[];

      await tester.tap(find.text(en.dekkaneFilterOpenNow));
      await tester.pumpAndSettle();

      expect(find.text(en.noShopsMatch), findsOneWidget);
      expect(find.text(en.tryClearingAFilter), findsOneWidget);
    });

    testWidgets('an answer that reached the search ceiling says it covered the nearest shops only',
        (WidgetTester tester) async {
      nearbyTruncated = true;
      await pumpBrowse(tester);

      // At the end of the list, so the last card is not taken for the edge of the neighbourhood...
      expect(find.text(en.dekkaneSearchedNearest(500)), findsOneWidget);

      // ...and in place of "try clearing a filter" when nothing among those shops matched.
      nearbyShops = <Map<String, dynamic>>[];
      await tester.tap(find.text(en.dekkaneFilterOpenNow));
      await tester.pumpAndSettle();

      expect(find.text(en.noShopsMatch), findsOneWidget);
      expect(find.text(en.dekkaneSearchedNearest(500)), findsOneWidget);
      expect(find.text(en.tryClearingAFilter), findsNothing);
    });

    testWidgets('an empty neighbourhood with no filter says that, not "no shops match"',
        (WidgetTester tester) async {
      nearbyShops = <Map<String, dynamic>>[];
      await pumpBrowse(tester);

      expect(find.text(en.dekkaneNoShopsNearby), findsOneWidget);
      expect(find.text(en.tryClearingAFilter), findsNothing);
      // Nothing to put on a map, so no map.
      expect(find.byType(OsmBasemap), findsNothing);
    });

    testWidgets('a first page that fails says so, and Try again asks again',
        (WidgetTester tester) async {
      failNearby = 1;
      await pumpBrowse(tester);

      expect(find.text(en.dekkaneCouldNotLoadShops), findsOneWidget);
      expect(find.text(en.dekkaneNoShopsNearby), findsNothing,
          reason: 'A request that failed is not an empty neighbourhood.');

      await tester.tap(find.text(en.tryAgain));
      await tester.pumpAndSettle();

      expect(nearbyQueries(), hasLength(2));
      expect(cardOf('Abu Hassan Mini Market'), findsOneWidget);
    });

    testWidgets('the map preview is drawn over shops it can show', (WidgetTester tester) async {
      await pumpBrowse(tester);

      expect(find.byType(OsmBasemap), findsOneWidget);
    });

    testWidgets('the location bar answers a tap on the band just under it',
        (WidgetTester tester) async {
      await pumpBrowse(tester);

      final Rect bar = tester.getRect(find
          .ancestor(
              of: find.text(en.dekkaneAreaInRegion('Mar Mikhael', 'Beirut')),
              matching: find.byType(InkWell))
          .first);
      expect(bar.height, lessThan(44), reason: "Drawn at the frame's height.");

      await tester.tapAt(bar.bottomCenter + const Offset(0, 8));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('a card opens that shop in the dekkane layout', (WidgetTester tester) async {
      await pumpBrowse(tester);

      await tester.tap(find.text('Abu Hassan Mini Market'));
      await tester.pumpAndSettle();

      final StorePageScreen shop = tester.widget<StorePageScreen>(find.byType(StorePageScreen));
      expect(shop.storeId, 's1');
      expect(shop.layout, StorePageLayout.dekkane);
    });

    testWidgets('on a 360px phone the distance gets all the room the power badge leaves it',
        (WidgetTester tester) async {
      await pumpBrowse(tester, size: const Size(360, 1600));

      final Finder abu = cardOf('Abu Hassan Mini Market');
      final Rect distance =
          tester.getRect(find.descendant(of: abu, matching: find.text('350 m away')));
      final Rect badge =
          tester.getRect(find.descendant(of: abu, matching: find.byType(DekkanePowerPill)));
      // A Flexible and a Spacer used to split that room evenly, so the distance was cut to
      // "350 m aw…" while an empty stretch as wide sat beside it. It now runs up to the badge's gap.
      expect(distance.right, closeTo(badge.left - DeliverySpacing.sm, 0.5));
      expect(find.descendant(of: abu, matching: find.byType(Spacer)), findsNothing);
      // And however little room there is, the badge's words shorten rather than overflowing.
      expect(tester.takeException(), isNull);
    });
  });

  group('without a point to measure from', () {
    testWidgets('lists the storefront instead, with no chips, no map and no distances',
        (WidgetTester tester) async {
      await pumpBrowse(tester, address: typed);

      expect(nearbyQueries(), isEmpty);
      expect(requests.where((RequestOptions r) => r.path == '/api/stores'), isNotEmpty);
      expect(cardOf('Abu Hassan Mini Market'), findsOneWidget);

      expect(find.text(en.dekkanePinAddressPrompt), findsOneWidget);
      expect(find.byType(YdChip), findsNothing);
      expect(find.byType(OsmBasemap), findsNothing);
      expect(find.textContaining(' away'), findsNothing,
          reason: 'There is no point to be "away" from.');
    });

    testWidgets('does not call the whole storefront your neighbourhood',
        (WidgetTester tester) async {
      await pumpBrowse(tester, address: typed);

      final YdScreenHeader header = tester.widget<YdScreenHeader>(find.byType(YdScreenHeader));
      expect(header.title, en.dekkaneBrowseTitleAll);
      expect(header.subtitle, en.dekkaneBrowseSubAll);
      expect(find.text(en.dekkaneAllShops.toUpperCase()), findsOneWidget);
      for (final String local in <String>[
        en.dekkaneBrowseTitle,
        en.custHyperlocalSub,
        en.dekkaneLocalShops.toUpperCase(),
        en.dekkaneNearbyShops.toUpperCase(),
      ]) {
        expect(find.text(local), findsNothing, reason: '"$local" is a claim about nearness.');
      }
    });

    testWidgets('with no address at all, the location bar asks for one',
        (WidgetTester tester) async {
      await pumpBrowse(tester, address: null);

      expect(find.text(en.setDeliveryAddress), findsOneWidget);
      expect(nearbyQueries(), isEmpty);
    });
  });

  group('the full map', () {
    testWidgets('a pin opens its shop, and a dark shop\'s pin is dimmed like its card',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final List<String> opened = <String>[];
      await tester.pumpWidget(app(NeighbourhoodMapScreen(
        home: LatLng(pinned.latitude!, pinned.longitude!),
        shops: <NearbyStore>[
          NearbyStore.fromJson(near(abuHassan, 350, latitude: 33.8990, longitude: 35.5236)),
          NearbyStore.fromJson(near(dark, 900, latitude: 33.8950, longitude: 35.5280)),
        ],
        onOpenShop: (StoreCard store) => opened.add(store.id),
      )));
      // The camera is fitted to the pins once the map knows its size, a frame after the first.
      await tester.pump();

      Finder pinOf(String id) => find.byWidgetPredicate(
          (Widget w) => w is NeighbourhoodShopPin && w.store.id == id);
      expect(pinOf('s1'), findsOneWidget);
      expect(find.descendant(of: pinOf('s4'), matching: find.byType(Opacity)), findsOneWidget);
      expect(find.descendant(of: pinOf('s1'), matching: find.byType(Opacity)), findsNothing);

      await tester.tap(pinOf('s1'));
      // The map's own double-tap zoom holds the gesture until its timeout has passed.
      await tester.pump(const Duration(milliseconds: 500));

      expect(opened, <String>['s1']);
      await tester.pumpAndSettle();
    });

    testWidgets('the expand-map pill answers a thumb that lands just beside it',
        (WidgetTester tester) async {
      int opened = 0;
      await tester.pumpWidget(app(Scaffold(
        body: Center(
          child: NeighbourhoodMapExpandButton(
              label: en.dekkaneExpandMap, onPressed: () => opened++),
        ),
      )));

      final Rect pill = tester.getRect(
          find.ancestor(of: find.text(en.dekkaneExpandMap), matching: find.byType(Material)).first);
      expect(pill.height, lessThan(30), reason: 'Drawn as the frame draws it.');

      await tester.tapAt(pill.topCenter - const Offset(0, 8));
      await tester.tapAt(pill.bottomCenter + const Offset(0, 8));
      expect(opened, 2);
      expect(tester.getSize(find.byType(NeighbourhoodMapExpandButton)).height,
          NeighbourhoodMapExpandButton.hitHeight);
    });
  });

  group('the distance line', () {
    test('tens of metres under a kilometre, one decimal above', () {
      expect(dekkaneDistanceLabel(en, 350), '350 m away');
      expect(dekkaneDistanceLabel(en, 347), '350 m away');
      expect(dekkaneDistanceLabel(en, 4), '10 m away');
      expect(dekkaneDistanceLabel(en, 1234), '1.2 km away');
      // 996 m rounds to a thousand, which is a kilometre, not "1,000 m".
      expect(dekkaneDistanceLabel(en, 996), en.dekkaneDistanceKm(1.0));
    });

    test('is Arabic in Arabic', () {
      expect(dekkaneDistanceLabel(ar, 350), ar.dekkaneDistanceMetres(350));
      expect(dekkaneDistanceLabel(ar, 350), isNot(dekkaneDistanceLabel(en, 350)));
    });
  });

  testWidgets('in Arabic it reads Arabic and lays out right to left',
      (WidgetTester tester) async {
    await pumpBrowse(tester, locale: const Locale('ar'));

    expect(find.text(ar.dekkaneBrowseTitle), findsOneWidget);
    expect(find.text(ar.dekkaneFilterOpenNow), findsOneWidget);
    expect(find.text(ar.dekkaneTrustedLocal), findsOneWidget);
    expect(find.text(dekkaneDistanceLabel(ar, 350)), findsOneWidget);
    expect(Directionality.of(tester.element(cardOf('Abu Hassan Mini Market'))),
        TextDirection.rtl);

    // Mirrored: the badge follows the name, which in right-to-left puts it on the name's left.
    final Offset name = tester.getCenter(find.text('Abu Hassan Mini Market'));
    final Offset badge = tester.getCenter(find.text(ar.dekkaneTrustedLocal));
    expect(badge.dx, lessThan(name.dx));
    expect(tester.takeException(), isNull);
  });
}
