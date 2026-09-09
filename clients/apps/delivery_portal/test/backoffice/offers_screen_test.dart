import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_portal/src/backoffice/offers_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The fee-waiver budget panel, and the one rule that holds it together: every figure on it is
/// money, so every figure on it is written the same way.
///
/// The budget bar was the exception. It took [UsageBar]'s default of one decimal place — right for
/// a quota of things, wrong for USD — and drew "12.5 / 100" immediately under the same two amounts
/// printed as "12.50" and "100.00" in the tiles above it. An operator comparing them has to work
/// out whether they are the same number.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.budget);

  final Map<String, dynamic> budget;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    if (options.path.startsWith('/api/offers/budget')) {
      return ResponseBody.fromString(jsonEncode(budget), 200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>[Headers.jsonContentType]
          });
    }
    return ResponseBody.fromString('[]', 200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

OfferApi _api(Map<String, dynamic> budget) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost:8100'));
  dio.httpClientAdapter = _FakeAdapter(budget);
  return OfferApi(dio);
}

/// Amounts the server sends at three different scales, which is exactly how they arrive: a whole
/// number, one decimal, and two.
const Map<String, dynamic> _budget = <String, dynamic>{
  'earned': 1000,
  'budget': 100,
  'given': 12.5,
  'givenCustomer': 12.5,
  'givenMerchant': 0,
  'givenCarrier': 0,
  'remaining': 87.5,
  'usedPercent': 12.5,
  'kept': 987.5,
  'capPercentage': 10,
  'allowance': 0,
  'windowDays': 30,
};

/// Every number this screen prints that is not a percentage or a day count.
final RegExp _amount = RegExp(r'^-?\d+(\.\d+)?$');

void main() {
  testWidgets('every amount on the budget panel is written to the cent',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      home: Scaffold(body: OffersScreen(api: _api(_budget))),
    ));
    await tester.pumpAndSettle();

    // The tiles and the bar under them: the figures a reader compares against each other in one
    // glance, and the only place on this panel where every number is money. The bar prints both of
    // its numbers in one string, so the sweep splits on the separator rather than reading whole
    // Text values.
    final List<String> numbers = <String>[
      for (final Finder panel in <Finder>[find.byType(StatRow), find.byType(UsageBar)])
        for (final Text text
            in tester.widgetList<Text>(find.descendant(of: panel, matching: find.byType(Text))))
          if (text.data case final String value)
            for (final String piece in value.split(RegExp(r'[\s/]+')))
              if (_amount.hasMatch(piece)) piece,
    ];

    expect(numbers, isNotEmpty, reason: 'the panel drew no amounts at all');
    for (final String amount in numbers) {
      expect(amount, endsWith('.${amount.split('.').last}'));
      expect(
        amount.split('.').last.length,
        2,
        reason: 'USD is two decimals everywhere on this platform, and "$amount" is not: $numbers',
      );
    }
  });

  testWidgets('the budget bar agrees with the tiles above it', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      home: Scaffold(body: OffersScreen(api: _api(_budget))),
    ));
    await tester.pumpAndSettle();

    // "Given away" reads 12.50 in its tile; the bar under it used to read 12.5.
    expect(find.text('12.50'), findsOneWidget);
    expect(find.text('12.50 / 100.00'), findsOneWidget);
  });
}
