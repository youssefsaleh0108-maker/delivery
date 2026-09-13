import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Demand Radar's two doors inside the merchant package: a card on the dashboard, and a row in
/// Settings beside Shop Analytics.
///
/// Neither frame draws them, so both follow the statement row's rule rather than the "Soon" chip's:
/// drawn when the host hands over a callback, absent when it does not. The hosts hand one over for
/// the shop's owner only — that choice is pinned in the app's shell wiring test.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body);

  final Object body;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    return ResponseBody.fromString(jsonEncode(body), 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _day(String day, int orders) => <String, dynamic>{
      'day': day,
      'orders': orders,
      'delivered': orders,
      'money': 100.0,
      'waived': 0.0,
    };

Map<String, dynamic> _summary() {
  final List<Map<String, dynamic>> days = <Map<String, dynamic>>[
    for (int i = 13; i >= 0; i--) _day('2026-09-${(13 - i + 1).toString().padLeft(2, '0')}', 4),
  ];
  return <String, dynamic>{
    'windowDays': 14,
    'days': days,
    'today': days.last,
    'yesterday': days[days.length - 2],
    'window': <String, dynamic>{'orders': 56, 'delivered': 56, 'money': 1400.0, 'waived': 0.0},
    'platformFees': 175.0,
    'savedByOffers': 0.0,
    'commissionPercentage': 12.5,
    'awaitingYou': 0,
    'preparing': 0,
    'readyForPickup': 0,
    'onTheWay': 0,
    'topProducts': <Map<String, dynamic>>[],
  };
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  Future<void> pumpDashboard(WidgetTester tester,
      {VoidCallback? onDemandRadar, Locale locale = const Locale('en'), double width = 390}) async {
    tester.view.physicalSize = Size(width, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))
      ..httpClientAdapter = _StubAdapter(_summary());
    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      locale: locale,
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: MerchantDashboardScreen(api: OrderApi(dio), onDemandRadar: onDemandRadar),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> pumpSettings(WidgetTester tester, {VoidCallback? onDemandRadar}) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: MerchantSettingsScreen(
        locale: LocaleController(read: () async => 'en', write: (String _) async {}),
        accountName: 'Rima Haddad',
        onDemandRadar: onDemandRadar,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the dashboard card opens the radar when the host wires it',
      (WidgetTester tester) async {
    int opened = 0;
    await pumpDashboard(tester, onDemandRadar: () => opened++);

    expect(find.text(en.heatmapEntryBlurb), findsOneWidget);
    await tester.tap(find.text(en.heatmapTitle));
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dashboard draws no card at all when the host does not wire it',
      (WidgetTester tester) async {
    await pumpDashboard(tester);

    expect(find.text(en.ordersToday), findsOneWidget);
    expect(find.text(en.heatmapTitle), findsNothing);
    expect(find.text(en.heatmapEntryBlurb), findsNothing);
  });

  testWidgets('the card fits a 320px phone in Arabic', (WidgetTester tester) async {
    await pumpDashboard(tester,
        onDemandRadar: () {}, locale: const Locale('ar'), width: 320);

    expect(find.text(ar.heatmapTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings offers the radar beside Shop Analytics when wired',
      (WidgetTester tester) async {
    int opened = 0;
    await pumpSettings(tester, onDemandRadar: () => opened++);

    expect(find.text(en.merchbShopAnalytics), findsOneWidget);
    await tester.tap(find.text(en.heatmapTitle));
    expect(opened, 1);
  });

  testWidgets('Settings hides the row, rather than marking it Soon, when not wired',
      (WidgetTester tester) async {
    await pumpSettings(tester);

    expect(find.text(en.merchbShopAnalytics), findsOneWidget);
    expect(find.text(en.heatmapTitle), findsNothing);
  });
}
