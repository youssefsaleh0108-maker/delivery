import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// "What your neighbours could not find" — the Demand Radar's second section.
///
/// What is pinned here is what the section is allowed to say. A rounded count and never an exact
/// one; a neighbourhood name and never a place finer than that; nothing at all about who searched.
/// And the silences, which are different things and must read as different things: a shop the
/// platform cannot place, a week too quiet to describe anybody, and a read that failed.
///
/// Also pinned: the words are read once, not sixty times an hour. They are weekly numbers, and a
/// screen left open on a counter all day must not ask for them every minute.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.unmet);

  /// A map is a 200 body; an int is an error status.
  final Object unmet;
  final List<RequestOptions> densityCalls = <RequestOptions>[];
  final List<RequestOptions> unmetCalls = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    final Map<String, List<String>> headers = <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    };
    if (options.path.startsWith('/api/products/demand/unmet')) {
      unmetCalls.add(options);
      if (unmet is int) {
        return ResponseBody.fromString('{"detail":"unavailable"}', unmet as int, headers: headers);
      }
      return ResponseBody.fromString(jsonEncode(unmet), 200, headers: headers);
    }
    densityCalls.add(options);
    return ResponseBody.fromString(jsonEncode(_density), 200, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

const Map<String, dynamic> _density = <String, dynamic>{
  'storeId': 'store-1',
  'region': 'Beirut',
  'windowMinutes': 60,
  'generatedAt': '2026-09-13T10:00:00Z',
  'minimumCustomers': 5,
  'areasAround': 2,
  'zones': <dynamic>[
    <String, dynamic>{
      'zoneId': 'z-hamra',
      'name': 'Hamra',
      'centerLat': 33.8959,
      'centerLng': 35.4787,
      'level': 'HIGH',
    },
  ],
};

Map<String, dynamic> _term(
  String term, {
  String kind = 'NONE',
  int about = 10,
  String? area = 'Hamra',
  bool alreadySold = false,
  int rank = 1,
}) =>
    <String, dynamic>{
      'areaId': 'z-hamra',
      'areaName': area,
      'region': 'Beirut',
      'kind': kind,
      'term': term,
      'about': about,
      'rank': rank,
      'alreadySold': alreadySold,
    };

Map<String, dynamic> _unmet({
  int areasAround = 2,
  List<Map<String, dynamic>> thisWeek = const <Map<String, dynamic>>[],
  List<Map<String, dynamic>> lastWeek = const <Map<String, dynamic>>[],
}) =>
    <String, dynamic>{
      'storeId': 'store-1',
      'region': 'Beirut',
      'areasAround': areasAround,
      'minimumPeople': 5,
      'farMetres': 2000,
      'thisWeek': <String, dynamic>{'weekStart': '2026-09-14T21:00:00Z', 'terms': thisWeek},
      'lastWeek': <String, dynamic>{'weekStart': '2026-09-07T21:00:00Z', 'terms': lastWeek},
    };

final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

Future<_Adapter> _pump(
  WidgetTester tester,
  Object unmet, {
  Locale locale = const Locale('en'),
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final _Adapter adapter = _Adapter(unmet);
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;

  await tester.pumpWidget(MaterialApp(
    theme: DeliveryTheme.light(),
    locale: locale,
    localizationsDelegates: DeliveryStrings.localizationsDelegates,
    supportedLocales: DeliveryStrings.supportedLocales,
    home: DemandRadarScreen(api: DemandApi(dio), storeId: 'store-1', onBack: () {}),
  ));
  for (int i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return adapter;
}

void main() {
  testWidgets('names the words, the area and a rounded count — and never an exact one',
      (WidgetTester tester) async {
    final _Adapter adapter = await _pump(
      tester,
      _unmet(thisWeek: <Map<String, dynamic>>[
        _term('حفاضات', about: 10),
        _term('basmati rice', kind: 'FAR', about: 5, rank: 2),
      ]),
    );

    expect(adapter.unmetCalls.single.path, '/api/products/demand/unmet/store-1');
    // Nothing personal in the request: a store id in the path and no query at all.
    expect(adapter.unmetCalls.single.queryParameters, isEmpty);

    expect(find.text(en.heatmapUnmetTitle), findsOneWidget);
    expect(find.text('حفاضات'), findsOneWidget);
    expect(find.text('basmati rice'), findsOneWidget);
    // "about 10 searches", not "10 searches" and not "9".
    expect(
      find.textContaining('Hamra · ${en.heatmapUnmetAbout(10)} · ${en.heatmapUnmetNothingNearby}'),
      findsOneWidget,
    );
    expect(find.textContaining(en.heatmapUnmetOnlyFar('2')), findsOneWidget);
    expect(find.text(en.heatmapUnmetPrivacy), findsOneWidget);
  });

  testWidgets('a word the shop already sells is marked, not hidden', (WidgetTester tester) async {
    await _pump(
      tester,
      _unmet(thisWeek: <Map<String, dynamic>>[_term('nescafe', alreadySold: true)]),
    );

    expect(find.text('nescafe'), findsOneWidget);
    expect(find.textContaining(en.heatmapUnmetYouSell), findsOneWidget);
  });

  testWidgets('last week is a tap away, and this week is what opens', (WidgetTester tester) async {
    await _pump(
      tester,
      _unmet(
        thisWeek: <Map<String, dynamic>>[_term('حفاضات')],
        lastWeek: <Map<String, dynamic>>[_term('رز بسمتي')],
      ),
    );

    expect(find.text('حفاضات'), findsOneWidget);
    expect(find.text('رز بسمتي'), findsNothing);

    await tester.tap(find.text(en.heatmapUnmetLastWeek));
    await tester.pump();

    expect(find.text('رز بسمتي'), findsOneWidget);
    expect(find.text('حفاضات'), findsNothing);
  });

  testWidgets('a quiet week says why it is quiet, rather than reading as a quiet neighbourhood',
      (WidgetTester tester) async {
    await _pump(tester, _unmet());

    expect(find.text(en.heatmapUnmetQuietTitle), findsOneWidget);
    expect(find.text(en.heatmapUnmetQuietMessage(5)), findsOneWidget);
  });

  testWidgets('a shop the platform cannot place is not told about searches at all',
      (WidgetTester tester) async {
    await _pump(tester, _unmet(areasAround: 0));

    // The map card already says the shop has no neighbourhood; a second empty section under it
    // would be the same silence said twice.
    expect(find.text(en.heatmapUnmetTitle), findsNothing);
    expect(find.text(en.heatmapUnmetQuietTitle), findsNothing);
  });

  testWidgets('a failed read offers a retry and leaves the map above it alone',
      (WidgetTester tester) async {
    final _Adapter adapter = await _pump(tester, 503);

    // The density answer is untouched: its areas are still listed.
    expect(find.text('Hamra'), findsWidgets);
    expect(find.text(en.heatmapUnmetCouldNotLoad), findsOneWidget);
    expect(adapter.unmetCalls, hasLength(1));

    await tester.tap(find.text(en.tryAgain));
    await tester.pump(const Duration(milliseconds: 50));
    expect(adapter.unmetCalls, hasLength(2));
  });

  testWidgets('the words are read once, not on every minute refresh', (WidgetTester tester) async {
    final _Adapter adapter = await _pump(
      tester,
      _unmet(thisWeek: <Map<String, dynamic>>[_term('حفاضات')]),
    );

    await tester.pump(const Duration(seconds: 61));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 61));
    await tester.pump(const Duration(milliseconds: 50));

    expect(adapter.densityCalls.length, greaterThan(1));
    expect(adapter.unmetCalls, hasLength(1));
  });

  testWidgets('fits a 320px phone in Arabic, right to left, without overflowing',
      (WidgetTester tester) async {
    await _pump(
      tester,
      _unmet(thisWeek: <Map<String, dynamic>>[
        _term('حفاضات بامبرز مقاس أربعة', about: 10),
        _term('رز بسمتي', kind: 'FAR', about: 5, alreadySold: true, rank: 2),
      ]),
      locale: const Locale('ar'),
      width: 320,
    );

    expect(find.text(ar.heatmapUnmetTitle), findsOneWidget);
    expect(find.text('حفاضات بامبرز مقاس أربعة'), findsOneWidget);
    expect(find.textContaining(ar.heatmapUnmetYouSell), findsOneWidget);
    expect(Directionality.of(tester.element(find.text(ar.heatmapUnmetTitle))), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });
}
