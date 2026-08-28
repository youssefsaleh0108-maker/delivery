import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shop's map pin.
///
/// The shop-config frame has always drawn a map slot and the screen has always filled it with a
/// styled lattice and a "Soon" chip, because nothing carried coordinates. `PUT/DELETE
/// /api/stores/{id}/location` and the store's own `latitude`/`longitude` mean it can be a real map
/// now, and this pins the three things that must hold: an unpinned shop says so rather than
/// showing a marker somewhere plausible, the picker's Save reaches the pin endpoint and not the
/// profile one, and a map whose tiles will not load falls back to the slot the screen drew before
/// maps existed rather than to a grey grid.
///
/// Tiles never load under `flutter_test` — the test HttpClient refuses every request — so every
/// map here is in its degraded state by design. That is the state worth testing hardest.
class _StoreAdapter implements HttpClientAdapter {
  _StoreAdapter({this.pinned = false});

  final bool pinned;

  /// Every method+path the screen reached for, so a test can say which endpoint a button hit.
  final List<String> calls = <String>[];

  Map<String, dynamic> get store => <String, dynamic>{
        'id': 'store-1',
        'slug': 'falafel-king',
        'name': 'Falafel King',
        'vertical': 'RESTAURANT',
        'availability': 'OPEN',
        'address': 'Hamra Street, Beirut',
        'deliveryFee': 2.5,
        'minOrder': 10.0,
        'etaMinMinutes': 20,
        'etaMaxMinutes': 40,
        if (pinned) 'latitude': 33.8938,
        if (pinned) 'longitude': 35.5018,
      };

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');

    Object body;
    if (options.path.endsWith('/hours')) {
      body = <dynamic>[];
    } else if (options.path.endsWith('/mine')) {
      body = <String, dynamic>{
        'content': <Map<String, dynamic>>[store],
        'page': 0,
        'size': 20,
        'totalElements': 1,
        'totalPages': 1,
      };
    } else {
      // Every write on this screen answers with the store.
      body = store;
    }

