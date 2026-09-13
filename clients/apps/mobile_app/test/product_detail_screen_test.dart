import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/product_detail_screen.dart';

/// The product page's add-to-basket bar.
///
/// Its label sat unconstrained in a row that only shrinks to fit, inside the space the quantity
/// stepper leaves. On a 360px phone with the system text a notch larger, "Add to basket" and the
/// line total no longer fitted, and the row overflowed its button instead of shortening the label.
void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  /// Nothing answers: the page's extras (the cross-sell rail) fail quietly, which is all this needs.
  Dio offline() {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) => handler.reject(
          DioException(requestOptions: options, type: DioExceptionType.connectionError)),
    ));
    return dio;
  }

  testWidgets('at a larger text size on a 360px phone the label shortens instead of overflowing',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocaleController.supported,
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.1)),
        child: child!,
      ),
      home: ProductDetailScreen(
        api: StoreApi(offline()),
        product: const Product(
          id: 'p-zaatar',
          merchantId: 'm1',
          name: 'Fresh Zaatar Bread',
          price: 12.5,
          status: ProductStatus.active,
        ),
        groups: const <OptionGroup>[],
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'The button row used to overflow here rather than shorten its label.');
    expect(find.text(en.custAddToBasket), findsOneWidget);
    // The total is the part a customer checks, so it is the part that keeps its room.
    expect(find.text('•  12.50'), findsOneWidget);
  });
}
