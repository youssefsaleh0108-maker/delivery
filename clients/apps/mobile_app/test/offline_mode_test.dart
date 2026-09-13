import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/cached_catalog_screen.dart';
import 'package:mobile_app/src/cart.dart';
import 'package:mobile_app/src/customer_nav_bar.dart';
import 'package:mobile_app/src/customer_shell.dart';
import 'package:mobile_app/src/my_orders_screen.dart';
import 'package:mobile_app/src/offline_banner.dart';
import 'package:mobile_app/src/offline_catalog.dart';
import 'package:mobile_app/src/offline_store.dart';
import 'package:mobile_app/src/order_outbox.dart';
import 'package:mobile_app/src/outbox_card.dart';

import 'widget_test.dart' show sessionWith;

/// The customer app with no connection (Figma 121:279), as the customer sees it: the strip over
/// every tab, the queued checkouts on Orders in each state they can be in, and the saved shelf.
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

  Map<String, dynamic> page(List<Map<String, dynamic>> content) => <String, dynamic>{
        'content': content,
        'page': 0,
        'totalElements': content.length,
        'totalPages': 1,
      };

  /// GETs answered from [answers] — any other order read is an empty page, anything else a 404 —
  /// and each POST /api/orders handed to [onPlace].
  Dio serve(
    Map<String, Object> answers, {
    void Function(RequestOptions o, RequestInterceptorHandler h)? onPlace,
  }) {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) {
        if (o.method == 'POST' && o.path == '/api/orders' && onPlace != null) {
          onPlace(o, h);
          return;
        }
        final Object? body = o.method != 'GET'
            ? null
            : answers[o.path] ??
                (o.path.startsWith('/api/orders') ? page(const <Map<String, dynamic>>[]) : null);
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

  void tallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('the offline strip', () {
    Future<void> pumpShell(WidgetTester tester, ConnectivityService connectivity) async {
      tallView(tester);
      final Dio dio = serve(<String, Object>{
        '/api/stores': page(const <Map<String, dynamic>>[]),
        '/api/stores/favorites': page(const <Map<String, dynamic>>[]),
        '/api/banners': const <dynamic>[],
        '/api/categories/chips': const <dynamic>[],
        '/api/notifications/unread-count': const <String, dynamic>{'unread': 0},
        '/api/butler/mine': page(const <Map<String, dynamic>>[]),
      });
      await tester.pumpWidget(app(CustomerShell(
        storeApi: StoreApi(dio),
        orderApi: OrderApi(dio),
        notificationApi: NotificationApi(dio),
        butlerApi: ButlerApi(dio),
        zoneApi: DeliveryZoneApi(dio),
        offerApi: OfferApi(dio),
        connectivity: connectivity,
        offlineStore: _MemoryStore(),
        session: sessionWith(<DeliveryRole>{DeliveryRole.customer}),
        locale: LocaleController(read: () async => 'en', write: (String _) async {}),
        onSignOut: () async {},
      )));
      await tester.pumpAndSettle();
    }

    testWidgets('sits over whichever tab is showing, never over the nav bar, and gives way to '
        '"Back online"', (WidgetTester tester) async {
      final ConnectivityService connectivity = ConnectivityService();
      addTearDown(connectivity.dispose);
      await pumpShell(tester, connectivity);

      // A cold start is assumed online: no strip until a request has actually failed.
      expect(find.text(en.offlineBanner), findsNothing);

      connectivity.reportUnreachable();
      await tester.pumpAndSettle();

      expect(find.text(en.offlineBanner), findsOneWidget);
      expect(find.text(en.offlinePill), findsOneWidget);
      final Rect strip = tester.getRect(find
          .ancestor(of: find.text(en.offlineBanner), matching: find.byType(ColoredBox))
          .first);
      expect(strip.bottom, lessThanOrEqualTo(tester.getRect(find.byType(CustomerNavBar)).top));

      // The bar still works under it, and the strip follows the customer to the next tab.
      await tester.tap(find.descendant(
          of: find.byType(CustomerNavBar), matching: find.text(en.navOrders)));
      await tester.pumpAndSettle();
      expect(find.text(en.custYourOrders), findsOneWidget);
      expect(find.text(en.offlineBanner), findsOneWidget);

      connectivity.reportReachable();
      await tester.pump();
      expect(find.text(en.offlineBanner), findsNothing);
      expect(find.text(en.offlineBackOnline), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text(en.offlineBackOnline), findsNothing);
    });

    testWidgets('its "Saved items" opens the cached catalog', (WidgetTester tester) async {
      final ConnectivityService connectivity = ConnectivityService();
      addTearDown(connectivity.dispose);
      await pumpShell(tester, connectivity);
      connectivity.reportUnreachable();
      await tester.pumpAndSettle();

      await tester.tap(find.text(en.offlineSavedItems));
      await tester.pumpAndSettle();

      expect(find.byType(CachedCatalogScreen), findsOneWidget);
      expect(find.text(en.offlineCachedCatalogTitle), findsOneWidget);
      expect(find.text(en.offlineModeBadge), findsOneWidget);
      // Nothing was ever bought on this account, so nothing was saved.
      expect(find.text(en.offlineNothingSaved), findsOneWidget);
    });

    testWidgets('in Arabic the pill leads from the right and "Saved items" ends it on the left',
        (WidgetTester tester) async {
      final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));
      await tester.pumpWidget(app(
        Scaffold(
          body: OfflineBanner(
            connectivity: ValueNotifier<bool>(false),
            onOpenSaved: () {},
            child: const SizedBox.expand(),
          ),
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      expect(ar.offlineBanner, isNot(en.offlineBanner));
      final Rect pill = tester.getRect(find.text(ar.offlinePill));
      final Rect message = tester.getRect(find.text(ar.offlineBanner));
      final Rect link = tester.getRect(find.text(ar.offlineSavedItems));
      expect(pill.left, greaterThanOrEqualTo(message.right));
      expect(link.right, lessThanOrEqualTo(message.left));
    });
  });

  group('queued checkouts on the Orders tab', () {
    /// Named by its shop, which is how its card is named — so each card in a test gets its own.
    PendingOrder queuedCheckout(String key, String shop,
            {DateTime? queuedAt, bool maybePlaced = false}) =>
        PendingOrder(
          submission: OrderSubmission(
            idempotencyKey: key,
            items: <OrderLineSubmission>[(productId: 'p1', qty: 1, optionIds: const <String>[])],
            deliveryAddress: '12 Rose Street',
          ),
          expectedTotal: 12.40,
          storeId: 's1',
          storeName: shop,
          createdAt: queuedAt ?? DateTime.now(),
          maybePlaced: maybePlaced,
        );

    void refuse(RequestOptions o, RequestInterceptorHandler h, int code,
            Map<String, dynamic> body) =>
        h.reject(DioException(
          requestOptions: o,
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(requestOptions: o, statusCode: code, data: body),
        ));

    testWidgets('each says where it stands and offers only what can work in that state',
        (WidgetTester tester) async {
      tallView(tester);
      int sends = 0;
      final Dio dio = serve(
        const <String, Object>{},
        onPlace: (RequestOptions o, RequestInterceptorHandler h) {
          switch (sends++) {
            case 0:
              refuse(o, h, 409, <String, dynamic>{
                'code': 'PRICE_CHANGED',
                'total': 13.90,
                'expectedTotal': 12.40,
              });
            case 1:
              refuse(o, h, 422, <String, dynamic>{'detail': 'The shop is closed right now'});
            default:
            // Never answered: this one is on the wire for the rest of the test, and the drain
            // waits behind it — which leaves the last one queued.
          }
        },
      );
      final ValueNotifier<bool> online = ValueNotifier<bool>(false);
      final OrderOutbox outbox = OrderOutbox(
          api: OrderApi(dio), store: _MemoryStore(), ownerId: 'user-1', connectivity: online);
      addTearDown(outbox.dispose);
      final PendingOrder repriced =
          queuedCheckout('aaaaaaaa-0000-4000-8000-000000000001', 'Dekkane Abou Selim');
      final PendingOrder refused =
          queuedCheckout('bbbbbbbb-0000-4000-8000-000000000002', 'Furn Al Hara');
      final PendingOrder onTheWire =
          queuedCheckout('cccccccc-0000-4000-8000-000000000003', 'Kaak Beirut');
      final PendingOrder waiting =
          queuedCheckout('dddddddd-0000-4000-8000-000000000004', 'Abou Joseph Grocery');
      for (final PendingOrder p in <PendingOrder>[repriced, refused, onTheWire, waiting]) {
        await outbox.enqueue(p);
      }

      await tester.pumpWidget(app(Scaffold(
        body: MyOrdersScreen(
          api: OrderApi(dio),
          storeApi: StoreApi(dio),
          cart: Cart(),
          onOpenBasket: () {},
          outbox: outbox,
        ),
      )));
      online.value = true;
      // Not pumpAndSettle: the card on the wire spins for as long as its answer is out.
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      Finder card(PendingOrder p) => find.ancestor(
          of: find.text(en.offlineQueuedTitle(p.storeName)), matching: find.byType(OutboxCard));
      Finder inCard(PendingOrder p, Finder f) => find.descendant(of: card(p), matching: f);

      expect(find.text(en.offlineOutboxTitle), findsOneWidget);
      // "No orders yet" under four queued orders would be untrue in the way that matters most.
      expect(find.text(en.noOrdersYet), findsNothing);

      // Repriced: the new total, and a send at that total — never on the customer's behalf.
      expect(inCard(repriced, find.text(en.offlinePriceChanged('\$13.90'))), findsOneWidget);
      expect(inCard(repriced, find.text(en.offlineSendAt('\$13.90'))), findsOneWidget);
      expect(inCard(repriced, find.text(en.offlineDiscard)), findsOneWidget);

      // Refused: the server's own reason, a retry and a discard.
      expect(inCard(refused, find.text(en.offlineFailed('The shop is closed right now'))),
          findsOneWidget);
      expect(inCard(refused, find.text(en.tryAgain)), findsOneWidget);

      // On the wire: nothing to press, least of all discard — its outcome is not known yet.
      expect(inCard(onTheWire, find.text(en.offlineSending)), findsOneWidget);
      expect(inCard(onTheWire, find.byType(IconButton)), findsNothing);
      expect(inCard(onTheWire, find.text(en.offlineDiscard)), findsNothing);

      // Waiting: the frame's own card — named by its shop, then when it was queued and for how
      // much, then the promise. No "#1234" anywhere: a queued checkout has no order number yet,
      // and one made up here would be a number the placed order never shows.
      final MaterialLocalizations dates = MaterialLocalizations.of(tester.element(card(waiting)));
      final String queuedAt =
          dates.formatTimeOfDay(TimeOfDay.fromDateTime(waiting.createdAt.toLocal()));
      expect(inCard(waiting, find.text(en.offlineWillSend)), findsOneWidget);
      expect(inCard(waiting, find.text(en.offlineQueuedWhenAmount(queuedAt, '\$12.40'))),
          findsOneWidget);
      expect(find.descendant(of: find.byType(OutboxCard), matching: find.textContaining('#')),
          findsNothing);

      // Discarding asks first, then removes it from the phone.
      await tester.tap(inCard(refused, find.text(en.offlineDiscard)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(en.offlineDiscardTitle), findsOneWidget);
      await tester.tap(
          find.descendant(of: find.byType(AlertDialog), matching: find.text(en.offlineDiscard)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(card(refused), findsNothing);
      expect(outbox.items.map((PendingOrder p) => p.key),
          <String>[repriced.key, onTheWire.key, waiting.key]);
    });

    testWidgets('one that may already have been placed is never called unsent: it says the outcome '
        'is being checked, its Discard warns that only the phone\'s copy goes, and once stale it '
        'offers to send again under the same key', (WidgetTester tester) async {
      tallView(tester);
      final List<RequestOptions> sends = <RequestOptions>[];
      final Dio dio = serve(
        const <String, Object>{},
        onPlace: (RequestOptions o, RequestInterceptorHandler h) {
          sends.add(o);
          // It had gone through: the key is answered with the order it placed back then.
          h.resolve(Response<dynamic>(requestOptions: o, statusCode: 200, data: <String, dynamic>{
            'id': 'order-earlier',
            'customerId': 'user-1',
            'merchantId': 'm1',
            'riderId': null,
            'status': 'PLACED',
            'totalAmount': 12.40,
            'deliveryAddress': '12 Rose Street',
            'paymentMethod': 'CASH',
            'paymentStatus': 'DUE',
            'items': <dynamic>[],
            'availableActions': <dynamic>[],
          }));
        },
      );
      final ValueNotifier<bool> online = ValueNotifier<bool>(false);
      final OrderOutbox outbox = OrderOutbox(
          api: OrderApi(dio), store: _MemoryStore(), ownerId: 'user-1', connectivity: online);
      addTearDown(outbox.dispose);
      // Queued yesterday, after a try whose answer never came back.
      final DateTime yesterday = DateTime.now().subtract(const Duration(days: 1));
      final PendingOrder unconfirmed = queuedCheckout(
          'eeeeeeee-0000-4000-8000-000000000005', 'Furn Al Hara',
          queuedAt: yesterday, maybePlaced: true);
      await outbox.enqueue(unconfirmed);

      await tester.pumpWidget(app(Scaffold(
        body: MyOrdersScreen(
          api: OrderApi(dio),
          storeApi: StoreApi(dio),
          cart: Cart(),
          onOpenBasket: () {},
          outbox: outbox,
        ),
      )));
      await tester.pumpAndSettle();

      Finder inCard(Finder f) => find.descendant(of: find.byType(OutboxCard), matching: f);

      // Waiting: never "will send", which would say it has not been sent.
      expect(inCard(find.text(en.offlineQueuedTitle('Furn Al Hara'))), findsOneWidget);
      expect(inCard(find.text(en.offlineMaybePlaced)), findsOneWidget);
      expect(inCard(find.text(en.offlineWillSend)), findsNothing);
      // Queued on another day, so the day is part of "when".
      final MaterialLocalizations dates =
          MaterialLocalizations.of(tester.element(find.byType(OutboxCard)));
      final DateTime local = yesterday.toLocal();
      final String when =
          '${dates.formatShortDate(local)} ${dates.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
      expect(inCard(find.text(en.offlineQueuedWhenAmount(when, '\$12.40'))), findsOneWidget);

      // Its Discard does not promise that nothing was sent.
      await tester.tap(inCard(find.byType(IconButton)));
      await tester.pumpAndSettle();
      expect(find.text(en.offlineDiscardMaybePlacedBody), findsOneWidget);
      expect(find.text(en.offlineDiscardBody), findsNothing);
      await tester.tap(find.text(en.keepIt));
      await tester.pumpAndSettle();
      expect(outbox.items.single.key, unconfirmed.key);

      // Back online, it has waited too long to go by itself: it asks, and says what sending does.
      online.value = true;
      await tester.pumpAndSettle();
      expect(sends, isEmpty);
      expect(inCard(find.text(en.offlineStaleMaybePlaced)), findsOneWidget);
      expect(inCard(find.text(en.offlineStale)), findsNothing);

      await tester.tap(inCard(find.text(en.offlineSendAgain)));
      await tester.pumpAndSettle();

      // The same key, answered with the order it had already placed — not a second order.
      expect(sends.single.headers[OrderApi.idempotencyKeyHeader], unconfirmed.key);
      expect(outbox.items, isEmpty);
    });
  });

  group('the cached catalog', () {
    Map<String, Object> platform() => <String, Object>{
          '/api/orders/mine': page(<Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'o1',
              'customerId': 'user-1',
              'merchantId': 'm1',
              'riderId': null,
              'status': 'DELIVERED',
              'totalAmount': 4.70,
              'deliveryAddress': '12 Rose Street',
              'paymentMethod': 'CASH',
              'paymentStatus': 'PAID',
              'storeId': 's1',
              'items': <dynamic>[
                <String, dynamic>{
                  'productId': 'p1',
                  'productName': "Fresh Man'oushe",
                  'unitPrice': 1.20,
                  'qty': 1,
                  'lineTotal': 1.20,
                },
                <String, dynamic>{
                  'productId': 'p2',
                  'productName': 'Knefe Kaak',
                  'unitPrice': 3.50,
                  'qty': 1,
                  'lineTotal': 3.50,
                },
              ],
              'availableActions': <dynamic>[],
            },
          ]),
          '/api/stores/s1/products': page(<Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'p1',
              'merchantId': 'm1',
              'storeId': 's1',
              'name': "Fresh Man'oushe",
              'price': 1.20,
              'status': 'ACTIVE',
            },
            <String, dynamic>{
              'id': 'p2',
              'merchantId': 'm1',
              'storeId': 's1',
              'name': 'Knefe Kaak',
              'price': 3.50,
              'status': 'ACTIVE',
            },
          ]),
          '/api/stores/s1': <String, dynamic>{
            'id': 's1',
            'slug': 'dekkane-abou-selim',
            'name': 'Dekkane Abou Selim',
            'availability': 'OPEN',
            'deliveryFee': 2,
            'minOrder': 0,
          },
          '/api/products/p1/options': const <dynamic>[],
          '/api/products/p2/options': <dynamic>[
            <String, dynamic>{
              'id': 'size',
              'name': 'Size',
              'options': <dynamic>[
                <String, dynamic>{'id': 'large', 'name': 'Large', 'priceDelta': 1},
              ],
            },
          ],
        };

    testWidgets('shows the saved shelf and when its prices were saved; Quick Add adds at that '
        'price, and a product with sizes says why it cannot', (WidgetTester tester) async {
      tallView(tester);
      final Dio dio = serve(platform());
      final OfflineCatalog catalog = OfflineCatalog(store: _MemoryStore(), ownerId: 'user-1');
      addTearDown(catalog.dispose);
      await tester.runAsync(() => catalog.refresh(orders: OrderApi(dio), stores: StoreApi(dio)));
      final Cart cart = Cart();
      final ValueNotifier<bool> online = ValueNotifier<bool>(false);

      await tester.pumpWidget(app(CachedCatalogScreen(
          catalog: catalog, cart: cart, connectivity: online, onOpenBasket: () {})));
      await tester.pumpAndSettle();

      expect(find.text(en.offlineCachedCatalogTitle), findsOneWidget);
      expect(find.text('Dekkane Abou Selim'), findsOneWidget);
      expect(find.text(en.offlineModeBadge), findsOneWidget);
      final MaterialLocalizations dates =
          MaterialLocalizations.of(tester.element(find.byType(CachedCatalogScreen)));
      final DateTime saved = catalog.savedAt!.toLocal();
      expect(
          find.text(en.offlinePricesAsOf(
              '${dates.formatShortDate(saved)} ${dates.formatTimeOfDay(TimeOfDay.fromDateTime(saved))}')),
          findsOneWidget);
      expect(find.text("Fresh Man'oushe"), findsOneWidget);
      expect(find.text('\$1.20'), findsOneWidget);
      expect(find.text('\$3.50'), findsOneWidget);
      // One Quick Add, for the one product that needs no choice; the knefe explains instead.
      expect(find.text(en.offlineQuickAdd), findsOneWidget);
      expect(find.text(en.offlineNeedsOptions), findsOneWidget);

      await tester.tap(find.text(en.offlineQuickAdd));
      await tester.pumpAndSettle();

      expect(cart.itemCount, 1);
      expect(cart.subtotal, 1.20);
      expect(cart.store?.name, 'Dekkane Abou Selim');
      expect(find.text(en.addedToBasket(1)), findsOneWidget);

      // Back online the page is just recent purchases; a pill saying otherwise would be untrue.
      online.value = true;
      await tester.pumpAndSettle();
      expect(find.text(en.offlineModeBadge), findsNothing);
    });

    testWidgets('with nothing saved yet it says so instead of drawing an empty track',
        (WidgetTester tester) async {
      tallView(tester);
      final OfflineCatalog catalog = OfflineCatalog(store: _MemoryStore(), ownerId: 'user-1');
      addTearDown(catalog.dispose);

      await tester.pumpWidget(app(CachedCatalogScreen(
          catalog: catalog,
          cart: Cart(),
          connectivity: ValueNotifier<bool>(false),
          onOpenBasket: () {})));
      await tester.pumpAndSettle();

      expect(find.text(en.offlineNothingSaved), findsOneWidget);
      expect(find.text(en.offlineQuickAdd), findsNothing);
    });
  });
}

class _MemoryStore implements OfflineStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