    return ResponseBody.fromString(jsonEncode(body), 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

Future<_StoreAdapter> _pump(WidgetTester tester,
    {bool pinned = false, Locale locale = const Locale('en')}) async {
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final _StoreAdapter adapter = _StoreAdapter(pinned: pinned);
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;

  await tester.pumpWidget(MaterialApp(
    theme: DeliveryTheme.light(),
    locale: locale,
    localizationsDelegates: DeliveryStrings.localizationsDelegates,
    supportedLocales: DeliveryStrings.supportedLocales,
    home: StoreScreen(api: StoreApi(dio)),
  ));
  await tester.pumpAndSettle();
  return adapter;
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  testWidgets('the map slot is a map now, not a promise', (WidgetTester tester) async {
    await _pump(tester);

    // The chip that stood in for the feature is gone from this screen entirely.
    expect(find.byType(YdComingSoon), findsNothing);
    expect(find.text(en.merchbMapPreviewSoon), findsNothing);
    expect(find.byType(StorePinPreview), findsOneWidget);
  });

  testWidgets('a shop with no pin says so instead of drawing one somewhere plausible',
      (WidgetTester tester) async {
    await _pump(tester);

    expect(find.textContaining(en.merchPinNoneYet), findsOneWidget);
    expect(find.textContaining(en.addressPinnedOnMap), findsNothing);
  });

  testWidgets('a pinned shop is shown as pinned', (WidgetTester tester) async {
    await _pump(tester, pinned: true);

    expect(find.textContaining(en.addressPinnedOnMap), findsOneWidget);
  });

  testWidgets('the slot keeps the size the frame gives it', (WidgetTester tester) async {
    await _pump(tester);

    // 100px is the frame's map thumbnail. A real map that grew the slot would push the operating
    // card down the page on every shop-config screen in both hosts.
    expect(tester.getSize(find.byType(StorePinPreview)).height, 100);
  });

  testWidgets('tiles that will not load fall back to the styled slot, never a grey grid',
      (WidgetTester tester) async {
    await _pump(tester);

    // Two failure shapes, and this environment is the quiet one: the requests do not come back at
    // all rather than coming back refused. The map gives itself a deadline for exactly this.
    expect(find.text(en.merchMapUnavailable), findsNothing,
        reason: 'a map still waiting for its tiles has not failed yet');

    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();

    expect(find.text(en.merchMapUnavailable), findsOneWidget);
    expect(find.byType(MapSlotPlaceholder), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the picker opens from the slot and can be dismissed',
      (WidgetTester tester) async {
    final _StoreAdapter adapter = await _pump(tester);

    await tester.tap(find.byType(StorePinPreview));
    await tester.pumpAndSettle();

    expect(find.text(en.merchPinShopLocation), findsOneWidget);
    // Nothing is written by opening a picker.
    expect(adapter.calls.where((String c) => c.contains('/location')), isEmpty);

    Navigator.of(tester.element(find.text(en.merchPinShopLocation))).pop();
    await tester.pumpAndSettle();
    expect(find.text(en.merchPinShopLocation), findsNothing);
  });

  testWidgets('Save is inert until there is a point to save', (WidgetTester tester) async {
    final _StoreAdapter adapter = await _pump(tester);

    await tester.tap(find.byType(StorePinPreview));
    await tester.pumpAndSettle();

    // No pin to start from, and the map cannot be tapped because its tiles are gone. Pressing
    // Save must therefore do nothing at all rather than saving a default point.
    await tester.tap(find.text(en.save));
    await tester.pumpAndSettle();

    expect(adapter.calls.where((String c) => c.contains('/location')), isEmpty);
  });

  testWidgets('a point tapped on the map is saved through the pin endpoint',
      (WidgetTester tester) async {
    final _StoreAdapter adapter = await _pump(tester);

    await tester.tap(find.byType(StorePinPreview));
    await tester.pumpAndSettle();

    // Somewhere inside the picker's map — the later of the two on screen, the slot's own preview
    // being deliberately inert.
    await tester.tapAt(tester.getCenter(find.byType(FlutterMap).last));
    // The map's tap detector holds the tap briefly to see whether a second one is coming.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    await tester.tap(find.text(en.save));
    await tester.pumpAndSettle();

    // The pin has its own endpoint for a reason: a profile save with two coordinates bolted on
    // would clear the pin on every tagline edit made by a client that did not know about them.
    expect(adapter.calls, contains('PUT /api/stores/store-1/location'));
    expect(adapter.calls.where((String c) => c == 'PUT /api/stores/store-1'), isEmpty);
    expect(find.text(en.merchPinSaved), findsOneWidget);
  });

  testWidgets('a pinned shop can have its pin removed, through the pin endpoint',
      (WidgetTester tester) async {
    final _StoreAdapter adapter = await _pump(tester, pinned: true);

    await tester.tap(find.byType(StorePinPreview));
    await tester.pumpAndSettle();

    await tester.tap(find.text(en.remove));
    await tester.pumpAndSettle();

    // Its own call, not a profile save with two nulls in it — which is how a client that did not
    // know the fields existed would silently unpin a shop on every tagline edit.
    expect(adapter.calls, contains('DELETE /api/stores/store-1/location'));
    expect(find.text(en.merchPinCleared), findsOneWidget);
  });

  testWidgets('a shop with no pin is not offered a Remove it cannot use',
      (WidgetTester tester) async {
    await _pump(tester);

    await tester.tap(find.byType(StorePinPreview));
    await tester.pumpAndSettle();

    expect(find.text(en.remove), findsNothing);
  });

  testWidgets('the picker is translated, and lays out right to left',
      (WidgetTester tester) async {
    await _pump(tester, locale: const Locale('ar'));

    expect(find.textContaining(ar.merchPinNoneYet), findsOneWidget);

    await tester.tap(find.byType(StorePinPreview));
    await tester.pumpAndSettle();

    expect(find.text(ar.merchPinShopLocation), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text(ar.merchPinShopLocation))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the required OpenStreetMap credit is on the map itself',
      (WidgetTester tester) async {
    // Not a string the app owns — it is the licence's own credit line, so it is asserted verbatim.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: OsmAttributionLabel())),
    ));
    await tester.pumpAndSettle();

    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
  });
}
