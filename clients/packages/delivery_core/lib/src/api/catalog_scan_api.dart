import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/catalog_scan_models.dart';
import '../util/image_prep.dart';

/// Merchant Blitz, over product-service's `/api/products/scans`.
///
/// The flow the screen drives: [current] first, to pick up a scan left waiting; otherwise [start] a
/// scan, [addPhoto] once per shelf photo, [analyze], then [read] until the status leaves
/// `analyzing`, and finally [commit] the merchant's review. Every call is MERCHANT-only on the server
/// and scoped to the caller's own scans.
class CatalogScanApi {
  CatalogScanApi(this._dio, {Dio Function()? uploadClient})
      : _uploadClient = uploadClient ?? Dio.new;

  final Dio _dio;

  /// Builds the client the photo bytes are PUT with. A fresh, bare Dio by default — see [addPhoto]
  /// for why it must not be the app's own. Injectable so a test can see the PUT.
  final Dio Function() _uploadClient;

  /// The largest shelf photo sent. Larger than a product photo's ceiling on purpose: the server
  /// reads a shelf at about 1568px on the long edge, and small print on packaging is exactly what a
  /// product-photo downscale would blur away.
  static const int maxShelfPhotoBytes = 2 * 1024 * 1024;

  static const String _base = '/api/products/scans';

  /// The merchant's newest scan from the last day that still waits on them — photos still to add, a
  /// reading under way or retryable, lines not yet decided — or null when there is none.
  ///
  /// What the screen asks on opening, so a scan it lost (an app Android killed mid-capture, a
  /// merchant who left during the reading, a reloaded tab) is picked up rather than a new one spent.
  /// [storeId] narrows it to one of the merchant's shops.
  Future<CatalogScan?> current({String? storeId}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '$_base/current',
      queryParameters: <String, dynamic>{if (storeId != null) 'storeId': storeId},
    );
    final Object? body = response.data;
    // 204 when nothing is waiting.
    if (response.statusCode == 204 || body is! Map<String, dynamic>) return null;
    return CatalogScan.fromJson(body);
  }

  /// Starts a scan. Fails with 429 once the day's scans are spent.
  Future<CatalogScan> start({String? storeId}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      _base,
      data: <String, dynamic>{if (storeId != null) 'storeId': storeId},
    );
    return CatalogScan.fromJson(response.data as Map<String, dynamic>);
  }

  /// Uploads one shelf photo with the platform's three-step flow, and returns the scan as the
  /// server now sees it.
  Future<CatalogScan> addPhoto({
    required String scanId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    // Shrunk first, and presigned for what will actually be sent — re-encoding makes it JPEG.
    final PreparedImage prepared =
        ImagePrep.forUpload(bytes, contentType, maxBytes: maxShelfPhotoBytes);

    // 1. A one-shot URL. The server checks the scan is ours and still taking photos.
    final Response<dynamic> presign = await _dio.post<dynamic>(
      '$_base/$scanId/photos',
      data: <String, dynamic>{'contentType': prepared.contentType},
    );
    final Map<String, dynamic> upload = presign.data as Map<String, dynamic>;
    final String fileId = upload['fileId'] as String;
    final int maxSize = (upload['maxSizeBytes'] as num).toInt();
    if (prepared.bytes.length > maxSize) {
      throw ArgumentError('Photo is ${prepared.bytes.length} bytes; the limit is $maxSize');
    }

    // 2. Straight to storage, on a SEPARATE client. The app's Dio carries an Authorization header,
    // and S3-compatible storage rejects a presigned request that also presents one — two auth
    // mechanisms on one request. The URL is used exactly as issued; its signature covers it.
    await _uploadClient().put<void>(
      upload['uploadUrl'] as String,
      data: Stream<List<int>>.fromIterable(<List<int>>[prepared.bytes]),
      options: Options(headers: <String, dynamic>{
        'Content-Type': prepared.contentType,
        Headers.contentLengthHeader: prepared.bytes.length,
      }),
    );

    // 3. The bytes landed. Only now does the server trust the photo.
    final Response<dynamic> confirmed =
        await _dio.post<dynamic>('$_base/$scanId/photos/$fileId/confirm');
    return CatalogScan.fromJson(confirmed.data as Map<String, dynamic>);
  }

  /// Reads the photos. Returns at once with the scan `analyzing`; poll [read] for the outcome.
  Future<CatalogScan> analyze(String scanId) async {
    final Response<dynamic> response = await _dio.post<dynamic>('$_base/$scanId/analyze');
    return CatalogScan.fromJson(response.data as Map<String, dynamic>);
  }

  Future<CatalogScan> read(String scanId) async {
    final Response<dynamic> response = await _dio.get<dynamic>('$_base/$scanId');
    return CatalogScan.fromJson(response.data as Map<String, dynamic>);
  }

  /// Saves one line's corrections without deciding it.
  Future<CatalogScan> updateLine({
    required String scanId,
    required String lineId,
    required String name,
    double? price,
    String? categoryId,
  }) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '$_base/$scanId/items/$lineId',
      data: <String, dynamic>{
        'name': name,
        if (price != null) 'price': price.toStringAsFixed(2),
        if (categoryId != null) 'categoryId': categoryId,
      },
    );
    return CatalogScan.fromJson(response.data as Map<String, dynamic>);
  }

  Future<CatalogScan> rejectLine({required String scanId, required String lineId}) async {
    final Response<dynamic> response =
        await _dio.post<dynamic>('$_base/$scanId/items/$lineId/reject');
    return CatalogScan.fromJson(response.data as Map<String, dynamic>);
  }

  /// The whole review in one request — accepted lines become DRAFT products, skipped lines are
  /// closed. All or nothing on the server. Nothing is published.
  Future<CatalogScan> commit({
    required String scanId,
    required List<ScanLineDecision> accept,
    required List<String> reject,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '$_base/$scanId/commit',
      data: <String, dynamic>{
        'accept': accept.map((ScanLineDecision d) => d.toJson()).toList(),
        'reject': reject,
      },
    );
    return CatalogScan.fromJson(response.data as Map<String, dynamic>);
  }
}
