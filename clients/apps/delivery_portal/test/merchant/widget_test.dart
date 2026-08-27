import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:dio/dio.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delivery_merchant/delivery_merchant.dart';

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

/// The api and the adapter behind it, for the tests that assert on which call a tap made rather
/// than only on what is drawn.
({CatalogApi api, _StubAdapter adapter}) _stub(Object productsPage) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost:8100'));
  final _StubAdapter adapter = _StubAdapter(<String, Object>{
    '/api/products/mine': productsPage,
    '/api/categories': <dynamic>[],
  });
  dio.httpClientAdapter = adapter;
  return (api: CatalogApi(dio), adapter: adapter);
}

CatalogApi _apiReturning(Object productsPage) => _stub(productsPage).api;

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

  /// A draft can be put on the shelf; a live product can only be taken off it.
  ///
  /// The word "Publish" is gone: the redesign replaced the row's overflow menu (Edit / Publish /
  /// Archive) with the frame's availability switch, so publishing is now one tap on a toggle
  /// rather than two taps through a menu. The rule the old assertion stood for is untouched, and
  /// it is the rule — not the word — that this protects. A DRAFT must offer the merchant a way to
  /// publish it, and a live product must not offer publishing again; the switch expresses both by
  /// which way it points and by which call the tap makes.
  ///
  /// Asserted on the request rather than on the switch's pixels, because "offers Publish" has
  /// always meant "can reach POST /api/products/{id}/publish from this row".
  group('a draft offers Publish, a live product does not', () {
    Future<_StubAdapter> pumpOne(WidgetTester tester, String status) async {
      final ({CatalogApi api, _StubAdapter adapter}) stub = _stub(<String, dynamic>{
        'content': <dynamic>[_product(id: '2', name: 'Draft item', status: status)],
        'page': 0,
        'size': 20,
        'totalElements': 1,
        'totalPages': 1,
      });

      await tester.pumpWidget(_wrap(ProductListScreen(api: stub.api)));
      await tester.pumpAndSettle();
      return stub.adapter;
    }

    /// The switch, found by the label it carries for a screen reader — the only stable handle on
    /// it from outside the package, and the one a blind merchant uses too.
    Finder availabilitySwitch() => find.bySemanticsLabel('Availability');

    testWidgets('a draft', (WidgetTester tester) async {
      // Semantics is off unless a test asks for it, and it has to be on before the tree is built
      // for the labels below to exist at all. Disposed inside the body: the framework checks for a
      // live handle at the end of the test, which is before any tearDown runs.
      final SemanticsHandle handle = tester.ensureSemantics();

      final _StubAdapter adapter = await pumpOne(tester, 'DRAFT');

      // The row still names the state in words. "Draft" rather than "Off-shelf": a draft has never
      // been published and usually cannot be yet, and that is the thing the merchant has to fix.
      expect(find.text('Draft'), findsOneWidget);
      expect(find.text('Available'), findsNothing);

      await tester.tap(availabilitySwitch());
      await tester.pumpAndSettle();

      expect(adapter.requestedPaths, contains('/api/products/2/publish'));

      handle.dispose();
    });

    testWidgets('a live product', (WidgetTester tester) async {
      // Semantics is off unless a test asks for it, and it has to be on before the tree is built
      // for the labels below to exist at all. Disposed inside the body: the framework checks for a
      // live handle at the end of the test, which is before any tearDown runs.
      final SemanticsHandle handle = tester.ensureSemantics();

      final _StubAdapter adapter = await pumpOne(tester, 'ACTIVE');

      expect(find.text('Available'), findsOneWidget);
      expect(find.text('Draft'), findsNothing);

      // The same tap on a live product cannot publish it. It offers to withdraw it instead, behind
      // a confirmation — taking a listing off the shelf is not destructive, but it does stop
      // customers finding it.
      await tester.tap(availabilitySwitch());
      await tester.pumpAndSettle();

      expect(find.text('Archive this product?'), findsOneWidget);
      expect(
        adapter.requestedPaths.where((String path) => path.contains('publish')),
        isEmpty,
      );

      handle.dispose();
    });
  });

  /// The card grid, at the widths it actually has to survive.
  ///
  /// Every UI bug found in this project so far has been a layout overflow that only appears at a
  /// particular width — and Flutter fails a test on overflow, so simply rendering at several sizes
  /// catches them. This is the closest thing to the browser check nobody can run here.
  ///
  /// The 2026-08 redesign changed what a cell *is* — a lifted [SoftCard] holding a photo above a
  /// name and a row of buttons became a bordered [YdCard] holding a 64px photo, the name and price,
  /// and an availability switch — but not what a cell is *in*. One widget serves two hosts: the
  /// Android app gives it 360dp and gets the frame's single column, while the portal gives it most
  /// of a desktop beside its navigation rail, and a 1400px-wide pane drawing one 1400px-wide row
  /// would be a worse screen than the one this replaced. So the row shape is the design's at every
  /// width and only the column count moves, which is what these still measure.
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
      expect(find.byType(YdCard), findsWidgets);
    });

    testWidgets('lays out at a typical laptop width', (WidgetTester tester) async {
      await pumpAt(tester, const Size(1280, 900));
      expect(find.byType(YdCard), findsWidgets);
    });

    testWidgets('lays out on a wide monitor', (WidgetTester tester) async {
      await pumpAt(tester, const Size(2400, 1200));
      expect(find.byType(YdCard), findsWidgets);
    });

    testWidgets('reflows into more columns as the window widens',
        (WidgetTester tester) async {
      // The point of maxCrossAxisExtent over a fixed column count: no breakpoint table, and the
      // grid genuinely uses the space a stretched page now gives it.
      //
      // Counted off where the cards actually landed rather than divided out of the sliver's
      // cross-axis extent: the extent measured the window, and dividing it by the delegate's
      // current tile width only restated the arithmetic the screen had just done. Cards sharing
      // the topmost row are the outcome, and the outcome is the thing worth asserting — it stays
      // true through a change of tile width, and it is false the moment the phone's single column
      // is served to a monitor.
      int columnsAt(WidgetTester tester) {
        final Finder cards = find.byType(YdCard);
        final List<double> tops = <double>[
          for (int i = 0; i < cards.evaluate().length; i++) tester.getTopLeft(cards.at(i)).dy,
        ];
        expect(tops, isNotEmpty);
        final double first = tops.reduce((double a, double b) => a < b ? a : b);
        return tops.where((double dy) => dy == first).length;
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
      //
      // The row draws one photo and the preview behind it draws all of them, so a product with
      // several has to say so or the extra ones are invisible and there is no reason to tap. The
      // count moved from a caption on the old card to a badge in the corner of the new 64px
      // thumbnail; that it is *there at all* is the guarantee.
      expect(find.byIcon(Icons.photo_library_outlined), findsNWidgets(2));
    });

    testWidgets('a product with no photo says so rather than showing a broken frame',
        (WidgetTester tester) async {
      // Semantics is off unless a test asks for it, and it has to be on before the tree is built
      // for the labels below to exist at all. Disposed inside the body: the framework checks for a
      // live handle at the end of the test, which is before any tearDown runs.
      final SemanticsHandle handle = tester.ensureSemantics();

      await pumpAt(tester, const Size(1280, 900));

      // "No photo" is a normal state for a DRAFT — Phase 1 will not publish without an image, so
      // the gap is expected until then and must not look like a failure.
      //
      // The sentence is no longer printed under the glyph: the redesign's row gives the thumbnail
      // a 64px square and the caption does not fit inside it. It is still said, in the two places
      // that survive at that size — a tooltip for a pointer and a label for a screen reader — so
      // that is where this reads it. Four of the six fixtures carry no image.
      expect(find.byTooltip('No photo'), findsNWidgets(4));
      // Matched loosely on purpose: a label-only annotation has no semantics node of its own, so
      // "No photo" is spoken as part of the row's node, after the product's name and price. What
      // matters is that the row says it at all.
      expect(find.bySemanticsLabel(RegExp('No photo')), findsNWidgets(4));

      handle.dispose();
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
