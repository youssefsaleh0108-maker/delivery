import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/cart.dart';
import 'package:mobile_app/src/customer_shell.dart';
import 'package:mobile_app/src/delivery_address.dart';
import 'package:mobile_app/src/delivery_area_map_screen.dart';
import 'package:mobile_app/src/home_item_search_section.dart';
import 'package:mobile_app/src/item_search_screen.dart';
import 'package:mobile_app/src/product_detail_screen.dart' show AddButton, ProductDetailScreen;
import 'package:mobile_app/src/store_page_screen.dart';

import 'widget_test.dart' show sessionWith;

/// "Who near me sells Pepsi?", as the customer meets it: the items section under Home's search box,
/// and the full results screen behind its "See all items".
///
/// Everything runs against a fake gateway that answers `POST /api/products/search/items` with the
/// page `ItemSearchController` writes, so these are tests of what the app does with an answer: when
/// it asks, what it draws, and where each tap goes. What the server finds is product-service's
/// `ItemSearchServiceTest` and `ItemSearchDatabaseTest`.
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

  // ------------------------------------------------------------------------------ the gateway

  Map<String, dynamic> page(List<Map<String, dynamic>> content) => <String, dynamic>{
        'content': content,
        'page': 0,
        'totalElements': content.length,
        'totalPages': 1,
      };

  Map<String, dynamic> card(String id, String name, {String availability = 'OPEN'}) =>
      <String, dynamic>{
        'id': id,
        'slug': id,
        'name': name,
        'vertical': 'GROCERY',
        'availability': availability,
        'deliveryFee': 1.5,
        'minOrder': 0,
        'etaMinMinutes': 20,
        'etaMaxMinutes': 30,
      };

  Map<String, dynamic> product(String id, String shopId, String name, {double price = 1.25}) =>
      <String, dynamic>{
        'id': id,
        'merchantId': 'merchant-$shopId',
        'storeId': shopId,
        'name': name,
        'price': price,
        'status': 'ACTIVE',
        'inStock': true,
      };

  /// One shop of the answer, as `ShopItemsResponse` writes it.
  Map<String, dynamic> shopOf(String id, String name, List<Map<String, dynamic>> items,
          {int? matched, int? metres = 350, String availability = 'OPEN'}) =>
      <String, dynamic>{
        'store': card(id, name, availability: availability),
        'latitude': 33.9008,
        'longitude': 35.4829,
        'distanceMetres': metres,
        'items': items,
        'matchedInStore': matched ?? items.length,
      };

  /// A page of the answer, as `ItemSearchPageResponse` writes it.
  Map<String, dynamic> answerOf(List<Map<String, dynamic>> shops,
          {bool nearby = true, bool truncated = false, int? total}) =>
      <String, dynamic>{
        'content': shops,
        'page': 0,
        'size': 10,
        'totalElements': total ?? shops.length,
        'totalPages': 1,
        'truncated': truncated,
        'candidateLimit': 300,
        'nearby': nearby,
      };

  /// Corner Grocer, near the pin, with Pepsi and a Pepsi with options.
  Map<String, dynamic> cornerGrocer({int? matched}) => shopOf('shop-1', 'Corner Grocer', <Map<String, dynamic>>[
        product('p1', 'shop-1', 'Pepsi 1L'),
        product('p2', 'shop-1', 'Pepsi party pack', price: 6.0),
        product('p3', 'shop-1', 'Diet Pepsi Can', price: 0.9),
      ], matched: matched);

  /// Where Corner Grocer delivers, as its full store read says: 3 km around a pin on the results'
  /// pinned address, and to Hamra, the area of the address the shell finds saved on the phone.
  final Map<String, dynamic> deliveryArea = <String, dynamic>{
    'latitude': 33.8977,
    'longitude': 35.4829,
    'deliveryRadiusMetres': 3000,
    'deliveryZones': <dynamic>[
      <String, dynamic>{'id': 'z-hamra', 'name': 'Hamra', 'sortOrder': 10, 'active': true},
    ],
  };

  /// Every item search the app asked, by its body.
  final List<Map<String, dynamic>> searches = <Map<String, dynamic>>[];

  /// Every GET the app sent, for the shop page's searched shelf.
  final List<RequestOptions> reads = <RequestOptions>[];

  /// A fake gateway: [search] answers the item search from the request body, or null to fail it with
  /// a 500; with a [searchStatus] other than 200 its answer is the error body of that status, as
  /// `ApiExceptionHandler` writes a refusal. [options] gives a product's option groups (none by
  /// default); [shop] adds fields to a shop's full store read. The rest of what the shell and a
  /// shop page read on start is answered empty.
  Dio gateway(
    Map<String, dynamic>? Function(Map<String, dynamic> body) search, {
    Map<String, List<Map<String, dynamic>>> options = const <String, List<Map<String, dynamic>>>{},
    int searchStatus = 200,
    Map<String, dynamic> shop = const <String, dynamic>{},
  }) {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) {
        Object? body;
        int status = 200;
        if (o.method == 'POST' && o.path == '/api/products/search/items') {
          final Map<String, dynamic> sent = Map<String, dynamic>.from(o.data as Map<dynamic, dynamic>);
          searches.add(sent);
          body = search(sent);
          if (body == null) {
            status = 500;
          } else if (searchStatus != 200) {
            h.reject(DioException(
              requestOptions: o,
              type: DioExceptionType.badResponse,
              response: Response<dynamic>(requestOptions: o, statusCode: searchStatus, data: body),
            ));
            return;
          }
        } else if (o.method == 'GET') {
          reads.add(o);
          final String path = o.path;
          if (path.startsWith('/api/products/') && path.endsWith('/options')) {
            body = options[path.split('/')[3]] ?? const <dynamic>[];
          } else if (RegExp(r'^/api/stores/shop-\d+$').hasMatch(path)) {
            final String id = path.split('/').last;
            body = <String, dynamic>{
              ...card(id, 'Corner Grocer'),
              'offers': const <dynamic>[],
              ...shop,
            };
          } else if (path.endsWith('/products') || path.endsWith('/offers')) {
            body = page(const <Map<String, dynamic>>[]);
          } else if (path.endsWith('/aisles')) {
            body = const <dynamic>[];
          } else if (path.startsWith('/api/orders') || path == '/api/stores' ||
              path == '/api/stores/favorites' || path == '/api/butler/mine') {
            body = page(const <Map<String, dynamic>>[]);
          } else if (path == '/api/banners' || path == '/api/categories/chips') {
            body = const <dynamic>[];
          } else if (path == '/api/notifications/unread-count') {
            body = const <String, dynamic>{'unread': 0};
          }
        }
        if (body == null) {
          h.reject(DioException(
            requestOptions: o,
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(requestOptions: o, statusCode: status == 200 ? 404 : status),
          ));
          return;
        }
        h.resolve(Response<dynamic>(requestOptions: o, statusCode: 200, data: body));
      },
    ));
    return dio;
  }

  setUp(() {
    searches.clear();
    reads.clear();
  });

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

  void viewOf(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  // ------------------------------------------------------------------------------ Home

  group("Home's items section", () {
    Future<void> pumpShell(WidgetTester tester, Dio dio, {ConnectivityService? connectivity}) async {
      viewOf(tester, const Size(1000, 2400));
      await tester.pumpWidget(app(CustomerShell(
        storeApi: StoreApi(dio),
        orderApi: OrderApi(dio),
        notificationApi: NotificationApi(dio),
        butlerApi: ButlerApi(dio),
        zoneApi: DeliveryZoneApi(dio),
        offerApi: OfferApi(dio),
        connectivity: connectivity,
        session: sessionWith(<DeliveryRole>{DeliveryRole.customer}),
        locale: LocaleController(read: () async => 'en', write: (String _) async {}),
        onSignOut: () async {},
      )));
      await tester.pumpAndSettle();
    }

    /// Types into Home's search box and waits out its debounce.
    Future<void> type(WidgetTester tester, String words) async {
      await tester.enterText(
          find.descendant(of: find.byType(YdSearchField), matching: find.byType(TextField)).first,
          words);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    testWidgets('invites item searches, and appears at two characters, not one',
        (WidgetTester tester) async {
      await pumpShell(tester, gateway((_) => answerOf(<Map<String, dynamic>>[cornerGrocer()],
          nearby: false)));
      expect(find.text(en.isrchSearchHint), findsOneWidget);

      await type(tester, 'p');
      expect(searches, isEmpty);
      expect(find.text(en.isrchAnywhereTitle), findsNothing);

      await type(tester, 'pe');
      expect(searches.single, <String, dynamic>{'q': 'pe', 'page': 0, 'size': 3});
      expect(find.text(en.isrchAnywhereTitle), findsOneWidget);
      expect(find.text('Corner Grocer'), findsOneWidget);
      // Two items of the shop on Home; the third is behind "See all items".
      expect(find.text('Pepsi 1L'), findsOneWidget);
      expect(find.text('Pepsi party pack'), findsOneWidget);
      expect(find.text('Diet Pepsi Can'), findsNothing);
      expect(find.text(en.isrchSeeAll), findsOneWidget);
    });

    testWidgets('"See all items" is not drawn when Home already shows everything',
        (WidgetTester tester) async {
      await pumpShell(tester, gateway((Map<String, dynamic> body) => body['size'] == 3
          ? answerOf(<Map<String, dynamic>>[
              shopOf('shop-1', 'Corner Grocer', <Map<String, dynamic>>[product('p1', 'shop-1', 'Pepsi 1L')]),
            ], nearby: false)
          : answerOf(<Map<String, dynamic>>[cornerGrocer()], nearby: false)));

      await type(tester, 'pepsi');
      expect(find.text('Pepsi 1L'), findsOneWidget);
      expect(find.text(en.isrchSeeAll), findsNothing);
    });

    testWidgets('"See all items" opens every shop that sells it', (WidgetTester tester) async {
      await pumpShell(tester, gateway((Map<String, dynamic> body) => answerOf(
          <Map<String, dynamic>>[
            shopOf('shop-1', 'Corner Grocer', <Map<String, dynamic>>[product('p1', 'shop-1', 'Pepsi 1L')]),
          ],
          nearby: false,
          total: 4)));
      await type(tester, 'pepsi');
      await tester.tap(find.text(en.isrchSeeAll));
      await tester.pumpAndSettle();

      expect(find.byType(ItemSearchScreen), findsOneWidget);
      expect(searches.last, <String, dynamic>{'q': 'pepsi', 'page': 0, 'size': 10});
    });

    /// The address the shell finds saved on the phone, as the last session left it: in Hamra, with
    /// no pin.
    void savedInHamra() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(storageChannel, (MethodCall call) async {
        final Map<Object?, Object?> args =
            (call.arguments as Map<Object?, Object?>?) ?? const <Object?, Object?>{};
        if (call.method == 'read' && args['key'] == 'delivery.addresses.user-1') {
          const DeliveryAddress home = DeliveryAddress(line: '12 Rose Street', zoneId: 'z-hamra');
          return jsonEncode(<String, dynamic>{
            'selected': home.toJson(),
            'recents': <Object>[home.toJson()],
          });
        }
        return null;
      });
    }

    testWidgets("a shop opened from the section knows the shell's address: inside its area",
        (WidgetTester tester) async {
      savedInHamra();
      await pumpShell(
          tester,
          gateway((_) => answerOf(<Map<String, dynamic>>[cornerGrocer()], nearby: false),
              shop: deliveryArea));
      await type(tester, 'pepsi');

      await tester.tap(find.text('Corner Grocer'));
      await tester.pumpAndSettle();
      expect(find.byType(StorePageScreen), findsOneWidget);

      await tester.tap(find.text(en.dareaButton));
      await tester.pumpAndSettle();
      expect(find.byType(DeliveryAreaMapScreen), findsOneWidget);
      expect(find.text(en.dareaInside), findsOneWidget);
    });

    testWidgets('so does a shop opened from "See all items"', (WidgetTester tester) async {
      savedInHamra();
      await pumpShell(
          tester,
          gateway((_) => answerOf(<Map<String, dynamic>>[cornerGrocer()], nearby: false),
              shop: deliveryArea));
      await type(tester, 'pepsi');
      await tester.tap(find.text(en.isrchSeeAll));
      await tester.pumpAndSettle();
      expect(find.byType(ItemSearchScreen), findsOneWidget);

      await tester.tap(find.text('Corner Grocer'));
      await tester.pumpAndSettle();
      expect(find.byType(StorePageScreen), findsOneWidget);

      await tester.tap(find.text(en.dareaButton));
      await tester.pumpAndSettle();
      expect(find.byType(DeliveryAreaMapScreen), findsOneWidget);
      expect(find.text(en.dareaInside), findsOneWidget);
    });

    testWidgets('is not drawn while offline, and searches once the connection is back',
        (WidgetTester tester) async {
      final ConnectivityService connectivity = ConnectivityService();
      addTearDown(connectivity.dispose);
      await pumpShell(tester, gateway((_) => answerOf(<Map<String, dynamic>>[cornerGrocer()],
          nearby: false)), connectivity: connectivity);

      connectivity.reportUnreachable();
      await tester.pumpAndSettle();
      await type(tester, 'pepsi');
      expect(searches, isEmpty);
      expect(find.text(en.isrchAnywhereTitle), findsNothing);

      connectivity.reportReachable();
      await tester.pumpAndSettle();
      expect(searches, hasLength(1));
      expect(find.text(en.isrchAnywhereTitle), findsOneWidget);
    });

    testWidgets('nothing open has it: says so, and says how far the server looked when it stopped',
        (WidgetTester tester) async {
      await pumpShell(tester,
          gateway((_) => answerOf(const <Map<String, dynamic>>[], nearby: false, truncated: true)));

      await type(tester, 'pepsi');

      expect(find.text(en.isrchEmptyAnywhere('pepsi')), findsOneWidget);
      expect(find.text(en.isrchEmptyTruncated(300)), findsOneWidget);
      expect(find.text(en.isrchSeeAll), findsNothing);
    });

    testWidgets('nothing open has it, and the server looked at everything: no note',
        (WidgetTester tester) async {
      await pumpShell(tester, gateway((_) => answerOf(const <Map<String, dynamic>>[], nearby: false)));

      await type(tester, 'pepsi');

      expect(find.text(en.isrchEmptyAnywhere('pepsi')), findsOneWidget);
      expect(find.text(en.isrchEmptyTruncated(300)), findsNothing);
    });

    testWidgets('a failed search draws nothing, and the shop grid carries on',
        (WidgetTester tester) async {
      await pumpShell(tester, gateway((_) => null));

      await type(tester, 'pepsi');

      expect(searches, hasLength(1));
      expect(find.text(en.isrchAnywhereTitle), findsNothing);
      expect(find.bySemanticsLabel(en.isrchSearching), findsNothing);
      expect(find.text(en.custActiveStoresNearby), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------------ the results

  group('every shop that sells it', () {
    late Cart cart;
    late DeliveryAddressStore addresses;
    late int basketOpened;

    Future<void> pumpResults(
      WidgetTester tester,
      Dio dio, {
      bool pinned = true,
      Locale locale = const Locale('en'),
      Size size = const Size(420, 1600),
    }) async {
      viewOf(tester, size);
      cart = Cart();
      basketOpened = 0;
      addresses = DeliveryAddressStore(ownerId: 'customer-1');
      if (pinned) {
        await addresses.select(
            const DeliveryAddress(line: 'Hamra Street', latitude: 33.8977, longitude: 35.4829));
      } else {
        await addresses.select(const DeliveryAddress(line: 'Hamra Street'));
      }
      await tester.pumpWidget(app(
        ItemSearchScreen(
          storeApi: StoreApi(dio),
          cart: cart,
          addresses: addresses,
          query: const ItemSearchQuery.text('pepsi'),
          onOpenBasket: () => basketOpened++,
        ),
        locale: locale,
      ));
      await tester.pumpAndSettle();
    }

    Finder addFor(String name) => find.descendant(
        of: find.ancestor(of: find.text(name), matching: find.byType(InkWell)).first,
        matching: find.byType(AddButton));

    testWidgets('around the pin: the pin in the body, each shop with its distance',
        (WidgetTester tester) async {
      await pumpResults(tester, gateway((_) => answerOf(<Map<String, dynamic>>[cornerGrocer()])));

      expect(searches.single, <String, dynamic>{
        'q': 'pepsi',
        'latitude': 33.8977,
        'longitude': 35.4829,
        'page': 0,
        'size': 10,
      });
      expect(find.text(en.isrchNearTitle), findsOneWidget);
      expect(find.text(en.dekkaneDistanceMetres(350)), findsOneWidget);
      expect(find.text(en.isrchNotByDistance), findsNothing);
      // The server's price for each item, and three items a shop.
      expect(find.text(r'$1.25'), findsOneWidget);
      expect(find.text('Diet Pepsi Can'), findsOneWidget);
    });

    testWidgets('with no pin: no distance, and one line says the list is not by distance',
        (WidgetTester tester) async {
      await pumpResults(
          tester,
          gateway((_) => answerOf(<Map<String, dynamic>>[
                shopOf('shop-1', 'Corner Grocer', <Map<String, dynamic>>[product('p1', 'shop-1', 'Pepsi 1L')],
                    metres: null),
              ], nearby: false)),
          pinned: false);

      expect(searches.single.keys, isNot(contains('latitude')));
      expect(find.text(en.isrchAnywhereTitle), findsOneWidget);
      expect(find.text(en.isrchNotByDistance), findsOneWidget);
      expect(find.textContaining('m away'), findsNothing);
      expect(find.textContaining('km away'), findsNothing);
    });

    testWidgets('Add puts the product in the basket, filed under the shop it was found in',
        (WidgetTester tester) async {
      await pumpResults(tester, gateway((_) => answerOf(<Map<String, dynamic>>[cornerGrocer()])));

      await tester.tap(addFor('Pepsi 1L'));
      await tester.pumpAndSettle();

      expect(cart.itemCount, 1);
      expect(cart.qtyOf('p1'), 1);
      expect(cart.storeIds, <String>['shop-1']);
      expect(cart.storeFor('shop-1')?.name, 'Corner Grocer');
      // The basket bar arrives with the first item, and leads to the basket.
      await tester.tap(find.text(en.viewBasket));
      expect(basketOpened, 1);
    });

    testWidgets('a product with options opens its detail screen rather than going in as it is',
        (WidgetTester tester) async {
      await pumpResults(
        tester,
        gateway((_) => answerOf(<Map<String, dynamic>>[cornerGrocer()]), options: <String, List<Map<String, dynamic>>>{
          'p2': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'size',
              'name': 'Size',
              'required': true,
              'minSelect': 1,
              'maxSelect': 1,
              'options': <Map<String, dynamic>>[
                <String, dynamic>{'id': 'six', 'name': 'Six cans', 'priceDelta': 0, 'isDefault': true},
                <String, dynamic>{'id': 'twelve', 'name': 'Twelve cans', 'priceDelta': 5},
              ],
            },
          ],
        }),
      );

      await tester.tap(addFor('Pepsi party pack'));
      await tester.pumpAndSettle();

      expect(find.byType(ProductDetailScreen), findsOneWidget);
      expect(cart.isEmpty, isTrue);
    });

    testWidgets('a fourth shop is refused with the shop-limit dialog, and the basket is kept',
        (WidgetTester tester) async {
      await pumpResults(tester, gateway((_) => answerOf(<Map<String, dynamic>>[cornerGrocer()])));
      for (final String id in <String>['a', 'b', 'c']) {
        cart.add(
          Product(id: 'x$id', merchantId: 'm$id', storeId: 'other-$id', name: 'Bread $id', price: 1,
              status: ProductStatus.active),
          from: StoreCard(id: 'other-$id', slug: id, name: 'Shop $id', vertical: StoreVertical.grocery,
              availability: StoreAvailability.open),
        );
      }
      await tester.pumpAndSettle();

      await tester.tap(addFor('Pepsi 1L'));
      await tester.pumpAndSettle();

      expect(find.text(en.multiCartShopLimitTitle(Cart.maxShops)), findsOneWidget);
      expect(cart.storeCount, 3);
      expect(cart.qtyOf('p1'), 0);
    });

    testWidgets('"N more in this shop" opens the shop searched for the same words',
        (WidgetTester tester) async {
      await pumpResults(tester, gateway((_) => answerOf(<Map<String, dynamic>>[cornerGrocer(matched: 5)])));

      await tester.tap(find.text(en.isrchMoreInStore(2)));
      await tester.pumpAndSettle();

      expect(find.byType(StorePageScreen), findsOneWidget);
      final RequestOptions shelf =
          reads.lastWhere((RequestOptions o) => o.path == '/api/stores/shop-1/products');
      expect(shelf.queryParameters['search'], 'pepsi');
    });

    // The customer's address book goes with every shop opened from here, so the shop's "Delivery
    // area" map can say whether the chosen address is inside it.
    for (final (String way, String tapOn, int matched) in <(String, String, int)>[
      ('the shop line', 'Corner Grocer', 3),
      ('"N more in this shop"', en.isrchMoreInStore(2), 5),
    ]) {
      testWidgets('a shop opened by $way says the address is inside its delivery area',
          (WidgetTester tester) async {
        await pumpResults(
            tester,
            gateway((_) => answerOf(<Map<String, dynamic>>[cornerGrocer(matched: matched)]),
                shop: deliveryArea));

        await tester.tap(find.text(tapOn));
        await tester.pumpAndSettle();
        expect(tester.widget<StorePageScreen>(find.byType(StorePageScreen)).addresses,
            same(addresses));

        await tester.tap(find.text(en.dareaButton));
        await tester.pumpAndSettle();
        expect(find.byType(DeliveryAreaMapScreen), findsOneWidget);
        // The results' pinned address sits on the shop's pin, well inside its 3 km.
        expect(find.text(en.dareaInside), findsOneWidget);
      });
    }

    testWidgets('no "more in this shop" when the card shows everything the shop matched',
        (WidgetTester tester) async {
      await pumpResults(tester, gateway((_) => answerOf(<Map<String, dynamic>>[cornerGrocer()])));

      expect(find.textContaining('more in this shop'), findsNothing);
    });

    testWidgets('nothing found says so, and says when only the best matches were checked',
        (WidgetTester tester) async {
      await pumpResults(tester,
          gateway((_) => answerOf(const <Map<String, dynamic>>[], truncated: true)));

      expect(find.text(en.isrchEmptyNear('pepsi')), findsOneWidget);
      expect(find.text(en.isrchEmptyTruncated(300)), findsOneWidget);
    });

    testWidgets('a search that fails offers to try again', (WidgetTester tester) async {
      await pumpResults(tester, gateway((_) => null));

      expect(find.text(en.isrchCouldNotSearch), findsOneWidget);
      expect(find.text(en.tryAgain), findsOneWidget);
    });

    testWidgets('words the server will not search say what to change, with nothing to retry',
        (WidgetTester tester) async {
      await pumpResults(
          tester,
          gateway((_) => <String, dynamic>{'status': 400, 'code': 'SEARCH_TOO_SHORT'},
              searchStatus: 400));

      expect(find.text(en.isrchTypeMore), findsOneWidget);
      expect(find.text(en.isrchCouldNotSearch), findsNothing);
      expect(find.text(en.tryAgain), findsNothing);

      // A new screen, not the old one's state asked again.
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpResults(
          tester,
          gateway((_) => <String, dynamic>{'status': 400, 'code': 'SEARCH_TOO_MANY_WORDS'},
              searchStatus: 400));

      expect(find.text(en.isrchUseFewerWords), findsOneWidget);
      expect(find.text(en.tryAgain), findsNothing);
    });

    testWidgets('a server too busy to search now offers to try again', (WidgetTester tester) async {
      for (final (int status, String code) in <(int, String)>[
        (429, 'SEARCH_RATE_LIMITED'),
        (503, 'SEARCH_TIMED_OUT'),
      ]) {
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpResults(
            tester,
            gateway((_) => <String, dynamic>{'status': status, 'code': code, 'retryAfterSeconds': 5},
                searchStatus: status));

        expect(find.text(en.isrchCouldNotSearch), findsOneWidget, reason: code);
        expect(find.text(en.tryAgain), findsOneWidget, reason: code);
      }
    });

    testWidgets('fits a 320dp phone, busy shop and long names included', (WidgetTester tester) async {
      await pumpResults(
        tester,
        gateway((_) => answerOf(<Map<String, dynamic>>[
              shopOf('shop-1', 'Abu Hassan Mini Market and Roastery, Hamra Branch', <Map<String, dynamic>>[
                product('p1', 'shop-1', 'Pepsi Cola Original Taste Family Size Bottle 2.25L', price: 12.5),
                product('p2', 'shop-1', 'Pepsi 1L'),
                product('p3', 'shop-1', 'Diet Pepsi Can'),
              ], matched: 12, metres: 4800, availability: 'CLOSING_SOON'),
            ])),
        size: const Size(320, 700),
      );
      await tester.tap(addFor('Pepsi 1L'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(en.statusClosingSoon), findsOneWidget);
      expect(find.text(en.isrchMoreInStore(9)), findsOneWidget);
    });

    testWidgets('reads right to left in Arabic, at 320dp', (WidgetTester tester) async {
      await pumpResults(
        tester,
        gateway((_) => answerOf(<Map<String, dynamic>>[
              shopOf('shop-1', 'دكانة أبو حسن', <Map<String, dynamic>>[
                product('p1', 'shop-1', 'بيبسي ١ لتر'),
                product('p2', 'shop-1', 'بيبسي دايت'),
                product('p3', 'shop-1', 'بيبسي ماكس'),
              ], matched: 5, availability: 'BUSY'),
            ])),
        locale: const Locale('ar'),
        size: const Size(320, 700),
      );

      expect(tester.takeException(), isNull);
      expect(Directionality.of(tester.element(find.text(ar.isrchNearTitle))), TextDirection.rtl);
      expect(find.text(ar.isrchMoreInStore(2)), findsOneWidget);
      expect(find.text(ar.statusBusy), findsOneWidget);
      expect(find.text(ar.dekkaneDistanceMetres(350)), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------------ the words

  test('an empty answer says no open shop has it right now, never that no shop sells it', () {
    expect(en.isrchEmptyNear('pepsi'), 'No open shop near you has “pepsi” right now');
    expect(en.isrchEmptyAnywhere('pepsi'), 'No open shop has “pepsi” right now');
    expect(ar.isrchEmptyNear('بيبسي'), 'لا يتوفر «بيبسي» الآن في أي متجر مفتوح قريب منك');
    expect(ar.isrchEmptyAnywhere('بيبسي'), 'لا يتوفر «بيبسي» الآن في أي متجر مفتوح');
    expect(ar.isrchUseFewerWords, isNot(en.isrchUseFewerWords));
  });

  // ------------------------------------------------------------------------------ the section alone

  group('the items section on a narrow phone', () {
    Future<void> pumpSection(WidgetTester tester, {Locale locale = const Locale('en')}) async {
      viewOf(tester, const Size(320, 900));
      final DeliveryAddressStore addresses = DeliveryAddressStore(ownerId: 'customer-1');
      await addresses.select(
          const DeliveryAddress(line: 'Hamra Street', latitude: 33.8977, longitude: 35.4829));
      await tester.pumpWidget(app(
        Scaffold(
          body: ListView(children: <Widget>[
            HomeItemSearchSection(
              query: 'pepsi',
              storeApi: StoreApi(gateway((_) => answerOf(<Map<String, dynamic>>[
                    shopOf('shop-1', 'Abu Hassan Mini Market and Roastery', <Map<String, dynamic>>[
                      product('p1', 'shop-1', 'Pepsi Cola Original Taste Family Size 2.25L'),
                      product('p2', 'shop-1', 'بيبسي ١ لتر'),
                    ], matched: 3, availability: 'BUSY'),
                    cornerGrocer(),
                  ]))),
              cart: Cart(),
              addresses: addresses,
              onOpenBasket: () {},
              onOpenShop: (StoreCard _) {},
            ),
          ]),
        ),
        locale: locale,
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('fits 320dp', (WidgetTester tester) async {
      await pumpSection(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(en.isrchNearTitle), findsOneWidget);
      expect(find.text(en.isrchSeeAll), findsOneWidget);
    });

    testWidgets('fits 320dp in Arabic, right to left', (WidgetTester tester) async {
      await pumpSection(tester, locale: const Locale('ar'));

      expect(tester.takeException(), isNull);
      expect(Directionality.of(tester.element(find.text(ar.isrchNearTitle))), TextDirection.rtl);
      expect(find.text(ar.isrchSeeAll), findsOneWidget);
      expect(find.text(ar.statusBusy), findsOneWidget);
    });
  });
}
