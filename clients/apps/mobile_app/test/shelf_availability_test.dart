import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/cart.dart';
import 'package:mobile_app/src/product_detail_screen.dart' show AddButton;
import 'package:mobile_app/src/store_page_screen.dart';

/// The shop's own availability switch, as the customer's menu reads it.
///
/// `Product.inStock` has been on the wire since V25 and parsed by the client since, but until the
/// menu batch nothing on the customer's shelf read it: the public web menu at `/s/{slug}` has
/// always struck an unavailable item out and written "out of stock" on it (`ShopPageHtml`), while
/// the app drew the same item with a live Add button. The menu builder (Figma 139:8) turns that
/// switch into something a shop touches daily, so the two menus disagreeing stopped being a corner.
///
/// What is pinned here is only that: the shelf and the item's own screen refuse to offer what the
/// shop has switched off, in both layouts and both languages. The basket and checkout are not
/// touched — an unavailable item simply never reaches them.
void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  Map<String, dynamic> page(List<Map<String, dynamic>> content) => <String, dynamic>{
        'content': content,
        'page': 0,
        'totalElements': content.length,
        'totalPages': 1,
      };

  Map<String, dynamic> item(String id, String name, double price, {required bool inStock}) =>
      <String, dynamic>{
        'id': id,
        'merchantId': 'm1',
        'storeId': 's1',
        'name': name,
        'price': price,
        'categoryId': 'c-bakery',
        'status': 'ACTIVE',
        'inStock': inStock,
      };

  /// One of each, so every assertion below is a contrast rather than an absence: the same shelf,
  /// the same shop, the same open hours, and one switch thrown.
  final List<Map<String, dynamic>> shelf = <Map<String, dynamic>>[
    item('p-croissant', 'Croissant au Beurre', 2.5, inStock: true),
    item('p-knefe', 'Knefe', 5, inStock: false),
  ];

  late Map<String, dynamic> shop;

  setUp(() async {
    shop = <String, dynamic>{
      'id': 's1',
      'slug': 's1',
      'name': 'Boulangerie Antoine',
      'vertical': 'GROCERY',
      // Open, so that a missing Add button can only be the item's own doing and never the shop's.
      'availability': 'OPEN',
      'closesAt': '20:00:00',
      'neighborhood': 'Mar Mikhael',
      'rating': 4.8,
      'ratingCount': 234,
      'tagline': 'Fresh artisan baked goods since 1985',
      'deliveryFee': 0,
      'minOrder': 0,
    };
    await MarketRates.instance.load(_noRates());
  });

  tearDown(() async => MarketRates.instance.load(_noRates()));

  Object? answer(RequestOptions options) => switch (options.path) {
        '/api/stores/s1' => shop,
        '/api/stores/s1/products' => page(shelf),
        '/api/stores/s1/aisles' => const <Map<String, dynamic>>[],
        '/api/stores/s1/offers' => page(const <Map<String, dynamic>>[]),
        '/api/products/p-croissant/options' || '/api/products/p-knefe/options' => const <dynamic>[],
        _ => null,
      };

  Dio fakeServer() {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
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
    Locale locale = const Locale('en'),
    StorePageLayout layout = StorePageLayout.standard,
  }) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final Cart basket = Cart();
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
      ),
    ));
    await tester.pumpAndSettle();
    return basket;
  }

  group('the standard shelf', () {
    testWidgets('says so on the item the shop switched off, and offers no way to add it',
        (WidgetTester tester) async {
      await pumpShop(tester);

      // The whole shelf is still readable: an unavailable item is not hidden, because a menu that
      // silently shortens itself tells the customer less than one that says why.
      expect(find.text('Croissant au Beurre'), findsOneWidget);
      expect(find.text('Knefe'), findsOneWidget);

      expect(find.text(en.soldOut), findsOneWidget);
      // Exactly one Add button on a two-item shelf: the available one's.
      expect(find.byType(AddButton), findsOneWidget);
    });

    testWidgets('leaves the available item alone', (WidgetTester tester) async {
      final Cart basket = await pumpShop(tester);

      await tester.tap(find.byType(AddButton));
      await tester.pumpAndSettle();

      expect(basket.lines.length, 1);
      expect(basket.lines.single.product.id, 'p-croissant');
    });

    testWidgets('says it in Arabic, right to left', (WidgetTester tester) async {
      await pumpShop(tester, locale: const Locale('ar'));

      expect(find.text(ar.soldOut), findsOneWidget);
      expect(ar.soldOut, isNot(en.soldOut));
      expect(
        Directionality.of(tester.element(find.byType(StorePageScreen))),
        TextDirection.rtl,
      );
    });
  });

  group('the dekkane shelf', () {
    testWidgets('draws the label in the tile instead of its add control',
        (WidgetTester tester) async {
      await pumpShop(tester, layout: StorePageLayout.dekkane);

      final Finder gone = find.descendant(
        of: find.widgetWithText(ShelfGridTile, 'Knefe'),
        matching: find.text(en.soldOut),
      );
      expect(gone, findsOneWidget);

      // The tile that can be bought still carries its own add control, so the missing one is the
      // switch and not the layout.
      expect(
        find.descendant(
          of: find.widgetWithText(ShelfGridTile, 'Croissant au Beurre'),
          matching: find.text(en.custAddToBasket),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.widgetWithText(ShelfGridTile, 'Knefe'),
          matching: find.text(en.custAddToBasket),
        ),
        findsNothing,
      );
    });
  });

  group("the item's own screen", () {
    testWidgets('opens for an unavailable item but will not add it',
        (WidgetTester tester) async {
      final Cart basket = await pumpShop(tester);

      // Reading it is the point: the photo, the description and the price are what the customer
      // came for, and an item they cannot buy today is one they may buy tomorrow.
      await tester.tap(find.text('Knefe'));
      await tester.pumpAndSettle();

      final Finder cta = find.descendant(
        of: find.byType(InkWell),
        matching: find.text(en.soldOut),
      );
      expect(cta, findsWidgets);

      await tester.tap(find.text(en.soldOut).last);
      await tester.pumpAndSettle();

      expect(basket.lines, isEmpty);
    });
  });
}

/// A rate server with nothing in it: the LBP line is not what these tests are about, and a shelf
/// without a rate draws one figure per price instead of two.
Dio _noRates() {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
      handler.reject(DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      ));
    },
  ));
  return dio;
}
