import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The vertical on the merchant's own shop form, now that some shops are service shops.
///
/// The form listed every vertical there is. The server refuses to move a shop into or out of
/// Services, so offering that move would be a control that cannot work. A goods merchant is offered
/// the goods verticals only, and a provider sees Services without being able to leave it.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.store);

  final Map<String, dynamic> store;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    final Object body;
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
      body = store;
    }
    return ResponseBody.fromString(jsonEncode(body), 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _shop(String vertical, {String? serviceCategory}) => <String, dynamic>{
      'id': 'store-1',
      'slug': 'the-shop',
      'name': 'Al Fakhry Press',
      'vertical': vertical,
      if (serviceCategory != null) 'serviceCategory': serviceCategory,
      'availability': 'OPEN',
      'deliveryFee': 1.0,
      'minOrder': 5.0,
      'etaMinMinutes': 15,
      'etaMaxMinutes': 30,
    };

Future<void> _pump(WidgetTester tester, Map<String, dynamic> store) async {
  tester.view.physicalSize = const Size(420, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = _Adapter(store);

  await tester.pumpWidget(MaterialApp(
    theme: DeliveryTheme.light(),
    localizationsDelegates: DeliveryStrings.localizationsDelegates,
    supportedLocales: DeliveryStrings.supportedLocales,
    home: StoreScreen(api: StoreApi(dio)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  DropdownButton<StoreVertical> picker(WidgetTester tester) =>
      tester.widget(find.byType(DropdownButton<StoreVertical>));

  testWidgets('a goods shop is offered the goods verticals and never Services',
      (WidgetTester tester) async {
    await _pump(tester, _shop('GROCERY'));

    expect(picker(tester).items!.map((DropdownMenuItem<StoreVertical> i) => i.value),
        StoreVertical.pickerVerticals);
    expect(picker(tester).value, StoreVertical.grocery);
    expect(picker(tester).onChanged, isNotNull);
  });

  testWidgets("a service shop's vertical reads Services and cannot be changed",
      (WidgetTester tester) async {
    await _pump(tester, _shop('SERVICES', serviceCategory: 'PRINTING'));

    expect(picker(tester).items!.map((DropdownMenuItem<StoreVertical> i) => i.value),
        <StoreVertical>[StoreVertical.services]);
    expect(picker(tester).value, StoreVertical.services);
    expect(picker(tester).onChanged, isNull);
    expect(find.text(en.svcVerticalServices), findsWidgets);
  });
}
