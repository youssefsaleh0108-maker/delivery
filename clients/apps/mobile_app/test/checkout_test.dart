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
    await tester.pumpAndSettle();
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
}
