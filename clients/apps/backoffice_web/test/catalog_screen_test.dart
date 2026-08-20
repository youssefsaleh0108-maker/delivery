import 'dart:convert';

import 'package:backoffice_web/src/catalog_screen.dart';
import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The catalog grid, at the widths it has to survive.
///
/// Flutter fails a test on a layout overflow, so rendering at several sizes is the cheapest way to
/// catch the class of bug that has accounted for every UI defect found in this project — and the
/// closest available stand-in for the browser check nobody can run here.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body);

  final Object body;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType]
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _product(int i) => <String, dynamic>{
      'id': '$i',
      'merchantId': 'badd6a75-edab-4c11-9a2d-c753be63c274',
      'name': 'Slow-Roasted Something With A Very Long Product Name $i',
      'description': 'A description that is also quite long, as descriptions tend to be.',
      'price': 12.5,
      'categoryId': null,
      'imageRefs': const <String>[],
      'imageUrls': i.isEven
          ? const <String>['http://example.test/a.png']
          : const <String>[],
      'status': 'ACTIVE',
      'createdAt': '2026-08-07T10:00:00Z',
      'updatedAt': '2026-08-07T10:00:00Z',
    };

CatalogApi _api({int products = 6}) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))
    ..httpClientAdapter = _StubAdapter(<String, dynamic>{
      'content': <dynamic>[for (int i = 0; i < products; i++) _product(i)],
      'page': 0,
      'size': 20,
      'totalElements': products,
      'totalPages': 1,
    });
  return CatalogApi(dio);
}

void main() {
  Future<void> pumpAt(WidgetTester tester, Size size, {int products = 6}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      home: Scaffold(body: CatalogScreen(api: _api(products: products))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders products as cards, not list rows', (WidgetTester tester) async {
    await pumpAt(tester, const Size(1280, 900));

    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(SoftCard), findsWidgets);
    // The old layout was Card(ListTile(...)) with a 56px leading thumbnail.
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('every card previews its image', (WidgetTester tester) async {
    await pumpAt(tester, const Size(1280, 900));

    expect(find.byType(DeliveryProductImage), findsWidgets);
    // Odd-numbered fixtures carry no image, and that must read as a stated absence rather than a
    // broken frame.
    expect(find.text('No photo'), findsWidgets);
  });

  testWidgets('lays out on a narrow window without overflowing', (WidgetTester tester) async {
    await pumpAt(tester, const Size(420, 900));
    expect(find.byType(SoftCard), findsWidgets);
  });

  testWidgets('lays out on a wide monitor without overflowing', (WidgetTester tester) async {
    await pumpAt(tester, const Size(2400, 1200));
    expect(find.byType(SoftCard), findsWidgets);
  });

  testWidgets('fills the width it is given', (WidgetTester tester) async {
    // The page is a child of the rail shell and should use the whole width. It used to be wrapped
    // in a Center/ConstrainedBox pair that became a no-op once its max width was removed.
    await pumpAt(tester, const Size(2400, 1200));

    final double gridWidth =
        tester.renderObject<RenderBox>(find.byType(GridView)).size.width;
    // Allow for the page padding on either side; the point is that it is not capped near 880.
    expect(gridWidth, greaterThan(2000));
  });

  testWidgets('an empty catalog says where products come from', (WidgetTester tester) async {
    await pumpAt(tester, const Size(1280, 900), products: 0);

    expect(find.textContaining('No live products'), findsOneWidget);
  });
}
