import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/cart.dart';
import 'package:mobile_app/src/cart_screen.dart';
import 'package:mobile_app/src/delivery_address.dart';

import 'widget_test.dart' show product, storeCard;

/// The Smart Basket (Figma 121:358): a basket from several shops, grouped by shop, with every figure
/// the server's.
///
/// Every money figure asserted here comes from a FAKE quote, and deliberately differs from anything
/// the phone could add up from the shop cards (whose fees here are all zero): a screen that did its
/// own arithmetic would fail these cases rather than pass them by coincidence.
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

  Map<String, dynamic> shopLine(String id,
          {double subtotal = 10,
          double fee = 3,
          double? total,
          String? refusal,
          double shortfall = 0,
          double minimum = 0,
          bool priced = true}) =>
      <String, dynamic>{
        'storeId': id,
        'storeName': 'Shop $id',
        'refusal': refusal,
        'refusalMessage': refusal == null ? null : 'Shop $id cannot take this order',
        if (priced) ...<String, dynamic>{
          'subtotal': subtotal,
          'minimumOrder': minimum,
          'shortfall': shortfall,
          'deliveryFee': fee,
          'deliveryFeeCharged': fee,
          'expressSurcharge': 0,
          'discountAmount': 0,
          'totalAmount': total ?? subtotal + fee,
        },
        'deliveryFeeWaived': false,
      };

  /// The design's three shops: 9.00, 0.80 and 5.00 of goods, each with a 3.00 fee.
  Map<String, dynamic> threeShopQuote({Map<String, dynamic>? secondShop, bool? placeable}) {
    final List<Map<String, dynamic>> shops = <Map<String, dynamic>>[
      shopLine('s1', subtotal: 9),
      secondShop ?? shopLine('s2', subtotal: 0.8),
      shopLine('s3', subtotal: 5),
    ];
    final bool allPriced = shops.every((Map<String, dynamic> s) => s['totalAmount'] != null);
    return <String, dynamic>{
      'shops': shops,
      'placeable': placeable ?? shops.every((Map<String, dynamic> s) => s['refusal'] == null),
      if (allPriced) ...<String, dynamic>{
        'subtotal': 14.8,
        'deliveryFeeCharged': 9,
        'expressSurcharge': 0,
        'discountAmount': 0,
        'totalAmount': 23.8,
      },
      'maxShops': 3,
    };
  }

  /// Order Manager for these tests: the quote is whatever [quote] answers for the question asked (a
  /// 404 when it answers null), and anything else is a 404.
  ({Dio dio, List<RequestOptions> asked}) server(
      Map<String, dynamic>? Function(Map<String, dynamic> question) quote) {
    final List<RequestOptions> asked = <RequestOptions>[];
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) {
        if (o.path == '/api/orders/quote') {
          asked.add(o);
          final Map<String, dynamic>? body = quote(o.data as Map<String, dynamic>);
          if (body != null) {
            h.resolve(Response<dynamic>(requestOptions: o, statusCode: 200, data: body));
            return;
          }
        }
        h.reject(DioException(
          requestOptions: o,
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(requestOptions: o, statusCode: 404),
        ));
      },
    ));
    return (dio: dio, asked: asked);
  }

  Future<void> pumpBasket(
    WidgetTester tester, {
    required Dio dio,
    required Cart cart,
    DeliveryAddressStore? addresses,
    Locale locale = const Locale('en'),
    VoidCallback? onOrderPlaced,
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
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
      home: CartScreen(
        cart: cart,
        addresses: addresses ?? DeliveryAddressStore(ownerId: 'user-1'),
        orderApi: OrderApi(dio),
        offerApi: OfferApi(dio),
        onOrderPlaced: onOrderPlaced ?? () {},
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Two shawarmas from s1, a Pepsi from s2 and Panadol from s3 — every card's fee zero.
  Cart threeShops() => Cart()
    ..add(product('shawarma', 's1', 4.50), from: storeCard('s1'))
    ..add(product('shawarma', 's1', 4.50), from: storeCard('s1'))
    ..add(product('pepsi', 's2', 0.80), from: storeCard('s2'))
    ..add(product('panadol', 's3', 5.00), from: storeCard('s3'));

  YdPillButton checkoutButton(WidgetTester tester) =>
      tester.widget<YdPillButton>(find.byType(YdPillButton));

  testWidgets('three shops are three groups under one header, and the button carries the server\'s '
      'whole total', (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> asked}) s =
        server((Map<String, dynamic> _) => threeShopQuote());
    await pumpBasket(tester, dio: s.dio, cart: threeShops());

    expect(find.text(en.multiCartTitle), findsOneWidget);
    expect(find.text(en.multiCartSubtitle), findsOneWidget);
    expect(find.text(en.multiCartShopCount(3)), findsOneWidget);
    expect(find.text(en.multiCartFromShop(2, 'Shop s1').toUpperCase()), findsOneWidget);
    expect(find.text(en.multiCartFromShop(1, 'Shop s2').toUpperCase()), findsOneWidget);
    expect(find.text(en.multiCartFromShop(1, 'Shop s3').toUpperCase()), findsOneWidget);

    // Each shop's own delivery fee — the server's 3.00, where every card said zero — and all three.
    expect(find.text(en.multiCartShopDelivery), findsNWidgets(3));
    expect(find.textContaining('\$3.00'), findsNWidgets(3));
    expect(find.text(en.multiCartDeliveryFromShops(3)), findsOneWidget);

    // The total the button carries includes delivery: 23.80, not the 14.80 of goods the frame's
    // "Checkout — $34.50" pattern would have shown.
    expect(find.widgetWithText(YdPillButton, en.multiCartCheckoutAmount('\$23.80')), findsOneWidget);
    expect(checkoutButton(tester).onPressed, isNotNull);
    // No unified fee and no saving: the server gives neither.
    expect(find.textContaining('save'), findsNothing);

    // One question for the whole basket: every shop's lines in one list.
    expect((s.asked.last.data as Map<String, dynamic>)['items'], hasLength(3));
  });

  testWidgets('a shop under its minimum is named on its own line, holds checkout, and can be taken '
      'out', (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> asked}) s = server((Map<String, dynamic> question) =>
        (question['items'] as List<dynamic>).length == 3
            ? threeShopQuote(
                secondShop: shopLine('s2',
                    subtotal: 0.8, refusal: 'BELOW_MINIMUM', minimum: 5, shortfall: 4.2))
            : <String, dynamic>{
                'shops': <dynamic>[shopLine('s1', subtotal: 9), shopLine('s3', subtotal: 5)],
                'placeable': true,
                'subtotal': 14,
                'deliveryFeeCharged': 6,
                'expressSurcharge': 0,
                'discountAmount': 0,
                'totalAmount': 20,
                'maxShops': 3,
              });
    final Cart cart = threeShops();
    await pumpBasket(tester, dio: s.dio, cart: cart);

    expect(find.text(en.multiCartBelowMinimum('\$4.20', 'Shop s2')), findsOneWidget);
    expect(checkoutButton(tester).onPressed, isNull,
        reason: 'One shop cannot be checked out as it stands, so the basket cannot be either.');

    await tester.tap(find.text(en.multiCartRemoveShop('Shop s2')));
    await tester.pumpAndSettle();

    expect(cart.storeIds, <String>['s1', 's3']);
    expect(find.text(en.multiCartFromShop(1, 'Shop s2').toUpperCase()), findsNothing);
    expect(find.text(en.multiCartShopCount(2)), findsOneWidget);
    expect(find.widgetWithText(YdPillButton, en.multiCartCheckoutAmount('\$20.00')), findsOneWidget);
    expect(checkoutButton(tester).onPressed, isNotNull);
  });

  testWidgets('a closed shop leaves the basket without a total — a dash, never a total without it',
      (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> asked}) s = server((Map<String, dynamic> _) =>
        threeShopQuote(secondShop: shopLine('s2', refusal: 'CLOSED', priced: false)));
    await pumpBasket(tester, dio: s.dio, cart: threeShops());

    expect(find.text(en.multiCartShopClosed('Shop s2')), findsOneWidget);
    expect(find.textContaining('23.80'), findsNothing);
    expect(find.widgetWithText(YdPillButton, en.checkout), findsOneWidget);
    expect(checkoutButton(tester).onPressed, isNull);
  });

  testWidgets('without the server\'s price, a basket from several shops is not checked out — and '
      'can ask again', (WidgetTester tester) async {
    bool answer = false;
    final ({Dio dio, List<RequestOptions> asked}) s =
        server((Map<String, dynamic> _) => answer ? threeShopQuote() : null);
    await pumpBasket(tester, dio: s.dio, cart: threeShops());

    expect(find.text(en.multiCartPricesFailed), findsOneWidget);
    expect(checkoutButton(tester).onPressed, isNull);

    answer = true;
    await tester.tap(find.text(en.tryAgain));
    await tester.pumpAndSettle();

    expect(s.asked, hasLength(2));
    expect(find.widgetWithText(YdPillButton, en.multiCartCheckoutAmount('\$23.80')), findsOneWidget);
  });

  testWidgets('a gift from several shops waits until one shop is left, and says why',
      (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> asked}) s =
        server((Map<String, dynamic> _) => threeShopQuote());
    await pumpBasket(tester, dio: s.dio, cart: threeShops()..startGift());

    expect(find.text(en.multiCartGiftOneShop), findsOneWidget);
    expect(checkoutButton(tester).onPressed, isNull);
  });

  testWidgets('an earlier try that placed the whole checkout is not confirmed as one order: the '
      'customer is sent to Orders, where every order of it is listed', (WidgetTester tester) async {
    int ordersOpened = 0;
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) {
        switch (o.path) {
          case '/api/orders/quote':
            h.resolve(Response<dynamic>(requestOptions: o, statusCode: 200, data: threeShopQuote()));
          case '/api/orders/checkout':
            // This attempt's key already placed a checkout: the basket as it was before it changed.
            h.reject(DioException(
              requestOptions: o,
              type: DioExceptionType.badResponse,
              response: Response<dynamic>(requestOptions: o, statusCode: 409, data: <String, dynamic>{
                'code': 'IDEMPOTENCY_KEY_REUSED',
                'orderId': 'order-1',
              }),
            ));
          case '/api/orders/order-1':
            // The order carrying the key: one of three.
            h.resolve(Response<dynamic>(requestOptions: o, statusCode: 200, data: <String, dynamic>{
              'id': 'order-1',
              'customerId': 'user-1',
              'merchantId': 'm1',
              'riderId': null,
              'status': 'PLACED',
              'totalAmount': 12,
              'storeId': 's1',
              'deliveryAddress': '12 Rose Street',
              'paymentMethod': 'CASH',
              'paymentStatus': 'DUE',
              'items': <dynamic>[],
              'availableActions': <dynamic>[],
              'checkoutId': 'checkout-1',
              'checkoutSize': 3,
            }));
          default:
            h.reject(DioException(
              requestOptions: o,
              type: DioExceptionType.badResponse,
              response: Response<dynamic>(requestOptions: o, statusCode: 404),
            ));
        }
      },
    ));
    final DeliveryAddressStore addresses = DeliveryAddressStore(ownerId: 'user-1');
    await addresses.select(const DeliveryAddress(line: '12 Rose Street', label: 'Home'));
    final Cart cart = threeShops();
    await pumpBasket(tester,
        dio: dio, cart: cart, addresses: addresses, onOrderPlaced: () => ordersOpened++);

    // The basket's checkout, then checkout's own button.
    await tester.tap(find.byType(YdPillButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(YdPillButton));
    await tester.pumpAndSettle();

    expect(find.text(en.multiCartEarlierCheckoutPlaced(3)), findsOneWidget);
    expect(find.text(en.offlineAlreadyPlaced), findsNothing,
        reason: 'That sentence confirms a single order, and this try placed three.');
    expect(ordersOpened, 1);
    expect(cart.isEmpty, isTrue);
  });

  testWidgets('a basket from one shop keeps its own layout, priced for the address\'s area',
      (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> asked}) s = server((Map<String, dynamic> _) =>
        <String, dynamic>{
          'shops': <dynamic>[shopLine('s1', subtotal: 10, fee: 1.5)],
          'placeable': true,
          'subtotal': 10,
          'deliveryFeeCharged': 1.5,
          'expressSurcharge': 0,
          'discountAmount': 0,
          'totalAmount': 11.5,
          'maxShops': 3,
        });
    final DeliveryAddressStore addresses = DeliveryAddressStore(ownerId: 'user-1');
    await addresses.select(
        const DeliveryAddress(line: '12 Rose Street', zoneId: 'zone-hamra', zoneName: 'Hamra'));
    await pumpBasket(tester,
        dio: s.dio,
        cart: Cart()..add(product('a', 's1', 10), from: storeCard('s1', deliveryFee: 3)),
        addresses: addresses);

    expect(find.text(en.custMyBasket), findsOneWidget);
    expect(find.text(en.multiCartTitle), findsNothing);
    expect(find.text(en.multiCartShopCount(1)), findsNothing);
    // The area's 1.50, not the card's flat 3.00 — the Basket tab used to show the card's.
    expect(find.textContaining('\$1.50'), findsOneWidget);
    expect(find.textContaining('\$3.00'), findsNothing);
    expect(find.textContaining('\$11.50'), findsOneWidget);
    expect(find.widgetWithText(YdPillButton, en.custProceedToCheckout), findsOneWidget);
    expect((s.asked.last.data as Map<String, dynamic>)['deliveryZoneId'], 'zone-hamra');
  });

  testWidgets('at an area the server has not priced, a one-shop basket shows a dash, not the card\'s '
      'flat fee', (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> asked}) s = server((Map<String, dynamic> _) => null);
    final DeliveryAddressStore addresses = DeliveryAddressStore(ownerId: 'user-1');
    await addresses.select(const DeliveryAddress(line: '12 Rose Street', zoneId: 'zone-hamra'));
    await pumpBasket(tester,
        dio: s.dio,
        cart: Cart()..add(product('a', 's1', 10), from: storeCard('s1', deliveryFee: 3)),
        addresses: addresses);

    expect(find.textContaining('\$3.00'), findsNothing);
    expect(find.textContaining('\$13.00'), findsNothing);
    expect(find.text(en.multiCartPricesFailed), findsOneWidget);
  });

  testWidgets('in Arabic the Smart Basket reads right to left, in Arabic', (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> asked}) s =
        server((Map<String, dynamic> _) => threeShopQuote());
    await pumpBasket(tester, dio: s.dio, cart: threeShops(), locale: const Locale('ar'));

    expect(find.text(ar.multiCartTitle), findsOneWidget);
    expect(find.text(ar.multiCartShopCount(3)), findsOneWidget);
    expect(Directionality.of(tester.element(find.text(ar.multiCartTitle))), TextDirection.rtl);
    // Uppercased as the frame draws the label: Arabic has no case, so only the Latin shop name
    // changes.
    expect(find.text(ar.multiCartFromShop(2, 'Shop s1').toUpperCase()), findsOneWidget);
  });
}
