import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The window figures' comparison, which used to be blank.
///
/// The dashboard's own summary carries today, yesterday and then one flat total for the fortnight
/// with nothing behind it — so "how does this fortnight compare with the last one" had no answer
/// to give. `GET /api/orders/merchant/daily` has one, and sends no percentages: everything asserted
/// here is arithmetic the screen does itself, which is exactly why it is worth pinning.
class _RoutingAdapter implements HttpClientAdapter {
  _RoutingAdapter({required this.summary, this.series, this.seriesFails = false});

  final Map<String, dynamic> summary;
  final Map<String, dynamic>? series;

  /// The case that matters most: a comparison that cannot be fetched leaves a page of correct
  /// figures alone rather than replacing it with an apology.
  final bool seriesFails;

  final List<String> paths = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    paths.add(options.path);

    Object body;
    int status = 200;
    if (options.path.contains('/merchant/daily')) {
      if (seriesFails) {
        status = 500;
        body = <String, dynamic>{'message': 'nope'};
      } else {
        body = series ?? <String, dynamic>{'windowDays': 0, 'days': <dynamic>[]};
      }
    } else if (options.path.contains('/merchant/summary')) {
      body = summary;
    } else {
      // The recent-orders feed and anything else the screen asks for.
      body = <String, dynamic>{
        'content': <dynamic>[],
        'page': 0,
        'size': 20,
        'totalElements': 0,
        'totalPages': 0,
      };
    }

