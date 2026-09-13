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
/// from every shop's Demand Radar map. So two things are pinned: the list says which areas are on
/// that map, and a centre is saved whole or not at all. Half a centre would draw the area on the
/// equator; the server refuses it too, but a refusal after the dialog closed would cost the operator
/// what they typed.
class _ZonesAdapter implements HttpClientAdapter {
  Map<String, dynamic> hamra = <String, dynamic>{
    'id': 'z-1',
    'name': 'Hamra',
    'region': 'Beirut',
    'sortOrder': 10,
    'active': true,
    'centerLat': null,
    'centerLng': null,
  };

  final List<String> calls = <String>[];
  final List<Object?> bodies = <Object?>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    bodies.add(options.data);
    if (options.method == 'PUT') {
      hamra = <String, dynamic>{...hamra, ...(options.data as Map<String, dynamic>)};
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

Future<_ZonesAdapter> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final _ZonesAdapter adapter = _ZonesAdapter();
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

Finder _field(String label) => find.widgetWithText(TextFormField, label);

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
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text(en.heatmapZoneCentreBoth), findsOneWidget);
    expect(adapter.calls.where((String c) => c.startsWith('PUT')), isEmpty);
  });

  testWidgets('a latitude past the pole is refused before it reaches the server',
      (WidgetTester tester) async {
    final _ZonesAdapter adapter = await _pump(tester);
    await _openEdit(tester);

    await tester.enterText(_field(en.heatmapZoneCentreLatitude), '95');
    await tester.enterText(_field(en.heatmapZoneCentreLongitude), '35.4787');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text(en.heatmapZoneCentreLatRange), findsOneWidget);
    expect(adapter.calls.where((String c) => c.startsWith('PUT')), isEmpty);
  });

  testWidgets('a whole centre is saved with the area, and the list then shows it on the map',
      (WidgetTester tester) async {
    final _ZonesAdapter adapter = await _pump(tester);
    await _openEdit(tester);

    await tester.enterText(_field(en.heatmapZoneCentreLatitude), '33.8959');
    await tester.enterText(_field(en.heatmapZoneCentreLongitude), '35.4787');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final int put = adapter.calls.indexWhere((String c) => c == 'PUT /api/delivery-zones/z-1');
    expect(put, isNot(-1));
    final Map<String, dynamic> sent = adapter.bodies[put] as Map<String, dynamic>;
    expect(sent['centerLat'], 33.8959);
    expect(sent['centerLng'], 35.4787);
    expect(sent['name'], 'Hamra');

    expect(find.textContaining(en.heatmapZoneOnMap), findsOneWidget);
    expect(find.textContaining(en.heatmapZoneNotOnMap), findsNothing);
  });
}
