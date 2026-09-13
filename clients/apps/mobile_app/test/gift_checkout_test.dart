import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/cart.dart';
import 'package:mobile_app/src/cart_screen.dart';
import 'package:mobile_app/src/checkout_screen.dart';
import 'package:mobile_app/src/delivery_address.dart';
import 'package:mobile_app/src/gift_checkout_screen.dart';

import 'widget_test.dart' show product, sessionWith, storeCard;

/// What the gift checkout sends, what it refuses to send, and what it tells the customer.
///
/// The request body is where a gift can silently go wrong — a recipient folded into notes, a phone
/// the rider cannot ring, cash that bills the family, a total nobody saw — so that is what is
/// asserted, beside the few states the screen owes the customer: no method to pay with, no
/// connection, an answer that never came.
void main() {
  const MethodChannel storageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (MethodCall call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
  });

  /// A gateway answering the gift terms and the placement, and recording every request.
  ({Dio dio, List<RequestOptions> sent}) server({
    List<String> methods = const <String>['CARD', 'WALLET'],
    void Function(RequestOptions o, RequestInterceptorHandler h)? place,
  }) {
    final List<RequestOptions> sent = <RequestOptions>[];
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway.test'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) {
        sent.add(o);
        if (o.path == '/api/orders/gift-terms') {
          h.resolve(Response<dynamic>(
              requestOptions: o,
              statusCode: 200,
              data: <String, dynamic>{'wrapFee': 3.0, 'paymentMethods': methods}));
          return;
        }
        if (o.method == 'POST' && o.path == '/api/orders') {
          if (place != null) {
            place(o, h);
            return;
          }
          h.resolve(Response<dynamic>(requestOptions: o, statusCode: 201, data: <String, dynamic>{
            'id': 'order-gift-1',
            'customerId': 'user-1',
            'merchantId': 's1',
            'riderId': null,
            'status': 'PLACED',
            'totalAmount': 50.5,
            'deliveryAddress': 'Mar Mikhael, Facing Municipality, Beirut',
            'paymentMethod': 'CARD',
            'paymentStatus': 'AUTHORIZED',
            'items': <dynamic>[],
            'availableActions': <dynamic>[],
          }));
          return;
        }
        h.resolve(Response<dynamic>(requestOptions: o, statusCode: 200, data: <String, dynamic>{}));
      },
    ));
    return (dio: dio, sent: sent);
  }

  List<RequestOptions> placements(List<RequestOptions> sent) =>
      sent.where((RequestOptions o) => o.method == 'POST' && o.path == '/api/orders').toList();

  Future<DeliveryAddressStore> recipientStore({bool withAddress = true}) async {
    final DeliveryAddressStore store = DeliveryAddressStore(ownerId: 'test-user');
    if (withAddress) {
      await store.select(const DeliveryAddress(
        line: 'Mar Mikhael, Facing Municipality, Beirut',
        label: 'Mom',
        notes: 'Second floor, green door',
        zoneName: 'Mar Mikhael',
      ));
    }
    return store;
  }

  Cart giftBasket() => Cart()
    ..add(product('bundle', 's1', 45.0), from: storeCard('s1', deliveryFee: 2.5))
    ..startGift();

  Future<void> pumpGiftCheckout(
    WidgetTester tester, {
    required Dio dio,
    required DeliveryAddressStore addresses,
    required Cart cart,
    ValueListenable<bool>? connectivity,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1000, 2600);
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
      home: GiftCheckoutScreen(
        api: OrderApi(dio),
        cart: cart,
        addresses: addresses,
        connectivity: connectivity,
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder phoneField() => find.byType(TextFormField).at(1);

  Map<String, dynamic> bodyOf(RequestOptions request) =>
      jsonDecode(jsonEncode(request.data)) as Map<String, dynamic>;

  testWidgets('places the gift as its own part of the order, paid by a non-cash method',
      (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> sent}) gateway = server();
    final DeliveryAddressStore addresses = await recipientStore();
    final Cart cart = giftBasket();
    await pumpGiftCheckout(tester, dio: gateway.dio, addresses: addresses, cart: cart);

    // The recipient's name comes from the address that names them.
    expect(find.widgetWithText(TextFormField, 'Mom'), findsOneWidget);
    await tester.enterText(phoneField(), '71 234 567');
    await tester.enterText(find.byType(TextField).last, 'Habibti Mom');
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.giftSendAndPay));
    await tester.pumpAndSettle();

    final List<RequestOptions> sent = placements(gateway.sent);
    expect(sent, hasLength(1));
    final Map<String, dynamic> body = bodyOf(sent.single);
    expect(body['gift'], <String, dynamic>{
      'recipientName': 'Mom',
      'recipientPhone': '+96171234567',
      'message': 'Habibti Mom',
      'wrap': true,
    });
    expect(body['paymentMethod'], 'CARD');
    expect(body['paymentMethod'], isNot('CASH'));
    expect(body['deliveryTier'], 'STANDARD');
    expect(body['paymentInstrumentToken'], 'dev-test-instrument');
    // The recipient's door instructions travel as the notes; the card travels as the gift.
    expect(body['notes'], 'Second floor, green door');
    expect(body.containsKey('contactPhone'), isFalse);
    expect(sent.single.headers[OrderApi.idempotencyKeyHeader], isNotNull);

    // Remembered with the recipient for next time, and the basket's gift is over.
    expect(addresses.selected?.recipientPhone, '+96171234567');
    expect(addresses.selected?.recipientName, 'Mom');
    expect(cart.isEmpty, isTrue);
    expect(cart.isGift, isFalse);
  });

  testWidgets('never offers cash, and labels the methods it offers as test payments',
      (WidgetTester tester) async {
    await pumpGiftCheckout(tester,
        dio: server().dio, addresses: await recipientStore(), cart: giftBasket());

    expect(find.textContaining('Cash on Delivery'), findsNothing);
    expect(find.text(en.paymentWallet), findsOneWidget);
    expect(find.text(en.paymentTestModeNote), findsOneWidget);
    expect(find.text(en.giftCashNotAllowed), findsOneWidget);
  });

  testWidgets('where no method can pay for a gift, says so and sends nothing',
      (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> sent}) gateway = server(methods: const <String>['CASH']);
    await pumpGiftCheckout(tester,
        dio: gateway.dio, addresses: await recipientStore(), cart: giftBasket());

    expect(find.text(en.giftNoPaymentMethods), findsOneWidget);
    await tester.enterText(phoneField(), '71 234 567');
    await tester.tap(find.text(en.giftSendAndPay));
    await tester.pumpAndSettle();

    expect(placements(gateway.sent), isEmpty);
  });

  testWidgets('a name, a Lebanese phone and an address are needed before anything is sent',
      (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> sent}) gateway = server();
    final DeliveryAddressStore addresses = await recipientStore();
    await pumpGiftCheckout(tester, dio: gateway.dio, addresses: addresses, cart: giftBasket());

    await tester.enterText(find.byType(TextFormField).first, '');
    await tester.enterText(phoneField(), '12');
    await tester.tap(find.text(en.giftSendAndPay));
    await tester.pumpAndSettle();

    expect(find.text(en.giftRecipientNameRequired), findsOneWidget);
    expect(find.text(en.giftPhoneInvalid), findsOneWidget);
    expect(placements(gateway.sent), isEmpty);
  });

  testWidgets('with no address chosen, asks for one and sends nothing', (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> sent}) gateway = server();
    await pumpGiftCheckout(tester,
        dio: gateway.dio, addresses: await recipientStore(withAddress: false), cart: giftBasket());

    await tester.enterText(find.byType(TextFormField).first, 'Mona');
    await tester.enterText(phoneField(), '71 234 567');
    await tester.tap(find.text(en.giftSendAndPay));
    await tester.pump();

    expect(find.text(en.addressRequired), findsWidgets);
    expect(placements(gateway.sent), isEmpty);
  });

  testWidgets('the summary adds goods, delivery and the wrap at the server\'s price',
      (WidgetTester tester) async {
    await pumpGiftCheckout(tester,
        dio: server().dio, addresses: await recipientStore(), cart: giftBasket());

    expect(find.text(en.giftLineQty(1, 'Item bundle')), findsOneWidget);
    expect(find.text('\$47.50'), findsOneWidget);
    expect(find.text(en.giftWrapLine), findsNothing);
    // No rate has been fetched, so no lira figure is invented.
    expect(find.textContaining('LBP'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text(en.giftWrapSubtitle('\$3.00')), findsOneWidget);
    expect(find.text(en.giftWrapLine), findsOneWidget);
    expect(find.text('\$50.50'), findsOneWidget);
  });

  testWidgets('says plainly the gift goes today, and offers no day it cannot keep',
      (WidgetTester tester) async {
    await pumpGiftCheckout(tester,
        dio: server().dio, addresses: await recipientStore(), cart: giftBasket());

    expect(find.text(en.giftDeliveryDate), findsOneWidget);
    expect(find.text(en.giftDeliveredToday), findsOneWidget);
    expect(find.byType(YdComingSoon), findsNothing);
    expect(find.text(en.authComingSoon.toUpperCase()), findsNothing);
  });

  testWidgets('a refusal shows the server\'s own reason', (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> sent}) gateway = server(
      place: (RequestOptions o, RequestInterceptorHandler h) => h.reject(DioException(
        requestOptions: o,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(requestOptions: o, statusCode: 422, data: <String, dynamic>{
          'detail': 'Bloom & Wrap is closed and is not taking orders right now',
        }),
      )),
    );
    final Cart cart = giftBasket();
    await pumpGiftCheckout(tester, dio: gateway.dio, addresses: await recipientStore(), cart: cart);

    await tester.enterText(phoneField(), '71 234 567');
    await tester.tap(find.text(en.giftSendAndPay));
    await tester.pumpAndSettle();

    expect(find.text('Bloom & Wrap is closed and is not taking orders right now'), findsOneWidget);
    // A refusal is an answer: nothing may have been placed, and the basket is still the gift.
    expect(cart.checkoutUnconfirmed, isFalse);
    expect(cart.isGift, isTrue);
  });

  testWidgets('a double tap sends one request', (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> sent}) gateway = server();
    await pumpGiftCheckout(tester,
        dio: gateway.dio, addresses: await recipientStore(), cart: giftBasket());

    await tester.enterText(phoneField(), '71 234 567');
    await tester.tap(find.text(en.giftSendAndPay));
    await tester.tap(find.text(en.giftSendAndPay), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(placements(gateway.sent), hasLength(1));
  });

  testWidgets('offline, a gift is not sent and not queued, and the screen says why',
      (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> sent}) gateway = server();
    final ValueNotifier<bool> online = ValueNotifier<bool>(false);
    addTearDown(online.dispose);
    await pumpGiftCheckout(tester,
        dio: gateway.dio,
        addresses: await recipientStore(),
        cart: giftBasket(),
        connectivity: online);

    expect(find.text(en.giftOfflineCannotWait), findsOneWidget);
    await tester.enterText(phoneField(), '71 234 567');
    await tester.tap(find.text(en.giftSendAndPay));
    await tester.pump();

    expect(placements(gateway.sent), isEmpty);
    expect(find.text(en.offlineQueueAction), findsNothing);
  });

  testWidgets('an answer that never came keeps the key and never offers to send it later',
      (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> sent}) gateway = server(
      place: (RequestOptions o, RequestInterceptorHandler h) => h.reject(
          DioException(requestOptions: o, type: DioExceptionType.receiveTimeout)),
    );
    final Cart cart = giftBasket();
    await pumpGiftCheckout(tester, dio: gateway.dio, addresses: await recipientStore(), cart: cart);

    final String key = cart.checkoutKey;
    await tester.enterText(phoneField(), '71 234 567');
    await tester.tap(find.text(en.giftSendAndPay));
    await tester.pumpAndSettle();

    expect(cart.checkoutUnconfirmed, isTrue);
    expect(cart.checkoutKey, key);
    expect(find.textContaining(en.offlineUnconfirmedRetry), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('the basket sends a gift to the gift checkout, and "Not a gift" to the regular one',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final Dio dio = server().dio;
    final Cart cart = giftBasket();

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
        body: CartScreen(
          cart: cart,
          addresses: await recipientStore(),
          orderApi: OrderApi(dio),
          offerApi: OfferApi(dio),
          onOrderPlaced: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text(en.giftBasketBanner), findsOneWidget);
    await tester.tap(find.text(en.custProceedToCheckout));
    await tester.pumpAndSettle();
    expect(find.byType(GiftCheckoutScreen), findsOneWidget);

    // YdScreenHeader draws its own back button, so pop the route rather than look for Material's.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.giftBasketNotGift));
    await tester.pumpAndSettle();

    expect(cart.isGift, isFalse);
    expect(find.text(en.giftBasketBanner), findsNothing);
    await tester.tap(find.text(en.custProceedToCheckout));
    await tester.pumpAndSettle();
    expect(find.byType(CheckoutScreen), findsOneWidget);
  });

  testWidgets('in Arabic, the +961 prefix still reads before the number',
      (WidgetTester tester) async {
    await pumpGiftCheckout(tester,
        dio: server().dio,
        addresses: await recipientStore(),
        cart: giftBasket(),
        locale: const Locale('ar'));

    expect(tester.takeException(), isNull);
    final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));
    expect(find.text(ar.giftDetailsTitle), findsOneWidget);
    expect(tester.getCenter(find.text('+961')).dx, lessThan(tester.getCenter(phoneField()).dx));
  });

  testWidgets('in Arabic, the number is typed left to right but its error reads right to left',
      (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> sent}) gateway = server();
    await pumpGiftCheckout(tester,
        dio: gateway.dio,
        addresses: await recipientStore(),
        cart: giftBasket(),
        locale: const Locale('ar'));
    final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

    await tester.enterText(phoneField(), '12');
    await tester.tap(find.text(ar.giftSendAndPay));
    await tester.pumpAndSettle();

    final Finder error = find.text(ar.giftPhoneInvalid);
    expect(error, findsOneWidget);
    expect(Directionality.of(tester.element(error)), TextDirection.rtl);
    // Only the input stays left to right: the prefix first, then the number.
    final EditableText input = tester.widget<EditableText>(
        find.descendant(of: phoneField(), matching: find.byType(EditableText)));
    expect(input.textDirection, TextDirection.ltr);
    expect(tester.getCenter(find.text('+961')).dx, lessThan(tester.getCenter(phoneField()).dx));
    expect(placements(gateway.sent), isEmpty);
  });

  testWidgets('holds the card to the 240 units the server counts, where an emoji counts twice',
      (WidgetTester tester) async {
    final ({Dio dio, List<RequestOptions> sent}) gateway = server();
    await pumpGiftCheckout(tester,
        dio: gateway.dio, addresses: await recipientStore(), cart: giftBasket());

    // 121 emoji: 121 characters, which Flutter's own maxLength of 240 would have let through — and
    // 242 UTF-16 units, which the server's @Size(max = 240) refuses.
    final Finder card = find.byType(TextField).last;
    await tester.enterText(card, '😍' * 121);
    await tester.pump();

    final String kept = tester.widget<TextField>(card).controller!.text;
    expect(kept, '😍' * 120);
    expect(kept.length, 240);
    expect(find.text(en.giftNoteLength(240, 240)), findsOneWidget);

    await tester.enterText(phoneField(), '71 234 567');
    await tester.tap(find.text(en.giftSendAndPay));
    await tester.pumpAndSettle();

    final Map<String, dynamic> gift =
        bodyOf(placements(gateway.sent).single)['gift'] as Map<String, dynamic>;
    expect(gift['message'], '😍' * 120);
  });

  testWidgets('a gift basket offers no split, and one made a gift after Split was chosen shows none',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final Dio dio = server().dio;
    final Cart cart = Cart()..add(product('bundle', 's1', 45.0), from: storeCard('s1', deliveryFee: 2.5));
    final DeliveryAddressStore addresses = await recipientStore();

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
        // Rebuilt on every cart change, as CustomerShell rebuilds its tabs.
        body: AnimatedBuilder(
          animation: cart,
          builder: (BuildContext context, Widget? _) => CartScreen(
            cart: cart,
            addresses: addresses,
            orderApi: OrderApi(dio),
            offerApi: OfferApi(dio),
            splitApi: SplitApi(dio),
            profileApi: ProfileApi(dio),
            session: sessionWith(<DeliveryRole>{DeliveryRole.customer}),
            onOrderPlaced: () {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // An ordinary basket can be split with friends.
    await tester.tap(find.text(en.custSplitOrder));
    await tester.pumpAndSettle();
    expect(find.text(en.custSendPaymentRequests), findsOneWidget);

    // As a gift none of it is offered: the gift checkout could never attach the plan, and placing
    // the gift would clear it from under the friends' payment requests.
    cart.startGift();
    await tester.pumpAndSettle();
    expect(find.text(en.custSplitOrder), findsNothing);
    expect(find.text(en.custSendPaymentRequests), findsNothing);
  });
}
