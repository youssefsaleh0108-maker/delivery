import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delivery_merchant/delivery_merchant.dart';

// This portal had no localisation at all — no delegates, no saved locale, no dependency — while the
// market it serves reads Arabic. These assert on what a merchant would actually see.

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.responses);

  final Map<String, Object> responses;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    for (final MapEntry<String, Object> entry in responses.entries) {
      if (options.path.startsWith(entry.key)) {
        return ResponseBody.fromString(jsonEncode(entry.value), 200,
            headers: <String, List<String>>{
              Headers.contentTypeHeader: <String>[Headers.jsonContentType]
            });
      }
    }
    return ResponseBody.fromString('{}', 404);
  }

  @override
  void close({bool force = false}) {}
}

CatalogApi _api() {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost:8100'));
  dio.httpClientAdapter = _StubAdapter(<String, Object>{
    '/api/products/mine': <String, dynamic>{
      'content': <dynamic>[
        <String, dynamic>{
          'id': '1',
          'merchantId': 'm1',
          'name': 'Margherita',
          'description': null,
          'price': 12.5,
          'categoryId': null,
          'imageRefs': <String>[],
          'imageUrls': <String>[],
          'status': 'DRAFT',
          'createdAt': '2026-08-07T10:00:00Z',
          'updatedAt': '2026-08-07T10:00:00Z',
        },
      ],
      'page': 0,
      'size': 20,
      'totalElements': 1,
      'totalPages': 1,
    },
    '/api/categories': <dynamic>[],
  });
  return CatalogApi(dio);
}

Widget _wrap(Widget child, Locale locale) => MaterialApp(
      locale: locale,
      theme: DeliveryTheme.light(),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    );

/// Any Latin letter. A string on an Arabic screen containing one is either untranslated copy or
/// the merchant's own data — and the caller separates those by value.
final RegExp _latin = RegExp('[A-Za-z]');

/// Every string the screen is currently painting.
///
/// The named keys below are a spot-check; this is the net under them, so a literal added to the
/// screen tomorrow cannot pass by simply not being one of the keys anybody thought to assert.
List<String> _visibleText(WidgetTester tester, {required Set<String> ignoring}) {
  return <String>[
    for (final Text text in tester.widgetList<Text>(find.byType(Text)))
      if (text.data case final String value)
        if (value.trim().isNotEmpty && !ignoring.contains(value)) value,
  ];
}

void main() {
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  testWidgets('the product list is Arabic, with no English left behind',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(ProductListScreen(api: _api()), const Locale('ar')));
    await tester.pumpAndSettle();

    // The 2026-08 redesign renamed what this screen calls itself — "My products" became the
    // frame's "Menu Items" over a "Manage availability" subtitle, and the "New product" button
    // became the "Add Product" pill. Same three pieces of chrome, new keys.
    expect(find.text(ar.merchbMenuItems), findsOneWidget);
    expect(find.text(ar.merchbManageAvailability), findsOneWidget);
    expect(find.text(ar.merchbAddProduct), findsOneWidget);
    // The per-row publish button is now the availability switch, which carries no text of its
    // own — the row's translated word is the state label under it. The stub product is a DRAFT.
    expect(find.text(ar.draft), findsWidgets);
    // And the search band the redesign added, which is new surface for English to hide in.
    expect(find.text(ar.merchbSearchMenuItems), findsOneWidget);

    // The regression: every one of these was a hardcoded English literal.
    expect(find.text(en.merchbMenuItems), findsNothing);
    expect(find.text(en.merchbManageAvailability), findsNothing);
    expect(find.text(en.merchbAddProduct), findsNothing);
    expect(find.text(en.draft), findsNothing);
    expect(find.text(en.merchbSearchMenuItems), findsNothing);

    // Everything else on the screen, held to the same rule. The product's name and price are the
    // merchant's own catalog data, not copy, so they are excluded by value rather than by shape.
    final List<String> untranslated =
        _visibleText(tester, ignoring: <String>{'Margherita', '12.50'})
            .where(_latin.hasMatch)
            .toList();
    expect(untranslated, isEmpty,
        reason: 'English left on the Arabic product list: $untranslated');
  });

  testWidgets('lays out right-to-left', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(ProductListScreen(api: _api()), const Locale('ar')));
    await tester.pumpAndSettle();

    expect(Directionality.of(tester.element(find.byType(ProductListScreen))), TextDirection.rtl);
  });

  testWidgets('and stays English under an English locale', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(ProductListScreen(api: _api()), const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text(en.merchbMenuItems), findsOneWidget);
    expect(find.text(ar.merchbMenuItems), findsNothing);
    expect(Directionality.of(tester.element(find.byType(ProductListScreen))), TextDirection.ltr);
  });

  test('the merchant strings all have an Arabic translation', () {
    // Spot-checks across the four screens rather than reflection, which Dart does not offer here.
    for (final String Function(DeliveryStrings) pick in <String Function(DeliveryStrings)>[
      (DeliveryStrings t) => t.merchantPortal,
      (DeliveryStrings t) => t.whoCarriesYourOrders,
      (DeliveryStrings t) => t.openingHours,
      (DeliveryStrings t) => t.archiveThisProduct,
      (DeliveryStrings t) => t.columnAwaitingRider,
    ]) {
      expect(pick(ar), isNotEmpty);
      expect(pick(ar), isNot(pick(en)));
    }
  });
}
