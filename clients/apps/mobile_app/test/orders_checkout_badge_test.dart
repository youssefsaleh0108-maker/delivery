import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/cart.dart';
import 'package:mobile_app/src/my_orders_screen.dart';

/// A basket from several shops is placed as one order per shop. On the Orders tab each of those
/// orders says it belongs to one checkout, so three cards appearing at once read as the one purchase
/// the customer made — and an order placed alone says nothing of the kind.
void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  Map<String, dynamic> order(String id, String store, {String? checkoutId, int? size}) =>
      <String, dynamic>{
        'id': id,
        'customerId': 'user-1',
        'merchantId': 'm-$store',
        'riderId': null,
        'status': 'PLACED',
        'totalAmount': 12.5,
        'storeName': store,
        'deliveryAddress': '12 Rose Street',
        'paymentMethod': 'CASH',
        'paymentStatus': 'DUE',
        'items': <dynamic>[],
        'availableActions': <dynamic>[],
        'placedAt': DateTime.now().toUtc().toIso8601String(),
        if (checkoutId != null) 'checkoutId': checkoutId,
        if (size != null) 'checkoutSize': size,
      };

  testWidgets('each order of a multi-shop checkout says so; an order placed alone does not',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) {
        if (o.path == '/api/orders/mine') {
          h.resolve(Response<dynamic>(requestOptions: o, statusCode: 200, data: <String, dynamic>{
            'content': <dynamic>[
              order('o1', 'Abou Joseph Shawarma', checkoutId: 'c1', size: 2),
              order('o2', 'Byblos Pharmacy', checkoutId: 'c1', size: 2),
              order('o3', 'Dekkane Abou Selim'),
            ],
            'page': 0,
            'totalElements': 3,
            'totalPages': 1,
          }));
          return;
        }
        h.reject(DioException(
          requestOptions: o,
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(requestOptions: o, statusCode: 404),
        ));
      },
    ));

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocaleController.supported,
      home: Scaffold(
        body: MyOrdersScreen(
          api: OrderApi(dio),
          storeApi: StoreApi(dio),
          cart: Cart(),
          onOpenBasket: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Dekkane Abou Selim'), findsOneWidget);
    expect(find.text(en.multiCartPartOfOrder(2)), findsNWidgets(2));

    // Taken down so the screen's five-second poll does not outlive the test.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
