import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shop's district, on the merchant's own form.
///
/// The neighbourhood browse lists shops by `stores.neighborhood`, and nothing could ever write
/// it: this form had no field, the client call had no parameter, and the server wrote whatever the
/// profile save sent — nothing — over it on every save. So no shop anywhere had a district. These
/// pin the three halves of the fix that live on the client: the form shows what the shop declared,
/// saves what the merchant typed, and clears it only by saying so with an empty string.
class _Adapter implements HttpClientAdapter {
  _Adapter({this.neighborhood});

  final String? neighborhood;

  /// Every write's method, path and body, in order.
  final List<({String method, String path, Object? body})> writes =
      <({String method, String path, Object? body})>[];

  Map<String, dynamic> get store => <String, dynamic>{
        'id': 'store-1',
        'slug': 'abu-hassan',
        'name': 'Abu Hassan Mini Market',
        'vertical': 'GROCERY',
        'availability': 'OPEN',
        'deliveryFee': 1.0,
        'minOrder': 5.0,
        'etaMinMinutes': 15,
        'etaMaxMinutes': 30,
        'neighborhood': neighborhood,
      };

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    if (options.method != 'GET') {
      writes.add((method: options.method, path: options.path, body: options.data));
    }
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

Future<_Adapter> _pump(WidgetTester tester, {String? neighborhood}) async {
  tester.view.physicalSize = const Size(420, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final _Adapter adapter = _Adapter(neighborhood: neighborhood);
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;

  await tester.pumpWidget(MaterialApp(
    theme: DeliveryTheme.light(),
    localizationsDelegates: DeliveryStrings.localizationsDelegates,
    supportedLocales: DeliveryStrings.supportedLocales,
    home: StoreScreen(api: StoreApi(dio)),
  ));
  await tester.pumpAndSettle();
  return adapter;
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  Finder districtField(String showing) =>
      find.ancestor(of: find.text(showing), matching: find.byType(TextFormField));

  Future<void> save(WidgetTester tester) async {
    final Finder button = find.text(en.merchbSaveShopSettings);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Object? sentDistrict(_Adapter adapter) {
    final ({String method, String path, Object? body}) profile = adapter.writes
        .firstWhere((({String method, String path, Object? body}) w) =>
            w.method == 'PUT' && w.path == '/api/stores/store-1');
    return (profile.body! as Map<String, dynamic>)['neighborhood'];
  }

  testWidgets('the form shows the district the shop declared', (WidgetTester tester) async {
    await _pump(tester, neighborhood: 'Mar Mikhael');

    expect(find.text(en.dekkaneMerchNeighborhood), findsOneWidget);
    expect(districtField('Mar Mikhael'), findsOneWidget);
  });

  testWidgets('saving sends what the merchant typed', (WidgetTester tester) async {
    final _Adapter adapter = await _pump(tester, neighborhood: 'Mar Mikhael');

    await tester.enterText(districtField('Mar Mikhael'), '  Gemmayze ');
    await save(tester);

    expect(sentDistrict(adapter), 'Gemmayze');
  });

  /// Every save sends it, so a tagline edit can never again be the thing that wipes the district.
  testWidgets('saving without touching it sends it back unchanged', (WidgetTester tester) async {
    final _Adapter adapter = await _pump(tester, neighborhood: 'Mar Mikhael');

    await save(tester);

    expect(sentDistrict(adapter), 'Mar Mikhael');
  });

  /// Null would mean "a client that does not know the field" and leave it standing; this client
  /// knows it, so an emptied box has to arrive as a clear.
  testWidgets('emptying the box clears it by sending an empty string, never null',
      (WidgetTester tester) async {
    final _Adapter adapter = await _pump(tester, neighborhood: 'Mar Mikhael');

    await tester.enterText(districtField('Mar Mikhael'), '');
    await save(tester);

    expect(sentDistrict(adapter), '');
  });

  testWidgets('a district longer than the column is refused before anything is saved',
      (WidgetTester tester) async {
    final _Adapter adapter = await _pump(tester, neighborhood: 'Mar Mikhael');

    await tester.enterText(districtField('Mar Mikhael'), 'x' * 81);
    await save(tester);

    expect(find.text(en.dekkaneMerchNeighborhoodTooLong), findsOneWidget);
    expect(adapter.writes, isEmpty);
  });
}
