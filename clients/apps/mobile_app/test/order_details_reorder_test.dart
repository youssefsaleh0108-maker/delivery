import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/cart.dart';
import 'package:mobile_app/src/order_details_screen.dart';

import 'widget_test.dart' show product, storeCard;

/// Reorder on a past order from a shop the basket has no room for.
///
/// A basket holds items from at most [Cart.maxShops] shops. Reorder from a fourth used to say only
/// the limit's title — "Up to 3 shops per basket" — which tells the customer neither that nothing was
/// added nor what to do. It is now explained as the shop page explains it, with the way to the
/// basket, where room is made.
void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  Map<String, dynamic> page(List<Map<String, dynamic>> content) => <String, dynamic>{
        'content': content,
        'page': 0,
        'totalElements': content.length,
        'totalPages': 1,
      };

  /// Order Manager and the catalog, as far as an order from a fourth shop, s4, needs them.
  Dio server() {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) {
        final Object? body = switch (o.path) {
          '/api/orders/o4' => <String, dynamic>{
              'id': 'o4',
              'customerId': 'user-1',
              'merchantId': 'm4',
              'riderId': null,
              'status': 'DELIVERED',
              'totalAmount': 5,
              'storeId': 's4',
              'storeName': 'Shop s4',
              'deliveryAddress': '12 Rose Street',
              'paymentMethod': 'CASH',
              'paymentStatus': 'PAID',
              'items': <dynamic>[
                <String, dynamic>{
                  'productId': 'p4',
                  'productName': 'Dish of s4',
                  'unitPrice': 5,
                  'qty': 1,
                  'lineTotal': 5,
                },
              ],
              'availableActions': <dynamic>[],
              'placedAt': DateTime.now().toUtc().toIso8601String(),
            },
          '/api/stores/s4' => <String, dynamic>{
              'id': 's4',
              'slug': 's4',
              'name': 'Shop s4',
              'availability': 'OPEN',
              'deliveryFee': 0,
              'minOrder': 0,
            },
          '/api/stores/s4/products' => page(<Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'p4',
                'merchantId': 'm4',
                'storeId': 's4',
                'name': 'Dish of s4',
                'price': 5.0,
                'status': 'ACTIVE',
              },
            ]),
          _ => null,
        };
        if (body == null) {
          h.reject(DioException(
            requestOptions: o,
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(requestOptions: o, statusCode: 404),
          ));
          return;
        }
        h.resolve(Response<dynamic>(requestOptions: o, statusCode: 200, data: body));
      },
    ));
    return dio;
  }

  testWidgets('reordering from a shop past the basket\'s limit says nothing was added, and leads '
      'to the basket', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final Dio dio = server();
    final Cart cart = Cart()
      ..add(product('a', 's1', 1), from: storeCard('s1'))
      ..add(product('b', 's2', 1), from: storeCard('s2'))
      ..add(product('c', 's3', 1), from: storeCard('s3'));
    int basketOpened = 0;

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocaleController.supported,
      home: OrderDetailsScreen(
        orderApi: OrderApi(dio),
        storeApi: StoreApi(dio),
        cart: cart,
        orderId: 'o4',
        onOpenBasket: () => basketOpened++,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(YdPillButton, en.reorder));
    await tester.pumpAndSettle();

    // What the limit is, and what to do about it — not the title alone.
    expect(find.text(en.multiCartShopLimitTitle(Cart.maxShops)), findsOneWidget);
    expect(find.text(en.multiCartShopLimitBody), findsOneWidget);
    expect(cart.storeIds, <String>['s1', 's2', 's3'], reason: 'Nothing was added.');

    await tester.tap(find.widgetWithText(FilledButton, en.viewBasket));
    await tester.pumpAndSettle();

    expect(basketOpened, 1);
    expect(find.text(en.multiCartShopLimitBody), findsNothing);

    // Taken down so the screen's own polling does not outlive the test.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
