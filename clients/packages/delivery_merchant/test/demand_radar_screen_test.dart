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

/// Demand Radar (Figma 121:8) — the merchant's view of which neighbourhoods around the shop are
/// ordering.
///
/// The screen's job is to be honest about three different silences: a shop the platform cannot place
/// yet, a neighbourhood too quiet to show without describing somebody, and a refresh that failed.
/// Each has its own words, and none of them is an empty map pretending to be a quiet city. What is
/// pinned beside that: levels and never counts, the last good map kept through a failed refresh with
/// the LIVE badge withdrawn, a window change that asks again, and a poll that stops with the screen.
class _DensityAdapter implements HttpClientAdapter {
  _DensityAdapter(this.answers);

  /// One per request, in order; the last one repeats. A map is a 200 body, an int an error status.
  final List<Object> answers;
  final List<RequestOptions> calls = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add(options);
    final Object answer = answers[(calls.length - 1).clamp(0, answers.length - 1)];
    final Map<String, List<String>> headers = <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    };
    if (answer is int) {
      return ResponseBody.fromString('{"detail":"unavailable"}', answer, headers: headers);
    }
    return ResponseBody.fromString(jsonEncode(answer), 200, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _density({
  int areasAround = 3,
  String? region = 'Beirut',
  int window = 60,
  List<Map<String, dynamic>> zones = const <Map<String, dynamic>>[],
}) =>
    <String, dynamic>{
      'storeId': 'store-1',
      'region': region,
      'windowMinutes': window,
      'generatedAt': '2026-09-13T10:00:00Z',
      'minimumCustomers': 5,
      'areasAround': areasAround,
      'zones': zones,
    };

Map<String, dynamic> _area(String name, String level, {double? lat, double? lng}) =>
    <String, dynamic>{
      'zoneId': 'z-$name',
      'name': name,
      'centerLat': lat,
      'centerLng': lng,
      'level': level,
    };

final Map<String, dynamic> _busy = _density(zones: <Map<String, dynamic>>[
  _area('Mar Mikhael', 'HIGH', lat: 33.8981, lng: 35.5244),
  _area('Hamra', 'MEDIUM', lat: 33.8959, lng: 35.4787),
  // Around the shop, but the back office never placed it.
  _area('Verdun', 'LOW'),
]);

final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

Future<_DensityAdapter> _pump(
  WidgetTester tester,
  List<Object> answers, {
  String? storeId = 'store-1',
  Locale locale = const Locale('en'),
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final _DensityAdapter adapter = _DensityAdapter(answers);
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;

  await tester.pumpWidget(MaterialApp(
    theme: DeliveryTheme.light(),
    locale: locale,
    localizationsDelegates: DeliveryStrings.localizationsDelegates,
    supportedLocales: DeliveryStrings.supportedLocales,
    home: DemandRadarScreen(api: DemandApi(dio), storeId: storeId, onBack: () {}),
  ));
  await _settle(tester);
  return adapter;
}

/// Lets a request answer and the frame after it draw, without waiting on a spinner that never ends.
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('draws the busy areas and lists every one, with levels and never a count',
      (WidgetTester tester) async {
    final _DensityAdapter adapter = await _pump(tester, <Object>[_busy]);

    expect(adapter.calls.single.path, '/api/orders/demand/density');
    expect(adapter.calls.single.queryParameters,
        <String, dynamic>{'storeId': 'store-1', 'windowMinutes': 60});

    // On the map, labelled as the frame draws them.
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('Mar Mikhael (High)'), findsOneWidget);
    expect(find.text('Hamra (Med)'), findsOneWidget);
    // An unplaced area cannot be drawn, so it is listed and said to be off the map.
    expect(find.text('Verdun (Low)'), findsNothing);
    expect(find.text('Verdun'), findsOneWidget);
    expect(find.text(en.heatmapNotOnMap), findsOneWidget);

    expect(find.text(en.heatmapAreasTitle), findsOneWidget);
    expect(find.text('Beirut'), findsOneWidget);
    expect(find.text(en.carrBadgeLive), findsOneWidget);
    expect(find.text(en.heatmapLiveSyncing), findsOneWidget);
    // No figure on the map or in the list: the endpoint carries none, and nothing here invents one.
    expect(
      find.descendant(of: find.byType(YdCard), matching: find.textContaining(RegExp(r'\d'))),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed refresh keeps the last good map, withdraws LIVE and says so',
      (WidgetTester tester) async {
    final _DensityAdapter adapter = await _pump(tester, <Object>[_busy, 503]);

    await tester.pump(const Duration(seconds: 61));
    await _settle(tester);

    expect(adapter.calls, hasLength(2));
    // The last good answer is still on screen. Its map labels may be gone by now — a minute is well
    // past the tiles' deadline in a test with no network, which is the fallback's own case below —
    // so the list is what proves it.
    expect(find.text('Mar Mikhael'), findsOneWidget);
    expect(find.text(en.carrBadgeLive), findsNothing);
    expect(find.text(en.heatmapCantRefresh), findsOneWidget);
    expect(find.text(en.heatmapLiveSyncing), findsNothing);
  });

  testWidgets('a shop the platform cannot place yet is told how to fix that, not shown a map',
      (WidgetTester tester) async {
    await _pump(tester, <Object>[
      _density(areasAround: 0, region: null),
    ]);

    expect(find.text(en.heatmapNoAreaTitle), findsOneWidget);
    expect(find.text(en.heatmapNoAreaMessage), findsOneWidget);
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.text(en.heatmapAreasTitle), findsNothing);
  });

  testWidgets('a neighbourhood too quiet to show says why, naming the privacy floor',
      (WidgetTester tester) async {
    await _pump(tester, <Object>[_density(areasAround: 4)]);

    expect(find.text(en.heatmapNotEnoughTitle), findsOneWidget);
    expect(find.text(en.heatmapNotEnoughMessage(5)), findsOneWidget);
    expect(find.text(en.heatmapNoAreaTitle), findsNothing);
    expect(find.byType(FlutterMap), findsNothing);
  });

  testWidgets('another window is asked for, and the old window is not shown under its chip',
      (WidgetTester tester) async {
    final _DensityAdapter adapter = await _pump(tester, <Object>[
      _busy,
      _density(window: 1440, zones: <Map<String, dynamic>>[
        _area('Badaro', 'HIGH', lat: 33.8745, lng: 35.5147),
      ]),
    ]);

    await tester.tap(find.text(en.heatmapWindowDay));
    await _settle(tester);

    expect(adapter.calls.last.queryParameters['windowMinutes'], 1440);
    expect(find.text('Badaro (High)'), findsOneWidget);
    expect(find.text('Mar Mikhael (High)'), findsNothing);
  });

  testWidgets('the first load failing offers a retry that works', (WidgetTester tester) async {
    await _pump(tester, <Object>[500, _busy]);

    expect(find.text(en.heatmapCouldNotLoad), findsOneWidget);
    expect(find.text(en.carrBadgeLive), findsNothing);

    await tester.tap(find.text(en.tryAgain));
    await _settle(tester);

    expect(find.text('Mar Mikhael (High)'), findsOneWidget);
    expect(find.text(en.carrBadgeLive), findsOneWidget);
  });

  testWidgets('a merchant with no shop is told so and nothing is asked',
      (WidgetTester tester) async {
    final _DensityAdapter adapter = await _pump(tester, <Object>[_busy], storeId: null);

    expect(find.text(en.noShopYet), findsOneWidget);
    expect(adapter.calls, isEmpty);
  });

  testWidgets('the minute refresh stops when the screen goes away', (WidgetTester tester) async {
    final _DensityAdapter adapter = await _pump(tester, <Object>[_busy]);
    expect(adapter.calls, hasLength(1));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 3));

    expect(adapter.calls, hasLength(1));
  });

  testWidgets('tiles that never load fall back to the styled slot, and the list still names all',
      (WidgetTester tester) async {
    await _pump(tester, <Object>[_busy]);

    await tester.pump(const Duration(seconds: 9));
    await _settle(tester);

    expect(find.text(en.heatmapMapUnavailable), findsOneWidget);
    expect(find.byType(MapSlotPlaceholder), findsOneWidget);
    expect(find.text('Hamra'), findsOneWidget);
    expect(find.text('Verdun'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a 320px phone in Arabic, right to left, without overflowing',
      (WidgetTester tester) async {
    await _pump(tester, <Object>[_busy], locale: const Locale('ar'), width: 320);

    expect(find.text(ar.heatmapTitle), findsOneWidget);
    expect(find.text(ar.heatmapAreasTitle), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text(ar.heatmapAreasTitle))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });
}