    return ResponseBody.fromString(jsonEncode(body), status,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _summaryDay(int orders) => <String, dynamic>{
      'day': '2026-08-16',
      'orders': orders,
      'delivered': orders,
      'money': 100.0,
      'waived': 0.0,
    };

Map<String, dynamic> _summary() => <String, dynamic>{
      'windowDays': 14,
      'days': <Map<String, dynamic>>[_summaryDay(5)],
      'today': _summaryDay(5),
      'yesterday': _summaryDay(5),
      'window': <String, dynamic>{
        'orders': 140,
        'delivered': 120,
        'money': 4000.0,
        'waived': 0.0,
      },
      'platformFees': 500.0,
      'savedByOffers': 0.0,
      'commissionPercentage': 12.5,
      'awaitingYou': 0,
      'preparing': 0,
      'readyForPickup': 0,
      'onTheWay': 0,
      'topProducts': <dynamic>[],
    };

Map<String, dynamic> _tierDay(String day, int orders, int delivered) => <String, dynamic>{
      'day': day,
      'standard': <String, dynamic>{
        'orders': orders,
        'delivered': delivered,
        'gross': orders * 10.0,
      },
      'express': <String, dynamic>{'orders': 0, 'delivered': 0, 'gross': 0.0},
    };

/// 28 ascending days: fourteen of `older` a day, then fourteen of `newer` a day.
Map<String, dynamic> _series({required int older, required int newer, int days = 28}) {
  final List<Map<String, dynamic>> entries = <Map<String, dynamic>>[
    for (int i = 0; i < days; i++)
      _tierDay(
        '2026-07-${(20 + i).toString().padLeft(2, '0')}',
        i < days ~/ 2 ? older : newer,
        i < days ~/ 2 ? older : newer,
      ),
  ];
  return <String, dynamic>{'windowDays': days, 'days': entries};
}

Future<_RoutingAdapter> _pump(
  WidgetTester tester, {
  Map<String, dynamic>? series,
  bool seriesFails = false,
  bool wireAggregates = true,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final _RoutingAdapter adapter = _RoutingAdapter(
    summary: _summary(),
    series: series,
    seriesFails: seriesFails,
  );
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;

  await tester.pumpWidget(MaterialApp(
    theme: DeliveryTheme.light(),
    locale: locale,
    localizationsDelegates: DeliveryStrings.localizationsDelegates,
    supportedLocales: DeliveryStrings.supportedLocales,
    home: MerchantDashboardScreen(
      api: OrderApi(dio),
      aggregates: wireAggregates ? AggregatesApi(dio) : null,
    ),
  ));
  await tester.pumpAndSettle();
  return adapter;
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  testWidgets('says how the fortnight compares with the one before it',
      (WidgetTester tester) async {
    // 14 days of 12 against 14 days of 8: 168 against 112, which is 50% up.
    await _pump(tester, series: _series(older: 8, newer: 12));

    expect(find.text(en.merchUpOnPrevious(50, 14)), findsWidgets);
    expect(find.byIcon(Icons.trending_up_rounded), findsWidgets);
  });

  testWidgets('a fall is stated plainly and not painted as an alarm',
      (WidgetTester tester) async {
    await _pump(tester, series: _series(older: 12, newer: 6));

    final Finder fell = find.text(en.merchDownOnPrevious(50, 14));
    expect(fell, findsWidgets);
    // A quiet fortnight is not a fault. Red is reserved for things that need doing.
    expect(tester.widget<Text>(fell.first).style?.color, DeliveryColors.muted);
  });

  testWidgets('never divides by a period of nothing', (WidgetTester tester) async {
    await _pump(tester, series: _series(older: 0, newer: 5));

    expect(find.text(en.merchNonePrevious(14)), findsWidgets);
    expect(find.textContaining('Infinity'), findsNothing);
    expect(find.textContaining('NaN'), findsNothing);
  });

  testWidgets('two empty fortnights say so rather than showing a percentage',
      (WidgetTester tester) async {
    await _pump(tester, series: _series(older: 0, newer: 0));

    expect(find.text(en.merchNothingEitherPeriod), findsWidgets);
  });

  testWidgets('an unchanged fortnight is not dressed up as movement',
      (WidgetTester tester) async {
    await _pump(tester, series: _series(older: 7, newer: 7));

    expect(find.text(en.merchSameAsPrevious(14)), findsWidgets);
    expect(find.text(en.merchUpOnPrevious(0, 14)), findsNothing);
  });

  testWidgets('names the window the server actually returned, not the one asked for',
      (WidgetTester tester) async {
    // The server clamps `days` to 1..30 without complaining, so a shorter answer is a normal one.
    // Ten days back means five a side, and the comparison has to say five.
    await _pump(tester, series: _series(older: 2, newer: 4, days: 10));

    expect(find.text(en.merchUpOnPrevious(100, 5)), findsWidgets);
    expect(find.text(en.merchUpOnPrevious(100, 14)), findsNothing);
  });

  testWidgets('a comparison that cannot be fetched leaves the figures alone',
      (WidgetTester tester) async {
    await _pump(tester, seriesFails: true);

    // The window figure itself is still there and still correct...
    expect(find.text('140'), findsOneWidget);
    // ...and nothing under it claims a comparison that was never made.
    expect(find.textContaining('days before'), findsNothing);
    expect(find.text(en.merchNothingEitherPeriod), findsNothing);
  });

  testWidgets('a host that wires no series is unchanged', (WidgetTester tester) async {
    // The portal and the phone both mounted this screen with an OrderApi and nothing else for a
    // year. That has to keep working, and keep saying nothing it cannot support.
    final _RoutingAdapter adapter = await _pump(tester, wireAggregates: false);

    expect(adapter.paths.where((String p) => p.contains('daily')), isEmpty);
    expect(find.text('140'), findsOneWidget);
    expect(find.textContaining('days before'), findsNothing);
  });

  testWidgets('the comparison is translated too', (WidgetTester tester) async {
    await _pump(tester, series: _series(older: 8, newer: 12), locale: const Locale('ar'));

    expect(find.text(ar.merchUpOnPrevious(50, 14)), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a fortnight of comparisons still fits a 360dp phone',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))
      ..httpClientAdapter = _RoutingAdapter(
        summary: _summary(),
        series: _series(older: 8, newer: 12),
      );

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: MerchantDashboardScreen(api: OrderApi(dio), aggregates: AggregatesApi(dio)),
    ));
    await tester.pumpAndSettle();

    // The comparison is two extra lines inside a tile that was already tight at 180dp wide.
    expect(tester.takeException(), isNull);
  });
}
