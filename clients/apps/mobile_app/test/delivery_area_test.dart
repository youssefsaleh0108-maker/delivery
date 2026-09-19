import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/address_sheet.dart' show OsmBasemap;
import 'package:mobile_app/src/cart.dart';
import 'package:mobile_app/src/delivery_address.dart';
import 'package:mobile_app/src/delivery_area_button.dart';
import 'package:mobile_app/src/delivery_area_map_screen.dart';
import 'package:mobile_app/src/order_placement.dart';
import 'package:mobile_app/src/service_provider_screen.dart';
import 'package:mobile_app/src/services_kit.dart';
import 'package:mobile_app/src/shop_delivery_area.dart';
import 'package:mobile_app/src/store_page_screen.dart';

import 'service_fixtures.dart'
    show FakeServer, offerJson, pageJson, phone, storeJson, svcApp;

/// "When entering the shop, a button to open regions on the map": the shop page's "Delivery area"
/// row and the map behind it.
///
/// Pinned: the row is there only when there is a real area to show (a circle, or areas a customer
/// can pick, from a server that said which) and never as a dead control; a service provider shows it
/// only when one of its offers is delivered; the map draws the circle to the metre and writes a
/// placed area's name at its centre, never a region around it; an area retired from the picker is
/// never counted, named or listed, yet still judges an address saved in it; and the
/// "inside/outside" line is decided by the same two rules checkout applies — said only when it can
/// be, in Arabic right to left, at 320dp.
void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

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

  // The shop's pin in Hamra, and addresses measured from it (a degree of latitude is ~111.32 km).
  const double shopLat = 33.8977;
  const double shopLng = 35.4829;
  double north(double metres) => shopLat + metres / 111320;

  final Map<String, dynamic> hamra = <String, dynamic>{
    'id': 'z-hamra',
    'name': 'Hamra',
    'region': 'Beirut',
    'sortOrder': 10,
    'active': true,
    'centerLat': 33.8960,
    'centerLng': 35.4800,
  };
  final Map<String, dynamic> achrafieh = <String, dynamic>{
    'id': 'z-achrafieh',
    'name': 'Achrafieh',
    'region': 'Beirut',
    'sortOrder': 10,
    'active': true,
  };
  // Retired from the picker, still priced by the shop: a saved address naming it orders there.
  final Map<String, dynamic> rasBeirut = <String, dynamic>{
    'id': 'z-ras-beirut',
    'name': 'Ras Beirut',
    'region': 'Beirut',
    'sortOrder': 30,
    'active': false,
    'centerLat': 33.9010,
    'centerLng': 35.4730,
  };

  const Object absent = Object();

  Map<String, dynamic> shopJson({
    String vertical = 'GROCERY',
    double? latitude = shopLat,
    double? longitude = shopLng,
    int? radius = 3000,
    Object? zones = const <Map<String, dynamic>>[],
    String name = 'Hamra Corner Grocer',
  }) =>
      <String, dynamic>{
        'id': 's1',
        'slug': 's1',
        'name': name,
        'vertical': vertical,
        'availability': 'OPEN',
        'closesAt': '22:00:00',
        'rating': 4.6,
        'ratingCount': 12,
        'deliveryFee': 2,
        'minOrder': 0,
        'latitude': latitude,
        'longitude': longitude,
        'deliveryRadiusMetres': radius,
        if (!identical(zones, absent)) 'deliveryZones': zones,
      };

  Store store({
    String vertical = 'GROCERY',
    double? latitude = shopLat,
    double? longitude = shopLng,
    int? radius = 3000,
    Object? zones = const <Map<String, dynamic>>[],
  }) =>
      Store.fromJson(shopJson(
          vertical: vertical,
          latitude: latitude,
          longitude: longitude,
          radius: radius,
          zones: zones));

  DeliveryAddress at({double? latitude, double? longitude, String? zoneId}) => DeliveryAddress(
        line: 'Bliss Street, Building 12',
        label: 'Home',
        latitude: latitude,
        longitude: longitude,
        zoneId: zoneId,
      );

  // ------------------------------------------------------------------------------------ the rules

  group('what counts as an area to show', () {
    test('a circle, areas, or both', () {
      expect(ShopDeliveryArea.of(store()), isNotNull);
      expect(ShopDeliveryArea.of(store(radius: null, zones: <dynamic>[hamra])), isNotNull);
      expect(ShopDeliveryArea.of(store(zones: <dynamic>[hamra, achrafieh])), isNotNull);
    });

    test('nothing, for a shop its circle and its areas do not limit', () {
      expect(ShopDeliveryArea.of(store(radius: null)), isNull);
      // A radius with no pin binds nothing at checkout, so it is no circle here either.
      expect(ShopDeliveryArea.of(store(latitude: null, longitude: null)), isNull);
    });

    test('nothing, when the store read did not say which areas the shop serves', () {
      // A server from before the field: a circle drawn alone could be half the area.
      expect(ShopDeliveryArea.of(store(zones: absent)), isNull);
    });

    test('nothing, as with no areas at all, when every area is retired and there is no circle', () {
      expect(ShopDeliveryArea.of(store(radius: null, zones: <dynamic>[rasBeirut])), isNull);
      // A radius with no pin is no circle, whatever the areas are.
      expect(
          ShopDeliveryArea.of(
              store(latitude: null, longitude: null, zones: <dynamic>[rasBeirut])),
          isNull);
      // One area still in the picker is enough.
      expect(ShopDeliveryArea.of(store(radius: null, zones: <dynamic>[rasBeirut, achrafieh])),
          isNotNull);
    });

    test('a service provider only when one of its offers is delivered', () {
      final Store provider = store(vertical: 'SERVICES');
      expect(ShopDeliveryArea.of(provider, offersDeliver: true), isNotNull);
      expect(ShopDeliveryArea.of(provider, offersDeliver: false), isNull);
      expect(ShopDeliveryArea.of(provider), isNull, reason: 'Offers unknown: no guess.');
    });

    test('the summary says how far, how many areas, or both', () {
      expect(ShopDeliveryArea.of(store())!.summary(en), en.dareaWithinKm('3.0'));
      expect(ShopDeliveryArea.of(store(radius: null, zones: <dynamic>[hamra, achrafieh]))!
          .summary(en), en.dareaAreasCount(2));
      expect(ShopDeliveryArea.of(store(radius: 2500, zones: <dynamic>[hamra]))!.summary(en),
          '${en.dareaWithinKm('2.5')} · ${en.dareaAreasCount(1)}');
    });
  });

  group('inside or outside, by the rules checkout applies', () {
    test('the circle answers exactly as checkout does, on both sides of its edge', () {
      final ShopDeliveryArea area = ShopDeliveryArea.of(store())!;
      for (final double metres in <double>[0, 1000, 2900, 2990, 3010, 3100, 5000, 40000]) {
        final DeliveryAddress address = at(latitude: north(metres), longitude: shopLng);
        final bool checkoutRefuses = isOutsideDeliveryRadius(area.store.toCard(), address);
        expect(area.verdictFor(address),
            checkoutRefuses ? DeliveryAreaVerdict.outside : DeliveryAreaVerdict.inside,
            reason: '$metres m north');
        expect(checkoutRefuses, metres > 3000, reason: '$metres m north');
      }
    });

    test('the areas: served is inside, any other area is outside, a retired one still counts', () {
      final ShopDeliveryArea area =
          ShopDeliveryArea.of(store(radius: null, zones: <dynamic>[hamra, rasBeirut]))!;
      expect(area.verdictFor(at(zoneId: 'z-hamra')), DeliveryAreaVerdict.inside);
      expect(area.verdictFor(at(zoneId: 'z-ras-beirut')), DeliveryAreaVerdict.inside);
      expect(area.verdictFor(at(zoneId: 'z-jounieh')), DeliveryAreaVerdict.outside);
    });

    test('both rules bind: inside the circle in an unserved area is outside', () {
      final ShopDeliveryArea area = ShopDeliveryArea.of(store(zones: <dynamic>[hamra]))!;
      expect(area.verdictFor(at(latitude: north(500), longitude: shopLng, zoneId: 'z-jounieh')),
          DeliveryAreaVerdict.outside);
      expect(area.verdictFor(at(latitude: north(5000), longitude: shopLng, zoneId: 'z-hamra')),
          DeliveryAreaVerdict.outside);
      expect(area.verdictFor(at(latitude: north(500), longitude: shopLng, zoneId: 'z-hamra')),
          DeliveryAreaVerdict.inside);
      // What checkout lets through when only one rule can be checked, the map calls inside.
      expect(area.verdictFor(at(latitude: north(500), longitude: shopLng)),
          DeliveryAreaVerdict.inside);
      expect(area.verdictFor(at(zoneId: 'z-hamra')), DeliveryAreaVerdict.inside);
    });

    test('says nothing when nothing it checks is known about the address', () {
      final ShopDeliveryArea circle = ShopDeliveryArea.of(store())!;
      expect(circle.verdictFor(null), DeliveryAreaVerdict.unknown);
      expect(circle.verdictFor(at()), DeliveryAreaVerdict.unknown);
      // An area says nothing about a circle, and a pin nothing about an area.
      expect(circle.verdictFor(at(zoneId: 'z-hamra')), DeliveryAreaVerdict.unknown);
      final ShopDeliveryArea areas =
          ShopDeliveryArea.of(store(radius: null, zones: <dynamic>[hamra]))!;
      expect(areas.verdictFor(at(latitude: north(100), longitude: shopLng)),
          DeliveryAreaVerdict.unknown);
    });
  });

  group('an area retired from the picker', () {
    test('judges an address, but is never counted, named or framed', () {
      final ShopDeliveryArea area =
          ShopDeliveryArea.of(store(zones: <dynamic>[hamra, achrafieh, rasBeirut]))!;

      // Judged by every area the shop serves, as order placement is.
      expect(area.zones.map((DeliveryZone z) => z.id),
          <String>['z-hamra', 'z-achrafieh', 'z-ras-beirut']);
      expect(area.limitsByArea, isTrue);
      expect(area.verdictFor(at(zoneId: 'z-ras-beirut')), DeliveryAreaVerdict.inside);
      expect(
          area.verdictFor(at(latitude: north(500), longitude: shopLng, zoneId: 'z-ras-beirut')),
          DeliveryAreaVerdict.inside);
      expect(area.verdictFor(at(zoneId: 'z-jounieh')), DeliveryAreaVerdict.outside);

      // Shown: only what the address sheet still offers.
      expect(area.shownZones.map((DeliveryZone z) => z.name), <String>['Hamra', 'Achrafieh']);
      expect(area.placedZones.map((DeliveryZone z) => z.name), <String>['Hamra'],
          reason: 'Ras Beirut is placed, but retired.');
      expect(area.summary(en), '${en.dareaWithinKm('3.0')} · ${en.dareaAreasCount(2)}');
      // The camera frames what is drawn, and Ras Beirut is not.
      expect(area.framePoints, contains((33.8960, 35.4800)));
      expect(area.framePoints, isNot(contains((33.9010, 35.4730))));
    });

    test('a shop whose areas are all retired shows its circle alone, and still judges by them',
        () {
      final ShopDeliveryArea area = ShopDeliveryArea.of(store(zones: <dynamic>[rasBeirut]))!;

      expect(area.shownZones, isEmpty);
      expect(area.placedZones, isEmpty);
      expect(area.summary(en), en.dareaWithinKm('3.0'));
      // Order placement still refuses every other area there, and still serves the retired one.
      expect(area.limitsByArea, isTrue);
      expect(area.verdictFor(at(latitude: north(500), longitude: shopLng, zoneId: 'z-hamra')),
          DeliveryAreaVerdict.outside);
      expect(
          area.verdictFor(at(latitude: north(500), longitude: shopLng, zoneId: 'z-ras-beirut')),
          DeliveryAreaVerdict.inside);
      expect(area.verdictFor(at(latitude: north(500), longitude: shopLng)),
          DeliveryAreaVerdict.inside);
    });
  });

  // ------------------------------------------------------------------------------ the shop page

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

  Dio shopServer(Map<String, dynamic> shop) {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    Map<String, dynamic> empty() => <String, dynamic>{
          'content': <dynamic>[],
          'page': 0,
          'totalElements': 0,
          'totalPages': 1,
        };
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        final Object? body = switch (options.path) {
          '/api/stores/s1' => shop,
          '/api/stores/s1/products' || '/api/stores/s1/offers' => empty(),
          '/api/stores/s1/aisles' => <dynamic>[],
          _ => null,
        };
        if (body == null) {
          handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(requestOptions: options, statusCode: 404),
          ));
          return;
        }
        handler.resolve(Response<dynamic>(requestOptions: options, statusCode: 200, data: body));
      },
    ));
    return dio;
  }

  /// The customer's address pin on the map, found by what a screen reader hears.
  Finder addressPin() => find.byWidgetPredicate(
      (Widget w) => w is Semantics && w.properties.label == en.custYourAddress);

  Future<DeliveryAddressStore> book(DeliveryAddress? chosen) async {
    final DeliveryAddressStore addresses = DeliveryAddressStore(ownerId: 'user-1');
    if (chosen != null) await addresses.select(chosen);
    return addresses;
  }

  Future<void> pumpShop(
    WidgetTester tester,
    Map<String, dynamic> shop, {
    StorePageLayout layout = StorePageLayout.standard,
    DeliveryAddressStore? addresses,
    Locale locale = const Locale('en'),
    Size size = const Size(420, 2400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(
      StorePageScreen(
        storeApi: StoreApi(shopServer(shop)),
        cart: Cart(),
        storeId: 's1',
        addresses: addresses,
        onOpenBasket: () {},
        layout: layout,
      ),
      locale: locale,
    ));
    await tester.pumpAndSettle();
  }

  group('on the shop page', () {
    testWidgets('a shop with a circle and areas shows the row, and it opens the map',
        (WidgetTester tester) async {
      await pumpShop(tester, shopJson(zones: <dynamic>[hamra, achrafieh]));

      expect(find.text(en.dareaButton), findsOneWidget);
      expect(find.text('${en.dareaWithinKm('3.0')} · ${en.dareaAreasCount(2)}'), findsOneWidget);

      await tester.tap(find.text(en.dareaButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(DeliveryAreaMapScreen), findsOneWidget);
      final YdScreenHeader header = tester.widget<YdScreenHeader>(find.descendant(
          of: find.byType(DeliveryAreaMapScreen), matching: find.byType(YdScreenHeader)));
      expect(header.title, en.dareaButton);
      expect(header.subtitle, 'Hamra Corner Grocer');
      await tester.pumpAndSettle();
    });

    testWidgets('no row for a shop its circle and areas do not limit', (WidgetTester tester) async {
      await pumpShop(tester, shopJson(radius: null));

      expect(find.text(en.dareaButton), findsNothing);
      expect(find.byType(YdListRow), findsNothing);
    });

    testWidgets('no row when the store read did not say which areas', (WidgetTester tester) async {
      await pumpShop(tester, shopJson(zones: absent));

      expect(find.text(en.dareaButton), findsNothing);
    });

    testWidgets('no row for a shop with no circle whose areas are all retired',
        (WidgetTester tester) async {
      await pumpShop(tester, shopJson(radius: null, zones: <dynamic>[rasBeirut]));

      expect(find.text(en.dareaButton), findsNothing);
      expect(find.byType(YdListRow), findsNothing);
    });

    testWidgets('the row counts only the areas a customer can pick', (WidgetTester tester) async {
      await pumpShop(tester, shopJson(zones: <dynamic>[hamra, achrafieh, rasBeirut]));

      expect(find.text('${en.dareaWithinKm('3.0')} · ${en.dareaAreasCount(2)}'), findsOneWidget);
      expect(find.text('${en.dareaWithinKm('3.0')} · ${en.dareaAreasCount(3)}'), findsNothing);
    });

    testWidgets('a circle and nothing but retired areas: the circle alone, with no count',
        (WidgetTester tester) async {
      await pumpShop(tester, shopJson(zones: <dynamic>[rasBeirut]));

      final YdListRow row = tester.widget<YdListRow>(find.widgetWithText(YdListRow, en.dareaButton));
      expect(row.subtitle, en.dareaWithinKm('3.0'));
    });

    testWidgets('the dekkane page shows it as a card under the hero', (WidgetTester tester) async {
      await pumpShop(tester, shopJson(radius: null, zones: <dynamic>[hamra]),
          layout: StorePageLayout.dekkane);

      final YdListRow row = tester.widget<YdListRow>(find.widgetWithText(YdListRow, en.dareaButton));
      expect(row.card, isTrue);
      expect(row.subtitle, en.dareaAreasCount(1));
    });

    testWidgets('in Arabic at 320dp it reads Arabic, right to left, and nothing overflows',
        (WidgetTester tester) async {
      await pumpShop(tester, shopJson(zones: <dynamic>[hamra, achrafieh, rasBeirut]),
          locale: const Locale('ar'), size: const Size(320, 1200));

      expect(find.text(ar.dareaButton), findsOneWidget);
      // Ras Beirut is retired, so two areas, not three.
      expect(find.text('${ar.dareaWithinKm('3.0')} · ${ar.dareaAreasCount(2)}'), findsOneWidget);
      expect(Directionality.of(tester.element(find.text(ar.dareaButton))), TextDirection.rtl);
      expect(tester.takeException(), isNull);
    });
  });

  // ------------------------------------------------------------------------------ the map screen

  Future<void> pumpMap(
    WidgetTester tester,
    Store shop, {
    DeliveryAddress? chosen,
    Locale locale = const Locale('en'),
    Size size = const Size(420, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final DeliveryAddressStore addresses = await book(chosen);
    await tester.pumpWidget(app(
      DeliveryAreaMapScreen(area: ShopDeliveryArea.of(shop)!, addresses: addresses),
      locale: locale,
    ));
    // The camera is fitted once the map knows its size, a frame after the first.
    await tester.pump();
    await tester.pump();
  }

  group('the map', () {
    testWidgets('draws the circle to the metre, and names only the areas that were placed',
        (WidgetTester tester) async {
      await pumpMap(tester, store(zones: <dynamic>[hamra, achrafieh, rasBeirut]));

      final CircleMarker ring =
          tester.widget<CircleLayer>(find.byType(CircleLayer)).circles.single;
      expect(ring.radius, 3000);
      expect(ring.useRadiusInMeter, isTrue);
      expect(ring.point.latitude, shopLat);
      expect(ring.point.longitude, shopLng);

      // Placed areas get their name on the map; every area a customer can pick is in the words
      // below it. Ras Beirut is placed but retired, so it is in neither.
      final Iterable<String> onMap = tester
          .widgetList<DeliveryAreaZoneName>(find.byType(DeliveryAreaZoneName))
          .map((DeliveryAreaZoneName n) => n.name);
      expect(onMap, <String>['Hamra']);
      expect(find.text('Achrafieh'), findsOneWidget);
      expect(find.text('Ras Beirut'), findsNothing);
      expect(find.text(en.dareaCircleRule('3.0')), findsOneWidget);
      expect(find.text(en.dareaZonesTitle), findsOneWidget);
      expect(find.text(en.dareaBothRules), findsOneWidget);
      expect(find.text(en.dareaZoneLabelsNote), findsOneWidget);
      // Only the circle is a shape: no region is drawn around an area's centre.
      expect(find.byType(PolygonLayer), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('an address inside the circle is drawn and said to be inside',
        (WidgetTester tester) async {
      await pumpMap(tester, store(),
          chosen: at(latitude: north(1000), longitude: shopLng));

      expect(find.text(en.dareaInside), findsOneWidget);
      expect(find.text(en.dareaOutside), findsNothing);
      expect(find.text('Home · Bliss Street, Building 12'), findsOneWidget);
      expect(addressPin(), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('an address outside the circle is said to be outside', (WidgetTester tester) async {
      await pumpMap(tester, store(), chosen: at(latitude: north(5000), longitude: shopLng));

      expect(find.text(en.dareaOutside), findsOneWidget);
      expect(find.text(en.dareaInside), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('an address in an area the shop does not serve is outside, one it serves inside',
        (WidgetTester tester) async {
      final Store byArea = store(radius: null, zones: <dynamic>[hamra]);
      await pumpMap(tester, byArea, chosen: at(zoneId: 'z-jounieh'));
      expect(find.text(en.dareaOutside), findsOneWidget);
      await tester.pumpAndSettle();

      await pumpMap(tester, byArea, chosen: at(zoneId: 'z-hamra'));
      expect(find.text(en.dareaInside), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('an address nothing can be checked on gets no line, and no pin',
        (WidgetTester tester) async {
      await pumpMap(tester, store(), chosen: at());

      expect(find.text(en.dareaInside), findsNothing);
      expect(find.text(en.dareaOutside), findsNothing);
      expect(addressPin(), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('areas nobody placed, around a shop with no pin, are words without a map',
        (WidgetTester tester) async {
      await pumpMap(tester,
          store(latitude: null, longitude: null, radius: null, zones: <dynamic>[achrafieh]));

      expect(find.byType(OsmBasemap), findsNothing);
      expect(find.text('Achrafieh'), findsOneWidget);
      expect(find.text(en.dareaZonesTitle), findsOneWidget);
      // With no map there are no names on one to explain.
      expect(find.text(en.dareaZoneLabelsNote), findsNothing);
      expect(find.text(en.dareaCircleRule('3.0')), findsNothing);
    });

    testWidgets('a retired area is neither named nor listed, yet a saved address in it is inside',
        (WidgetTester tester) async {
      await pumpMap(tester, store(radius: null, zones: <dynamic>[hamra, achrafieh, rasBeirut]),
          chosen: at(zoneId: 'z-ras-beirut'));

      expect(find.text(en.dareaInside), findsOneWidget,
          reason: 'Order placement still serves an address saved in a retired area.');
      expect(find.text('Ras Beirut'), findsNothing);
      expect(
          tester
              .widgetList<DeliveryAreaZoneName>(find.byType(DeliveryAreaZoneName))
              .map((DeliveryAreaZoneName n) => n.name),
          <String>['Hamra']);
      expect(find.text('Achrafieh'), findsOneWidget);
      expect(find.text(en.dareaZonesTitle), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('areas all retired, around a circle: the circle alone, and no list',
        (WidgetTester tester) async {
      await pumpMap(tester, store(zones: <dynamic>[rasBeirut]),
          chosen: at(latitude: north(500), longitude: shopLng, zoneId: 'z-ras-beirut'));

      expect(find.byType(CircleLayer), findsOneWidget);
      expect(find.text(en.dareaCircleRule('3.0')), findsOneWidget);
      expect(find.text(en.dareaInside), findsOneWidget);
      // No "Delivers to these areas" over nothing, and no "one of these areas" either.
      expect(find.text(en.dareaZonesTitle), findsNothing);
      expect(find.text(en.dareaBothRules), findsNothing);
      expect(find.text(en.dareaZoneLabelsNote), findsNothing);
      expect(find.byType(DeliveryAreaZoneName), findsNothing);
      expect(find.text('Ras Beirut'), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets("a retired area's centre alone puts nothing on a map",
        (WidgetTester tester) async {
      // No pin, no circle: the only placed area is retired, so there is nothing to draw.
      await pumpMap(
          tester,
          store(
              latitude: null,
              longitude: null,
              radius: null,
              zones: <dynamic>[achrafieh, rasBeirut]));

      expect(find.byType(OsmBasemap), findsNothing);
      expect(find.text('Achrafieh'), findsOneWidget);
      expect(find.text('Ras Beirut'), findsNothing);
    });

    for (final (Locale locale, DeliveryStrings t) in <(Locale, DeliveryStrings)>[
      (const Locale('en'), en),
      (const Locale('ar'), ar),
    ]) {
      testWidgets(
          'with the tile server unreachable, says so where the map was, and the words stay '
          '(${locale.languageCode})', (WidgetTester tester) async {
        await pumpMap(tester, store(zones: <dynamic>[hamra]),
            chosen: at(latitude: north(1000), longitude: shopLng),
            locale: locale,
            size: const Size(320, 640));
        expect(find.text(t.dareaMapUnavailable), findsNothing);

        // Tiles failing with none ever loaded, as the tile layer reports them: after four, the
        // basemap calls the tile server unreachable and stands the screen's fallback in its place.
        final TileLayer tiles = tester.widget<TileLayer>(find.byType(TileLayer));
        for (int i = 0; i < 4; i++) {
          tiles.errorTileCallback!(_FailedTile(), Exception('unreachable'), null);
        }
        // The switch waits for the end of a frame, then rebuilds on the next. The tile layer's own
        // redraw of a failed tile is the frame that ends; here nothing else asks for one.
        tester.binding.scheduleFrame();
        await tester.pump();
        await tester.pump();

        expect(find.text(t.dareaMapUnavailable), findsOneWidget);
        expect(find.byIcon(Icons.map_outlined), findsOneWidget);
        expect(find.byType(FlutterMap), findsNothing);
        expect(find.text(OsmBasemap.attribution), findsNothing,
            reason: 'No tiles are shown, so there is nothing to credit.');
        // The words under it still say where the shop delivers, and where the address stands.
        expect(find.text(t.dareaCircleRule('3.0')), findsOneWidget);
        expect(find.text(t.dareaInside), findsOneWidget);
        expect(find.text('Hamra'), findsOneWidget, reason: 'In the list; no map to name it on.');
        expect(tester.takeException(), isNull);
        if (locale.languageCode == 'ar') {
          expect(Directionality.of(tester.element(find.text(ar.dareaMapUnavailable))),
              TextDirection.rtl);
        }
        await tester.pumpAndSettle();
      });

      testWidgets('fits a 320dp phone with many areas (${locale.languageCode})',
          (WidgetTester tester) async {
        final List<Map<String, dynamic>> many = <Map<String, dynamic>>[
          for (int i = 0; i < 24; i++)
            <String, dynamic>{
              'id': 'z-$i',
              'name': 'Neighbourhood With A Long Name $i',
              'sortOrder': i,
              'active': true,
              if (i.isEven) 'centerLat': 33.89 + i / 1000,
              if (i.isEven) 'centerLng': 35.48 + i / 1000,
            },
        ];
        await pumpMap(tester, store(zones: many),
            chosen: at(latitude: north(5000), longitude: shopLng, zoneId: 'z-3'),
            locale: locale,
            size: const Size(320, 640));

        expect(find.text(t.dareaOutside), findsOneWidget);
        expect(find.text(t.dareaCircleRule('3.0')), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (locale.languageCode == 'ar') {
          expect(Directionality.of(tester.element(find.text(ar.dareaOutside))),
              TextDirection.rtl);
          expect(tester.widget<YdScreenHeader>(find.byType(YdScreenHeader)).title,
              ar.dareaButton);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ---------------------------------------------------------------------- a service provider

  group('on a service provider\'s page', () {
    Future<void> pumpProvider(WidgetTester tester, {required List<String> fulfilments}) async {
      final FakeServer server = FakeServer()
        ..on('GET', '/api/stores/s1', (_) => <String, dynamic>{
              ...storeJson(),
              'deliveryRadiusMetres': 2000,
              'deliveryZones': <dynamic>[],
            })
        ..on('GET', '/api/stores/s1/products', (_) => pageJson(<Map<String, dynamic>>[
              for (final (int i, String fulfilment) in fulfilments.indexed)
                offerJson(id: 'p$i', name: 'Offer $i', fulfilment: fulfilment),
            ]));
      phone(tester);
      await tester.pumpWidget(svcApp(ServiceProviderScreen(
        kit: ServicesKit(
          storeApi: StoreApi(server.dio),
          orderApi: OrderApi(server.dio),
          zoneApi: DeliveryZoneApi(server.dio),
          addresses: DeliveryAddressStore(ownerId: 'test-user'),
          connectivity: ValueNotifier<bool>(true),
        ),
        storeId: 's1',
      )));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the row when one of its offers is delivered', (WidgetTester tester) async {
      await pumpProvider(tester, fulfilments: <String>['PICKUP', 'BOTH']);

      expect(find.text(en.dareaButton), findsOneWidget);
      expect(find.text(en.dareaWithinKm('2.0')), findsOneWidget);
    });

    testWidgets('a pickup-only provider has no delivery area to show', (WidgetTester tester) async {
      await pumpProvider(tester, fulfilments: <String>['PICKUP', 'PICKUP']);

      expect(find.text('Offer 0'), findsOneWidget, reason: 'The page itself is there.');
      expect(find.text(en.dareaButton), findsNothing);
    });
  });

  testWidgets('the row draws nothing before the full store arrives, then itself',
      (WidgetTester tester) async {
    Widget row(Store? shop) => app(Scaffold(body: DeliveryAreaButton(store: shop)));

    await tester.pumpWidget(row(null));
    expect(find.text(en.dareaButton), findsNothing);
    expect(find.byType(YdListRow), findsNothing);

    await tester.pumpWidget(row(store()));
    expect(find.text(en.dareaButton), findsOneWidget);
  });
}

/// A tile the tile server did not deliver, as the tile layer hands one to its error callback. The
/// basemap reads nothing of it but that it failed.
class _FailedTile extends Fake implements TileImage {}
