import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

/// Merchant Blitz, Figma 121:198, driven the way a shopkeeper drives it.
///
/// What is held down here:
///  * opening the page spends nothing — no scan is started, and so no daily allowance used, until a
///    photo is actually picked;
///  * "Take photo" exists only where a camera does, so the portal never draws a dead button;
///  * photos go up one after another on a scan the first one started, and the review button waits,
///    disabled, while the photos are read;
///  * sample results say they are samples, a reading that found nothing says so, and a failure
///    offers a retry only while the server says one is left;
///  * a spent daily allowance is worded with its own number;
///  * the finished page in Arabic on a 320-wide phone does not overflow;
///  * and the Inventory tab is where the door is, when — and only when — its host wires it.
final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAMAASsJTYQAAAAASUVORK5CYII=');

CatalogScan _scan({
  CatalogScanStatus status = CatalogScanStatus.uploading,
  List<ScanPhoto> photos = const <ScanPhoto>[],
  List<ScanLine> lines = const <ScanLine>[],
  bool sample = false,
  ScanFailure? failure,
  int attemptsLeft = 2,
  int? scansLeftToday = 4,
}) =>
    CatalogScan(
      id: 'scan-1',
      storeId: 'store-1',
      status: status,
      photos: photos,
      lines: lines,
      sample: sample,
      provider: sample ? 'FAKE' : 'CLAUDE',
      failure: failure,
      maxPhotos: 6,
      attemptsLeft: attemptsLeft,
      scansLeftToday: scansLeftToday,
    );

ScanLine _line(String id, String name, {double confidence = 0.9, double? guess}) => ScanLine(
      id: id,
      name: name,
      confidence: confidence,
      status: ScanLineStatus.pending,
      photoFileId: 'file-1',
      priceGuess: guess,
      box: const ScanBox(left: 0.1, top: 0.1, width: 0.3, height: 0.3),
    );

/// The scan client, scripted. Records every call in order.
class _FakeScanApi extends CatalogScanApi {
  _FakeScanApi() : super(Dio());

  final List<String> calls = <String>[];
  Object? startError;
  CatalogScan current = _scan();

  /// What "analyze" answers. Defaults to the scan moving to ANALYZING.
  CatalogScan Function(CatalogScan current)? analyzeResult;

  /// Answers to successive reads; the last one repeats.
  final List<CatalogScan> reads = <CatalogScan>[];

  @override
  Future<CatalogScan> start({String? storeId}) async {
    calls.add('start');
    final Object? error = startError;
    if (error != null) throw error;
    return current = _scan();
  }

  @override
  Future<CatalogScan> addPhoto({
    required String scanId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    calls.add('addPhoto $contentType');
    final int n = current.photos.length + 1;
    return current = _scan(photos: <ScanPhoto>[
      ...current.photos,
      ScanPhoto(fileId: 'file-$n', position: n - 1, uploaded: true),
    ]);
  }

  @override
  Future<CatalogScan> analyze(String scanId) async {
    calls.add('analyze');
    final CatalogScan Function(CatalogScan) answer = analyzeResult ??
        (CatalogScan c) => _scan(status: CatalogScanStatus.analyzing, photos: c.photos);
    return current = answer(current);
  }

  @override
  Future<CatalogScan> read(String scanId) async {
    calls.add('read');
    if (reads.isNotEmpty) current = reads.length == 1 ? reads.first : reads.removeAt(0);
    return current;
  }
}

class _FakePhotos extends ShelfPhotoSource {
  _FakePhotos({this.camera = true, this.picks = 1, this.cameraError});

  final bool camera;
  final int picks;

  /// What opening the camera throws — image_picker's answer to a refused camera permission, say.
  final Object? cameraError;

  @override
  bool get canUseCamera => camera;

  @override
  Future<PickedShelfPhoto?> takePhoto() async {
    final Object? error = cameraError;
    if (error != null) throw error;
    return PickedShelfPhoto(bytes: _png, contentType: 'image/png');
  }

