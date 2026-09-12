import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/address_sheet.dart' show OsmBasemap;
import 'package:mobile_app/src/cart.dart';
import 'package:mobile_app/src/customer_shell.dart';
import 'package:mobile_app/src/delivery_address.dart';
import 'package:mobile_app/src/hyperlocal_screen.dart';
import 'package:mobile_app/src/store_page_screen.dart';

import 'widget_test.dart' show sessionWith;

/// The neighbourhood browse (Figma 112:1941).
///
/// It was built and then never opened — the surface checklist listed it as UNREACHABLE — so the
/// first thing pinned here is the road to it from Home, through the real shell. The rest pins what
/// the redesign asks of it on real data: the list is measured from the customer's pinned address,
/// every chip is a question the server answers (and the frame's "Has generator" is asked as what
/// it can truthfully be — "on generator now"), and nothing is drawn that the data does not have: no
/// distance, chips or map without a point, no trust badge Backoffice did not grant, no power pill
/// for a shop that never declared.
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

  Map<String, dynamic> card(
    String id,
    String name, {
    String? tagline,
    bool verified = false,
    String power = 'UNKNOWN',
    double? rating = 4.6,
  }) =>
      <String, dynamic>{
        'id': id,
        'slug': id,
        'name': name,
        'vertical': 'GROCERY',
        'availability': 'OPEN',
        'tagline': tagline,
        'rating': rating,
        'ratingCount': 12,
        'verifiedLocal': verified,
        'powerStatus': power,
      };

  Map<String, dynamic> near(Map<String, dynamic> store, int metres) => <String, dynamic>{
        'store': store,
        'latitude': 33.8975,
        'longitude': 35.5241,
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
      '/api/stores/nearby' => page(nearbyShops),
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

  Future<void> pumpBrowse(WidgetTester tester,
      {DeliveryAddress? address = pinned, Locale locale = const Locale('en')}) async {
    tester.view.physicalSize = const Size(1000, 3000);
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
    Future<void> pumpShell(WidgetTester tester, {Locale locale = const Locale('en')}) async {
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

    testWidgets('Home has a way in, and it opens the neighbourhood browse over the shell',
        (WidgetTester tester) async {
      await pumpShell(tester);

      expect(find.byType(HyperlocalScreen), findsNothing);
      await tester.tap(find.text(en.dekkaneBrowseTitle));
      await tester.pumpAndSettle();

      expect(find.byType(HyperlocalScreen), findsOneWidget,
          reason: 'The Home entry must push the neighbourhood browse — it had no road in.');
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

    testWidgets('a card opens that shop in the dekkane layout', (WidgetTester tester) async {
      await pumpBrowse(tester);

      await tester.tap(find.text('Abu Hassan Mini Market'));
      await tester.pumpAndSettle();

      final StorePageScreen shop = tester.widget<StorePageScreen>(find.byType(StorePageScreen));
      expect(shop.storeId, 's1');
      expect(shop.layout, StorePageLayout.dekkane);
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

    testWidgets('with no address at all, the location bar asks for one',
        (WidgetTester tester) async {
      await pumpBrowse(tester, address: null);

      expect(find.text(en.setDeliveryAddress), findsOneWidget);
      expect(nearbyQueries(), isEmpty);
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
