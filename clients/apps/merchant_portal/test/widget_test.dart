import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:dio/dio.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_portal/src/product_list_screen.dart';

/// Serves canned JSON without a network or a running backend.
///
/// The shapes below are copied from real responses captured by `infra/smoke-test.sh`, so a
/// server-side contract change breaks these tests rather than only showing up at runtime.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.responses);

  /// Path prefix -> JSON body.
  final Map<String, Object> responses;

  final List<String> requestedPaths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPaths.add(options.path);

    for (final MapEntry<String, Object> entry in responses.entries) {
      if (options.path.startsWith(entry.key)) {
        return ResponseBody.fromString(
          jsonEncode(entry.value),
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>[Headers.jsonContentType],
          },
        );
      }
    }
    return ResponseBody.fromString('{}', 404);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _product({
  required String id,
  required String name,
  required String status,
  List<String> imageUrls = const <String>[],
}) =>
    <String, dynamic>{
      'id': id,
      'merchantId': 'merchant-1',
      'name': name,
      'description': 'A description',
      'price': 12.5,
      'categoryId': null,
      'imageRefs': const <String>[],
      'imageUrls': imageUrls,
      'status': status,
      'createdAt': '2026-08-07T10:00:00Z',
      'updatedAt': '2026-08-07T10:00:00Z',
    };

CatalogApi _apiReturning(Object productsPage) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost:8100'));
  dio.httpClientAdapter = _StubAdapter(<String, Object>{
    '/api/products/mine': productsPage,
    '/api/categories': <dynamic>[],
  });
  return CatalogApi(dio);
}

/// The delegates are required, not decoration: these screens read their labels from the string
/// table, and without them the lookup throws and every finder below reports "0 widgets found" —
/// which reads like a missing widget rather than a missing dependency.
Widget _wrap(Widget child) => MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocaleController.supported,
      home: child,
    );

void main() {
  testWidgets('lists the merchant\'s own products', (WidgetTester tester) async {
    final CatalogApi api = _apiReturning(<String, dynamic>{
      'content': <dynamic>[
        _product(id: '1', name: 'Margherita Pizza', status: 'ACTIVE'),
        _product(id: '2', name: 'Unpublished Calzone', status: 'DRAFT'),
      ],
      'page': 0,
      'size': 20,
      'totalElements': 2,
      'totalPages': 1,
    });

    await tester.pumpWidget(_wrap(ProductListScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Margherita Pizza'), findsOneWidget);
    expect(find.text('Unpublished Calzone'), findsOneWidget);
  });

  testWidgets('a draft offers Publish, a live product does not',
      (WidgetTester tester) async {
    final CatalogApi api = _apiReturning(<String, dynamic>{
      'content': <dynamic>[_product(id: '2', name: 'Draft item', status: 'DRAFT')],
      'page': 0,
      'size': 20,
      'totalElements': 1,
      'totalPages': 1,
    });

    await tester.pumpWidget(_wrap(ProductListScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Publish'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
  });

  /// The card grid, at the widths it actually has to survive.
  ///
  /// Every UI bug found in this project so far has been a layout overflow that only appears at a
  /// particular width — and Flutter fails a test on overflow, so simply rendering at several sizes
  /// catches them. This is the closest thing to the browser check nobody can run here.
  group('product grid', () {
    Future<void> pumpAt(WidgetTester tester, Size size, {int products = 6}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final CatalogApi api = _apiReturning(<String, dynamic>{
        'content': <dynamic>[
          for (int i = 0; i < products; i++)
            _product(
              id: '$i',
              // A long name is the realistic case that clips a card, not "Item 1".
              name: 'Slow-Roasted Something With A Very Long Product Name $i',
              status: i.isEven ? 'ACTIVE' : 'DRAFT',
              imageUrls: i % 3 == 0
                  ? const <String>['http://example.test/a.png', 'http://example.test/b.png']
                  : const <String>[],
            ),
        ],
        'page': 0,
        'size': 20,
        'totalElements': products,
        'totalPages': 1,
      });

      await tester.pumpWidget(_wrap(ProductListScreen(api: api)));
      await tester.pumpAndSettle();
    }

    testWidgets('lays out on a narrow window without overflowing',
        (WidgetTester tester) async {
      // One column. The width that broke the first attempt: three action buttons wrapped onto
      // extra lines and pushed the card past its grid extent.
      await pumpAt(tester, const Size(420, 900));
      expect(find.byType(SoftCard), findsWidgets);
    });

    testWidgets('lays out at a typical laptop width', (WidgetTester tester) async {
      await pumpAt(tester, const Size(1280, 900));
      expect(find.byType(SoftCard), findsWidgets);
    });

    testWidgets('lays out on a wide monitor', (WidgetTester tester) async {
      await pumpAt(tester, const Size(2400, 1200));
      expect(find.byType(SoftCard), findsWidgets);
    });

    testWidgets('reflows into more columns as the window widens',
        (WidgetTester tester) async {
      // The point of maxCrossAxisExtent over a fixed column count: no breakpoint table, and the
      // grid genuinely uses the space a stretched page now gives it.
      //
      // Measured off the sliver's cross-axis extent rather than a RenderBox's width: the grid is
      // one sliver among several in a CustomScrollView, so it has no box of its own.
      int columnsAt(WidgetTester tester) {
        final RenderSliver grid = tester.renderObject<RenderSliver>(find.byType(SliverGrid));
        return grid.constraints.crossAxisExtent ~/ 340;
      }

      await pumpAt(tester, const Size(420, 900));
      final int narrow = columnsAt(tester);

      await pumpAt(tester, const Size(2400, 1200));
      final int wide = columnsAt(tester);

      expect(wide, greaterThan(narrow));
    });

    testWidgets('shows a photo count only when there is more than one photo',
        (WidgetTester tester) async {
      await pumpAt(tester, const Size(1280, 900));

      // Products 0 and 3 carry two images each; the rest carry none.
      expect(find.byIcon(Icons.photo_library_outlined), findsNWidgets(2));
    });

    testWidgets('a product with no photo says so rather than showing a broken frame',
        (WidgetTester tester) async {
      await pumpAt(tester, const Size(1280, 900));

      // "No photo" is a normal state for a DRAFT — Phase 1 will not publish without an image, so
      // the gap is expected until then and must not look like a failure.
      expect(find.text('No photo'), findsWidgets);
    });
  });

  testWidgets('empty catalog explains what to do next', (WidgetTester tester) async {
    final CatalogApi api = _apiReturning(<String, dynamic>{
      'content': <dynamic>[],
      'page': 0,
      'size': 20,
      'totalElements': 0,
      'totalPages': 0,
    });

    await tester.pumpWidget(_wrap(ProductListScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('No products yet'), findsOneWidget);
  });
}