  @override
  Future<List<PickedShelfPhoto>> choosePhotos({required String label}) async =>
      List<PickedShelfPhoto>.generate(
          picks, (_) => PickedShelfPhoto(bytes: _png, contentType: 'image/png'));
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

Future<DeliveryStrings> _pump(
  WidgetTester tester,
  Widget home, {
  Locale locale = const Locale('en'),
  Size size = const Size(400, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: DeliveryTheme.light(),
    locale: locale,
    localizationsDelegates: DeliveryStrings.localizationsDelegates,
    supportedLocales: DeliveryStrings.supportedLocales,
    home: home,
  ));
  await tester.pump();
  return DeliveryStrings.of(tester.element(find.byType(Scaffold).first));
}

MerchantBlitzScreen _blitz(_FakeScanApi api, {_FakePhotos? photos}) => MerchantBlitzScreen(
      api: api,
      catalogApi: _FakeCatalog(),
      storeId: 'store-1',
      photoSource: photos ?? _FakePhotos(),
    );

/// Picks the source's photos through "Choose photos" and lets the uploads finish.
Future<void> _choose(WidgetTester tester, DeliveryStrings t) async {
  await tester.tap(find.text(t.blitzChoosePhotos));
  await tester.pump();
  await tester.pump();
}

ElevatedButton _buttonWith(WidgetTester tester, String label) => tester.widget<ElevatedButton>(
    find.ancestor(of: find.text(label), matching: find.byType(ElevatedButton)));

void main() {
  testWidgets('opening the page spends nothing and explains itself', (WidgetTester tester) async {
    final _FakeScanApi api = _FakeScanApi();
    final DeliveryStrings t = await _pump(tester, _blitz(api));

    expect(find.text(t.blitzTitle), findsOneWidget);
    expect(find.text(t.blitzIntroTitle), findsOneWidget);
    expect(find.text(t.blitzTakePhoto), findsOneWidget);
    expect(find.text(t.blitzChoosePhotos), findsOneWidget);
    // The honest footer, not the frame's "Your shop online in 24 hours".
    expect(find.text(t.blitzFooter), findsOneWidget);
    // No scan started, so none of the day's allowance used, by merely looking.
    expect(api.calls, isEmpty);
  });

  testWidgets('where there is no camera there is no camera button', (WidgetTester tester) async {
    final DeliveryStrings t =
        await _pump(tester, _blitz(_FakeScanApi(), photos: _FakePhotos(camera: false)));

    expect(find.text(t.blitzTakePhoto), findsNothing);
    expect(find.text(t.blitzChoosePhotos), findsOneWidget);
  });

  testWidgets('a camera that will not open says so, points at the gallery, and starts nothing',
      (WidgetTester tester) async {
    final _FakeScanApi api = _FakeScanApi();
    final DeliveryStrings t = await _pump(
      tester,
      _blitz(api,
          photos: _FakePhotos(
              cameraError: PlatformException(code: 'camera_access_denied'))),
    );

    await tester.tap(find.text(t.blitzTakePhoto));
    await tester.pump();
    await tester.pump();

    expect(find.text(t.blitzCameraFailed), findsOneWidget);
    // The gallery is still there, and no scan — no share of the day's allowance — was spent on a
    // photo that never came.
    expect(find.text(t.blitzChoosePhotos), findsOneWidget);
    expect(api.calls, isEmpty);
  });

  testWidgets(
      'photos go up one at a time on a scan the first starts, then the review waits for the reading',
      (WidgetTester tester) async {
    final _FakeScanApi api = _FakeScanApi();
    final DeliveryStrings t = await _pump(tester, _blitz(api, photos: _FakePhotos(picks: 2)));

    await _choose(tester, t);

    expect(api.calls, <String>['start', 'addPhoto image/png', 'addPhoto image/png']);
    expect(find.text(t.blitzPhotoCount(2, 6)), findsOneWidget);
    expect(find.text(t.blitzScansLeft(4)), findsOneWidget);

    await tester.tap(find.text(t.blitzScanPhotos(2)));
    await tester.pump();

    expect(api.calls.last, 'analyze');
    expect(find.text(t.blitzAnalyzing), findsOneWidget);
    expect(_buttonWith(tester, t.blitzReviewCta).onPressed, isNull);

    // The reading finishes between two polls.
    api.reads.add(_scan(
      status: CatalogScanStatus.complete,
      photos: api.current.photos,
      sample: true,
      lines: <ScanLine>[
        _line('line-1', 'Pepsi 1L', guess: 1.2),
        _line('line-2', "Lay's Classic", guess: 0.8),
      ],
    ));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(api.calls.last, 'read');
    expect(find.text(t.blitzScanComplete), findsOneWidget);
    expect(find.text(t.blitzItemsFound(2)), findsOneWidget);
    // Sample lines are said to be samples, not presented as a reading of this shelf.
    expect(find.text(t.blitzSampleTitle), findsOneWidget);
    expect(_buttonWith(tester, t.blitzReviewCta).onPressed, isNotNull);

    // And the polling stopped with the reading.
    final int reads = api.calls.where((String c) => c == 'read').length;
    await tester.pump(const Duration(seconds: 10));
    expect(api.calls.where((String c) => c == 'read').length, reads);
  });

  testWidgets('a reading that found nothing says so and offers a fresh scan, not an empty review',
      (WidgetTester tester) async {
    final _FakeScanApi api = _FakeScanApi()
      ..analyzeResult =
          (CatalogScan c) => _scan(status: CatalogScanStatus.complete, photos: c.photos);
    final DeliveryStrings t = await _pump(tester, _blitz(api));

    await _choose(tester, t);
    await tester.tap(find.text(t.blitzScanPhotos(1)));
    await tester.pump();

    expect(find.text(t.blitzItemsFound(0)), findsOneWidget);
    expect(find.text(t.blitzNoneFound), findsOneWidget);
    expect(find.text(t.blitzReviewCta), findsNothing);

    await tester.tap(find.text(t.blitzNewScan));
    await tester.pump();
    expect(find.text(t.blitzIntroTitle), findsOneWidget);
  });

  testWidgets('a failed reading offers a retry while one is left, and a new scan once none is',
      (WidgetTester tester) async {
    final _FakeScanApi api = _FakeScanApi()
      ..analyzeResult = (CatalogScan c) => _scan(
            status: CatalogScanStatus.failed,
            photos: c.photos,
            failure: ScanFailure.providerError,
            attemptsLeft: 1,
          );
    final DeliveryStrings t = await _pump(tester, _blitz(api));

    await _choose(tester, t);
    await tester.tap(find.text(t.blitzScanPhotos(1)));
    await tester.pump();

    expect(find.text(t.blitzFailedProvider), findsOneWidget);
    expect(find.text(t.blitzNoRetriesLeft), findsNothing);

    api.analyzeResult = (CatalogScan c) => _scan(
          status: CatalogScanStatus.failed,
          photos: c.photos,
          failure: ScanFailure.refused,
          attemptsLeft: 0,
        );
    await tester.tap(find.text(t.tryAgain));
    await tester.pump();

    expect(api.calls.where((String c) => c == 'analyze').length, 2);
    expect(find.text(t.blitzFailedRefused), findsOneWidget);
    expect(find.text(t.blitzNoRetriesLeft), findsOneWidget);
    expect(find.text(t.tryAgain), findsNothing);
    expect(find.text(t.blitzNewScan), findsOneWidget);
  });

  testWidgets('a spent daily allowance is worded with its own number, and nothing is uploaded',
      (WidgetTester tester) async {
    final RequestOptions request = RequestOptions(path: '/api/products/scans');
    final _FakeScanApi api = _FakeScanApi()
      ..startError = DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: request,
          statusCode: 429,
          data: <String, dynamic>{
            'title': 'Scan limit reached',
            'detail': 'You can start 5 scans a day; try again tomorrow',
            'limit': 5,
          },
        ),
      );
    final DeliveryStrings t = await _pump(tester, _blitz(api));

    await _choose(tester, t);

    expect(find.text(t.blitzQuotaReached(5)), findsOneWidget);
    expect(api.calls, <String>['start']);
  });

