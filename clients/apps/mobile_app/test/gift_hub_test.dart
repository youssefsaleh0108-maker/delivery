import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/cart.dart';
import 'package:mobile_app/src/delivery_address.dart';
import 'package:mobile_app/src/gift_hub_screen.dart';
import 'package:mobile_app/src/shops_listing_screen.dart';

/// The gift hub: its four ways in lead where they say, the recipients are the people the address
/// book names, and the bundles section shows only what the platform returned.
void main() {
  const MethodChannel storageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (MethodCall call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
  });

  Map<String, dynamic> bundle(String id, String name, double price, {required bool today}) =>
      <String, dynamic>{
        'productId': id,
        'merchantId': 'merchant-1',
        'storeId': 'store-1',
        'storeSlug': 'dekkane',
        'storeName': 'Dekkane Abou Selim',
        'name': name,
        'description': 'Oil, rice, lentils, tea & tinned foods.',
        'price': price,
        'imageUrls': <String>[],
        'imageThumbUrls': <String>[],
        'availability': today ? 'OPEN' : 'CLOSED',
        'sameDayDeliverable': today,
      };

  /// A gateway answering the bundles (or failing them) and an empty shop listing.
  Dio gateway({List<Map<String, dynamic>>? bundles, bool bundlesFail = false}) {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway.test'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) {
        if (o.path == '/api/gift-bundles') {
          if (bundlesFail) {
            h.reject(DioException(
              requestOptions: o,
              type: DioExceptionType.badResponse,
              response: Response<dynamic>(requestOptions: o, statusCode: 500),
            ));
          } else {
            h.resolve(Response<dynamic>(
                requestOptions: o, statusCode: 200, data: bundles ?? <dynamic>[]));
          }
          return;
        }
        if (o.path == '/api/stores') {
          h.resolve(Response<dynamic>(requestOptions: o, statusCode: 200, data: <String, dynamic>{
            'content': <dynamic>[],
            'page': 0,
            'size': 20,
            'totalElements': 0,
            'totalPages': 0,
          }));
          return;
        }
        h.resolve(Response<dynamic>(requestOptions: o, statusCode: 200, data: <dynamic>[]));
      },
    ));
    return dio;
  }

  Future<void> pumpHub(
    WidgetTester tester, {
    required Dio dio,
    required DeliveryAddressStore addresses,
    required Cart cart,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      locale: locale,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocaleController.supported,
      home: GiftHubScreen(
        storeApi: StoreApi(dio),
        orderApi: OrderApi(dio),
        cart: cart,
        addresses: addresses,
        zoneApi: DeliveryZoneApi(dio),
        onOpenBasket: () {},
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<DeliveryAddressStore> addressBook() async {
    final DeliveryAddressStore store = DeliveryAddressStore(ownerId: 'test-user');
    await store.select(const DeliveryAddress(line: '4 Clemenceau Street', label: 'Home'));
    await store.select(
        const DeliveryAddress(line: 'Achrafieh, Sassine Square', label: 'Teta Layla', zoneName: 'Beirut'));
    await store.select(
        const DeliveryAddress(line: 'Tripoli, Mina Road', label: 'Cousin Rami', zoneName: 'Tripoli'));
    return store;
  }

  testWidgets('shows the promise, the three steps and the five gift categories',
      (WidgetTester tester) async {
    await pumpHub(tester,
        dio: gateway(), addresses: DeliveryAddressStore(ownerId: 'test-user'), cart: Cart());

    expect(find.text(en.giftHubTitle), findsOneWidget);
    expect(find.text(en.custDiasporaSub), findsOneWidget);
    expect(find.text(en.giftHubBannerTitle), findsOneWidget);
    for (final String step in <String>[en.giftStep1Title, en.giftStep2Title, en.giftStep3Title]) {
      expect(find.text(step), findsOneWidget);
    }
    for (final String category in <String>[
      en.giftCatCarePackage,
      en.giftCatGroceries,
      en.giftCatSweets,
      en.giftCatBabyKids,
      en.giftCatMedicine,
    ]) {
      expect(find.text(category), findsOneWidget);
    }
  });

  testWidgets('a category opens its shops and makes the basket a gift', (WidgetTester tester) async {
    final Cart cart = Cart();
    await pumpHub(tester,
        dio: gateway(), addresses: DeliveryAddressStore(ownerId: 'test-user'), cart: cart);

    await tester.tap(find.text(en.giftCatGroceries));
    await tester.pumpAndSettle();

    final ShopsListingScreen groceries =
        tester.widget<ShopsListingScreen>(find.byType(ShopsListingScreen));
    expect(groceries.initialVertical, StoreVertical.grocery);
    expect(groceries.title, isNull);
    expect(cart.isGift, isTrue);

    // YdScreenHeader draws its own back button, so pop the route rather than look for Material's.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.giftCatSweets));
    await tester.pumpAndSettle();

    // No vertical sells sweets: a name search, titled so it is not passed off as every store.
    final ShopsListingScreen sweets =
        tester.widget<ShopsListingScreen>(find.byType(ShopsListingScreen));
    expect(sweets.initialVertical, isNull);
    expect(sweets.initialSearch, 'sweet');
    expect(sweets.title, en.giftCatSweets);
  });

  testWidgets('recipients are the saved addresses that name a person; choosing one is the gift\'s',
      (WidgetTester tester) async {
    final DeliveryAddressStore addresses = await addressBook();
    final Cart cart = Cart();
    await pumpHub(tester, dio: gateway(), addresses: addresses, cart: cart);

    expect(find.text('Teta Layla'), findsOneWidget);
    expect(find.text('Cousin Rami'), findsOneWidget);
    expect(find.text('TL'), findsOneWidget);
    expect(find.text('Tripoli'), findsOneWidget);
    // A place is not a person.
    expect(find.text('Home'), findsNothing);
    expect(find.text(en.custStartOrder), findsNothing);

    await tester.tap(find.text('Teta Layla'));
    await tester.pumpAndSettle();

    expect(addresses.selected?.line, 'Achrafieh, Sassine Square');
    expect(cart.isGift, isTrue);
    expect(find.text(en.custStartOrder), findsOneWidget);
  });

  testWidgets('with nobody saved yet, adding a recipient opens the address sheet',
      (WidgetTester tester) async {
    await pumpHub(tester,
        dio: gateway(), addresses: DeliveryAddressStore(ownerId: 'test-user'), cart: Cart());

    await tester.tap(find.text(en.giftAddRecipient));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('bundles show their price and shop, and promise today only where it is true',
      (WidgetTester tester) async {
    await pumpHub(
      tester,
      dio: gateway(bundles: <Map<String, dynamic>>[
        bundle('b1', 'Family Essentials', 45, today: true),
        bundle('b2', 'Sweet Treats', 25, today: false),
      ]),
      addresses: DeliveryAddressStore(ownerId: 'test-user'),
      cart: Cart(),
    );

    expect(find.text(en.giftFeaturedBundles.toUpperCase()), findsOneWidget);
    expect(find.text('Family Essentials'), findsOneWidget);
    expect(find.text('\$45.00'), findsOneWidget);
    expect(find.text('Sweet Treats'), findsOneWidget);
    expect(find.text('Dekkane Abou Selim'), findsNWidgets(2));
    expect(find.text(en.giftSameDayDeliverable), findsOneWidget);
  });

  testWidgets('the bundles section is hidden when the call fails or returns nothing',
      (WidgetTester tester) async {
    await pumpHub(tester,
        dio: gateway(bundlesFail: true),
        addresses: DeliveryAddressStore(ownerId: 'test-user'),
        cart: Cart());

    expect(find.text(en.giftFeaturedBundles.toUpperCase()), findsNothing);
    expect(find.text(en.giftStep1Title), findsOneWidget);

    await pumpHub(tester,
        dio: gateway(bundles: <Map<String, dynamic>>[]),
        addresses: DeliveryAddressStore(ownerId: 'test-user'),
        cart: Cart());

    expect(find.text(en.giftFeaturedBundles.toUpperCase()), findsNothing);
  });

  testWidgets('in Arabic, the hub renders without overflow and its scrollers run right to left',
      (WidgetTester tester) async {
    await pumpHub(
      tester,
      dio: gateway(bundles: <Map<String, dynamic>>[bundle('b1', 'سلة العائلة', 45, today: true)]),
      addresses: await addressBook(),
      cart: Cart(),
      locale: const Locale('ar'),
    );

    expect(tester.takeException(), isNull);
    final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));
    expect(find.text(ar.giftHubTitle), findsOneWidget);
    expect(
      tester.getCenter(find.text(ar.giftCatCarePackage)).dx,
      greaterThan(tester.getCenter(find.text(ar.giftCatGroceries)).dx),
    );
  });
}
