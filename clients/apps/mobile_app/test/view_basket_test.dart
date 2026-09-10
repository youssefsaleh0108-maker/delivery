import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/cart_screen.dart';
import 'package:mobile_app/src/checkout_screen.dart';
import 'package:mobile_app/src/customer_nav_bar.dart';
import 'package:mobile_app/src/customer_shell.dart';
import 'package:mobile_app/src/product_detail_screen.dart' show AddButton;
import 'package:mobile_app/src/store_page_screen.dart';

import 'widget_test.dart' show sessionWith;

/// "After adding products to basket, pressing View basket should open it."
///
/// <p>It did not. The shop page's basket bar was wired as `Navigator.pop()`, on the theory that
/// the basket was "back there". The shop page is a route pushed over the customer shell — from the
/// home grid, a banner, a category listing, a past order — so popping it went back to whichever of
/// those the customer had come from. On the commonest road that is Home: the customer filled a
/// basket, pressed View basket, and was shown the shop grid they had started on, with the basket
/// still behind a tab they had not been told to tap.
///
/// <p>Nothing caught it, because the one test that walks a purchase — the device-level order
/// lifecycle — tapped the Basket tab itself straight after the bar, doing on the customer's behalf
/// the exact step the customer did not know to take.
///
/// <p>So these pump the REAL shell rather than the shop page on its own: the defect was never in
/// the bar, it was in where the bar went, and only the shell knows where the basket is. Its
/// constructor did not change with the fix, so this file compiles against the old wiring too —
/// and fails there, at "the basket is showing".
void main() {
  /// Secure storage, answered in-process — the shell loads the address book on start, and a real
  /// platform channel in fake async awaits a reply that never arrives. See checkout_test.dart.
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

  const String shopName = 'Shop s1';
  const String productName = 'Falafel wrap';

  /// No minimum order, so the bar reads View basket and is tappable. Under a minimum it names the
  /// shortfall instead and does nothing — a different path, and not the one being tested.
  const Map<String, dynamic> shop = <String, dynamic>{
    'id': 's1',
    'slug': 's1',
    'name': shopName,
    'availability': 'OPEN',
    'deliveryFee': 0,
    'minOrder': 0,
  };

  const Map<String, dynamic> falafel = <String, dynamic>{
    'id': 'p1',
    'merchantId': 's1',
    'storeId': 's1',
    'name': productName,
    'price': 6.5,
    'status': 'ACTIVE',
  };

  Map<String, dynamic> page(List<Map<String, dynamic>> content) => <String, dynamic>{
        'content': content,
        'page': 0,
        'totalElements': content.length,
        'totalPages': 1,
      };

  /// What the fake server says to a GET, or null for "not found".
  ///
  /// One shop with one product without options, and an empty answer for the rest of what the
  /// shell's five tabs ask on start. Everything else — butler terms, offer previews — is refused,
  /// and every screen that asks already treats a refusal as "nothing to show".
  Object? answer(String path) {
    if (path.startsWith('/api/orders')) return page(const <Map<String, dynamic>>[]);
    return switch (path) {
      '/api/stores' => page(<Map<String, dynamic>>[shop]),
      '/api/stores/favorites' => page(const <Map<String, dynamic>>[]),
      '/api/banners' => const <dynamic>[],
      '/api/categories/chips' => const <dynamic>[],
      '/api/stores/s1' => shop,
      '/api/stores/s1/products' => page(<Map<String, dynamic>>[falafel]),
      '/api/stores/s1/aisles' => const <dynamic>[],
      '/api/stores/s1/offers' => page(const <Map<String, dynamic>>[]),
      '/api/products/p1/options' => const <dynamic>[],
      '/api/notifications/unread-count' => const <String, dynamic>{'unread': 0},
      '/api/butler/mine' => page(const <Map<String, dynamic>>[]),
      _ => null,
    };
  }

  /// An interceptor rather than an adapter, as in checkout_test.dart: it answers before any socket
  /// is opened, so nothing here waits on a connection.
  Dio fakeServer() {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        final Object? body = options.method == 'GET' ? answer(options.path) : null;
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

  /// The customer shell, either as the app's first route or — [pushedOverAnotherRoute] — pushed
  /// over one, the way main.dart's `_exploreAsCustomer` puts it over an applicant's status screen.
  Future<void> pumpShell(WidgetTester tester, {bool pushedOverAnotherRoute = false}) async {
    // Tall enough that the basket's checkout button is laid out without scrolling.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final Dio dio = fakeServer();
    final Widget shell = CustomerShell(
      storeApi: StoreApi(dio),
      orderApi: OrderApi(dio),
      notificationApi: NotificationApi(dio),
      butlerApi: ButlerApi(dio),
      zoneApi: DeliveryZoneApi(dio),
      offerApi: OfferApi(dio),
      session: sessionWith(<DeliveryRole>{DeliveryRole.customer}),
      locale: LocaleController(read: () async => 'en', write: (String _) async {}),
      onSignOut: () async {},
    );

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocaleController.supported,
      home: pushedOverAnotherRoute
          ? Builder(
              builder: (BuildContext context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => shell)),
                    child: const Text('Explore as a customer'),
                  ),
                ),
              ),
            )
          : shell,
    ));
    await tester.pumpAndSettle();

    if (pushedOverAnotherRoute) {
      await tester.tap(find.text('Explore as a customer'));
      await tester.pumpAndSettle();
    }
    expect(find.byType(CustomerShell), findsOneWidget);
  }

  /// Home → the shop → Add, which is the road the customer described.
  Future<void> fillABasketOnTheShopPage(WidgetTester tester) async {
    await tester.tap(find.text(shopName).first);
    await tester.pumpAndSettle();
    expect(find.byType(StorePageScreen), findsOneWidget);

    await tester.tap(find.descendant(
        of: find.byType(StorePageScreen), matching: find.byType(AddButton)));
    await tester.pumpAndSettle();

    expect(find.byType(StickyBasketBar), findsOneWidget);
    expect(find.text(en.viewBasket), findsOneWidget,
        reason: 'The bar must read View basket and be tappable. If it names a shortfall instead, '
            'the fixture shop grew a minimum order.');
  }

  /// The basket is the screen actually SHOWING — not merely built.
  ///
  /// The shell keeps every tab alive in an IndexedStack, so the basket screen is always in the
  /// tree; the default finders skip offstage widgets, and that is exactly the difference between
  /// "the basket is open" and "the basket exists somewhere behind Home".
  void expectOnTheBasket(WidgetTester tester) {
    expect(find.byType(StorePageScreen), findsNothing,
        reason: 'The shop page is still covering the shell.');
    expect(find.byType(CartScreen), findsOneWidget,
        reason: 'View basket did not open the basket. The old wiring popped the shop page and '
            'left the customer on Home, which is what failing here means.');
    expect(
        find.descendant(of: find.byType(CartScreen), matching: find.text(productName)),
        findsOneWidget,
        reason: 'The basket that opened is not the one the shop page filled.');
    expect(tester.widget<CustomerNavBar>(find.byType(CustomerNavBar)).index,
        CustomerNavBar.basketIndex,
        reason: 'The nav bar must agree with the screen it is under.');
  }

  testWidgets('View basket on a shop page opens the basket, and checkout goes on from there',
      (WidgetTester tester) async {
    await pumpShell(tester);
    await fillABasketOnTheShopPage(tester);

    await tester.tap(find.text(en.viewBasket));
    await tester.pumpAndSettle();

    expectOnTheBasket(tester);

    // And the basket that opened is a working one: its checkout button goes to checkout.
    final Finder proceed = find.widgetWithText(YdPillButton, en.custProceedToCheckout);
    expect(proceed, findsOneWidget);
    await tester.tap(proceed);
    await tester.pumpAndSettle();
    expect(find.byType(CheckoutScreen), findsOneWidget);

    // Back from checkout is back to the basket — the one screen underneath it now — rather than to
    // a shop page that was left behind somewhere in the stack.
    await Navigator.of(tester.element(find.byType(CheckoutScreen))).maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(CheckoutScreen), findsNothing);
    expectOnTheBasket(tester);
  });

  testWidgets('and it stops at the shell when the shell is not the first route',
      (WidgetTester tester) async {
    // The applicant's road into the shop. Popping to the FIRST route would have closed the whole
    // shell and dropped them back on the screen underneath it — out of the shop, basket and all.
    await pumpShell(tester, pushedOverAnotherRoute: true);
    await fillABasketOnTheShopPage(tester);

    await tester.tap(find.text(en.viewBasket));
    await tester.pumpAndSettle();

    expect(find.text('Explore as a customer'), findsNothing,
        reason: 'View basket popped past the shell to the route underneath it.');
    expect(find.byType(CustomerShell), findsOneWidget);
    expectOnTheBasket(tester);
  });
}
