import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/order_tracking_panel.dart';

/// What a customer's tracking panel shows of the rider, now that the tracking service decides.
///
/// Before pickup there is a rider to show and no trail: the rider's dot comes from what the
/// service says the customer may see, never from the trail's last point, and the frames pushed
/// while the order is still READY move the dot without drawing a line through where the rider
/// claimed it — often their home. When the service withholds the rider (still far from the shop,
/// or on somebody else's delivery), the panel says so instead of showing a spinner.
void main() {
  group('the rider on the customer\'s map', () {
    testWidgets('before pickup the rider is shown from the sighting, with no line and no count',
        (WidgetTester tester) async {
      final _Server server = _Server(state: 'VISIBLE');
      await _pump(tester, server, status: 'READY');
      final DeliveryStrings t = _t(tester);

      // Something to show, so no "waiting" sentence is over the map.
      expect(find.text(t.waitingForRider), findsNothing);
      expect(find.text(t.custRiderShownNearShop), findsNothing);
      // And no trail: nothing recorded before pickup, so nothing counted; the card says when the
      // line starts.
      expect(find.text(t.fixes), findsNothing);
      expect(find.text(t.custRouteAfterPickup), findsOneWidget);
    });

    testWidgets('pushed frames before pickup move the dot and never extend the line',
        (WidgetTester tester) async {
      final _Server server = _Server(state: 'NO_FIX');
      final _Socket socket = _Socket();
      await _pump(tester, server, status: 'READY', socket: socket);
      final DeliveryStrings t = _t(tester);
      expect(find.text(t.waitingForRider), findsOneWidget);

      socket.push(_frame(onTrail: false));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();

      expect(find.text(t.waitingForRider), findsNothing, reason: 'The dot is on the map.');
      expect(find.text(t.fixes), findsNothing, reason: 'But it is not a line.');

      socket.push(_frame(onTrail: true, lat: 33.8950));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();

      expect(find.text(t.fixes), findsOneWidget, reason: 'After pickup, the line begins.');
    });

    testWidgets('still far from the shop: the estimate, and why the rider is not on the map',
        (WidgetTester tester) async {
      final _Server server = _Server(state: 'HEADING_TO_SHOP', eta: <String, dynamic>{
        'available': true,
        'leg': 'TO_PICKUP',
        'remainingMetres': 5200.0,
        'remainingSeconds': 900,
      });
      await _pump(tester, server, status: 'READY');
      final DeliveryStrings t = _t(tester);

      expect(find.text(t.custRiderShownNearShop), findsOneWidget);
      expect(find.text('15 ${t.etaMinShort}'), findsOneWidget);
      expect(find.textContaining(t.etaHeadingToShop), findsOneWidget);
    });

    testWidgets('on another customer\'s delivery: said in words, with no number and no rider',
        (WidgetTester tester) async {
      final _Server server = _Server(state: 'ON_ANOTHER_DELIVERY', eta: <String, dynamic>{
        'available': false,
        'reason': 'RIDER_ON_ANOTHER_DELIVERY',
      });
      await _pump(tester, server, status: 'PICKED_UP');
      final DeliveryStrings t = _t(tester);

      // Over the map, and under the headline.
      expect(find.text(t.etaRiderOnAnotherDelivery), findsNWidgets(2));
      expect(find.text(t.fixes), findsNothing);
      expect(find.textContaining(t.etaMinShort), findsNothing);
    });

    testWidgets('a tracking service without the sighting read still shows the trail\'s last point',
        (WidgetTester tester) async {
      final _Server server = _Server(state: null, trail: <Map<String, dynamic>>[_fix(33.8938)]);
      await _pump(tester, server, status: 'PICKED_UP');
      final DeliveryStrings t = _t(tester);

      expect(find.text(t.fixes), findsOneWidget);
      // "Last seen" has a time, not a dash: the rider is the trail's last point, as before.
      expect(find.text('—'), findsNothing);
    });
  });
}

// ---------------------------------------------------------------------------------------- rig

const String _orderId = 'order-1';

DeliveryStrings _t(WidgetTester tester) =>
    DeliveryStrings.of(tester.element(find.byType(OrderTrackingPanel)));

Map<String, dynamic> _fix(double lat, {double lng = 35.5018}) => <String, dynamic>{
      'orderId': _orderId,
      'riderId': 'rider-sub',
      'lat': lat,
      'lng': lng,
      'accuracyM': 6,
      'recordedAt': '2026-09-19T10:00:00Z',
    };

Map<String, dynamic> _frame({required bool onTrail, double lat = 33.8938}) =>
    <String, dynamic>{..._fix(lat), 'onTrail': onTrail};

Future<void> _pump(WidgetTester tester, _Server server,
    {required String status, _Socket? socket}) async {
  tester.view.physicalSize = const Size(420, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = server;
  final DeliveryOrder order = DeliveryOrder.fromJson(<String, dynamic>{
    'id': _orderId,
    'customerId': 'customer-sub',
    'merchantId': 'merchant-1',
    'riderId': 'rider-sub',
    'status': status,
    'totalAmount': 12.5,
    'storeName': 'Abu Hassan',
    'deliveryAddress': 'Hamra Street, Beirut',
    'placedAt': '2026-09-19T09:30:00Z',
  });
  await tester.pumpWidget(MaterialApp(
    theme: DeliveryTheme.light(),
    localizationsDelegates: DeliveryStrings.localizationsDelegates,
    supportedLocales: DeliveryStrings.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: OrderTrackingPanel(
          api: OrderApi(dio),
          order: order,
          trackingApi: TrackingApi(dio),
          liveSocket: socket,
        ),
      ),
    ),
  ));
  for (int i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The tracking service's three reads for one order: the trail, the sighting and the ETA.
class _Server implements HttpClientAdapter {
  _Server({
    required this.state,
    this.trail = const <Map<String, dynamic>>[],
    Map<String, dynamic>? eta,
  }) : eta = eta ?? <String, dynamic>{'available': false, 'reason': 'NO_FIX'};

  /// The sighting's state, or null for a service that predates the read (404).
  final String? state;
  final List<Map<String, dynamic>> trail;
  final Map<String, dynamic> eta;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    final String path = options.path;
    Object body = <String, dynamic>{};
    int status = 200;
    if (path == '/api/tracking/orders/$_orderId/history') {
      body = trail;
    } else if (path == '/api/tracking/orders/$_orderId/rider') {
      final String? state = this.state;
      if (state == null) {
        status = 404;
      } else {
        body = <String, dynamic>{
          'orderId': _orderId,
          'state': state,
          'position': state == 'VISIBLE' ? _fix(33.8938) : null,
        };
      }
    } else if (path == '/api/tracking/orders/$_orderId/eta') {
      body = <String, dynamic>{'orderId': _orderId, 'provider': 'OSRM', ...eta};
    } else {
      status = 404;
    }
    return ResponseBody.fromString(jsonEncode(body), status, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

class _Socket implements UserQueueSocket {
  final StreamController<Map<String, dynamic>> _frames =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  final ValueNotifier<bool> connected = ValueNotifier<bool>(true);

  @override
  Stream<Map<String, dynamic>> subscribe(String destination) => _frames.stream;

  void push(Map<String, dynamic> frame) => _frames.add(frame);

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