  testWidgets('in Arabic on a 320-wide phone the finished scan lays out without overflowing',
      (WidgetTester tester) async {
    final _FakeScanApi api = _FakeScanApi()
      ..analyzeResult = (CatalogScan c) => _scan(
            status: CatalogScanStatus.complete,
            photos: c.photos,
            sample: true,
            scansLeftToday: 3,
            lines: <ScanLine>[
              _line('line-1', 'Tannourine Water 1.5L', guess: 0.6),
              _line('line-2', 'Picon Cheese Portions', confidence: 0.4),
            ],
          );
    final DeliveryStrings t = await _pump(
      tester,
      _blitz(api),
      locale: const Locale('ar'),
      size: const Size(320, 1600),
    );

    await _choose(tester, t);
    await tester.tap(find.text(t.blitzScanPhotos(1)));
    await tester.pump();

    expect(find.text(t.blitzScanComplete), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Inventory opens the scan when its host hands it the client',
      (WidgetTester tester) async {
    final DeliveryStrings t = await _pump(
      tester,
      InventoryScreen(catalogApi: _FakeCatalog(), catalogScanApi: _FakeScanApi(), storeId: 'store-1'),
    );

    await tester.tap(find.text(t.blitzEntryAction).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(MerchantBlitzScreen), findsOneWidget);
  });

  testWidgets('and shows no such door when it is not handed one', (WidgetTester tester) async {
    final DeliveryStrings t = await _pump(tester, InventoryScreen(catalogApi: _FakeCatalog()));

    expect(find.text(t.blitzEntryAction), findsNothing);
  });
}
