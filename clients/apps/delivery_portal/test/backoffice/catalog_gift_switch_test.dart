import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_portal/src/backoffice/catalog_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Backoffice's one hand on a live product: putting it on the customer gift hub.
///
/// What is pinned is the conversation with the server — the switch shows what the server holds,
/// asks when flipped, shows the server's answer, and goes back with the reason when refused —
/// because a switch reading "featured" for a product the hub does not show is exactly the kind of
/// quiet lie a back-office user acts on.
class _GiftHubServer implements HttpClientAdapter {
  _GiftHubServer({required this.featured, this.refuse = false});

  final bool featured;
  final bool refuse;
  final List<String> calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    if (options.method == 'PUT') {
      return refuse
          ? _json(<String, dynamic>{
              'detail': 'Only a live product can be featured on the gift hub; this one is ARCHIVED',
            }, 422)
          : _json(<String, dynamic>{
              'productId': 'p1',
              'giftFeatured': true,
              'giftFeaturedAt': '2026-09-13T08:00:00Z',
            }, 200);
    }
    return _json(<String, dynamic>{
      'content': <dynamic>[
        <String, dynamic>{
          'id': 'p1',
          'merchantId': 'badd6a75-edab-4c11-9a2d-c753be63c274',
          'name': 'Family Essentials',
          'price': 45.0,
          'imageRefs': const <String>[],
          'imageUrls': const <String>[],
          'status': 'ACTIVE',
          'giftFeatured': featured,
        },
      ],
      'page': 0,
      'size': 20,
      'totalElements': 1,
      'totalPages': 1,
    }, 200);
  }

  static ResponseBody _json(Object body, int status) => ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType]
        },
      );

  @override
  void close({bool force = false}) {}
}

void main() {
  Future<_GiftHubServer> pump(WidgetTester tester,
      {required bool featured, bool refuse = false}) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final _GiftHubServer server = _GiftHubServer(featured: featured, refuse: refuse);
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = server;
    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      home: Scaffold(body: CatalogScreen(api: CatalogApi(dio))),
    ));
    await tester.pumpAndSettle();
    return server;
  }

  bool switchValue(WidgetTester tester) => tester.widget<Switch>(find.byType(Switch)).value;

  testWidgets('a live product shows whether it is on the gift hub', (WidgetTester tester) async {
    await pump(tester, featured: true);

    expect(find.text('Featured on the gift hub'), findsOneWidget);
    expect(switchValue(tester), isTrue);
  });

  testWidgets('switching it on asks the server and shows what the server says',
      (WidgetTester tester) async {
    final _GiftHubServer server = await pump(tester, featured: false);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(server.calls, contains('PUT /api/products/p1/gift-featured'));
    expect(switchValue(tester), isTrue);
  });

  testWidgets('a refusal puts the switch back and says why', (WidgetTester tester) async {
    await pump(tester, featured: false, refuse: true);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(switchValue(tester), isFalse);
    expect(find.textContaining('Could not update the gift hub'), findsOneWidget);
  });
}
