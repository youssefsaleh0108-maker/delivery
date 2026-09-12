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
import 'package:mobile_app/src/checkout_screen.dart';
import 'package:mobile_app/src/delivery_address.dart';
import 'package:mobile_app/src/offline_store.dart';
import 'package:mobile_app/src/order_outbox.dart';

import 'widget_test.dart' show product, storeCard;

/// Checkout with no connection (Figma 121:279): what is offered, what is refused, and what a queued
/// checkout carries with it.
///
/// Queuing is only honest for a checkout that can actually be placed later without the customer
/// watching — cash, one shop's basket, written safely to the phone — and only when the platform
/// could not be reached. A refused basket is a refusal, not an outage; a split basket or a card
/// cannot wait; and a checkout the phone could not save must never look saved.
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

  /// Order Manager for these tests: each POST /api/orders gets the next reply, or a new order once
  /// the replies run out; a GET gets [gets] or a 404.
  ({Dio dio, List<RequestOptions> placed}) server(
    List<void Function(RequestOptions o, RequestInterceptorHandler h)> replies, {
    Map<String, Object> gets = const <String, Object>{},
  }) {
    final List<RequestOptions> placed = <RequestOptions>[];
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) {
        if (o.method == 'POST' && o.path == '/api/orders') {
          final int n = placed.length;
          placed.add(o);
          if (n < replies.length) {
            replies[n](o, h);
          } else {
            h.resolve(Response<dynamic>(requestOptions: o, statusCode: 201, data: <String, dynamic>{
              'id': 'order-1',
              'customerId': 'user-1',
              'merchantId': 's1',
              'riderId': null,
              'status': 'PLACED',
              'totalAmount': 9.75,
              'deliveryAddress': '12 Rose Street',
              'paymentMethod': 'CASH',
              'paymentStatus': 'DUE',
              'items': <dynamic>[],
              'availableActions': <dynamic>[],
            }));
          }
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

  void unreachable(RequestOptions o, RequestInterceptorHandler h) =>
      h.reject(DioException(requestOptions: o, type: DioExceptionType.connectionError));

  Cart basket() => Cart()..add(product('a', 's1', 9.75), from: storeCard('s1'));

  /// Checkout pushed over a launcher, so what it pops with can be read.
  Future<({Object? Function() result, bool Function() returned})> openCheckout(
    WidgetTester tester, {
    required Dio dio,
    required Cart cart,
    required OrderOutbox outbox,
    ValueListenable<bool>? connectivity,
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final DeliveryAddressStore addresses = DeliveryAddressStore(ownerId: 'user-1');
    await addresses.select(const DeliveryAddress(
        line: '12 Rose Street', label: 'Home', zoneId: 'zone-home', zoneName: 'Riverside'));

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
                  builder: (_) => CheckoutScreen(
                    api: OrderApi(dio),
                    cart: cart,
                    addresses: addresses,
                    outbox: outbox,
                    connectivity: connectivity,
                  ),
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

  OrderOutbox outboxOver(Dio dio, OfflineStore store) {
    final OrderOutbox outbox = OrderOutbox(
      api: OrderApi(dio),
      store: store,
      ownerId: 'user-1',
      // Still offline as far as the outbox knows, so nothing it queues is sent during the test.
      connectivity: ValueNotifier<bool>(false),
    );
    addTearDown(outbox.dispose);
    return outbox;
  }

  Future<void> tapPlace(WidgetTester tester) async {
    await tester.tap(find.byType(YdPillButton));
    await tester.pumpAndSettle();
  }

  testWidgets('a placement that never reached the platform offers to send it later, and the '
      'queued checkout is that same attempt', (WidgetTester tester) async {
    final Cart cart = basket();
    final s = server(<void Function(RequestOptions, RequestInterceptorHandler)>[unreachable]);
    final OrderOutbox outbox = outboxOver(s.dio, _MemoryStore());
    final checkout = await openCheckout(tester, dio: s.dio, cart: cart, outbox: outbox);

    await tapPlace(tester);

    expect(find.text(en.offlineQueueTitle), findsOneWidget);
    expect(find.text(en.offlineQueueBody), findsOneWidget);

    await tester.tap(find.text(en.offlineQueueAction));
    await tester.pumpAndSettle();

    final PendingOrder queued = outbox.items.single;
    // The attempt that went unanswered, not a new one: if it did reach the kitchen, the outbox's
    // send is answered with that order.
    expect(queued.key, s.placed.single.headers[OrderApi.idempotencyKeyHeader]);
    // What the button said is what the customer agreed to, and what the server must match.
    expect(queued.expectedTotal, 9.75);
    expect(queued.storeId, 's1');
    expect(queued.storeName, 'Shop s1');
    expect(queued.submission.paymentMethod, PaymentMethod.cash);
    expect(queued.submission.deliveryZoneId, 'zone-home');
    // Only now that it is safely on the phone is the basket let go.
    expect(cart.isEmpty, isTrue);
    expect(checkout.returned(), isTrue);
    expect(checkout.result(),
        isA<PendingOrder>().having((PendingOrder p) => p.key, 'key', queued.key));
  });

  testWidgets('already known to be offline, it offers the queue without spending a request',
      (WidgetTester tester) async {
    final Cart cart = basket();
    final s = server(<void Function(RequestOptions, RequestInterceptorHandler)>[]);
    final OrderOutbox outbox = outboxOver(s.dio, _MemoryStore());
    final checkout = await openCheckout(tester,
        dio: s.dio, cart: cart, outbox: outbox, connectivity: ValueNotifier<bool>(false));

    await tapPlace(tester);

    expect(find.text(en.offlineQueueTitle), findsOneWidget);
    expect(s.placed, isEmpty);

    // Not now: nothing queued, nothing lost, still on checkout.
    await tester.tap(find.text(en.notNow));
    await tester.pumpAndSettle();

    expect(find.text(en.offlineQueueTitle), findsNothing);
    expect(outbox.items, isEmpty);
    expect(cart.isNotEmpty, isTrue);
    expect(checkout.returned(), isFalse);
  });

  testWidgets('a basket the server refused is reported as it always was, and never queued',
      (WidgetTester tester) async {
    final Cart cart = basket();
    final s = server(<void Function(RequestOptions, RequestInterceptorHandler)>[
      (RequestOptions o, RequestInterceptorHandler h) => h.reject(DioException(
            requestOptions: o,
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
                requestOptions: o,
                statusCode: 422,
                data: <String, dynamic>{'detail': 'Item a is sold out'}),
          )),
    ]);
    final OrderOutbox outbox = outboxOver(s.dio, _MemoryStore());
    await openCheckout(tester, dio: s.dio, cart: cart, outbox: outbox);

    await tapPlace(tester);

    expect(find.text('Item a is sold out'), findsOneWidget);
    expect(find.text(en.offlineQueueTitle), findsNothing);
    expect(outbox.items, isEmpty);
    expect(cart.isNotEmpty, isTrue);
  });

  testWidgets('a basket being split with friends cannot wait, and is not told to "choose cash"',
      (WidgetTester tester) async {
    final Cart cart = basket()..splitPlanId = 'plan-1';
    final s = server(<void Function(RequestOptions, RequestInterceptorHandler)>[unreachable]);
    final OrderOutbox outbox = outboxOver(s.dio, _MemoryStore());
    await openCheckout(tester, dio: s.dio, cart: cart, outbox: outbox);

    await tapPlace(tester);

    expect(find.text(en.offlineQueueUnavailable), findsOneWidget);
    expect(find.text(en.offlineQueueCashOnly), findsNothing);
    // No button that could only fail later.
    expect(find.text(en.offlineQueueAction), findsNothing);

    await tester.tap(find.text(en.close));
    await tester.pumpAndSettle();

    expect(outbox.items, isEmpty);
    expect(cart.isNotEmpty, isTrue);
  });

  testWidgets('a checkout the phone could not save keeps its basket, and says nothing was queued',
      (WidgetTester tester) async {
    final Cart cart = basket();
    final s = server(<void Function(RequestOptions, RequestInterceptorHandler)>[unreachable]);
    final OrderOutbox outbox = outboxOver(s.dio, _MemoryStore()..failWrites = true);
    final checkout = await openCheckout(tester, dio: s.dio, cart: cart, outbox: outbox);

    await tapPlace(tester);
    await tester.tap(find.text(en.offlineQueueAction));
    await tester.pumpAndSettle();

    expect(find.text(en.offlineQueueSaveFailed), findsOneWidget);
    expect(outbox.items, isEmpty);
    expect(cart.isNotEmpty, isTrue);
    expect(checkout.returned(), isFalse);
  });
}

class _MemoryStore implements OfflineStore {
  final Map<String, String> values = <String, String>{};
  bool failWrites = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('the disk refused the write');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}
