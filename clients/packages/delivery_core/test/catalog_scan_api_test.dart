import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Merchant Blitz's client, against a recording adapter.
///
/// Pinned here: the verbs and paths product-service's `CatalogScanController` serves; that a shelf
/// photo's bytes go to the presigned URL on a bare client carrying NO Authorization header (storage
/// refuses a presigned request that also presents one, which is exactly the failure a shared client
/// would produce); that the presign asks for the type actually being sent; that nothing is uploaded
/// when the photo is over the presign's own ceiling; and that a price travels as the two-decimal
/// string the merchant confirmed rather than as a float.
///
/// And the model half: an unknown status or failure code this build has never heard of reads as
/// `unknown` rather than as a guess, and a box that does not fit its photo is dropped so no tag is
/// ever drawn where the product is not.
class _Recorder implements HttpClientAdapter {
  _Recorder(this.respond);

  final Object? Function(RequestOptions options) respond;
  final List<RequestOptions> requests = <RequestOptions>[];
  final Map<String, Uint8List> bodies = <String, Uint8List>{};

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    if (requestStream != null) {
      final BytesBuilder sent = BytesBuilder();
      await for (final Uint8List chunk in requestStream) {
        sent.add(chunk);
      }
      bodies['${options.method} ${options.uri}'] = sent.takeBytes();
    }
    final Object? body = respond(options);
    if (body == null) return ResponseBody.fromString('', 200);
    return ResponseBody.fromString(jsonEncode(body), 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _scan({
  String status = 'UPLOADING',
  List<Map<String, dynamic>> photos = const <Map<String, dynamic>>[],
  List<Map<String, dynamic>> items = const <Map<String, dynamic>>[],
  bool sample = false,
  String? failureCode,
  int attemptsLeft = 2,
  int? scansLeftToday = 4,
}) =>
    <String, dynamic>{
      'id': 'scan-1',
      'storeId': 'store-1',
      'status': status,
      'provider': sample ? 'FAKE' : null,
      'sample': sample,
      'failureCode': failureCode,
      'maxPhotos': 6,
      'attemptsLeft': attemptsLeft,
      if (scansLeftToday != null) 'scansLeftToday': scansLeftToday,
      'photos': photos,
      'items': items,
      'createdAt': '2026-09-12T08:00:00Z',
      'completedAt': null,
    };

void main() {
  late _Recorder app;
  late Dio dio;

  Dio appDio(Object? Function(RequestOptions options) respond) {
    app = _Recorder(respond);
    return Dio(BaseOptions(
      baseUrl: 'http://gateway',
      headers: <String, dynamic>{'Authorization': 'Bearer app-token'},
    ))
      ..httpClientAdapter = app;
  }

  group('the scan calls', () {
    setUp(() {
      dio = appDio((RequestOptions o) => _scan());
    });

    test('a scan starts in the named shop, or in the merchant\'s own when none is named', () async {
      final CatalogScanApi api = CatalogScanApi(dio);

      await api.start(storeId: 'store-9');
      await api.start();

      expect(app.requests.map((RequestOptions r) => '${r.method} ${r.path}'),
          <String>['POST /api/products/scans', 'POST /api/products/scans']);
      expect(app.requests[0].data, <String, dynamic>{'storeId': 'store-9'});
      expect(app.requests[1].data, <String, dynamic>{});
    });

    test('analysing, reading, correcting and skipping each hit their own path', () async {
      final CatalogScanApi api = CatalogScanApi(dio);

      await api.analyze('scan-1');
      await api.read('scan-1');
      await api.updateLine(scanId: 'scan-1', lineId: 'line-1', name: 'Pepsi 1L', price: 1.2);
      await api.rejectLine(scanId: 'scan-1', lineId: 'line-2');

      expect(app.requests.map((RequestOptions r) => '${r.method} ${r.path}'), <String>[
        'POST /api/products/scans/scan-1/analyze',
        'GET /api/products/scans/scan-1',
        'PUT /api/products/scans/scan-1/items/line-1',
        'POST /api/products/scans/scan-1/items/line-2/reject',
      ]);
      // A string with two decimals, never 1.2 as a float.
      expect(app.requests[2].data, <String, dynamic>{'name': 'Pepsi 1L', 'price': '1.20'});
    });

    test('the review goes in one request, prices as two-decimal strings, skipped lines by id',
        () async {
      final CatalogScanApi api = CatalogScanApi(dio);

      await api.commit(
        scanId: 'scan-1',
        accept: const <ScanLineDecision>[
          ScanLineDecision(lineId: 'line-1', name: 'Pepsi 1L', price: 1.2, categoryId: 'cat-1'),
          ScanLineDecision(lineId: 'line-2', name: "Lay's Classic", price: 0.8),
        ],
        reject: const <String>['line-3'],
      );

      expect(app.requests.single.path, '/api/products/scans/scan-1/commit');
      expect(app.requests.single.data, <String, dynamic>{
        'accept': <Map<String, dynamic>>[
          <String, dynamic>{
            'itemId': 'line-1',
            'name': 'Pepsi 1L',
            'price': '1.20',
            'categoryId': 'cat-1',
          },
          <String, dynamic>{'itemId': 'line-2', 'name': "Lay's Classic", 'price': '0.80'},
        ],
        'reject': <String>['line-3'],
      });
    });
  });

  group('a shelf photo upload', () {
    final Uint8List bytes = Uint8List.fromList(List<int>.generate(64, (int i) => i));

    Map<String, dynamic> presign({int maxSizeBytes = 10 * 1024 * 1024}) => <String, dynamic>{
          'fileId': 'file-1',
          'uploadUrl': 'http://minio:9000/product-images/scans/scan-1/file-1.jpg?X-Amz-Signature=abc',
          'objectKey': 'scans/scan-1/file-1.jpg',
          'contentType': 'image/jpeg',
          'expiresAt': '2026-09-12T08:15:00Z',
          'maxSizeBytes': maxSizeBytes,
        };

    test('is presigned, PUT to storage on a bare client with no app token, then confirmed',
        () async {
      dio = appDio((RequestOptions o) => o.path.endsWith('/photos')
          ? presign()
          : _scan(photos: <Map<String, dynamic>>[
              <String, dynamic>{'fileId': 'file-1', 'position': 0, 'status': 'UPLOADED'},
            ]));
      final _Recorder storage = _Recorder((_) => null);
      final CatalogScanApi api = CatalogScanApi(
        dio,
        uploadClient: () => Dio()..httpClientAdapter = storage,
      );

      final CatalogScan scan =
          await api.addPhoto(scanId: 'scan-1', bytes: bytes, contentType: 'image/jpeg');

      expect(app.requests.map((RequestOptions r) => '${r.method} ${r.path}'), <String>[
        'POST /api/products/scans/scan-1/photos',
        'POST /api/products/scans/scan-1/photos/file-1/confirm',
      ]);
      expect(app.requests.first.data, <String, dynamic>{'contentType': 'image/jpeg'});

      final RequestOptions put = storage.requests.single;
      expect(put.method, 'PUT');
      // Exactly as issued: the signature covers the host and the query.
      expect(put.uri.toString(), presign()['uploadUrl']);
      expect(put.headers.keys.map((String k) => k.toLowerCase()), isNot(contains('authorization')));
      expect(put.headers[Headers.contentTypeHeader], 'image/jpeg');
      expect(storage.bodies['PUT ${put.uri}'], bytes);

      expect(scan.uploadedPhotos.single.fileId, 'file-1');
    });

    test('over the presign\'s ceiling is refused before a byte leaves or anything is confirmed',
        () async {
      dio = appDio((RequestOptions o) => presign(maxSizeBytes: 10));
      final _Recorder storage = _Recorder((_) => null);
      final CatalogScanApi api = CatalogScanApi(
        dio,
        uploadClient: () => Dio()..httpClientAdapter = storage,
      );

      await expectLater(
        api.addPhoto(scanId: 'scan-1', bytes: bytes, contentType: 'image/jpeg'),
        throwsArgumentError,
      );
      expect(storage.requests, isEmpty);
      expect(app.requests.map((RequestOptions r) => r.path),
          <String>['/api/products/scans/scan-1/photos']);
    });
  });

  group('reading a scan', () {
    test('states and failure codes this build does not know read as unknown, not as a guess', () {
      final CatalogScan scan = CatalogScan.fromJson(_scan(status: 'ARCHIVED', failureCode: 'QUOTA'));

      expect(scan.status, CatalogScanStatus.unknown);
      expect(scan.failure, ScanFailure.unknown);
      expect(CatalogScan.fromJson(_scan()).failure, isNull);
      expect(CatalogScan.fromJson(_scan(status: 'FAILED', failureCode: 'REFUSED')).failure,
          ScanFailure.refused);
    });

    test('a box that leaves its photo is dropped, and a guess stays apart from the price', () {
      final CatalogScan scan = CatalogScan.fromJson(_scan(
        status: 'COMPLETE',
        sample: true,
        items: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'line-1',
            'photoFileId': 'file-1',
            'name': 'Pepsi 1L',
            'confidence': 0.93,
            'priceGuess': 1.2,
            'price': null,
            'box': <String, dynamic>{'left': 0.1, 'top': 0.2, 'width': 0.3, 'height': 0.4},
            'status': 'PENDING',
          },
          <String, dynamic>{
            'id': 'line-2',
            'photoFileId': 'file-1',
            'name': 'Mystery tin',
            'confidence': 0.4,
            'box': <String, dynamic>{'left': 0.8, 'top': 0.2, 'width': 0.5, 'height': 0.4},
            'status': 'ACCEPTED',
            'productId': 'product-1',
          },
        ],
      ));

      expect(scan.sample, isTrue);
      expect(scan.lines[0].box, isNotNull);
      expect(scan.lines[0].priceGuess, 1.2);
      expect(scan.lines[0].price, isNull);
      expect(scan.lines[0].isDoubtful, isFalse);
      expect(scan.lines[1].box, isNull);
      expect(scan.lines[1].isDoubtful, isTrue);
      expect(scan.pendingLines.map((ScanLine l) => l.id), <String>['line-1']);
    });

    test('no daily count from an older server is no number, and only a failed scan retries', () {
      expect(CatalogScan.fromJson(_scan(scansLeftToday: null)).scansLeftToday, isNull);
      expect(CatalogScan.fromJson(_scan(status: 'FAILED', attemptsLeft: 1)).canRetry, isTrue);
      expect(CatalogScan.fromJson(_scan(status: 'FAILED', attemptsLeft: 0)).canRetry, isFalse);
      expect(CatalogScan.fromJson(_scan(status: 'COMPLETE', attemptsLeft: 1)).canRetry, isFalse);
    });
  });
}
