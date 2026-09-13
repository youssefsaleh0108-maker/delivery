import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/cart.dart';
import 'package:mobile_app/src/checkout_screen.dart';
import 'package:mobile_app/src/delivery_address.dart';

import 'widget_test.dart' show product, storeCard;

/// A checkout whose answer was lost is retried as the SAME attempt, never as a new one.
///
/// The failure this pins is invisible on the phone and very visible in the kitchen: a customer on a
/// bad connection taps Place, the request times out after the server has already placed the order,
/// they tap Place again — and a second order is cooked, redeemed and held. Order Manager recognises
/// a repeat by its Idempotency-Key, so everything here is about which key the app sends when.
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

  Map<String, dynamic> orderJson(String id) => <String, dynamic>{
        'id': id,
        'customerId': 'user-1',
        'merchantId': 'm1',
        'riderId': null,
        'status': 'PLACED',
        'totalAmount': 9.75,
        'deliveryAddress': '12 Rose Street',
        'paymentMethod': 'CASH',
        'paymentStatus': 'DUE',
        'items': <dynamic>[],
        'availableActions': <dynamic>[],
      };

  /// A server that answers each POST /api/orders with the next of [placements], and a GET with
  /// [gets] (or a 404). Records every placement request.
  ({Dio dio, List<RequestOptions> placed}) server(
    List<void Function(RequestOptions o, RequestInterceptorHandler h)> placements, {
    Map<String, Object> gets = const <String, Object>{},
  }) {
    final List<RequestOptions> placed = <RequestOptions>[];
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) {
        if (o.method == 'POST' && o.path == '/api/orders') {
          placements[placed.length](o, h);
          placed.add(o);
          return;
        }
        final Object? body = o.method == 'GET' ? gets[o.path] : null;
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
    return (dio: dio, placed: placed);
  }

  void created(RequestOptions o, RequestInterceptorHandler h) => h.resolve(
      Response<dynamic>(requestOptions: o, statusCode: 201, data: orderJson('order-1')));

  /// The request left and no answer came back: the order may or may not exist.
  void unanswered(RequestOptions o, RequestInterceptorHandler h) =>
      h.reject(DioException(requestOptions: o, type: DioExceptionType.receiveTimeout));

  Future<DeliveryAddressStore> home() async {
    final DeliveryAddressStore store = DeliveryAddressStore(ownerId: 'test-user');
    await store.select(const DeliveryAddress(
        line: '12 Rose Street', label: 'Home', zoneId: 'zone-home', zoneName: 'Riverside'));
    return store;
  }

  /// Checkout, pushed over a launcher so what it pops with can be read.
  Future<({Object? Function() result, bool Function() returned})> openCheckout(
    WidgetTester tester, {
    required Dio dio,
    required Cart cart,
    required DeliveryAddressStore addresses,
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Object? result;
    bool returned = false;
    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocaleController.supported,
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<Object>(MaterialPageRoute<Object>(
                  builder: (_) =>
                      CheckoutScreen(api: OrderApi(dio), cart: cart, addresses: addresses),
                ));
                returned = true;
              },
              child: const Text('Check out'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Check out'));
    await tester.pumpAndSettle();
    return (result: () => result, returned: () => returned);
  }

  Future<void> tapPlace(WidgetTester tester) async {
    await tester.tap(find.byType(YdPillButton));
    await tester.pumpAndSettle();
  }

  testWidgets('a try whose answer was lost is retried with the same key and the same request',
      (WidgetTester tester) async {
    final Cart cart = Cart()..add(product('a', 's1', 9.75), from: storeCard('s1'));
    final s = server(<void Function(RequestOptions, RequestInterceptorHandler)>[
      unanswered,
      created,
    ]);
    final checkout = await openCheckout(tester, dio: s.dio, cart: cart, addresses: await home());

    await tapPlace(tester);
    // Nothing is known yet, so nothing is cleared: the basket is still there to try again with —
    // and the customer is not told it failed, because it may not have.
    expect(find.text(en.offlineUnconfirmedRetry), findsOneWidget);
    expect(find.text(en.couldNotPlaceOrder), findsNothing);
    expect(cart.isNotEmpty, isTrue);
    expect(cart.checkoutUnconfirmed, isTrue);
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
    await tester.pumpAndSettle();

    await tapPlace(tester);

    expect(s.placed, hasLength(2));
    final Object? firstKey = s.placed[0].headers[OrderApi.idempotencyKeyHeader];
    expect(firstKey, isA<String>().having((String k) => k.length, 'length', 36));
    // The second tap is the same attempt: if the first did reach the kitchen, the server answers
    // this one with that order instead of cooking another.
    expect(s.placed[1].headers[OrderApi.idempotencyKeyHeader], firstKey);
    expect(s.placed[1].data, s.placed[0].data);
    expect(checkout.returned(), isTrue);
    expect(checkout.result(), isA<DeliveryOrder>());
    expect(cart.isEmpty, isTrue);
  });

  testWidgets('when an earlier try already went through, that order is the answer',
      (WidgetTester tester) async {
    // The customer's first try timed out after the server placed it, and they added something
    // before trying again. Placing the bigger basket too is the duplicate the key exists to stop;
    // the server refuses it and names the order that exists.
    final Cart cart = Cart()..add(product('a', 's1', 9.75), from: storeCard('s1'));
    final s = server(
      <void Function(RequestOptions, RequestInterceptorHandler)>[
        (RequestOptions o, RequestInterceptorHandler h) => h.reject(DioException(
              requestOptions: o,
              type: DioExceptionType.badResponse,
              response: Response<dynamic>(requestOptions: o, statusCode: 409, data: <String, dynamic>{
                'code': 'IDEMPOTENCY_KEY_REUSED',
                'orderId': 'order-earlier',
              }),
            )),
      ],
      gets: <String, Object>{'/api/orders/order-earlier': orderJson('order-earlier')},
    );
    final checkout = await openCheckout(tester, dio: s.dio, cart: cart, addresses: await home());

    await tapPlace(tester);

    expect(s.placed, hasLength(1));
    expect(checkout.returned(), isTrue);
    expect(checkout.result(),
        isA<DeliveryOrder>().having((DeliveryOrder o) => o.id, 'id', 'order-earlier'));
    expect(find.text(en.offlineAlreadyPlaced), findsOneWidget);
    expect(cart.isEmpty, isTrue);
  });

  group('the basket\'s checkout key', () {
    test('survives edits, because an edited basket is still the same attempt', () {
      final Cart cart = Cart()..add(product('a', 's1', 2), from: storeCard('s1'));
      final String key = cart.checkoutKey;

      cart.add(product('b', 's1', 3), from: storeCard('s1'));
      cart.remove('b');

      expect(cart.checkoutKey, key);
    });

    test('is replaced whenever the basket is emptied, which ends the attempt', () {
      final Cart cart = Cart()..add(product('a', 's1', 2), from: storeCard('s1'));
      final Set<String> keys = <String>{cart.checkoutKey};

      // Placed (or queued): checkout clears the basket.
      cart.clear();
      cart.add(product('a', 's1', 2), from: storeCard('s1'));
      keys.add(cart.checkoutKey);

      // The customer took the last thing out.
      cart.remove('a');
      cart.add(product('a', 's1', 2), from: storeCard('s1'));
      keys.add(cart.checkoutKey);

      // Started again at another shop.
      cart.switchTo(storeCard('s2'));
      keys.add(cart.checkoutKey);

      expect(keys, hasLength(4));
    });

    test('outlives the basket after a send that may have placed an order, until checkout settles '
        'the attempt', () {
      final Cart cart = Cart()..add(product('a', 's1', 2), from: storeCard('s1'));
      final String key = cart.checkoutKey;
      cart.markCheckoutUnconfirmed(key);

      // Emptied and refilled, cleared, even moved to another shop: still the same attempt.
      cart.remove('a');
      cart.add(product('b', 's1', 3), from: storeCard('s1'));
      expect(cart.checkoutKey, key);
      cart.clear();
      cart.switchTo(storeCard('s2'));
      expect(cart.checkoutKey, key);

      // Placed, found already placed, or queued: the outcome is known, and the next basket is new.
      cart.settleCheckout();
      expect(cart.checkoutUnconfirmed, isFalse);
      expect(cart.checkoutKey, isNot(key));
    });
  });

  testWidgets('a basket emptied and refilled after a try whose answer was lost goes under that '
      'try\'s key, so the order that may exist is the answer rather than a second order',
      (WidgetTester tester) async {
    final Cart cart = Cart()..add(product('a', 's1', 9.75), from: storeCard('s1'));
    final s = server(
      <void Function(RequestOptions, RequestInterceptorHandler)>[
        unanswered,
        // The first try had landed; the refilled basket is refused under its key.
        (RequestOptions o, RequestInterceptorHandler h) => h.reject(DioException(
              requestOptions: o,
              type: DioExceptionType.badResponse,
              response: Response<dynamic>(requestOptions: o, statusCode: 409, data: <String, dynamic>{
                'code': 'IDEMPOTENCY_KEY_REUSED',
                'orderId': 'order-earlier',
              }),
            )),
      ],
      gets: <String, Object>{'/api/orders/order-earlier': orderJson('order-earlier')},
    );
    await openCheckout(tester, dio: s.dio, cart: cart, addresses: await home());

    await tapPlace(tester);
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
    await tester.pumpAndSettle();

    // The customer takes everything out, and puts something else in.
    cart.remove('a');
    expect(cart.isEmpty, isTrue);
    cart.add(product('b', 's1', 4.50), from: storeCard('s1'));

    await tapPlace(tester);

    expect(s.placed, hasLength(2));
    expect(s.placed[1].headers[OrderApi.idempotencyKeyHeader],
        s.placed[0].headers[OrderApi.idempotencyKeyHeader]);
    expect(find.text(en.offlineAlreadyPlaced), findsOneWidget);
    // The attempt has its answer now, so the next basket is a new one.
    expect(cart.checkoutUnconfirmed, isFalse);
  });
}
