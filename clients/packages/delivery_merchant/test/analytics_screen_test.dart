import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shop Analytics — the settings row that carried a "Soon" chip because nothing aggregated a
/// shop's trade beyond one flat window total.
///
/// The screen exists to say two things the dashboard cannot: how one day sits against the one
/// before it, and how much of the window was Express. The second comes with a caveat that is not
/// decoration — the series' money is the whole bill the customer paid, and the shop is settled on
/// the goods, so this screen must never let that figure read as a payout.
class _SeriesAdapter implements HttpClientAdapter {
  _SeriesAdapter(this.body, {this.status = 200});

  final Object body;
  final int status;
  final List<String> paths = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    paths.add('${options.path}?days=${options.queryParameters['days']}');
    return ResponseBody.fromString(jsonEncode(body), status,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _day(
  String day, {
  int stdOrders = 0,
  int stdDelivered = 0,
  double stdGross = 0,
  int expOrders = 0,
  int expDelivered = 0,
  double expGross = 0,
}) =>
    <String, dynamic>{
      'day': day,
      'standard': <String, dynamic>{
        'orders': stdOrders,
        'delivered': stdDelivered,
        'gross': stdGross,
      },
      'express': <String, dynamic>{
        'orders': expOrders,
        'delivered': expDelivered,
        'gross': expGross,
      },
    };

/// Three days: a quiet one, then yesterday at 4 orders, then today at 6 — 50% up, and with a
/// two-order Express slice that must be reported separately.
Map<String, dynamic> _series() => <String, dynamic>{
      'windowDays': 3,
      'days': <Map<String, dynamic>>[
        _day('2026-08-14', stdOrders: 1, stdDelivered: 1, stdGross: 10),
        _day('2026-08-15', stdOrders: 4, stdDelivered: 3, stdGross: 40),
        _day('2026-08-16',
            stdOrders: 4,
            stdDelivered: 4,
            stdGross: 44.50,
            expOrders: 2,
            expDelivered: 1,
            expGross: 26.50),
      ],
    };

Future<_SeriesAdapter> _pump(
  WidgetTester tester, {
  Object? body,
  int status = 200,
  int days = 14,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final _SeriesAdapter adapter = _SeriesAdapter(body ?? _series(), status: status);
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;

  await tester.pumpWidget(MaterialApp(
    theme: DeliveryTheme.light(),
    locale: locale,
    localizationsDelegates: DeliveryStrings.localizationsDelegates,
    supportedLocales: DeliveryStrings.supportedLocales,
    home: MerchantAnalyticsScreen(api: AggregatesApi(dio), days: days),
  ));
  await tester.pumpAndSettle();
  return adapter;
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  testWidgets('asks the shop-scoped series, not the platform one',
      (WidgetTester tester) async {
    final _SeriesAdapter adapter = await _pump(tester);

    // A merchant asking `/api/orders/daily` is a 403 and a screen that says nothing. The scope is
    // the path here, not a parameter.
    expect(adapter.paths, <String>['/api/orders/merchant/daily?days=14']);
  });

  testWidgets('names the window the server returned, not the one asked for',
      (WidgetTester tester) async {
    // `days` is clamped server-side to 1..30 with no error, so what came back is the only honest
    // heading.
    await _pump(tester, days: 90);

    expect(find.text(en.lastDaysHeading(3)), findsWidgets);
    expect(find.text(en.lastDaysHeading(90)), findsNothing);
  });

  testWidgets('compares today with yesterday from the series itself',
      (WidgetTester tester) async {
    await _pump(tester);

    // 6 orders against 4 is 50% up; 5 delivered against 3 is 67%.
    expect(find.text(en.upOnYesterday(50)), findsOneWidget);
    expect(find.text('6'), findsWidgets);
  });

  testWidgets('splits the window by tier and says whose money the total is',
      (WidgetTester tester) async {
    await _pump(tester);

    expect(find.text(en.merchTierSplit), findsOneWidget);
    expect(find.text(en.deliveryTierStandard), findsOneWidget);
    expect(find.text(en.deliveryTierExpress), findsOneWidget);

    // Express: 2 orders, 1 delivered, 26.50 of order value. Nothing here is rounded, summed
    // across tiers, or quietly relabelled.
    expect(find.text('26.50'), findsOneWidget);
    expect(find.text('94.50'), findsOneWidget);

    // The caveat is the point: the express premium is the platform's revenue, so this figure is
    // not a payout and never says it is.
    expect(find.text(en.merchOrderValueNote), findsWidgets);
    expect(find.text(en.salesInWindow), findsNothing);
  });

  testWidgets('a single day has nothing to compare against and says nothing',
      (WidgetTester tester) async {
    await _pump(tester, body: <String, dynamic>{
      'windowDays': 1,
      'days': <Map<String, dynamic>>[_day('2026-08-16', stdOrders: 3, stdDelivered: 3)],
    });

    expect(find.text('3'), findsWidgets);
    expect(find.byIcon(Icons.trending_up_rounded), findsNothing);
    expect(find.byIcon(Icons.trending_down_rounded), findsNothing);
    expect(find.byIcon(Icons.trending_flat_rounded), findsNothing);
  });

  testWidgets('a shop with no trade yet gets a sentence, not a wall of zeros',
      (WidgetTester tester) async {
    await _pump(tester,
        body: <String, dynamic>{'windowDays': 0, 'days': <dynamic>[]});

    expect(find.text(en.quietSoFar), findsOneWidget);
  });

  testWidgets('a refusal offers a way out rather than a dead screen',
      (WidgetTester tester) async {
    await _pump(tester, status: 500, body: <String, dynamic>{'message': 'no'});

    expect(find.text(en.couldNotLoadOrdersShort), findsOneWidget);
    expect(find.text(en.tryAgain), findsOneWidget);
  });

  testWidgets('the settings row that used to say Soon now leads here',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))
      ..httpClientAdapter = _SeriesAdapter(_series());
    final LocaleController locale = LocaleController(
      read: () async => 'en',
      write: (String _) async {},
    );
    addTearDown(locale.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: MerchantSettingsScreen(
        locale: locale,
        accountName: 'Falafel King',
        aggregates: AggregatesApi(dio),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(en.merchbShopAnalytics));
    await tester.pumpAndSettle();

    expect(find.byType(MerchantAnalyticsScreen), findsOneWidget);
    expect(find.text(en.merchTierSplit), findsOneWidget);
  });

  testWidgets('and keeps its chip for a host that wired no series',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final LocaleController locale = LocaleController(
      read: () async => 'en',
      write: (String _) async {},
    );
    addTearDown(locale.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: MerchantSettingsScreen(locale: locale, accountName: 'Falafel King'),
    ));
    await tester.pumpAndSettle();

    // A row that leads nowhere says so, rather than opening an empty page.
    await tester.tap(find.text(en.merchbShopAnalytics));
    await tester.pumpAndSettle();
    expect(find.byType(MerchantAnalyticsScreen), findsNothing);
  });

  testWidgets('fits a 360dp phone in Arabic', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))
      ..httpClientAdapter = _SeriesAdapter(_series());

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      locale: const Locale('ar'),
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: MerchantAnalyticsScreen(api: AggregatesApi(dio)),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(ar.merchTierSplit), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text(ar.merchTierSplit))),
      TextDirection.rtl,
    );
  });
}
