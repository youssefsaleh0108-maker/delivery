import 'dart:async';

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

/// What the checkout screen sends, and what it refuses to send.
///
/// These are the two changes that can silently ship wrong: an address picked from the saved list
/// that travels without the area it belongs to, and a payment method the customer never saw. Both
/// are invisible on screen and only visible in the request body, so that is what is asserted.
///
/// The 2026-08 redesign changed the controls under all of it — the address dropdown became a list
/// of radio cards, the payment radios became a two-up strip of cards, and the place button became a
/// [YdPillButton] — so the finders below moved with them. Every assertion about the *request* is
/// unchanged, which is the point: the wire format survived the repaint.
void main() {
  /// Secure storage, answered in-process.
  ///
  /// Not optional. A `testWidgets` body runs inside fake async, and a real platform channel is
  /// replied to on the real event loop — so `select()`, which writes the address book, awaits a
  /// reply that never arrives and the test hangs rather than fails. Answering the channel here
  /// keeps the whole await chain inside the same fake clock.
  const MethodChannel storageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (MethodCall call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
  });

  /// Captures the placement request instead of making one.
  ///
  /// An interceptor rather than a fake adapter: it resolves before any socket is opened, so the
  /// test neither waits on a connection nor depends on how Dio encodes the body on the wire.
  ({Dio dio, List<RequestOptions> sent}) recordingDio() {
    final List<RequestOptions> sent = <RequestOptions>[];
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        // Checkout asks for the server's quote as it opens (POST /api/orders/quote). Not a
        // placement, so not recorded; refused here, so the screen shows what it shows without one —
        // which is what these cases were written against.
        if (options.path == '/api/orders/quote') {
          handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(requestOptions: options, statusCode: 404),
          ));
          return;
        }
        sent.add(options);
        handler.resolve(Response<dynamic>(
          requestOptions: options,
          statusCode: 201,
          data: <String, dynamic>{
            'id': 'order-1',
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
          },
        ));
      },
    ));
    return (dio: dio, sent: sent);
  }

  /// A store with two saved addresses, the second of which is selected.
  ///
  /// [load] is never called, so nothing reads the platform channel. Writing through [select] does
  /// touch it, and the store swallows that failure by design — persistence is a convenience, and a
  /// test that could not select an address would be testing the storage plugin rather than this
  /// screen.
  Future<DeliveryAddressStore> storeWithAddresses() async {
    final DeliveryAddressStore store = DeliveryAddressStore(ownerId: 'test-user');
    await store.select(const DeliveryAddress(
      line: '4 Mill Lane',
      label: 'Work',
      notes: 'Reception desk, ask for me',
      zoneId: 'zone-work',
      zoneName: 'Downtown',
    ));
    await store.select(const DeliveryAddress(
      line: '12 Rose Street',
      label: 'Home',
      zoneId: 'zone-home',
      zoneName: 'Riverside',
    ));
    return store;
  }

  Cart cartWithOneItem() {
    final Cart cart = Cart();
    cart.add(product('a', 's1', 9.75), from: storeCard('s1'));
    return cart;
  }

  Future<void> pumpCheckout(
    WidgetTester tester, {
    required Dio dio,
    required DeliveryAddressStore addresses,
    required Cart cart,
    bool settle = true,
  }) async {
    // Tall enough for the whole form: at the default 800x600 the place-order button falls outside
    // the viewport, where a lazy ListView never builds it and no finder can reach it.
    tester.view.physicalSize = const Size(1000, 2400);
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
      home: CheckoutScreen(api: OrderApi(dio), cart: cart, addresses: addresses),
    ));
    if (settle) await tester.pumpAndSettle();
  }

  /// Whether the card carrying [label] reads as the chosen one.
  ///
  /// Selection is a border colour and a radio dot now rather than a widget type, so it is read off
  /// the semantics the cards publish — which is also what a screen reader is told, and therefore
  /// the version of "chosen" that has to be right.
  bool isSelected(WidgetTester tester, String label) {
    return tester
        .widgetList<Semantics>(find.ancestor(
          of: find.text(label),
          matching: find.byType(Semantics),
        ))
        .any((Semantics s) => s.properties.selected ?? false);
  }

  testWidgets('the address is picked from a list, not typed', (WidgetTester tester) async {
    final DeliveryAddressStore addresses = await storeWithAddresses();
    await pumpCheckout(
        tester, dio: recordingDio().dio, addresses: addresses, cart: cartWithOneItem());

    // No free-text box for the address anywhere on the screen: both saved addresses are offered as
    // cards, and one of them is chosen.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    // The most recently selected one, already chosen — the customer picked it on the home screen
    // and should not have to pick it again.
    expect(isSelected(tester, 'Home'), isTrue);
    expect(isSelected(tester, 'Work'), isFalse);
    // And the area behind it, which is what the fee is priced from.
    expect(find.textContaining('Riverside'), findsOneWidget);
  });

  testWidgets('cash on delivery is offered and already chosen', (WidgetTester tester) async {
    final DeliveryAddressStore addresses = await storeWithAddresses();
    await pumpCheckout(
        tester, dio: recordingDio().dio, addresses: addresses, cart: cartWithOneItem());

    // The Lebanese redesign: the section is the local-methods list, cash names both currencies,
    // and it is chosen — not merely asked about — because it is the one method that moves real
    // money.
    expect(find.text('Local Payment Methods'), findsOneWidget);
    expect(find.text('Cash on Delivery (USD/LBP)'), findsOneWidget);
    expect(isSelected(tester, 'Cash on Delivery (USD/LBP)'), isTrue);
    // The old dev card/wallet strip left with the redesign; wallet transfers (Whish/OMT) appear
    // only when the transfer service says a connector carries them, and this test pumps the
    // screen with no transfer service at all — so no wallet rows, and no test-payment caption.
    expect(find.text('Card'), findsNothing);
    expect(find.text('Wallet'), findsNothing);
    // The Apple Pay placeholder and its coming-soon chip are gone with the wiring.
    expect(find.text('Apple Pay'), findsNothing);
  });

  testWidgets('cash placement carries the split default: the whole total in USD',
      (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> sent}) recorder = recordingDio();
    final DeliveryAddressStore addresses = await storeWithAddresses();
    await pumpCheckout(
        tester, dio: recorder.dio, addresses: addresses, cart: cartWithOneItem());

    await tester.tap(find.byType(YdPillButton));
    await tester.pumpAndSettle();

    final Map<String, dynamic> body = recorder.sent.single.data as Map<String, dynamic>;
    // Cash stays the wire method; the USD/LBP split is the transfer ledger's business, recorded
    // separately (and skipped entirely here, where no transfer service was provided).
    expect(body['paymentMethod'], 'CASH');
    expect(body['paymentInstrumentToken'], isNull);
  });

  testWidgets('placing sends the picked address, its area, and CASH',
      (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> sent}) recorder = recordingDio();
    final DeliveryAddressStore addresses = await storeWithAddresses();
    await pumpCheckout(
        tester, dio: recorder.dio, addresses: addresses, cart: cartWithOneItem());

    // Switch to the other saved address: the zone has to follow the choice, which is the whole
    // reason the free-text box went.
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(YdPillButton));
    await tester.pumpAndSettle();

    expect(recorder.sent, hasLength(1));
    final Map<String, dynamic> body = recorder.sent.single.data as Map<String, dynamic>;
    expect(body['deliveryAddress'], '4 Mill Lane');
    expect(body['deliveryZoneId'], 'zone-work');
    expect(body['paymentMethod'], 'CASH');
  });

  testWidgets('the door notes follow the address, and what is typed still wins',
      (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> sent}) recorder = recordingDio();
    final DeliveryAddressStore addresses = await storeWithAddresses();
    await pumpCheckout(
        tester, dio: recorder.dio, addresses: addresses, cart: cartWithOneItem());

    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();

    // Switching door brings that door's instructions with it, rather than carrying the previous
    // address's over. The redesign shows them on the address card itself, in its detail line.
    expect(find.textContaining('Reception desk, ask for me'), findsWidgets);

    // The order note is its own box now, headed "Order Notes" and hinted rather than labelled.
    await tester.enterText(
      find.ancestor(
        of: find.text('e.g. Leave package at the door, bell is not working...'),
        matching: find.byType(TextFormField),
      ),
      'No onions',
    );
    await tester.tap(find.byType(YdPillButton));
    await tester.pumpAndSettle();

    // Placing re-selects the address to promote it in the recents, which notifies the store — and
    // that notification must not overwrite what the customer just typed.
    final Map<String, dynamic> body = recorder.sent.single.data as Map<String, dynamic>;
    expect(body['notes'], 'No onions');
    // And the saved address keeps its own note rather than inheriting the order's.
    expect(addresses.selected?.notes, 'Reception desk, ask for me');
  });

  testWidgets('with nothing saved there is nothing to place against',
      (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> sent}) recorder = recordingDio();
    await pumpCheckout(
        tester, dio: recorder.dio, addresses: DeliveryAddressStore(ownerId: 'test-user'), cart: cartWithOneItem());

    await tester.tap(find.byType(YdPillButton));
    await tester.pumpAndSettle();

    // No request, and a reason on screen rather than a silent no-op.
    expect(recorder.sent, isEmpty);
    expect(find.text('We need somewhere to deliver to'), findsOneWidget);
  });

  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  Map<String, dynamic> orderJson(String id, String storeId, double total) => <String, dynamic>{
        'id': id,
        'customerId': 'user-1',
        'merchantId': storeId,
        'riderId': null,
        'status': 'PLACED',
        'totalAmount': total,
        'storeId': storeId,
        'deliveryAddress': '12 Rose Street',
        'paymentMethod': 'CASH',
        'paymentStatus': 'DUE',
        'items': <dynamic>[],
        'availableActions': <dynamic>[],
        'checkoutId': 'checkout-1',
        'checkoutSize': 2,
      };

  /// Order Manager answering the quote with [quote] (a 404 when null) and a checkout or placement
  /// with [placement] (every order of a two-shop checkout when null). Records every request that is
  /// not a quote.
  ({Dio dio, List<RequestOptions> sent}) orderManager({
    FutureOr<Map<String, dynamic>?> Function(Map<String, dynamic> question)? quote,
    void Function(RequestOptions o, RequestInterceptorHandler h)? placement,
  }) {
    final List<RequestOptions> sent = <RequestOptions>[];
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) async {
        if (o.path == '/api/orders/quote') {
          final Map<String, dynamic>? answer = await quote?.call(o.data as Map<String, dynamic>);
          if (answer == null) {
            h.reject(DioException(
              requestOptions: o,
              type: DioExceptionType.badResponse,
              response: Response<dynamic>(requestOptions: o, statusCode: 404),
            ));
          } else {
            h.resolve(Response<dynamic>(requestOptions: o, statusCode: 200, data: answer));
          }
          return;
        }
        sent.add(o);
        if (placement != null) {
          placement(o, h);
          return;
        }
        h.resolve(Response<dynamic>(requestOptions: o, statusCode: 201, data: <String, dynamic>{
          'checkoutId': 'checkout-1',
          'orders': <dynamic>[orderJson('order-1', 's1', 9.75), orderJson('order-2', 's2', 4)],
          'totalAmount': 13.75,
        }));
      },
    ));
    return (dio: dio, sent: sent);
  }

  Cart twoShops({StoreCard? second}) => Cart()
    ..add(product('a', 's1', 9.75), from: storeCard('s1'))
    ..add(product('b', 's2', 4.00), from: second ?? storeCard('s2'));

  /// Order Manager's price for [twoShops] as it stands: 9.75 and 4.00 of goods, delivery free, 13.75
  /// in all. [refusal] is the second shop's reason it cannot take its part — under a 5.00 minimum, say
  /// — which leaves the basket priced but not placeable.
  Map<String, dynamic> twoShopQuote({String? refusal}) {
    Map<String, dynamic> line(String id, double subtotal, {String? why}) => <String, dynamic>{
          'storeId': id,
          'storeName': 'Shop $id',
          'refusal': why,
          'subtotal': subtotal,
          'minimumOrder': why == null ? 0 : 5,
          'shortfall': why == null ? 0 : 5 - subtotal,
          'deliveryFee': 0,
          'deliveryFeeCharged': 0,
          'deliveryFeeWaived': false,
          'expressSurcharge': 0,
          'discountAmount': 0,
          'totalAmount': subtotal,
        };
    return <String, dynamic>{
      'shops': <dynamic>[line('s1', 9.75), line('s2', 4.00, why: refusal)],
      'placeable': refusal == null,
      'subtotal': 13.75,
      'deliveryFeeCharged': 0,
      'expressSurcharge': 0,
      'discountAmount': 0,
      'totalAmount': 13.75,
      'maxShops': 3,
    };
  }

  YdPillButton placeButton(WidgetTester tester) =>
      tester.widget<YdPillButton>(find.byType(YdPillButton));

  /// Order Manager refusing a checkout sent at 13.75 because it now comes to [total]: nothing placed.
  void priceChanged(RequestOptions o, RequestInterceptorHandler h, double total) =>
      h.reject(DioException(
        requestOptions: o,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(requestOptions: o, statusCode: 409, data: <String, dynamic>{
          'code': 'PRICE_CHANGED',
          'total': total,
          'expectedTotal': 13.75,
        }),
      ));

  testWidgets('a basket from several shops is sent once, as one checkout of every shop',
      (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> sent}) recorder =
        orderManager(quote: (Map<String, dynamic> _) => twoShopQuote());
    final Cart cart = twoShops();
    await pumpCheckout(tester, dio: recorder.dio, addresses: await storeWithAddresses(), cart: cart);

    // No USD/LBP split card: several orders have no one total to split.
    expect(find.text(en.custSplitPayment), findsNothing);

    await tester.tap(find.byType(YdPillButton));
    await tester.pumpAndSettle();

    expect(recorder.sent.map((RequestOptions o) => o.path), <String>['/api/orders/checkout']);
    final Map<String, dynamic> body = recorder.sent.single.data as Map<String, dynamic>;
    expect(body['items'], hasLength(2));
    // At the total the customer was shown, which Order Manager places at or not at all.
    expect(body['expectedTotal'], 13.75);
    expect(recorder.sent.single.headers[OrderApi.idempotencyKeyHeader], isNotNull);
    // Placed: the attempt is over, and the basket with it.
    expect(cart.isEmpty, isTrue);
  });

  testWidgets('a shop that refuses the checkout is named, and the basket is kept',
      (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> sent}) recorder = orderManager(
      // Quoted while open; closed by the time the checkout arrives.
      quote: (Map<String, dynamic> _) => twoShopQuote(),
      placement: (RequestOptions o, RequestInterceptorHandler h) => h.reject(DioException(
        requestOptions: o,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(requestOptions: o, statusCode: 422, data: <String, dynamic>{
          'code': 'SHOP_REFUSED',
          'refusal': 'CLOSED',
          'storeId': 's2',
          'detail': 'Shop s2 is closed and is not taking orders right now',
        }),
      )),
    );
    final Cart cart = twoShops();
    await pumpCheckout(tester, dio: recorder.dio, addresses: await storeWithAddresses(), cart: cart);

    await tester.tap(find.byType(YdPillButton));
    await tester.pumpAndSettle();

    expect(find.text('Shop s2 is closed and is not taking orders right now'), findsOneWidget);
    expect(cart.storeIds, <String>['s1', 's2']);
  });

  testWidgets('a one-shop basket refused by a service rule shows Order Manager\'s own sentence',
      (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> sent}) recorder = orderManager(
      // A basket holding a service offer, which is ordered from its own screen or not at all.
      placement: (RequestOptions o, RequestInterceptorHandler h) => h.reject(DioException(
        requestOptions: o,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(requestOptions: o, statusCode: 422, data: <String, dynamic>{
          'title': 'Order rule violated',
          'code': 'OFFER_NOT_ORDERABLE',
          'detail': 'Business cards can\'t be ordered right now',
        }),
      )),
    );
    final Cart cart = cartWithOneItem();
    await pumpCheckout(tester, dio: recorder.dio, addresses: await storeWithAddresses(), cart: cart);

    await tester.tap(find.byType(YdPillButton));
    await tester.pumpAndSettle();

    expect(recorder.sent.map((RequestOptions o) => o.path), <String>['/api/orders']);
    expect(find.text('Business cards can\'t be ordered right now'), findsOneWidget);
    expect(find.text(en.couldNotPlaceOrder), findsNothing);
    expect(cart.isEmpty, isFalse);
  });

  testWidgets('every shop\'s delivery circle is checked before anything is sent',
      (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> sent}) recorder =
        orderManager(quote: (Map<String, dynamic> _) => twoShopQuote());
    final DeliveryAddressStore addresses = DeliveryAddressStore(ownerId: 'test-user');
    await addresses.select(const DeliveryAddress(
        line: '12 Rose Street', label: 'Home', latitude: 33.8938, longitude: 35.5018));
    // The second shop is 10 km away and delivers within 2 km.
    final Cart cart = twoShops(
      second: const StoreCard(
        id: 's2',
        slug: 's2',
        name: 'Shop s2',
        vertical: StoreVertical.pharmacy,
        availability: StoreAvailability.open,
        latitude: 33.98,
        longitude: 35.52,
        deliveryRadiusMetres: 2000,
      ),
    );
    await pumpCheckout(tester, dio: recorder.dio, addresses: addresses, cart: cart);

    await tester.tap(find.byType(YdPillButton));
    await tester.pumpAndSettle();

    expect(recorder.sent, isEmpty);
    expect(find.text(en.custOutsideDeliveryArea('Shop s2', '2.0')), findsOneWidget);
  });

  testWidgets('the total on the button is the server\'s quote, Express premium included',
      (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> sent}) recorder = orderManager(
      quote: (Map<String, dynamic> question) {
        final bool express = question['deliveryTier'] == 'EXPRESS';
        return <String, dynamic>{
          'shops': <dynamic>[
            <String, dynamic>{
              'storeId': 's1',
              'storeName': 'Shop s1',
              'subtotal': 9.75,
              'minimumOrder': 0,
              'shortfall': 0,
              'deliveryFee': 1.25,
              'deliveryFeeCharged': 1.25,
              'deliveryFeeWaived': false,
              'expressSurcharge': express ? 2 : 0,
              'discountAmount': 0,
              'totalAmount': express ? 13 : 11,
            },
          ],
          'placeable': true,
          'subtotal': 9.75,
          'deliveryFeeCharged': 1.25,
          'expressSurcharge': express ? 2 : 0,
          'discountAmount': 0,
          'totalAmount': express ? 13 : 11,
          'maxShops': 3,
        };
      },
    );
    await pumpCheckout(
        tester, dio: recorder.dio, addresses: await storeWithAddresses(), cart: cartWithOneItem());
    // The quote is asked once the screen has been still for a moment, and nothing on it animates
    // meanwhile for pumpAndSettle to wait on.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(YdPillButton, en.custPlaceOrderAmount('\$11.00')), findsOneWidget);

    await tester.tap(find.text(en.deliveryTierExpress));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(YdPillButton, en.custPlaceOrderAmount('\$13.00')), findsOneWidget);
    expect(recorder.sent, isEmpty, reason: 'Quoting places nothing.');
  });

  group('a basket from several shops is placed only at a total the server quoted for it', () {
    testWidgets('not while that price is on its way', (WidgetTester tester) async {
      final ({Dio dio, List<RequestOptions> sent}) recorder = orderManager(
          quote: (Map<String, dynamic> _) => Completer<Map<String, dynamic>?>().future);
      await pumpCheckout(tester,
          dio: recorder.dio, addresses: await storeWithAddresses(), cart: twoShops(), settle: false);
      // Well past the quote's debounce; its answer never comes.
      await tester.pump(const Duration(seconds: 1));

      expect(find.text(en.multiCartPricesUpdating), findsOneWidget);
      expect(placeButton(tester).onPressed, isNull);

      await tester.tap(find.byType(YdPillButton), warnIfMissed: false);
      await tester.pump(const Duration(seconds: 1));
      expect(recorder.sent, isEmpty);

      // Taken down so the spinners do not outlive the test.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('not when that price cannot be had — which it asks for again on request',
        (WidgetTester tester) async {
      bool answers = false;
      final ({Dio dio, List<RequestOptions> sent}) recorder = orderManager(
          quote: (Map<String, dynamic> _) => answers ? twoShopQuote() : null);
      await pumpCheckout(
          tester, dio: recorder.dio, addresses: await storeWithAddresses(), cart: twoShops());

      expect(find.text(en.multiCartPricesFailed), findsOneWidget);
      // A plain label, carrying no total the server never gave.
      expect(find.widgetWithText(YdPillButton, en.checkout), findsOneWidget);
      expect(placeButton(tester).onPressed, isNull);
      await tester.tap(find.byType(YdPillButton), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(recorder.sent, isEmpty);

      answers = true;
      await tester.tap(find.text(en.tryAgain));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(YdPillButton, en.custPlaceOrderAmount('\$13.75')), findsOneWidget);
      expect(placeButton(tester).onPressed, isNotNull);
    });

    testWidgets('not while a shop cannot take its part, which is named', (WidgetTester tester) async {
      final ({Dio dio, List<RequestOptions> sent}) recorder = orderManager(
          quote: (Map<String, dynamic> _) => twoShopQuote(refusal: 'BELOW_MINIMUM'));
      await pumpCheckout(
          tester, dio: recorder.dio, addresses: await storeWithAddresses(), cart: twoShops());

      expect(find.text(en.multiCartBelowMinimum('\$1.00', 'Shop s2')), findsOneWidget);
      expect(placeButton(tester).onPressed, isNull);
      await tester.tap(find.byType(YdPillButton), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(recorder.sent, isEmpty);
    });

    testWidgets('a total that moved since is shown, and placed only once the customer confirms it',
        (WidgetTester tester) async {
      final ({Dio dio, List<RequestOptions> sent}) recorder = orderManager(
        quote: (Map<String, dynamic> _) => twoShopQuote(),
        placement: (RequestOptions o, RequestInterceptorHandler h) {
          if ((o.data as Map<String, dynamic>)['expectedTotal'] != 15.25) {
            priceChanged(o, h, 15.25);
            return;
          }
          h.resolve(Response<dynamic>(requestOptions: o, statusCode: 201, data: <String, dynamic>{
            'checkoutId': 'checkout-1',
            'orders': <dynamic>[orderJson('order-1', 's1', 11.25), orderJson('order-2', 's2', 4)],
            'totalAmount': 15.25,
          }));
        },
      );
      final Cart cart = twoShops();
      await pumpCheckout(tester, dio: recorder.dio, addresses: await storeWithAddresses(), cart: cart);

      await tester.tap(find.byType(YdPillButton));
      await tester.pumpAndSettle();

      // Nothing placed yet: the new total beside the one the customer saw, and the question.
      expect(find.text(en.multiCartPriceChangedTitle), findsOneWidget);
      expect(find.text(en.multiCartPriceChangedBody('\$15.25', '\$13.75')), findsOneWidget);
      expect(cart.isEmpty, isFalse);

      await tester.tap(find.widgetWithText(FilledButton, en.custPlaceOrderAmount('\$15.25')));
      await tester.pumpAndSettle();

      expect(
          recorder.sent.map((RequestOptions o) => (o.data as Map<String, dynamic>)['expectedTotal']),
          <Object>[13.75, 15.25]);
      // One attempt throughout, so a lost answer to either send is still answered with its orders.
      expect(
          recorder.sent.map((RequestOptions o) => o.headers[OrderApi.idempotencyKeyHeader]).toSet(),
          hasLength(1));
      expect(cart.isEmpty, isTrue);
    });

    testWidgets('declining the new total places nothing and keeps the basket',
        (WidgetTester tester) async {
      final ({Dio dio, List<RequestOptions> sent}) recorder = orderManager(
        quote: (Map<String, dynamic> _) => twoShopQuote(),
        placement: (RequestOptions o, RequestInterceptorHandler h) => priceChanged(o, h, 15.25),
      );
      final Cart cart = twoShops();
      await pumpCheckout(tester, dio: recorder.dio, addresses: await storeWithAddresses(), cart: cart);

      await tester.tap(find.byType(YdPillButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.notNow));
      await tester.pumpAndSettle();

      expect(recorder.sent, hasLength(1));
      expect(find.text(en.multiCartPriceChangedTitle), findsNothing);
      expect(cart.storeIds, <String>['s1', 's2']);
      expect(placeButton(tester).onPressed, isNotNull,
          reason: 'The customer can look at the figures again and place it.');
    });
  });
}
