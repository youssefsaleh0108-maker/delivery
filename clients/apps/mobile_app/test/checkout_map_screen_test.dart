import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile_app/src/address_sheet.dart' show OsmBasemap;
import 'package:mobile_app/src/cart.dart';
import 'package:mobile_app/src/cart_screen.dart';
import 'package:mobile_app/src/checkout_map_screen.dart';
import 'package:mobile_app/src/customer_shell.dart';
import 'package:mobile_app/src/delivery_address.dart';
import 'package:mobile_app/src/my_orders_screen.dart';
import 'package:mobile_app/src/order_details_screen.dart';

import 'service_fixtures.dart';
import 'widget_test.dart' show product, sessionWith, storeCard;

/// The checkout map: a basket from several shops, every one of its orders on one map.
///
/// What is pinned here is mostly what the map refuses to draw: no pin for a place the platform has
/// no coordinate for, no number on a stop unless one rider carries several orders, no estimate
/// before a rider, no road where the server sent straight lines — and the chip saying so only when
/// they are straight.
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
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  const String checkoutId = 'c-1';
  const String orderA = 'o-a';
  const String orderB = 'o-b';
  // Hamra (west), Achrafieh (east of it), and the door in Mar Mikhael.
  const Map<String, dynamic> shopA = <String, dynamic>{'lat': 33.8938, 'lng': 35.5018};
  const Map<String, dynamic> shopB = <String, dynamic>{'lat': 33.8869, 'lng': 35.5131};
  const Map<String, dynamic> door = <String, dynamic>{'lat': 33.8981, 'lng': 35.5214};

  final DateTime arrival = DateTime.now().add(const Duration(minutes: 9));

  Map<String, dynamic> eta(String id,
          {bool available = false, String? reason = 'NO_FIX', int seconds = 540}) =>
      <String, dynamic>{
        'orderId': id,
        'available': available,
        'reason': available ? null : reason,
        'leg': available ? 'TO_PICKUP' : null,
        'remainingMetres': available ? 2700.0 : null,
        'remainingSeconds': available ? seconds : null,
        'estimatedArrival': available ? arrival.toUtc().toIso8601String() : null,
        'provider': 'HAVERSINE_DEV',
        'fixRecordedAt': null,
        'computedAt': DateTime.now().toUtc().toIso8601String(),
      };

  Map<String, dynamic> order(
    String id,
    String name,
    String status, {
    Map<String, dynamic>? shop,
    bool rider = false,
    int? stop,
    bool expected = false,
    DateTime? completedAt,
    Map<String, dynamic>? etaJson,
  }) =>
      <String, dynamic>{
        'orderId': id,
        'storeName': name,
        'status': status,
        'shop': shop,
        'riderAssigned': rider,
        'stop': stop,
        'expected': expected,
        'pickedUpAt': null,
        'completedAt': completedAt?.toUtc().toIso8601String(),
        'eta': etaJson ??
            eta(id,
                reason: status == 'DELIVERED' || status == 'CANCELLED'
                    ? 'ORDER_COMPLETE'
                    : 'NO_FIX'),
      };

  Map<String, dynamic> riderJson(List<String> orderIds,
          {bool run = false,
          Map<String, dynamic>? at,
          Duration ago = const Duration(seconds: 20),
          bool stale = false,
          String? sighting,
          bool others = false}) =>
      <String, dynamic>{
        'orderIds': orderIds,
        'run': run,
        'sighting': sighting ?? (at == null ? 'NO_FIX' : 'VISIBLE'),
        'position': at == null
            ? null
            : <String, dynamic>{
                ...at,
                'recordedAt': DateTime.now().subtract(ago).toUtc().toIso8601String(),
                'stale': stale,
              },
        'hasOtherDeliveries': others,
      };

  Map<String, dynamic> path(List<String> orderIds, String kind, List<Map<String, dynamic>> points,
          {String? polyline6}) =>
      <String, dynamic>{
        'orderIds': orderIds,
        'kind': kind,
        'points': points,
        'polyline6': polyline6,
        'metres': 2700.0,
        'provider': polyline6 == null ? 'HAVERSINE_DEV' : 'OSRM',
      };

  Map<String, dynamic> view({
    required List<Map<String, dynamic>> orders,
    List<Map<String, dynamic>> riders = const <Map<String, dynamic>>[],
    List<Map<String, dynamic>> paths = const <Map<String, dynamic>>[],
    String geometry = 'STRAIGHT',
    Map<String, dynamic>? doorPin = door,
  }) =>
      <String, dynamic>{
        'checkoutId': checkoutId,
        'provider': geometry == 'ROAD' ? 'OSRM' : 'HAVERSINE_DEV',
        'geometry': geometry,
        'door': doorPin,
        'orders': orders,
        'riders': riders,
        'paths': paths,
        'computedAt': DateTime.now().toUtc().toIso8601String(),
      };

  /// Before anybody is on the way: two shops being prepared.
  Map<String, dynamic> beforeARider() => view(
        orders: <Map<String, dynamic>>[
          order(orderA, 'Hamra Bakery', 'PREPARING', shop: shopA),
          order(orderB, 'Achrafieh Pharmacy', 'READY', shop: shopB),
        ],
        paths: <Map<String, dynamic>>[
          path(<String>[orderA], 'PLANNED', <Map<String, dynamic>>[shopA, door]),
          path(<String>[orderB], 'PLANNED', <Map<String, dynamic>>[shopB, door]),
        ],
      );

  /// One rider carrying both: A collected (stop 1, a fact), B expected next (stop 2).
  Map<String, dynamic> aRun({bool others = true, String? aName, String? bName}) => view(
        orders: <Map<String, dynamic>>[
          order(orderA, aName ?? 'Hamra Bakery', 'PICKED_UP',
              shop: shopA, rider: true, stop: 1, etaJson: eta(orderA, available: true)),
          order(orderB, bName ?? 'Achrafieh Pharmacy', 'READY',
              shop: shopB,
              rider: true,
              stop: 2,
              expected: true,
              etaJson: eta(orderB, available: true)),
        ],
        riders: <Map<String, dynamic>>[
          riderJson(<String>[orderA, orderB],
              run: true,
              at: <String, dynamic>{'lat': 33.8930, 'lng': 35.5050},
              others: others),
        ],
        paths: <Map<String, dynamic>>[
          path(<String>[orderA, orderB], 'RIDER_LEG', <Map<String, dynamic>>[
            <String, dynamic>{'lat': 33.8930, 'lng': 35.5050},
            shopB,
            door,
          ]),
        ],
      );

  Future<FakeServer> pumpMap(
    WidgetTester tester,
    FutureOr<Object?> Function(RequestOptions) answer, {
    Locale locale = const Locale('en'),
    Size size = const Size(390, 844),
    double textScale = 1.0,
    void Function(String orderId)? onOpenOrder,
    int? shopCount = 2,
    bool justPlaced = false,
    UserQueueSocket? socket,
    bool settle = true,
  }) async {
    phone(tester, size: size);
    final FakeServer server = FakeServer()
      ..on('GET', '/api/tracking/checkouts/$checkoutId', answer);
    await tester.pumpWidget(svcApp(
      Builder(
        builder: (BuildContext context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: CheckoutMapScreen(
            api: CheckoutTrackingApi(server.dio),
            checkoutId: checkoutId,
            shopCount: shopCount,
            justPlaced: justPlaced,
            liveSocket: socket,
            onOpenOrder: onOpenOrder,
          ),
        ),
      ),
      locale: locale,
    ));
    if (settle) await tester.pumpAndSettle();
    return server;
  }

  /// Unmounts the screen so its poll and subscriptions end with the test.
  Future<void> done(WidgetTester tester) => tester.pumpWidget(const SizedBox.shrink());

  Finder pinOf(String orderId) => find.byWidgetPredicate(
      (Widget w) => w is CheckoutShopPin && w.order.orderId == orderId);

  List<Polyline<Object>> lines(WidgetTester tester) {
    final Finder layer = find.byType(PolylineLayer<Object>);
    if (layer.evaluate().isEmpty) return const <Polyline<Object>>[];
    return tester.widget<PolylineLayer<Object>>(layer).polylines;
  }

  List<Marker> markers(WidgetTester tester) =>
      tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers;

  /// A widget announced to screen readers as [label] — read off the Semantics widget itself, so
  /// the test needs no semantics tree.
  Finder labelled(String label) => find.byWidgetPredicate(
      (Widget w) => w is Semantics && w.properties.label == label);

  group('before a rider is assigned', () {
    testWidgets('shops, the door and lighter planned lines — no numbers and no estimate',
        (WidgetTester tester) async {
      await pumpMap(tester, (_) => beforeARider());

      expect(find.text(en.checkoutMapTitle(2)), findsOneWidget);
      expect(pinOf(orderA), findsOneWidget);
      expect(pinOf(orderB), findsOneWidget);
      expect(find.byIcon(Icons.location_on), findsOneWidget, reason: 'The door.');
      expect(find.text(en.checkoutMapNoRiderYet), findsNWidgets(2));
      // No fix, no number: not even a reason line, since "no rider yet" already says why.
      expect(find.textContaining('Estimated arrival'), findsNothing);
      expect(find.text(en.etaWaitingFirstFix), findsNothing);
      // Nothing is numbered without a run.
      expect(find.textContaining('Stop '), findsNothing);
      expect(find.descendant(of: pinOf(orderA), matching: find.text('1')), findsNothing);

      final List<Polyline<Object>> drawn = lines(tester);
      expect(drawn, hasLength(2));
      for (final Polyline<Object> line in drawn) {
        expect(line.pattern.segments, isNotNull, reason: 'Straight lines are dashed.');
        expect(line.color.a, lessThan(1), reason: 'Planned is lighter than live.');
      }
      expect(find.text(en.checkoutMapApproximate), findsOneWidget);
      await done(tester);
    });
  });

  group('in progress', () {
    testWidgets('a run numbers its stops — collected as fact, the next as expected — and every '
        'order carries the run\'s estimate, labelled as one', (WidgetTester tester) async {
      await pumpMap(tester, (_) => aRun());

      expect(find.text(en.checkoutMapStop(1)), findsOneWidget);
      expect(find.text(en.checkoutMapStopExpected(2)), findsOneWidget);
      expect(find.descendant(of: pinOf(orderA), matching: find.text('1')), findsOneWidget);
      expect(find.descendant(of: pinOf(orderB), matching: find.text('2')), findsOneWidget);

      expect(find.text(en.checkoutMapRiderHasIt), findsOneWidget);
      expect(find.text(en.checkoutMapRiderToShop), findsOneWidget);
      final BuildContext context = tester.element(find.byType(CheckoutMapScreen));
      final String time = MaterialLocalizations.of(context)
          .formatTimeOfDay(TimeOfDay.fromDateTime(arrival.toLocal()));
      expect(find.text(en.checkoutMapEtaEstimate(time, 9)), findsNWidgets(2));
      expect(find.text(en.etaStraightLineNote), findsNWidgets(2));
      expect(find.text(en.checkoutMapOtherDeliveries), findsNWidgets(2));

      // One marker for the rider, and one live leg drawn solid-coloured and dashed.
      expect(labelled(en.checkoutMapYourRider), findsOneWidget);
      final List<Polyline<Object>> drawn = lines(tester);
      expect(drawn, hasLength(1));
      expect(drawn.single.color.a, 1);
      expect(drawn.single.pattern.segments, isNotNull);
      await done(tester);
    });

    testWidgets('one rider per order: no numbers anywhere', (WidgetTester tester) async {
      await pumpMap(
          tester,
          (_) => view(
                orders: <Map<String, dynamic>>[
                  order(orderA, 'Hamra Bakery', 'READY', shop: shopA, rider: true),
                  order(orderB, 'Achrafieh Pharmacy', 'READY', shop: shopB, rider: true),
                ],
                riders: <Map<String, dynamic>>[
                  riderJson(<String>[orderA], at: shopA),
                  riderJson(<String>[orderB], at: shopB),
                ],
              ));

      expect(find.textContaining('Stop '), findsNothing);
      for (final String id in <String>[orderA, orderB]) {
        expect(find.descendant(of: pinOf(id), matching: find.byType(Text)), findsNothing);
      }
      expect(labelled(en.checkoutMapYourRider), findsNWidgets(2));
      expect(find.text(en.checkoutMapOtherDeliveries), findsNothing);
      await done(tester);
    });

    testWidgets('a rider whose fix is stale is "last seen", with the server\'s reason and no number',
        (WidgetTester tester) async {
      await pumpMap(
          tester,
          (_) => view(
                orders: <Map<String, dynamic>>[
                  order(orderA, 'Hamra Bakery', 'PICKED_UP',
                      shop: shopA, rider: true, etaJson: eta(orderA, reason: 'STALE_FIX')),
                ],
                riders: <Map<String, dynamic>>[
                  riderJson(<String>[orderA],
                      at: shopA, ago: const Duration(minutes: 12), stale: true),
                ],
              ),
          shopCount: null);

      expect(find.text(en.checkoutMapRiderLastSeen(en.minutesAgo(12))), findsOneWidget);
      expect(find.text(custEtaReasonLabel(en, EtaUnavailableReason.staleFix)), findsOneWidget);
      expect(find.textContaining('Estimated arrival'), findsNothing);
      expect(labelled(en.checkoutMapRiderMarkerLastSeen(en.minutesAgo(12))),
          findsOneWidget);
      await done(tester);
    });

    testWidgets('a pushed position glides the rider marker to where the rider now is',
        (WidgetTester tester) async {
      final _FakeSocket socket = _FakeSocket();
      await pumpMap(tester, (_) => aRun(), socket: socket);

      expect(socket.subscribed, unorderedEquals(<String>[
        '/topic/orders/$orderA/position',
        '/topic/orders/$orderB/position',
      ]));

      socket.push(<String, dynamic>{
        'orderId': orderA,
        'riderId': 'rider-sub',
        'lat': 33.8905,
        'lng': 35.5100,
        'accuracyM': 5,
        'recordedAt': DateTime.now().toUtc().toIso8601String(),
      });
      // The frame arrives, the glide starts from where the marker was...
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final Iterable<LatLng> midway = markers(tester).map((Marker m) => m.point);
      expect(midway, isNot(contains(const LatLng(33.8905, 35.5100))),
          reason: 'Mid-glide the marker is on its way, not teleported.');
      expect(midway, isNot(contains(const LatLng(33.8930, 35.5050))));
      // ...and ends where the rider now is.
      await tester.pumpAndSettle();
      expect(markers(tester).map((Marker m) => m.point),
          contains(const LatLng(33.8905, 35.5100)));
      await done(tester);
    });
  });

  group('finished orders', () {
    testWidgets('delivered is ticked with its time; cancelled is dimmed and its row opens the order '
        'page, where the reason is', (WidgetTester tester) async {
      final List<String> opened = <String>[];
      final DateTime deliveredAt = DateTime.now().subtract(const Duration(minutes: 5));
      final FakeServer server = await pumpMap(
          tester,
          (_) => view(orders: <Map<String, dynamic>>[
                order(orderA, 'Hamra Bakery', 'DELIVERED',
                    shop: shopA, rider: true, completedAt: deliveredAt),
                order(orderB, 'Achrafieh Pharmacy', 'CANCELLED', shop: shopB),
              ]),
          onOpenOrder: opened.add);

      final BuildContext context = tester.element(find.byType(CheckoutMapScreen));
      expect(
          find.text(en.checkoutMapDeliveredAt(MaterialLocalizations.of(context)
              .formatTimeOfDay(TimeOfDay.fromDateTime(deliveredAt)))),
          findsOneWidget);
      expect(find.descendant(of: pinOf(orderA), matching: find.byIcon(Icons.check_rounded)),
          findsOneWidget);
      expect(find.descendant(of: pinOf(orderB), matching: find.byIcon(Icons.close_rounded)),
          findsOneWidget);
      expect(find.descendant(of: pinOf(orderB), matching: find.byType(Opacity)), findsOneWidget);
      // Every order finished: a static summary — no lines, no rider, no estimate.
      expect(find.text(en.checkoutMapAllFinished), findsOneWidget);
      expect(lines(tester), isEmpty);
      expect(labelled(en.checkoutMapYourRider), findsNothing);

      await tester.tap(find.text(en.checkoutMapCancelledSeeWhy));
      await tester.pumpAndSettle();
      expect(opened, <String>[orderB]);

      // Nothing is moving, so nothing is asked again.
      final int asked = server.sent('GET', '/api/tracking/checkouts/$checkoutId').length;
      await tester.pump(const Duration(seconds: 45));
      expect(server.sent('GET', '/api/tracking/checkouts/$checkoutId'), hasLength(asked));
      await done(tester);
    });

    testWidgets('without a way to open an order, no row is tappable and none offers a reason',
        (WidgetTester tester) async {
      await pumpMap(
          tester,
          (_) => view(orders: <Map<String, dynamic>>[
                order(orderA, 'Hamra Bakery', 'CANCELLED', shop: shopA),
                order(orderB, 'Achrafieh Pharmacy', 'PREPARING', shop: shopB),
              ]));

      expect(find.text(en.checkoutMapCancelledSeeWhy), findsNothing);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      for (final YdCard card in tester.widgetList<YdCard>(find.byType(YdCard))) {
        expect(card.onTap, isNull);
      }
      await done(tester);
    });

    testWidgets('while an order is live, the view is asked again every fifteen seconds',
        (WidgetTester tester) async {
      final FakeServer server = await pumpMap(tester, (_) => beforeARider());

      final int asked = server.sent('GET', '/api/tracking/checkouts/$checkoutId').length;
      await tester.pump(CheckoutMapScreen.pollInterval);
      await tester.pump();
      expect(server.sent('GET', '/api/tracking/checkouts/$checkoutId'), hasLength(asked + 1));
      await done(tester);
    });
  });

  group('nothing is drawn the platform cannot back up', () {
    testWidgets('a shop with no pin is not drawn and its row says why; no door pin, no door',
        (WidgetTester tester) async {
      await pumpMap(
          tester,
          (_) => view(
                orders: <Map<String, dynamic>>[
                  order(orderA, 'Hamra Bakery', 'PREPARING'),
                  order(orderB, 'Achrafieh Pharmacy', 'PREPARING', shop: shopB),
                ],
                doorPin: null,
              ));

      expect(pinOf(orderA), findsNothing);
      expect(pinOf(orderB), findsOneWidget);
      expect(find.text(en.checkoutMapShopNoPin), findsOneWidget);
      expect(find.byIcon(Icons.location_on), findsNothing);
      expect(find.text(en.checkoutMapDoorNoPin), findsOneWidget);
      expect(lines(tester), isEmpty);
      // No lines drawn, so nothing to call approximate.
      expect(find.text(en.checkoutMapApproximate), findsNothing);
      await done(tester);
    });

    testWidgets('with no pin at all, the map says so instead of showing an empty city',
        (WidgetTester tester) async {
      await pumpMap(
          tester,
          (_) => view(
                orders: <Map<String, dynamic>>[order(orderA, 'Hamra Bakery', 'PREPARING')],
                doorPin: null,
              ),
          shopCount: null);

      expect(find.text(en.checkoutMapNothingToDraw), findsOneWidget);
      await done(tester);
    });

    testWidgets('road geometry is drawn as the road, solid, and never called approximate',
        (WidgetTester tester) async {
      await pumpMap(
          tester,
          (_) => view(
                geometry: 'ROAD',
                orders: <Map<String, dynamic>>[
                  order(orderA, 'Hamra Bakery', 'PREPARING', shop: shopA),
                ],
                paths: <Map<String, dynamic>>[
                  path(<String>[orderA], 'PLANNED', <Map<String, dynamic>>[shopA, door],
                      polyline6: 'oyus_AomzubAfnLgaU_{TweO'),
                ],
              ),
          shopCount: null);

      final Polyline<Object> road = lines(tester).single;
      expect(road.pattern.segments, isNull, reason: 'A road is solid.');
      expect(road.points, const <LatLng>[
        LatLng(33.8938, 35.5018),
        LatLng(33.8869, 35.5131),
        LatLng(33.8981, 35.5214),
      ]);
      expect(find.text(en.checkoutMapApproximate), findsNothing);
      await done(tester);
    });
  });

  group('when the service withholds the rider', () {
    /// Claims often happen at home, so a rider more than 2 km from the shop is not shown. The map
    /// draws no marker and no line, and the row says when they will appear rather than leaving an
    /// empty map to be read as a fault.
    testWidgets('says the rider appears near the shop, and draws neither marker nor line',
        (WidgetTester tester) async {
      await pumpMap(
          tester,
          (_) => view(
                orders: <Map<String, dynamic>>[
                  order(orderA, 'Hamra Bakery', 'READY',
                      shop: shopA, rider: true, etaJson: eta(orderA, available: true)),
                ],
                riders: <Map<String, dynamic>>[
                  riderJson(<String>[orderA], sighting: 'HEADING_TO_SHOP'),
                ],
              ));

      expect(find.text(en.custRiderShownNearShop), findsOneWidget);
      expect(find.byType(CheckoutShopPin), findsOneWidget);
      expect(markers(tester).length, 2, reason: 'The shop and the door, and no rider.');
      expect(lines(tester), isEmpty);
      await done(tester);
    });

    testWidgets('says the rider is finishing another delivery, and shows no number',
        (WidgetTester tester) async {
      await pumpMap(
          tester,
          (_) => view(
                orders: <Map<String, dynamic>>[
                  order(orderA, 'Hamra Bakery', 'PICKED_UP',
                      shop: shopA,
                      rider: true,
                      etaJson: eta(orderA, reason: 'RIDER_ON_ANOTHER_DELIVERY')),
                ],
                riders: <Map<String, dynamic>>[
                  riderJson(<String>[orderA], sighting: 'ON_ANOTHER_DELIVERY'),
                ],
              ));

      expect(find.text(en.etaRiderOnAnotherDelivery), findsOneWidget);
      expect(find.textContaining('Estimated arrival'), findsNothing);
      expect(markers(tester).length, 2);
      expect(lines(tester), isEmpty);
      await done(tester);
    });

    /// The answer said the fix was fresh when it was computed. Minutes later, with refreshes
    /// failing, it is not — and the screen has to say so on its own.
    testWidgets('calls a fix that has aged on screen last seen, though the answer did not',
        (WidgetTester tester) async {
      await pumpMap(
          tester,
          (_) => view(
                orders: <Map<String, dynamic>>[
                  order(orderA, 'Hamra Bakery', 'PICKED_UP', shop: shopA, rider: true),
                ],
                riders: <Map<String, dynamic>>[
                  riderJson(<String>[orderA],
                      at: <String, dynamic>{'lat': 33.8930, 'lng': 35.5050},
                      ago: const Duration(minutes: 6),
                      stale: false),
                ],
              ));

      expect(find.textContaining(en.checkoutMapRiderLastSeen('')), findsOneWidget);
      expect(labelled(en.checkoutMapYourRider), findsNothing);
      await done(tester);
    });
  });

  group('reaching the map', () {
    testWidgets('a checkout still on its way to the tracking service is waited for, briefly',
        (WidgetTester tester) async {
      int asked = 0;
      await pumpMap(tester, (_) {
        asked++;
        return asked < 3 ? const FakeReply(404) : beforeARider();
      }, justPlaced: true, settle: false);

      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump(CheckoutMapScreen.catchUpInterval);
      await tester.pump(CheckoutMapScreen.catchUpInterval);
      await tester.pumpAndSettle();

      expect(pinOf(orderA), findsOneWidget);
      expect(find.text(en.checkoutMapNotFound), findsNothing);
      await done(tester);
    });

    testWidgets('a checkout that is not there says so, and can be asked for again',
        (WidgetTester tester) async {
      final FakeServer server = await pumpMap(tester, (_) => const FakeReply(404),
          justPlaced: true, settle: false);
      for (int i = 0; i <= CheckoutMapScreen.catchUpAttempts; i++) {
        await tester.pump(CheckoutMapScreen.catchUpInterval);
      }
      await tester.pumpAndSettle();

      expect(find.text(en.checkoutMapNotFound), findsOneWidget);
      final int asked = server.sent('GET', '/api/tracking/checkouts/$checkoutId').length;
      await tester.tap(find.text(en.tryAgain));
      await tester.pump(const Duration(milliseconds: 100));
      expect(server.sent('GET', '/api/tracking/checkouts/$checkoutId'), hasLength(asked + 1));
      await done(tester);
    });

    /// An order from before the service kept checkouts has no map and never will. Waiting on it
    /// is ten seconds of spinner before the same answer.
    testWidgets('an older order\'s checkout says so at once, without the catch-up wait',
        (WidgetTester tester) async {
      final FakeServer server =
          await pumpMap(tester, (_) => const FakeReply(404), settle: false);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text(en.checkoutMapNotFound), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(server.sent('GET', '/api/tracking/checkouts/$checkoutId'), hasLength(1));
      await done(tester);
    });

    testWidgets('an Orders card of a multi-shop checkout opens the map from its badge',
        (WidgetTester tester) async {
      // Wide, as the order page's own tests draw it: the test font is wider than any real one.
      phone(tester, size: const Size(1000, 2400));
      final FakeServer server = FakeServer()
        ..on('GET', '/api/orders/mine', (_) => pageJson(<Map<String, dynamic>>[
              _orderJson('o1', 'Hamra Bakery', checkoutId: checkoutId, size: 2),
              _orderJson('o2', 'Achrafieh Pharmacy', checkoutId: checkoutId, size: 2),
              _orderJson('o3', 'Dekkane Abou Selim'),
            ]))
        ..on('GET', '/api/tracking/checkouts/$checkoutId', (_) => beforeARider());
      await tester.pumpWidget(svcApp(Scaffold(
        body: MyOrdersScreen(
          api: OrderApi(server.dio),
          storeApi: StoreApi(server.dio),
          cart: Cart(),
          onOpenBasket: () {},
          checkoutTrackingApi: CheckoutTrackingApi(server.dio),
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.text(en.checkoutMapSeeAll(2)), findsNWidgets(2));
      expect(find.text(en.multiCartPartOfOrder(2)), findsNothing);

      await tester.tap(find.text(en.checkoutMapSeeAll(2)).first);
      await tester.pumpAndSettle();

      expect(find.byType(CheckoutMapScreen), findsOneWidget);
      expect(find.text(en.checkoutMapTitle(2)), findsOneWidget);
      await done(tester);
    });

    testWidgets('an order\'s page opens the map from its badge, and its own row leads back to it',
        (WidgetTester tester) async {
      // Wide, as the order page's own tests draw it: the test font is wider than any real one.
      phone(tester, size: const Size(1000, 2400));
      final FakeServer server = FakeServer()
        ..on('GET', '/api/orders/o-a', (_) => _orderJson(orderA, 'Hamra Bakery',
            checkoutId: checkoutId, size: 2, status: 'DELIVERED'))
        ..on('GET', '/api/tracking/checkouts/$checkoutId', (_) => view(orders: <Map<String, dynamic>>[
              order(orderA, 'Hamra Bakery', 'DELIVERED', shop: shopA, rider: true),
              order(orderB, 'Achrafieh Pharmacy', 'DELIVERED', shop: shopB, rider: true),
            ]));
      await tester.pumpWidget(svcApp(OrderDetailsScreen(
        orderApi: OrderApi(server.dio),
        storeApi: StoreApi(server.dio),
        cart: Cart(),
        orderId: orderA,
        onOpenBasket: () {},
        checkoutTrackingApi: CheckoutTrackingApi(server.dio),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text(en.checkoutMapSeeAll(2)));
      await tester.pumpAndSettle();
      expect(find.byType(CheckoutMapScreen), findsOneWidget);

      // This order's own row: back to its page, not a second copy of it.
      await tester.tap(find.text('Hamra Bakery').last);
      await tester.pumpAndSettle();
      expect(find.byType(CheckoutMapScreen), findsNothing);
      expect(find.byType(OrderDetailsScreen), findsOneWidget);
      await done(tester);
    });

    testWidgets('a basket placed as several shops\' orders hands its checkout to the map, after '
        'moving to Orders', (WidgetTester tester) async {
      phone(tester, size: const Size(1000, 2400));
      final List<String> calls = <String>[];
      Map<String, dynamic> quoteShop(String id, double subtotal) => <String, dynamic>{
            'storeId': id,
            'storeName': 'Shop $id',
            'refusal': null,
            'refusalMessage': null,
            'subtotal': subtotal,
            'minimumOrder': 0,
            'shortfall': 0,
            'deliveryFee': 3,
            'deliveryFeeCharged': 3,
            'expressSurcharge': 0,
            'discountAmount': 0,
            'totalAmount': subtotal + 3,
            'deliveryFeeWaived': false,
          };
      final FakeServer server = FakeServer()
        ..on('POST', '/api/orders/quote', (_) => <String, dynamic>{
              'shops': <dynamic>[quoteShop('s1', 9), quoteShop('s2', 5)],
              'placeable': true,
              'subtotal': 14,
              'deliveryFeeCharged': 6,
              'expressSurcharge': 0,
              'discountAmount': 0,
              'totalAmount': 20,
              'maxShops': 3,
            })
        ..on('POST', '/api/orders/checkout', (_) => FakeReply(201, <String, dynamic>{
              'checkoutId': 'checkout-1',
              'orders': <dynamic>[
                _orderJson('o1', 'Shop s1', checkoutId: 'checkout-1', size: 2),
                _orderJson('o2', 'Shop s2', checkoutId: 'checkout-1', size: 2),
              ],
              'totalAmount': 20,
            }));
      final DeliveryAddressStore addresses = DeliveryAddressStore(ownerId: 'user-1');
      await addresses.select(const DeliveryAddress(line: '12 Rose Street', label: 'Home'));
      final Cart cart = Cart()
        ..add(product('shawarma', 's1', 9), from: storeCard('s1'))
        ..add(product('panadol', 's2', 5), from: storeCard('s2'));
      await tester.pumpWidget(svcApp(CartScreen(
        cart: cart,
        addresses: addresses,
        orderApi: OrderApi(server.dio),
        offerApi: OfferApi(server.dio),
        onOrderPlaced: () => calls.add('orders'),
        onCheckoutPlaced: (String id, int shops) => calls.add('map $id $shops'),
      )));
      await tester.pumpAndSettle();

      // The basket's checkout, then checkout's own button.
      await tester.tap(find.byType(YdPillButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(YdPillButton));
      await tester.pumpAndSettle();

      expect(calls, <String>['orders', 'map checkout-1 2']);
      await done(tester);
    });

    testWidgets('the shell opens that map over the Orders tab, and Back lands on Orders',
        (WidgetTester tester) async {
      phone(tester, size: const Size(390, 1600));
      final FakeServer server = FakeServer()
        ..on('GET', '/api/stores', (_) => pageJson(<Map<String, dynamic>>[storeJson()]))
        ..on('GET', '/api/stores/favorites', (_) => pageJson(const <Map<String, dynamic>>[]))
        ..on('GET', '/api/banners', (_) => <dynamic>[])
        ..on('GET', '/api/categories/chips', (_) => <dynamic>[])
        ..on('GET', '/api/notifications/unread-count', (_) => <String, dynamic>{'unread': 0})
        ..on('GET', '/api/butler/mine', (_) => pageJson(const <Map<String, dynamic>>[]))
        ..on('GET', '/api/orders/mine', (_) => pageJson(const <Map<String, dynamic>>[]))
        ..on('GET', '/api/stores/service-categories', (_) => <String>['PRINTING'])
        ..on('GET', '/api/tracking/checkouts/checkout-1', (_) => beforeARider());
      await tester.pumpWidget(svcApp(CustomerShell(
        storeApi: StoreApi(server.dio),
        orderApi: OrderApi(server.dio),
        notificationApi: NotificationApi(server.dio),
        butlerApi: ButlerApi(server.dio),
        zoneApi: DeliveryZoneApi(server.dio),
        offerApi: OfferApi(server.dio),
        catalogApi: CatalogApi(server.dio),
        checkoutTrackingApi: CheckoutTrackingApi(server.dio),
        session: sessionWith(<DeliveryRole>{DeliveryRole.customer}),
        locale: LocaleController(read: () async => 'en', write: (String _) async {}),
        onSignOut: () async {},
      )));
      await tester.pumpAndSettle();

      // Exactly what the basket does after a multi-shop checkout.
      final CartScreen basket =
          tester.widget<CartScreen>(find.byType(CartScreen, skipOffstage: false));
      expect(basket.onCheckoutPlaced, isNotNull);
      basket.onOrderPlaced();
      basket.onCheckoutPlaced!('checkout-1', 2);
      await tester.pumpAndSettle();

      expect(find.byType(CheckoutMapScreen), findsOneWidget);
      expect(find.text(en.checkoutMapTitle(2)), findsOneWidget);

      await tester.tap(find.byType(YdBackButton));
      await tester.pumpAndSettle();
      expect(find.byType(CheckoutMapScreen), findsNothing);
      expect(find.byType(MyOrdersScreen), findsOneWidget);
      await done(tester);
    });

    testWidgets('without the checkout map, the badge on an order\'s page stays a plain statement',
        (WidgetTester tester) async {
      // Wide, as the order page's own tests draw it: the test font is wider than any real one.
      phone(tester, size: const Size(1000, 2400));
      final FakeServer server = FakeServer()
        ..on('GET', '/api/orders/o-a', (_) => _orderJson(orderA, 'Hamra Bakery',
            checkoutId: checkoutId, size: 2, status: 'DELIVERED'));
      await tester.pumpWidget(svcApp(OrderDetailsScreen(
        orderApi: OrderApi(server.dio),
        storeApi: StoreApi(server.dio),
        cart: Cart(),
        orderId: orderA,
        onOpenBasket: () {},
      )));
      await tester.pumpAndSettle();

      expect(find.text(en.multiCartPartOfOrder(2)), findsOneWidget);
      expect(find.byType(CheckoutMapBadge), findsNothing);
      await done(tester);
    });
  });

  group('at 320dp, text at 130%', () {
    for (final (Locale locale, DeliveryStrings t) in <(Locale, DeliveryStrings)>[
      (const Locale('en'), en),
      (const Locale('ar'), ar),
    ]) {
      testWidgets('a busy run fits without overflow in ${locale.languageCode}',
          (WidgetTester tester) async {
        await pumpMap(
          tester,
          (_) => aRun(
            aName: 'The Very Long Named Hamra Neighbourhood Bakery and Pastry House',
            bName: 'صيدلية الأشرفية الكبرى للأدوية ومستحضرات التجميل والعناية',
          ),
          locale: locale,
          size: const Size(320, 568),
          textScale: 1.3,
          onOpenOrder: (_) {},
        );

        expect(tester.takeException(), isNull);
        expect(find.text(t.checkoutMapStop(1)), findsOneWidget);
        expect(find.text(t.checkoutMapOtherDeliveries), findsWidgets);
        // The map's own height: 40% of the screen, inside the 220–420 clamp.
        expect(tester.getSize(find.byType(OsmBasemap)).height, closeTo(568 * 0.4, 0.01));

        // The second order, scrolled into view, fits as well.
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(t.checkoutMapStopExpected(2)), findsOneWidget);
        await done(tester);
      });
    }

    testWidgets('in Arabic the rows read right to left, while the map is never mirrored',
        (WidgetTester tester) async {
      await pumpMap(tester, (_) => aRun(), locale: const Locale('ar'), onOpenOrder: (_) {});

      expect(
          Directionality.of(tester.element(find.text(ar.checkoutMapStop(1)))), TextDirection.rtl);
      expect(find.byIcon(Icons.chevron_left_rounded), findsNWidgets(2));
      // Achrafieh is east of Hamra, so it is to the right on the map in every language.
      expect(tester.getCenter(pinOf(orderB)).dx, greaterThan(tester.getCenter(pinOf(orderA)).dx));
      await done(tester);

      await pumpMap(tester, (_) => aRun(), onOpenOrder: (_) {});
      expect(tester.getCenter(pinOf(orderB)).dx, greaterThan(tester.getCenter(pinOf(orderA)).dx));
      await done(tester);
    });
  });
}

/// The tracking socket, standing still until a test pushes a frame.
class _FakeSocket implements UserQueueSocket {
  final StreamController<Map<String, dynamic>> _frames =
      StreamController<Map<String, dynamic>>.broadcast();
  final List<String> subscribed = <String>[];

  @override
  final ValueNotifier<bool> connected = ValueNotifier<bool>(true);

  @override
  Stream<Map<String, dynamic>> subscribe(String destination) {
    subscribed.add(destination);
    final String orderId = destination.split('/')[3];
    return _frames.stream.where((Map<String, dynamic> f) => f['orderId'] == orderId);
  }

  void push(Map<String, dynamic> frame) => _frames.add(frame);

  @override
  Future<void> close() => _frames.close();
}

/// An order on the Orders list or its own page.
Map<String, dynamic> _orderJson(String id, String store,
        {String? checkoutId, int? size, String status = 'PLACED'}) =>
    <String, dynamic>{
      'id': id,
      'customerId': 'user-1',
      'merchantId': 'm-$id',
      'riderId': null,
      'status': status,
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
