import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Menu Insights (Figma 139:255) — what the screen is allowed to say.
///
/// Most of what is pinned here is about restraint, because most of this screen's design work was
/// deciding what not to draw:
///
/// * an opens figure is always banded and always prefixed "about", never the raw number;
/// * a window under the floor says *too few to report* and never draws a zero, because "too few to
///   say anything about" and "nobody" are different facts and only the first was ever claimed;
/// * the day is four parts and no clock time is ever shown as a figure's own timestamp;
/// * best sellers are exact, because they are the shop's own receipts;
/// * nothing on the screen is called a scan, and nothing claims a per-item view count.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.body);

  /// A map is a 200 body; an int is an error status.
  final Object body;
  final List<RequestOptions> calls = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add(options);
    final Map<String, List<String>> headers = <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    };
    if (body is int) {
      return ResponseBody.fromString('{"detail":"unavailable"}', body as int, headers: headers);
    }
    return ResponseBody.fromString(jsonEncode(body), 200, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _opens(int about, {bool enough = true}) =>
    <String, dynamic>{'about': about, 'enough': enough};

Map<String, dynamic> _part(String part, int about, {bool enough = true}) =>
    <String, dynamic>{'part': part, 'opens': _opens(about, enough: enough)};

Map<String, dynamic> _report({
  Map<String, dynamic>? opens,
  Map<String, dynamic>? fromTableCodes,
  List<Map<String, dynamic>>? shape,
  List<Map<String, dynamic>>? bestSellers,
  String? countingSince,
  int days = 7,
}) =>
    <String, dynamic>{
      'storeId': 'store-1',
      'from': '2026-09-16',
      'to': '2026-09-22',
      'days': days,
      'opens': opens ?? _opens(40),
      'fromTableCodes': fromTableCodes ?? _opens(0, enough: false),
      'shape': shape ??
          <Map<String, dynamic>>[
            _part('MORNING', 20),
            _part('MIDDAY', 40),
            _part('EVENING', 0, enough: false),
            _part('NIGHT', 0, enough: false),
          ],
      'bestSellers': bestSellers ??
          <Map<String, dynamic>>[
            <String, dynamic>{
              'productId': 'p-croissant',
              'name': 'Croissant au Beurre',
              'baskets': 7,
              'units': 23,
            },
          ],
      'countingSince': countingSince,
      'minimumOpens': 20,
    };

Future<_Adapter> _pump(
  WidgetTester tester,
  Object body, {
  Locale locale = const Locale('en'),
  VoidCallback? onDemandRadar,
}) async {
  tester.view.physicalSize = const Size(420, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
  final _Adapter adapter = _Adapter(body);
  dio.httpClientAdapter = adapter;

  await tester.pumpWidget(MaterialApp(
    theme: DeliveryTheme.light(),
    locale: locale,
    localizationsDelegates: DeliveryStrings.localizationsDelegates,
    supportedLocales: DeliveryStrings.supportedLocales,
    home: MenuInsightsScreen(
      api: MenuInsightsApi(dio),
      storeId: 'store-1',
      onBack: () {},
      onDemandRadar: onDemandRadar,
    ),
  ));
  for (int i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return adapter;
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  group('the opens figure', () {
    testWidgets('is a band with "about" in front of it, never the raw number',
        (WidgetTester tester) async {
      await _pump(tester, _report(opens: _opens(40)));

      expect(find.text(en.merchMenuOpensAbout(40)), findsWidgets);
      // The server rounded 47 down to 40 before it left; the screen must not dress that up as an
      // exact figure by dropping the word.
      expect(en.merchMenuOpensAbout(40), contains('about'));
      expect(find.text('40'), findsNothing);
    });

    testWidgets('under the floor says too few, and never draws a zero',
        (WidgetTester tester) async {
      // Counting has been running — this shop is quiet, not new. The two are different silences
      // and the screen says different things about them.
      await _pump(tester, _report(
        opens: _opens(0, enough: false),
        countingSince: '2026-09-16',
      ));

      expect(find.text(en.merchMenuOpensTooFewShort), findsWidgets);
      // And the floor itself is named beside it, so the merchant knows what "too few" was measured
      // against rather than being left to guess.
      expect(find.text(en.merchMenuOpensTooFew(20)), findsWidgets);
      // A 0 would say "nobody read your menu", which is not what the server said.
      expect(find.text('0'), findsNothing);
      expect(find.text(en.merchMenuOpensAbout(0)), findsNothing);
    });

    testWidgets('says what it is counting, and what it cannot see',
        (WidgetTester tester) async {
      await _pump(tester, _report());

      // Not a disclaimer to be trimmed: a merchant deciding anything from this number needs to
      // know it counts opens rather than people, and misses cached readers entirely.
      expect(find.text(en.merchMenuOpensWhatItCounts), findsOneWidget);
    });
  });

  group('the table-code figure', () {
    testWidgets('is never called a scan, and says why scans cannot be counted',
        (WidgetTester tester) async {
      await _pump(tester, _report());

      expect(find.text(en.merchMenuFromTablesTitle), findsWidgets);
      // The explanation is on the screen, not buried in a tooltip: a merchant who came looking for
      // the frame's scan count must be told why there is not one.
      expect(find.text(en.merchMenuNoScanCount), findsOneWidget);
      // And the frame's tile itself is nowhere on it.
      expect(find.text('QR Scans'), findsNothing);
      expect(find.textContaining('QR scans', findRichText: true), findsNothing);
    });

    testWidgets('a shop with no table codes reads as none, not as too few',
        (WidgetTester tester) async {
      await _pump(tester, _report(fromTableCodes: _opens(0, enough: false)));

      // A true zero — no codes have been scanned — is its own sentence, and a different one from
      // a figure suppressed by the floor.
      expect(find.text(en.merchMenuFromTablesNone), findsOneWidget);
    });
  });

  group('when the menu is read', () {
    testWidgets('draws four parts of the day and no hour', (WidgetTester tester) async {
      await _pump(tester, _report());

      // Rich text: each row pairs the part's name with the hours it covers in a lighter weight.
      for (final String part in <String>[
        en.merchMenuPartMorning,
        en.merchMenuPartMidday,
        en.merchMenuPartEvening,
        en.merchMenuPartNight,
      ]) {
        expect(find.textContaining(part, findRichText: true), findsOneWidget);
      }
      expect(find.text(en.merchMenuWhenWhyNotHours), findsOneWidget);
      // Four parts and no hour is a figure's own label anywhere.
      expect(find.textContaining('19:00', findRichText: true), findsNothing);
    });

    testWidgets('a part under the floor shows no figure of its own',
        (WidgetTester tester) async {
      await _pump(tester, _report(shape: <Map<String, dynamic>>[
        _part('MORNING', 40),
        // One open, late, inside an otherwise busy week: the sentence the whole design avoids.
        _part('MIDDAY', 0, enough: false),
        _part('EVENING', 0, enough: false),
        _part('NIGHT', 0, enough: false),
      ]));

      expect(find.text(en.merchMenuOpensAbout(40)), findsWidgets);
      // Three suppressed bars, each saying so rather than drawing a zero-length bar that would
      // read as "nobody, ever".
      expect(find.text(en.merchMenuOpensTooFewShort), findsNWidgets(3));
    });

    testWidgets('a period too quiet to place says so instead of drawing empty bars',
        (WidgetTester tester) async {
      await _pump(tester, _report(
        opens: _opens(0, enough: false),
        shape: <Map<String, dynamic>>[
          _part('MORNING', 0, enough: false),
          _part('MIDDAY', 0, enough: false),
          _part('EVENING', 0, enough: false),
          _part('NIGHT', 0, enough: false),
        ],
      ));

      expect(find.text(en.merchMenuWhenTooQuiet), findsOneWidget);
    });
  });

  group('what sold', () {
    testWidgets('is exact, unlike everything above it', (WidgetTester tester) async {
      await _pump(tester, _report());

      expect(find.text('1. Croissant au Beurre'), findsOneWidget);
      // Seven orders and twenty-three units, said exactly: the shop's own receipts.
      expect(find.text(en.merchMenuBestSellerLine(7, 23)), findsOneWidget);
      expect(find.text(en.merchMenuBestSellersNote), findsOneWidget);
    });

    testWidgets('says there is no per-item view count', (WidgetTester tester) async {
      await _pump(tester, _report());

      // The frame's "Most Viewed Items" rail. Absent, and explained, rather than faked.
      expect(find.text(en.merchMenuNoItemViews), findsOneWidget);
    });

    testWidgets('a window with no delivered orders says so', (WidgetTester tester) async {
      await _pump(tester, _report(bestSellers: <Map<String, dynamic>>[]));

      expect(find.text(en.merchMenuBestSellersEmpty), findsOneWidget);
    });
  });

  group('the window', () {
    testWidgets('asks for seven days first, and re-reads when another is picked',
        (WidgetTester tester) async {
      final _Adapter adapter = await _pump(tester, _report());

      expect(adapter.calls, hasLength(1));
      expect(adapter.calls.first.queryParameters['days'], 7);

      await tester.tap(find.text(en.merchMenuInsightsWindowMonth));
      for (int i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(adapter.calls, hasLength(2));
      expect(adapter.calls.last.queryParameters['days'], 30);
    });

    testWidgets('picking the window already shown asks for nothing',
        (WidgetTester tester) async {
      final _Adapter adapter = await _pump(tester, _report());

      await tester.tap(find.text(en.merchMenuInsightsWindowWeek));
      await tester.pump(const Duration(milliseconds: 50));

      expect(adapter.calls, hasLength(1));
    });
  });

  group('the silences', () {
    testWidgets('a shop that has not been counted yet is told so', (WidgetTester tester) async {
      await _pump(tester, _report(
        opens: _opens(0, enough: false),
        countingSince: null,
      ));

      // Not "nobody read your menu": nothing has been counted, which is what a shop whose page
      // predates the counting sees.
      expect(find.text(en.merchMenuOpensNothingYet), findsOneWidget);
    });

    testWidgets('a read that failed offers another go', (WidgetTester tester) async {
      await _pump(tester, 503);

      expect(find.text(en.merchMenuInsightsFailed), findsOneWidget);
      expect(find.text(en.tryAgain), findsOneWidget);
    });
  });

  group('the radar door', () {
    testWidgets('is drawn when the host has one, and opens it', (WidgetTester tester) async {
      int opened = 0;
      await _pump(tester, _report(), onDemandRadar: () => opened++);

      await tester.tap(find.text(en.merchMenuDemandRadarRow));
      await tester.pump();

      // The neighbourhood's searches are the radar's numbers. This screen points at them rather
      // than drawing a second copy.
      expect(opened, 1);
    });

    testWidgets('is not drawn when the host has nowhere to send them',
        (WidgetTester tester) async {
      await _pump(tester, _report());

      expect(find.text(en.merchMenuDemandRadarRow), findsNothing);
    });
  });

  group('Arabic', () {
    testWidgets('reads right to left, in Arabic, with the figures still banded',
        (WidgetTester tester) async {
      await _pump(tester, _report(), locale: const Locale('ar'));

      expect(
        Directionality.of(tester.element(find.byType(MenuInsightsScreen))),
        TextDirection.rtl,
      );
      expect(find.text(ar.merchMenuInsightsTitle), findsWidgets);
      expect(ar.merchMenuInsightsTitle, isNot(en.merchMenuInsightsTitle));
      expect(find.text(ar.merchMenuOpensAbout(40)), findsWidgets);
      // The honesty notes are translated too — they are the point of the screen, not chrome.
      expect(find.text(ar.merchMenuNoScanCount), findsOneWidget);
      expect(find.text(ar.merchMenuNoItemViews), findsOneWidget);
    });

    testWidgets('at 320 dp nothing overflows', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
      dio.httpClientAdapter = _Adapter(_report());

      await tester.pumpWidget(MaterialApp(
        theme: DeliveryTheme.light(),
        locale: const Locale('ar'),
        localizationsDelegates: DeliveryStrings.localizationsDelegates,
        supportedLocales: DeliveryStrings.supportedLocales,
        home: MenuInsightsScreen(api: MenuInsightsApi(dio), storeId: 'store-1', onBack: () {}),
      ));
      for (int i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('an account with no shop yet draws the empty state, and asks for nothing',
      (WidgetTester tester) async {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    final _Adapter adapter = _Adapter(_report());
    dio.httpClientAdapter = adapter;

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: MenuInsightsScreen(api: MenuInsightsApi(dio)),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(en.noShopYet), findsOneWidget);
    expect(adapter.calls, isEmpty);
  });
}
