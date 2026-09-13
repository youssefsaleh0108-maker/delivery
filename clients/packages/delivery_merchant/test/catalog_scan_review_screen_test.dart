import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The review behind "Review and save as drafts" — every line the reader found, kept or skipped.
///
/// Held down here:
///  * the reader's price guess is never put in the price box for the merchant: it sits beside it,
///    labelled, and a line cannot be saved on the guess alone;
///  * prices follow the server's own rule for every product — above zero, at most two decimals — and
///    a price typed with an Arabic keyboard is still a price;
///  * each switch decides its own line, the button counts what will be saved, and one request
///    carries every keep and every skip;
///  * a suggested section the shop does not have is shown, and saved, as no section;
///  * after saving, the page says the drafts are hidden and need a photo, and hands the scan back;
///  * and the page in Arabic on a 320-wide phone does not overflow.
CatalogScan _scanWith(List<ScanLine> lines, {bool sample = false}) => CatalogScan(
      id: 'scan-1',
      storeId: 'store-1',
      status: CatalogScanStatus.complete,
      photos: const <ScanPhoto>[ScanPhoto(fileId: 'file-1', position: 0, uploaded: true)],
      lines: lines,
      sample: sample,
      provider: sample ? 'FAKE' : 'CLAUDE',
      attemptsLeft: 1,
      scansLeftToday: 4,
    );

ScanLine _line(
  String id,
  String name, {
  double confidence = 0.9,
  double? guess,
  double? price,
  String? categoryId,
  String? brand,
  String? size,
}) =>
    ScanLine(
      id: id,
      name: name,
      confidence: confidence,
      status: ScanLineStatus.pending,
      photoFileId: 'file-1',
      priceGuess: guess,
      price: price,
      categoryId: categoryId,
      brand: brand,
      size: size,
    );

/// Records the one commit and answers with the lines decided the way it was asked.
class _FakeScanApi extends CatalogScanApi {
  _FakeScanApi(this.base) : super(Dio());

  final CatalogScan base;
  int commits = 0;
  List<ScanLineDecision>? accepted;
  List<String>? rejected;

  /// When set, the commit's answer waits for it: a save still on the wire.
  Completer<void>? gate;

  @override
  Future<CatalogScan> commit({
    required String scanId,
    required List<ScanLineDecision> accept,
    required List<String> reject,
  }) async {
    commits++;
    accepted = accept;
    rejected = reject;
    final Completer<void>? held = gate;
    if (held != null) await held.future;
    final Set<String> kept = accept.map((ScanLineDecision d) => d.lineId).toSet();
    return CatalogScan(
      id: base.id,
      storeId: base.storeId,
      status: CatalogScanStatus.complete,
      photos: base.photos,
      lines: <ScanLine>[
        for (final ScanLine l in base.lines)
          ScanLine(
            id: l.id,
            name: l.name,
            confidence: l.confidence,
            photoFileId: l.photoFileId,
            status: kept.contains(l.id) ? ScanLineStatus.accepted : ScanLineStatus.rejected,
            productId: kept.contains(l.id) ? 'product-${l.id}' : null,
          ),
      ],
      attemptsLeft: 1,
      scansLeftToday: 4,
    );
  }
}

class _FakeCatalog extends CatalogApi {
  _FakeCatalog() : super(Dio());

  @override
  Future<List<Category>> categories() async =>
      const <Category>[Category(id: 'cat-drinks', name: 'Drinks')];

  @override
  Future<List<Category>> storeCategories(String storeId) async =>
      const <Category>[Category(id: 'cat-own', name: 'Cold Drinks', storeId: 'store-1')];
}

