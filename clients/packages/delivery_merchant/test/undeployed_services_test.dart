import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// PT-8: the merchant suite's pages on an environment that does not run the service behind them.
///
/// dev and qa run neither pos-service nor inventory-service, and the edge answers every one of
/// their paths with its own plain-text 404. Both screens have a "not available" state and neither
/// could reach it, because both hosts hand them a live client and a client is not evidence that a
/// service exists — so the till drew a working register and the shelf offered a Try again over
/// nothing. These pin the state the server's own answer now puts them in, and, just as importantly,
/// that a service which DOES answer is left alone.
class _Edge implements HttpClientAdapter {
  _Edge({this.missing = const <String>['/api/pos', '/api/inventory']});

  /// Path prefixes the gateway routes nowhere.
  final List<String> missing;

  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    final String path = options.path;
    if (missing.any(path.startsWith)) {
      // Exactly what Traefik sends for a path no router matches.
      return ResponseBody.fromString('404 page not found\n', 404,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['text/plain; charset=utf-8'],
          });
    }
    Object body = <String, dynamic>{'content': <dynamic>[], 'totalElements': 0};
    if (path == '/api/products/mine') {
      body = <String, dynamic>{
        'content': <dynamic>[
          <String, dynamic>{
            'id': 'p1',
            'storeId': 'store-1',
            'name': 'Manoushe',
            'price': 3.5,
            'status': 'ACTIVE',
            'images': <dynamic>[],
          },
        ],
        'totalElements': 1,
      };
    } else if (path == '/api/categories') {
      body = <dynamic>[];
    } else if (path.startsWith('/api/pos') || path.startsWith('/api/inventory')) {
      // A deployed service with nothing to report: the shape that must NOT trip the notice.
      body = path.contains('/items')
          ? <String, dynamic>{'content': <dynamic>[], 'totalElements': 0, 'totalPages': 0}
          : <String, dynamic>{};
    }
    return ResponseBody.fromString(jsonEncode(body), path.contains('/shifts/current') ? 404 : 200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[
            path.contains('/shifts/current')
                ? 'application/problem+json'
                : Headers.jsonContentType,
          ],
        });
  }

  @override
  void close({bool force = false}) {}
}

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      theme: DeliveryTheme.light(),
      supportedLocales: DeliveryStrings.supportedLocales,
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      home: Scaffold(body: child),
    );

Future<Dio> _pump(WidgetTester tester, Widget Function(Dio dio) build,
    {List<String> missing = const <String>['/api/pos', '/api/inventory'],
    Locale locale = const Locale('en')}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))
    ..httpClientAdapter = _Edge(missing: missing);
  await tester.pumpWidget(_wrap(build(dio), locale: locale));
  await tester.pumpAndSettle();
  return dio;
}

void main() {
  group('the register', () {
    testWidgets('says it is not available when nothing is routed at /api/pos',
        (WidgetTester tester) async {
      final Dio dio = await _pump(
          tester,
          (Dio d) => PosTerminalScreen(
                api: PosApi(d),
                catalogApi: CatalogApi(d),
                storeId: 'store-1',
                onCheckout: (BuildContext _, PosSale __) async => null,
              ));
      final DeliveryStrings t = lookupDeliveryStrings(const Locale('en'));

      final _Edge edge = dio.httpClientAdapter as _Edge;
      expect(edge.requests.where((RequestOptions r) => r.path.startsWith('/api/pos')), isNotEmpty,
          reason: 'the page has to ask the server, not the environment it thinks it is on');
      expect(find.text(t.posTerminalUnavailable), findsOneWidget);
    });

    testWidgets('leaves a pos-service that answers alone, even when it answers "no shift"',
        (WidgetTester tester) async {
      await _pump(
          tester,
          (Dio d) => PosTerminalScreen(
                api: PosApi(d),
                catalogApi: CatalogApi(d),
                storeId: 'store-1',
                onCheckout: (BuildContext _, PosSale __) async => null,
              ),
          missing: const <String>['/api/inventory']);
      final DeliveryStrings t = lookupDeliveryStrings(const Locale('en'));

      // A 404 from pos-service itself is the ordinary morning state, not a missing service.
      expect(find.text(t.posTerminalUnavailable), findsNothing);
    });

    testWidgets('a host that was handed no client says the same thing',
        (WidgetTester tester) async {
      await _pump(
          tester,
          (Dio d) => PosTerminalScreen(
                api: null,
                catalogApi: CatalogApi(d),
                storeId: 'store-1',
              ));
      expect(find.text(lookupDeliveryStrings(const Locale('en')).posTerminalUnavailable),
          findsOneWidget);
    });
  });

  group('the shelf', () {
    testWidgets('says it is not switched on, and offers no retry, when /api/inventory is nowhere',
        (WidgetTester tester) async {
      await _pump(
          tester,
          (Dio d) => InventoryScreen(
                api: InventoryApi(d),
                catalogApi: CatalogApi(d),
                storeId: 'store-1',
              ));
      final DeliveryStrings t = lookupDeliveryStrings(const Locale('en'));

      expect(find.text(t.invUnavailable), findsOneWidget);
      expect(find.text(t.invCouldNotLoad), findsNothing,
          reason: 'a service that is not deployed is not a load that failed');
      expect(find.text(t.tryAgain), findsNothing,
          reason: 'there is nothing here to retry into existence');
    });

    testWidgets('an inventory-service that answers keeps its ordinary empty state',
        (WidgetTester tester) async {
      await _pump(
          tester,
          (Dio d) => InventoryScreen(
                api: InventoryApi(d),
                catalogApi: CatalogApi(d),
                storeId: 'store-1',
              ),
          missing: const <String>['/api/pos']);
      final DeliveryStrings t = lookupDeliveryStrings(const Locale('en'));

      expect(find.text(t.invUnavailable), findsNothing);
    });

    testWidgets('and says it in Arabic', (WidgetTester tester) async {
      await _pump(
          tester,
          (Dio d) => InventoryScreen(
                api: InventoryApi(d),
                catalogApi: CatalogApi(d),
                storeId: 'store-1',
              ),
          locale: const Locale('ar'));
      final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

      expect(find.text(ar.invUnavailable), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
