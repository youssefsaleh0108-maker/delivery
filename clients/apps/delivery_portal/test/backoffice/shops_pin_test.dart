import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/backoffice/shops_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

/// Back office putting a shop on the map.
///
/// The shops that need it are the ones already trading without a pin — twelve of them on dev, three
/// from real sign-ups through the public site. A shop cannot be PUBLISHED without a pin any more,
/// but one that was already listed keeps trading, and until now its own merchant was the only
/// person on the platform who could place it. So back office needs the column, and support needs a
/// way to repair a live shop that no "near you" can find.
///
/// Pinned here: the column says which shops have no pin; the picker is the merchant's own, opened
/// from the row; a saved point reaches `PUT /api/stores/{id}/location` and its circle reaches the
/// radius endpoint, in that order, because the server refuses a circle with no centre; and a
/// refusal is said as what it is and leaves the row alone.
///
/// Tiles never load under `flutter_test`, so the maps here are all in their degraded state — the
/// same condition `delivery_merchant`'s own pin test runs in.
typedef _Answer = ({int status, Object? body});

class _Routes implements HttpClientAdapter {
  _Routes(this.answer);

  final _Answer Function(RequestOptions options) answer;

  final List<String> calls = <String>[];
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    requests.add(options);
    final _Answer a = answer(options);
    return ResponseBody.fromString(
      jsonEncode(a.body),
      a.status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType]
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _card({
  String id = 'store-grill-1',
  String name = 'Abu Hassan Mini Market',
  double? latitude,
  double? longitude,
}) =>
    <String, dynamic>{
      'id': id,
      'slug': id,
      'name': name,
      'vertical': 'GROCERY',
      'tagline': 'Round the corner since 1998',
      'ratingCount': 0,
      'deliveryFee': 0,
      'minOrder': 0,
      'etaMinMinutes': 20,
      'etaMaxMinutes': 40,
      'availability': 'OPEN',
      'verifiedLocal': false,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    };

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  late _Routes routes;
  late List<Map<String, dynamic>> shops;
  late int writeStatus;

  setUp(() {
    shops = <Map<String, dynamic>>[_card()];
    writeStatus = 200;
    routes = _Routes((RequestOptions o) {
      if (o.method == 'GET') {
        return (
          status: 200,
          body: <String, dynamic>{
            'content': shops,
            'page': 0,
            'totalElements': shops.length,
            'totalPages': 1,
          },
        );
      }
      if (writeStatus != 200) {
        return (status: writeStatus, body: <String, dynamic>{'status': writeStatus});
      }
      // Every write answers with the shop as the server now holds it.
      return (
        status: 200,
        body: <String, dynamic>{
          ..._card(latitude: 33.8938, longitude: 35.5018),
          'status': 'ACTIVE',
        },
      );
    });
  });

  Future<void> pump(WidgetTester tester, {Size size = const Size(1440, 1200)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = routes;
    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: Scaffold(body: ShopsScreen(api: StoreApi(dio))),
    ));
    await tester.pumpAndSettle();
  }

  /// The row's pin control, found by the tooltip it carries rather than by position.
  Future<void> openPicker(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
  }

  testWidgets('a listed shop with no pin says so', (WidgetTester tester) async {
    await pump(tester);

    expect(find.text(en.boShopNoPin), findsOneWidget);
    expect(find.text(en.boShopPinned), findsNothing);
    expect(find.byTooltip(en.boShopSetPin), findsOneWidget);
  });

  testWidgets('a shop that has one says that instead, and offers to move it',
      (WidgetTester tester) async {
    shops = <Map<String, dynamic>>[_card(latitude: 33.8938, longitude: 35.5018)];
    await pump(tester);

    expect(find.text(en.boShopPinned), findsOneWidget);
    expect(find.byTooltip(en.boShopMovePin), findsOneWidget);
  });

  testWidgets('opening the picker writes nothing', (WidgetTester tester) async {
    await pump(tester);
    await openPicker(tester, en.boShopSetPin);

    expect(find.text(en.merchPinShopLocation), findsOneWidget);
    expect(routes.calls.where((String c) => c.contains('/location')), isEmpty);
  });

  testWidgets('a point saved from the row reaches the pin endpoint, then the radius',
      (WidgetTester tester) async {
    await pump(tester);
    await openPicker(tester, en.boShopSetPin);

    await tester.tapAt(tester.getCenter(find.byType(FlutterMap).last));
    // The map's tap detector holds the tap briefly to see whether a second one is coming.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    await tester.tap(find.text(en.save));
    await tester.pumpAndSettle();

    final List<String> writes =
        routes.calls.where((String c) => c.startsWith('PUT') || c.startsWith('POST')).toList();
    // Pin first, circle second: a delivery circle needs a centre, and the server refuses a radius
    // on a shop with no pin.
    expect(writes, <String>[
      'PUT /api/stores/store-grill-1/location',
      'POST /api/stores/store-grill-1/delivery-radius',
    ]);
    expect(find.text(en.boShopPinSaved), findsOneWidget);
    // And the row now reads back what the server stored, without waiting for a page reload.
    expect(find.text(en.boShopPinned), findsOneWidget);
  });

  testWidgets('Save stays inert until there is a point, so no default is ever written',
      (WidgetTester tester) async {
    await pump(tester);
    await openPicker(tester, en.boShopSetPin);

    await tester.tap(find.text(en.save));
    await tester.pumpAndSettle();

    expect(routes.calls.where((String c) => c.contains('/location')), isEmpty);
  });

  testWidgets('a shop that has gone says so, and the row is left as it was',
      (WidgetTester tester) async {
    writeStatus = 404;
    await pump(tester);
    await openPicker(tester, en.boShopSetPin);

    await tester.tapAt(tester.getCenter(find.byType(FlutterMap).last));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.save));
    await tester.pumpAndSettle();

    expect(find.text(en.boShopPinGone), findsOneWidget);
    expect(find.text(en.boShopNoPin), findsOneWidget);
  });

  testWidgets('any other refusal is said plainly and changes nothing',
      (WidgetTester tester) async {
    writeStatus = 403;
    await pump(tester);
    await openPicker(tester, en.boShopSetPin);

    await tester.tapAt(tester.getCenter(find.byType(FlutterMap).last));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.save));
    await tester.pumpAndSettle();

    expect(find.text(en.boShopPinFailed), findsOneWidget);
    expect(find.text(en.boShopNoPin), findsOneWidget);
  });
}