/// Pushes the review from a host page, so what it pops is observable.
Future<DeliveryStrings> _open(
  WidgetTester tester, {
  required _FakeScanApi api,
  List<CatalogScan?>? results,
  Locale locale = const Locale('en'),
  Size size = const Size(420, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: DeliveryTheme.light(),
    locale: locale,
    localizationsDelegates: DeliveryStrings.localizationsDelegates,
    supportedLocales: DeliveryStrings.supportedLocales,
    home: Builder(
      builder: (BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async {
              final CatalogScan? result = await Navigator.of(context).push<CatalogScan>(
                MaterialPageRoute<CatalogScan>(
                  builder: (_) => CatalogScanReviewScreen(
                    api: api,
                    catalogApi: _FakeCatalog(),
                    scan: api.base,
                    storeId: 'store-1',
                  ),
                ),
              );
              results?.add(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return DeliveryStrings.of(tester.element(find.byType(CatalogScanReviewScreen)));
}

Finder _priceFields(DeliveryStrings t) => find.widgetWithText(TextField, t.blitzPriceUsd);

Future<void> _tapSave(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('the price guess sits beside the price box, never in it, until the merchant uses it',
      (WidgetTester tester) async {
    final _FakeScanApi api = _FakeScanApi(_scanWith(<ScanLine>[_line('line-1', 'Pepsi 1L', guess: 1.2)]));
    final DeliveryStrings t = await _open(tester, api: api);

    expect(tester.widget<TextField>(_priceFields(t)).controller!.text, isEmpty);
    expect(find.text(t.blitzGuess(r'$1.20')), findsOneWidget);

    // A guess is not a price: saving now is refused, and nothing is sent.
    await _tapSave(tester, t.blitzSaveDrafts(1));
    expect(api.commits, 0);
    expect(find.text(t.blitzNeedPrice), findsOneWidget);

    await tester.tap(find.text(t.blitzUseGuess));
    await tester.pump();
    expect(tester.widget<TextField>(_priceFields(t)).controller!.text, '1.20');
  });

  testWidgets("prices follow the server's rule, and an Arabic keyboard's price is still a price",
      (WidgetTester tester) async {
    final _FakeScanApi api = _FakeScanApi(_scanWith(<ScanLine>[_line('line-1', 'Nido Milk Powder')]));
    final DeliveryStrings t = await _open(tester, api: api);

    for (final (String typed, String error) in <(String, String)>[
      ('0', t.blitzNeedPrice),
      ('-2', t.blitzNeedPrice),
      ('abc', t.blitzNeedPrice),
      ('1.205', t.blitzPriceDecimals),
    ]) {
      await tester.enterText(_priceFields(t), typed);
      await _tapSave(tester, t.blitzSaveDrafts(1));
      expect(find.text(error), findsOneWidget, reason: typed);
    }
    expect(api.commits, 0);

    // Arabic-Indic digits and the Arabic decimal separator.
    await tester.enterText(_priceFields(t), '٩٫٥٠');
    await _tapSave(tester, t.blitzSaveDrafts(1));

    expect(api.commits, 1);
    expect(api.accepted!.single.price, 9.5);
  });

  testWidgets('each switch decides its line, the button counts, and one request carries it all',
      (WidgetTester tester) async {
    final _FakeScanApi api = _FakeScanApi(_scanWith(<ScanLine>[
      _line('line-1', 'Pepsi 1L', brand: 'Pepsi', size: '1 L'),
      _line('line-2', "Lay's Classic"),
      _line('line-3', 'Mystery tin', confidence: 0.3),
    ]));
    final DeliveryStrings t = await _open(tester, api: api);

    expect(find.text(t.blitzSaveDrafts(3)), findsOneWidget);
    // The doubtful line comes first, and says it is doubtful.
    expect(find.text(t.blitzCheckThis), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    await tester.pump();

    expect(find.text(t.blitzSaveDrafts(2)), findsOneWidget);
    // A skipped line asks for nothing more.
    expect(_priceFields(t), findsNWidgets(2));

    await tester.enterText(_priceFields(t).at(0), '1.25');
    await tester.enterText(_priceFields(t).at(1), '0.8');
    await _tapSave(tester, t.blitzSaveDrafts(2));

    expect(api.commits, 1);
    expect(api.accepted!.map((ScanLineDecision d) => d.lineId), <String>['line-1', 'line-2']);
    expect(api.accepted!.map((ScanLineDecision d) => d.price), <double>[1.25, 0.8]);
    expect(api.rejected, <String>['line-3']);
  });

  testWidgets('with every line switched off the button skips them all', (WidgetTester tester) async {
    final _FakeScanApi api = _FakeScanApi(_scanWith(<ScanLine>[_line('line-1', 'Pepsi 1L')]));
    final DeliveryStrings t = await _open(tester, api: api);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await _tapSave(tester, t.blitzSkipAll);

    expect(api.accepted, isEmpty);
    expect(api.rejected, <String>['line-1']);
  });

  testWidgets('a suggested section the shop does not have is shown, and saved, as no section',
      (WidgetTester tester) async {
    final _FakeScanApi api = _FakeScanApi(_scanWith(<ScanLine>[
      _line('line-1', 'Pepsi 1L', price: 1, categoryId: 'cat-own'),
      _line('line-2', 'Old tin', price: 2, categoryId: 'cat-gone'),
    ]));
    final DeliveryStrings t = await _open(tester, api: api);
    await tester.pump();

    final List<DropdownButtonFormField<String?>> pickers = tester
        .widgetList<DropdownButtonFormField<String?>>(find.byType(DropdownButtonFormField<String?>))
        .toList();
    expect(pickers.map((DropdownButtonFormField<String?> p) => p.initialValue),
        <String?>['cat-own', null]);

    await _tapSave(tester, t.blitzSaveDrafts(2));
    expect(api.accepted!.map((ScanLineDecision d) => d.categoryId), <String?>['cat-own', null]);
  });

  testWidgets('once saved it says the drafts are hidden and need a photo, and hands the scan back',
      (WidgetTester tester) async {
    final List<CatalogScan?> results = <CatalogScan?>[];
    final _FakeScanApi api = _FakeScanApi(_scanWith(<ScanLine>[_line('line-1', 'Pepsi 1L', price: 2.5)]));
    final DeliveryStrings t = await _open(tester, api: api, results: results);

    await _tapSave(tester, t.blitzSaveDrafts(1));

    expect(find.text(t.blitzSavedTitle), findsOneWidget);
    expect(find.text(t.blitzSavedCount(1)), findsOneWidget);
    expect(find.text(t.blitzSavedHint), findsOneWidget);
    expect(api.accepted!.single.price, 2.5);

    await tester.tap(find.text(t.blitzDone));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(CatalogScanReviewScreen), findsNothing);
    expect(results.single?.lines.single.status, ScanLineStatus.accepted);
  });

  testWidgets('leaving while the save is on the wire waits for it, so its answer is never lost',
      (WidgetTester tester) async {
    final List<CatalogScan?> results = <CatalogScan?>[];
    final _FakeScanApi api =
        _FakeScanApi(_scanWith(<ScanLine>[_line('line-1', 'Pepsi 1L', price: 2.5)]))
          ..gate = Completer<void>();
    final DeliveryStrings t = await _open(tester, api: api, results: results);
    final NavigatorState navigator = tester.state<NavigatorState>(find.byType(Navigator));

    await _tapSave(tester, t.blitzSaveDrafts(1));
    expect(api.commits, 1);

    // Back, mid-save — the same pop the header's arrow and the system back ask for. Had the page
    // closed here, the Blitz screen would still offer to review a line that is already a product.
    await navigator.maybePop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CatalogScanReviewScreen), findsOneWidget);
    expect(results, isEmpty);

    api.gate!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text(t.blitzSavedTitle), findsOneWidget);

    // And back now leaves, carrying the saved scan home.
    await navigator.maybePop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CatalogScanReviewScreen), findsNothing);
    expect(results.single?.lines.single.status, ScanLineStatus.accepted);
  });

  testWidgets('in Arabic on a 320-wide phone the review lays out without overflowing',
      (WidgetTester tester) async {
    final _FakeScanApi api = _FakeScanApi(_scanWith(
      <ScanLine>[
        _line('line-1', 'Al Wadi Al Akhdar Tahini Paste Premium', confidence: 0.4, guess: 2.2,
            brand: 'Al Wadi Al Akhdar', size: '400 g', categoryId: 'cat-own'),
        _line('line-2', 'Kinder Bueno', guess: 1),
      ],
      sample: true,
    ));
    await _open(tester, api: api, locale: const Locale('ar'), size: const Size(320, 2400));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
