import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/cart.dart';
import 'package:mobile_app/src/product_detail_screen.dart' show ProductDetailScreen;
import 'package:mobile_app/src/store_page_screen.dart';

import 'widget_test.dart' show product, storeCard;

/// The dekkane shop page (Figma 112:2041): the same shop page — its basket rules, its option
/// sheet, its paging — drawn to the neighbourhood frame.
///
/// What is pinned is what the frame asks of real data: the district under the name, an open pill
/// that reads the shop's real closing time, the power pill only when the merchant declared a
/// generator, a two-column shelf whose Add goes through exactly the flows the standard page uses,
/// an LBP line that exists only when there is a rate to convert with — and the chat pill's slot,
/// which is a documented hook that draws nothing until a chat capability exists to put in it.
void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  Map<String, dynamic> page(List<Map<String, dynamic>> content) => <String, dynamic>{
        'content': content,
        'page': 0,
        'totalElements': content.length,
        'totalPages': 1,
      };

  Map<String, dynamic> item(String id, String name, double price, String categoryId) =>
      <String, dynamic>{
        'id': id,
        'merchantId': 'm1',
        'storeId': 's1',
        'name': name,
        'price': price,
        'categoryId': categoryId,
        'status': 'ACTIVE',
      };

  final List<Map<String, dynamic>> shelf = <Map<String, dynamic>>[
    item('p-halloumi', 'Local Halloumi Cheese', 3.5, 'c-dairy'),
    item('p-zaatar', 'Fresh Zaatar Bread', 1.2, 'c-bakery'),
    item('p-pepsi', 'Pepsi Glass Bottle 330ml', 0.8, 'c-drinks'),
  ];

  late Map<String, dynamic> shop;
  late List<RequestOptions> requests;

  setUp(() async {
    shop = <String, dynamic>{
      'id': 's1',
      'slug': 's1',
      'name': 'Abu Hassan Mini Market',
      'vertical': 'GROCERY',
      'availability': 'OPEN',
      'closesAt': '22:00:00',
      'neighborhood': 'Mar Mikhael',
      'powerStatus': 'GENERATOR',
      // Declared two hours ago and still current: long enough ago that the age reads in hours and
      // cannot tick over while the test runs.
      'powerUpdatedAt':
          DateTime.now().toUtc().subtract(const Duration(hours: 2)).toIso8601String(),
      'powerCurrent': true,
      'rating': 4.8,
      'ratingCount': 234,
      'tagline': 'Family-run since 1985',
      'deliveryFee': 0,
      'minOrder': 0,
    };
    requests = <RequestOptions>[];
    await MarketRates.instance.load(_rateServer(0));
  });

  tearDown(() async => MarketRates.instance.load(_rateServer(0)));

  List<Map<String, dynamic>> shelfQueries() => requests
      .where((RequestOptions r) => r.path == '/api/stores/s1/products')
      .map((RequestOptions r) => r.queryParameters)
      .toList();

  Object? answer(RequestOptions options) => switch (options.path) {
        '/api/stores/s1' => shop,
        '/api/stores/s1/products' => page(options.queryParameters['categoryId'] == null
            ? shelf
            : shelf
                .where((Map<String, dynamic> p) =>
                    p['categoryId'] == options.queryParameters['categoryId'])
                .toList()),
        '/api/stores/s1/aisles' => <Map<String, dynamic>>[
            <String, dynamic>{'categoryId': 'c-dairy', 'name': 'Dairy', 'productCount': 1},
            <String, dynamic>{'categoryId': 'c-drinks', 'name': 'Drinks', 'productCount': 1},
          ],
        '/api/stores/s1/offers' => page(const <Map<String, dynamic>>[]),
        '/api/products/p-halloumi/options' || '/api/products/p-pepsi/options' =>
          const <dynamic>[],
        '/api/products/p-zaatar/options' => <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'g-size',
              'name': 'Size',
              'minSelect': 1,
              'maxSelect': 1,
              'required': true,
              'singleChoice': true,
              'options': <Map<String, dynamic>>[
                <String, dynamic>{'id': 'o-small', 'name': 'Small', 'priceDelta': 0},
              ],
            },
          ],
        _ => null,
      };

  Dio fakeServer() {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        requests.add(options);
        final Object? body = options.method == 'GET' ? answer(options) : null;
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

  Future<Cart> pumpShop(
    WidgetTester tester, {
    Cart? cart,
    Locale locale = const Locale('en'),
    ShopChatActionBuilder? chat,
    StorePageLayout layout = StorePageLayout.dekkane,
  }) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final Cart basket = cart ?? Cart();
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
      home: StorePageScreen(
        storeApi: StoreApi(fakeServer()),
        cart: basket,
        storeId: 's1',
        onOpenBasket: () {},
        layout: layout,
        shopChatAction: chat,
      ),
    ));
    await tester.pumpAndSettle();
    return basket;
  }

  Finder tileOf(String name) => find.widgetWithText(ShelfGridTile, name);

  Finder addOn(String name) =>
      find.descendant(of: tileOf(name), matching: find.text(en.custAddToBasket));

  group('the header and hero', () {
    testWidgets('name the district, and read open with the shop\'s real closing time',
        (WidgetTester tester) async {
      await pumpShop(tester);

      expect(find.descendant(of: find.byType(YdScreenHeader), matching: find.text('Mar Mikhael')),
          findsOneWidget);
      expect(find.text(en.dekkaneOpenClosesAt('10:00 PM')), findsOneWidget);
      // The rating, how many gave it, and the merchant's own line — "since 1985" is theirs.
      expect(
          find.text('★ 4.8 (${en.custRatingsCount(234)}) · Family-run since 1985'),
          findsOneWidget);
      // No tabs, search or heart: the frame has none.
      expect(find.byType(TabBarView), findsNothing);
    });

    testWidgets('a shop with no district has no subtitle rather than an empty one',
        (WidgetTester tester) async {
      shop['neighborhood'] = null;
      await pumpShop(tester);

      expect(tester.widget<YdScreenHeader>(find.byType(YdScreenHeader)).subtitle, isNull);
    });

    testWidgets('the generator pill is there only when the merchant declared a generator',
        (WidgetTester tester) async {
      await pumpShop(tester);
      expect(find.text(en.dekkaneGeneratorActive), findsOneWidget);
    });

    testWidgets('and mains draws no pill at all', (WidgetTester tester) async {
      shop['powerStatus'] = 'MAINS';
      await pumpShop(tester);
      expect(find.text(en.dekkaneGeneratorActive), findsNothing);
    });

    testWidgets('the pill says how long ago the merchant declared it', (WidgetTester tester) async {
      await pumpShop(tester);
      expect(find.text(en.dekkanePowerUpdatedHours(2)), findsOneWidget);
    });

    testWidgets('a declaration too old to count as now draws no pill, whatever it said',
        (WidgetTester tester) async {
      // "Generator active" is a claim about now; the server said this one no longer is.
      shop['powerCurrent'] = false;
      await pumpShop(tester);
      expect(find.text(en.dekkaneGeneratorActive), findsNothing);
      expect(find.text(en.dekkanePowerUpdatedHours(2)), findsNothing);
    });
  });

  group('a closed shop', () {
    testWidgets('says so, and its shelf still browses — with nothing to add',
        (WidgetTester tester) async {
      shop['availability'] = 'CLOSED';
      shop['closesAt'] = null;
      await pumpShop(tester);

      expect(find.text(StoreAvailability.closed.labelIn(en)), findsOneWidget);
      expect(tileOf('Local Halloumi Cheese'), findsOneWidget);
      expect(find.text(en.custAddToBasket), findsNothing,
          reason: 'A closed shop cannot take the order, so no button offers to.');
    });
  });

  group('the shelf', () {
    testWidgets('is two columns', (WidgetTester tester) async {
      await pumpShop(tester);

      final Offset first = tester.getTopLeft(tileOf('Local Halloumi Cheese'));
      final Offset second = tester.getTopLeft(tileOf('Fresh Zaatar Bread'));
      final Offset third = tester.getTopLeft(tileOf('Pepsi Glass Bottle 330ml'));

      expect(second.dy, first.dy, reason: 'The first two products share a row.');
      expect(second.dx, greaterThan(first.dx));
      expect(third.dy, greaterThan(first.dy), reason: 'The third starts the next row.');
      expect(third.dx, first.dx);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Add to basket on a product without options puts it in the basket',
        (WidgetTester tester) async {
      final Cart cart = await pumpShop(tester);

      await tester.tap(addOn('Local Halloumi Cheese'));
      await tester.pumpAndSettle();

      expect(cart.qtyOf('p-halloumi'), 1);
      expect(cart.storeId, 's1');
      // The button turned into the stepper, and the basket bar arrived with the item.
      expect(find.descendant(of: tileOf('Local Halloumi Cheese'), matching: find.text('1')),
          findsOneWidget);
      expect(find.byType(StickyBasketBar), findsOneWidget);
    });

    testWidgets('with options it asks them first, on the product screen',
        (WidgetTester tester) async {
      final Cart cart = await pumpShop(tester);
      // Widened for this one test. The product screen is not this frame's, and its button is laid
      // out for the real font: the test font draws every glyph a full em wide, so at a phone width
      // "Select required options" overflows beside the quantity stepper. The grid itself stays
      // pinned at phone width by the tests around this one.
      tester.view.physicalSize = const Size(1000, 2400);
      await tester.pumpAndSettle();

      await tester.tap(addOn('Fresh Zaatar Bread'));
      await tester.pumpAndSettle();

      expect(find.byType(ProductDetailScreen), findsOneWidget);
      expect(cart.qtyOf('p-zaatar'), 0);
    });

    testWidgets('from another shop\'s basket the shelf item joins it, and nothing is replaced',
        (WidgetTester tester) async {
      final Cart cart = Cart()..add(product('p-other', 's2', 5), from: storeCard('s2'));
      await pumpShop(tester, cart: cart);

      await tester.tap(addOn('Local Halloumi Cheese'));
      await tester.pumpAndSettle();

      // A basket holds several shops now: the dekkane's item is added, and nothing offers to throw
      // the other shop's basket away.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(en.startNewBasket), findsNothing);
      expect(cart.qtyOf('p-halloumi'), 1);
      expect(cart.qtyOf('p-other'), 1, reason: 'The other shop\'s item is still in the basket.');
      expect(cart.storeIds, containsAll(<String>['s1', 's2']));
    });

    testWidgets('past the basket\'s shop limit the tap is explained, and the basket keeps every shop',
        (WidgetTester tester) async {
      final Cart cart = Cart();
      for (final String shop in <String>['s2', 's3', 's4']) {
        cart.add(product('p-$shop', shop, 5), from: storeCard(shop));
      }
      await pumpShop(tester, cart: cart);

      await tester.tap(addOn('Local Halloumi Cheese'));
      await tester.pumpAndSettle();

      expect(find.text(en.multiCartShopLimitTitle(Cart.maxShops)), findsOneWidget);
      expect(find.text(en.multiCartShopLimitBody), findsOneWidget);
      expect(cart.qtyOf('p-halloumi'), 0);
      expect(cart.storeIds, <String>['s2', 's3', 's4']);
    });

    testWidgets('the LBP line exists only once there is a rate to convert with',
        (WidgetTester tester) async {
      await pumpShop(tester);
      expect(find.text(en.dekkaneLbpAmount(313000)), findsNothing);

      // Outside the test's fake clock. The rate arrives through a client whose future completes
      // only on the real event loop; awaited inside testWidgets' zone it never did, and the test
      // sat there until the ten-minute timeout.
      await tester.runAsync(() => MarketRates.instance.load(_rateServer(89500)));
      await tester.pumpAndSettle();

      // $3.50 at 89,500, rounded to the thousand — and it arrived without anything else rebuilding.
      expect(find.text(en.dekkaneLbpAmount(313000)), findsOneWidget);
      expect(find.text('LBP 313,000'), findsOneWidget);
    });

    testWidgets('"All" clears the aisle, and the shelf is asked for without one',
        (WidgetTester tester) async {
      await pumpShop(tester);

      await tester.tap(find.text('Dairy'));
      await tester.pumpAndSettle();
      expect(shelfQueries().last['categoryId'], 'c-dairy');
      expect(tileOf('Fresh Zaatar Bread'), findsNothing);

      await tester.tap(find.text(en.all));
      await tester.pumpAndSettle();
      expect(shelfQueries().last.containsKey('categoryId'), isFalse);
      expect(tileOf('Fresh Zaatar Bread'), findsOneWidget);
    });
  });

  group('the chat hook', () {
    testWidgets('draws nothing when nobody has wired a chat', (WidgetTester tester) async {
      await pumpShop(tester);

      final Scaffold scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.floatingActionButton, isNull,
          reason: 'There is no shop chat to open, so no pill offers one.');
    });

    testWidgets('places what it is given above the basket bar, told which shop it is for',
        (WidgetTester tester) async {
      StoreCard? askedAbout;
      await pumpShop(tester, chat: (BuildContext context, StoreCard store) {
        askedAbout = store;
        return const Text('shop chat slot');
      });

      expect(askedAbout?.id, 's1');
      expect(find.text('shop chat slot'), findsOneWidget);

      await tester.tap(addOn('Local Halloumi Cheese'));
      await tester.pumpAndSettle();

      final Rect slot = tester.getRect(find.text('shop chat slot'));
      final Rect bar = tester.getRect(find.byType(StickyBasketBar));
      expect(slot.bottom, lessThanOrEqualTo(bar.top),
          reason: 'The chat pill and the basket bar must never overlap.');
    });

    testWidgets('and the standard layout, which has no such slot, ignores it',
        (WidgetTester tester) async {
      await pumpShop(tester,
          layout: StorePageLayout.standard,
          chat: (BuildContext context, StoreCard store) => const Text('shop chat slot'));

      expect(find.text('shop chat slot'), findsNothing);
    });
  });

  testWidgets('in Arabic it reads Arabic and the grid runs right to left',
      (WidgetTester tester) async {
    await pumpShop(tester, locale: const Locale('ar'));

    expect(find.text(ar.dekkaneShopInventory), findsOneWidget);
    expect(find.text(ar.custAddToBasket), findsNWidgets(3));
    expect(Directionality.of(tester.element(tileOf('Local Halloumi Cheese'))), TextDirection.rtl);

    final Offset first = tester.getTopLeft(tileOf('Local Halloumi Cheese'));
    final Offset second = tester.getTopLeft(tileOf('Fresh Zaatar Bread'));
    expect(first.dx, greaterThan(second.dx), reason: 'The first product starts on the right.');
    expect(tester.takeException(), isNull);
  });
}

/// The market config endpoint, answering with one rate.
Dio _rateServer(num lbpPerUsd) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (RequestOptions options, RequestInterceptorHandler handler) => handler.resolve(
      Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: <String, dynamic>{'lbpPerUsd': lbpPerUsd},
      ),
    ),
  ));
  return dio;
}
