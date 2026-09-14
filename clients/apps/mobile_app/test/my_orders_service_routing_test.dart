import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/cart.dart';
import 'package:mobile_app/src/my_orders_screen.dart';
import 'package:mobile_app/src/order_details_screen.dart';
import 'package:mobile_app/src/service_order_tracking_screen.dart';

import 'service_fixtures.dart';

/// The Orders tab with service orders in it.
///
/// A service order opens its own tracking page, and its card says what it is — the offer's name, a
/// Service chip, and its status in a service's words, a provider's decline included. A basket's card
/// is exactly as it was. Reorder stays a basket's: it rebuilds a basket in a goods shop.
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

  Map<String, dynamic> basket({String status = 'PREPARING'}) => <String, dynamic>{
        'id': 'basket01-0000-4000-8000-000000000002',
        'customerId': 'user-1',
        'merchantId': 'm2',
        'riderId': null,
        'status': status,
        'totalAmount': 9.75,
        'subtotal': 9.75,
        'deliveryAddress': '12 Rose Street',
        'paymentMethod': 'CASH',
        'paymentStatus': 'DUE',
        'storeId': 's2',
        'storeName': 'Bloom & Wrap',
        'placedAt': DateTime.now().toUtc().toIso8601String(),
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'productId': 'a',
            'productName': 'Roses',
            'unitPrice': 9.75,
            'qty': 1,
            'lineTotal': 9.75,
          },
        ],
        'availableActions': <dynamic>[],
      };

  Future<void> pump(WidgetTester tester, List<Map<String, dynamic>> orders,
      {Size size = const Size(390, 1600)}) async {
    phone(tester, size: size);
    final FakeServer server = FakeServer()
      ..on('GET', '/api/orders/mine', (_) => pageJson(orders))
      ..on('GET', '/api/orders/$svcOrderId', (_) => orders.first)
      ..on('GET', '/api/orders/$svcOrderId/history',
          (_) => historyJson(<String>['PLACED', 'ACCEPTED', 'PREPARING']));
    // Under a Scaffold, as the shell hosts it: its cards ink on the Material that provides.
    await tester.pumpWidget(svcApp(Scaffold(
      body: MyOrdersScreen(
        api: OrderApi(server.dio),
        storeApi: StoreApi(server.dio),
        cart: Cart(),
        onOpenBasket: () {},
      ),
    )));
    await tester.pumpAndSettle();
  }

  /// The status pills may draw their words in capitals; what they say is the point.
  Finder says(String words) => find.byWidgetPredicate(
      (Widget w) => w is Text && (w.data ?? '').toLowerCase() == words.toLowerCase());

  testWidgets('a service order opens its tracking page, and a basket its order page',
      (WidgetTester tester) async {
    // Wide: the basket's own order page, which this slice does not touch, is laid out for a phone's
    // real font rather than the test font's full-em glyphs.
    await pump(tester, <Map<String, dynamic>>[serviceOrderJson(), basket()],
        size: const Size(1000, 1600));

    expect(find.text(en.svcServiceChip), findsOneWidget);
    expect(find.text('Business Card Printing'), findsOneWidget);
    expect(says(en.svcStatusInProgress), findsOneWidget);
    expect(find.text(en.custItemsCountLine(1)), findsOneWidget, reason: 'the basket is unchanged');

    await tester.tap(find.text('Al Fakhry Press'));
    await tester.pumpAndSettle();
    expect(find.byType(ServiceOrderTrackingScreen), findsOneWidget);
    expect(find.byType(OrderDetailsScreen), findsNothing);

    await tester.tap(find.byType(YdBackButton));
    await tester.pumpAndSettle();
    expect(find.byType(ServiceOrderTrackingScreen), findsNothing);

    await tester.tap(find.text('Bloom & Wrap'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(OrderDetailsScreen), findsOneWidget);
    expect(find.byType(ServiceOrderTrackingScreen), findsNothing);
  });

  testWidgets('a pickup at the counter reads as ready for pickup', (WidgetTester tester) async {
    await pump(tester, <Map<String, dynamic>>[serviceOrderJson(status: 'READY')]);

    expect(says(en.svcStatusReadyPickup), findsOneWidget);
  });

  testWidgets('a declined service order reads as declined, and only the basket offers Reorder',
      (WidgetTester tester) async {
    await pump(tester, <Map<String, dynamic>>[
      serviceOrderJson(status: 'CANCELLED', cancelReason: 'PROVIDER_DECLINED: TOO_BUSY'),
      basket(status: 'DELIVERED'),
    ]);

    await tester.tap(find.text(en.custPastOrdersTab));
    await tester.pumpAndSettle();

    expect(says(en.svcStatusDeclined), findsOneWidget);
    expect(says(en.statusCancelled), findsNothing);
    expect(find.text(en.custReorder), findsOneWidget);
  });
}
