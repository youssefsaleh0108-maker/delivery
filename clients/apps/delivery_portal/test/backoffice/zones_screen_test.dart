import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/backoffice/zones_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The back office placing delivery areas on the merchant demand map.
///
/// A centre is optional, and an area without one keeps working everywhere — it is simply missing
/// from every shop's Demand Radar map. So three things are pinned. The list says which areas are on
/// that map. A centre is saved whole or not at all: half a centre would draw the area on the equator,
/// and a refusal after the dialog closed would cost the operator what they typed. And an area comes
/// off the map only when the operator empties both boxes: an edit that sends no centre keeps the one
/// stored, so taking it off has to be said, and is said only when it was meant.
class _ZonesAdapter implements HttpClientAdapter {
  _ZonesAdapter({bool placed = false})
      : hamra = <String, dynamic>{
          'id': 'z-1',
          'name': 'Hamra',
          'region': 'Beirut',
          'sortOrder': 10,
          'active': true,
          'centerLat': placed ? 33.8959 : null,
          'centerLng': placed ? 35.4787 : null,
        };

  Map<String, dynamic> hamra;

  final List<String> calls = <String>[];
  final List<Object?> bodies = <Object?>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    bodies.add(options.data);
    if (options.method == 'PUT') {
      final Map<String, dynamic> body = options.data as Map<String, dynamic>;
      // What Product Service does with an edit: no centre in the body keeps the stored one, and only
      // an explicit clearCentre takes it off.
      hamra = <String, dynamic>{
        ...hamra,
        'name': body['name'],
        'region': body['region'],
        'sortOrder': body['sortOrder'],
        if (body['clearCentre'] == true) ...<String, dynamic>{'centerLat': null, 'centerLng': null},
        if (body['centerLat'] != null) 'centerLat': body['centerLat'],
        if (body['centerLng'] != null) 'centerLng': body['centerLng'],
      };
      return _json(hamra);
    }
    return _json(<Map<String, dynamic>>[hamra]);
  }

  static ResponseBody _json(Object body) => ResponseBody.fromString(jsonEncode(body), 200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      });

  @override
  void close({bool force = false}) {}
}

final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

Future<_ZonesAdapter> _pump(WidgetTester tester, {bool placed = false}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final _ZonesAdapter adapter = _ZonesAdapter(placed: placed);
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;
  await tester.pumpWidget(MaterialApp(
    theme: DeliveryTheme.light(),
    localizationsDelegates: DeliveryStrings.localizationsDelegates,
    supportedLocales: DeliveryStrings.supportedLocales,
    home: ZonesScreen(api: DeliveryZoneApi(dio)),
  ));
  await tester.pumpAndSettle();
  return adapter;
}

Future<void> _openEdit(WidgetTester tester) async {
  await tester.tap(find.text('Edit'));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

/// The body of the last edit sent.
Map<String, dynamic> _lastPut(_ZonesAdapter adapter) {
  final int put = adapter.calls.lastIndexWhere((String c) => c == 'PUT /api/delivery-zones/z-1');
  expect(put, isNot(-1), reason: 'no edit was sent');
  return adapter.bodies[put] as Map<String, dynamic>;
}

void main() {
  testWidgets('an unplaced area says it is not on the demand map', (WidgetTester tester) async {
    await _pump(tester);

    expect(find.textContaining(en.heatmapZoneNotOnMap), findsOneWidget);
    expect(find.textContaining(en.heatmapZoneOnMap), findsNothing);
  });

  testWidgets('half a centre is refused in the dialog and never sent', (WidgetTester tester) async {
    final _ZonesAdapter adapter = await _pump(tester);
    await _openEdit(tester);

    await tester.enterText(_field(en.heatmapZoneCentreLatitude), '33.8959');
    await _save(tester);

    expect(find.text(en.heatmapZoneCentreBoth), findsOneWidget);
    expect(adapter.calls.where((String c) => c.startsWith('PUT')), isEmpty);
  });

  testWidgets('a latitude past the pole is refused before it reaches the server',
      (WidgetTester tester) async {
    final _ZonesAdapter adapter = await _pump(tester);
    await _openEdit(tester);

    await tester.enterText(_field(en.heatmapZoneCentreLatitude), '95');
    await tester.enterText(_field(en.heatmapZoneCentreLongitude), '35.4787');
    await _save(tester);

    expect(find.text(en.heatmapZoneCentreLatRange), findsOneWidget);
    expect(adapter.calls.where((String c) => c.startsWith('PUT')), isEmpty);
  });

  testWidgets('a whole centre is saved with the area, and the list then shows it on the map',
      (WidgetTester tester) async {
    final _ZonesAdapter adapter = await _pump(tester);
    await _openEdit(tester);

    await tester.enterText(_field(en.heatmapZoneCentreLatitude), '33.8959');
    await tester.enterText(_field(en.heatmapZoneCentreLongitude), '35.4787');
    await _save(tester);

    final Map<String, dynamic> sent = _lastPut(adapter);
    expect(sent['centerLat'], 33.8959);
    expect(sent['centerLng'], 35.4787);
    expect(sent['name'], 'Hamra');
    expect(sent.containsKey('clearCentre'), isFalse);

    expect(find.textContaining(en.heatmapZoneOnMap), findsOneWidget);
    expect(find.textContaining(en.heatmapZoneNotOnMap), findsNothing);
  });

  testWidgets('renaming a placed area without touching its centre leaves it on the map',
      (WidgetTester tester) async {
    final _ZonesAdapter adapter = await _pump(tester, placed: true);
    await _openEdit(tester);

    await tester.enterText(_field('Area name'), 'Hamra Street');
    await _save(tester);

    final Map<String, dynamic> sent = _lastPut(adapter);
    expect(sent['name'], 'Hamra Street');
    expect(sent.containsKey('clearCentre'), isFalse);
    expect(find.text('Hamra Street'), findsOneWidget);
    expect(find.textContaining(en.heatmapZoneOnMap), findsOneWidget);
  });

  testWidgets('emptying both boxes of a placed area takes it off the map, and says so',
      (WidgetTester tester) async {
    final _ZonesAdapter adapter = await _pump(tester, placed: true);
    await _openEdit(tester);

    await tester.enterText(_field(en.heatmapZoneCentreLatitude), '');
    await tester.enterText(_field(en.heatmapZoneCentreLongitude), '');
    await _save(tester);

    final Map<String, dynamic> sent = _lastPut(adapter);
    expect(sent['clearCentre'], isTrue);
    expect(sent.containsKey('centerLat'), isFalse);
    expect(sent.containsKey('centerLng'), isFalse);
    expect(find.textContaining(en.heatmapZoneNotOnMap), findsOneWidget);
  });

  testWidgets('saving an area whose boxes opened empty asks for nothing to be cleared',
      (WidgetTester tester) async {
    // Another tab may have placed the area since this dialog opened; boxes nobody emptied must not
    // take that away.
    final _ZonesAdapter adapter = await _pump(tester);
    await _openEdit(tester);

    await _save(tester);

    final Map<String, dynamic> sent = _lastPut(adapter);
    expect(sent.containsKey('clearCentre'), isFalse);
    expect(sent.containsKey('centerLat'), isFalse);
    expect(sent.containsKey('centerLng'), isFalse);
  });
}
