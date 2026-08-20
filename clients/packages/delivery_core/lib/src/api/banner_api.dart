import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/catalog_models.dart';
import '../models/store_models.dart';

/// The editorial half of the Product Service: home banners and category artwork.
///
/// Separate from [StoreApi] because the audience is different. Everything here except the two
/// read calls is BACKOFFICE-only — this is platform-curated content, unlike a store's own logo,
/// which its merchant owns and edits from the portal.
class BannerApi {
  BannerApi(this._dio);

  final Dio _dio;

  // ---------------------------------------------------------------- reads

  /// Live banners in curated order — what the customer app's home rail shows.
  Future<List<HomeBanner>> live() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/banners');
    return (response.data as List<dynamic>)
        .map((dynamic j) => HomeBanner.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Every banner including withdrawn and scheduled ones, newest arrangement first.
  ///
  /// Paged, so an account with years of campaigns behind it does not fetch all of them to render
  /// the first screen.
  Future<Paged<HomeBanner>> all({int page = 0, int size = 20}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/banners/all',
      queryParameters: <String, dynamic>{'page': page, 'size': size},
    );
    return Paged<HomeBanner>.fromJson(
        response.data as Map<String, dynamic>, HomeBanner.fromJson);
  }

  // ---------------------------------------------------------------- writes

  Future<HomeBanner> create({
    required String title,
    String? subtitle,
    BannerLinkKind linkKind = BannerLinkKind.none,
    String? linkTarget,
    int position = 0,
    bool active = true,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/banners',
      data: _body(title, subtitle, linkKind, linkTarget, position, active),
    );
    return HomeBanner.fromJson(response.data as Map<String, dynamic>);
  }

  Future<HomeBanner> update(
    String id, {
    required String title,
    String? subtitle,
    BannerLinkKind linkKind = BannerLinkKind.none,
    String? linkTarget,
    int position = 0,
    bool active = true,
  }) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/banners/$id',
      data: _body(title, subtitle, linkKind, linkTarget, position, active),
    );
    return HomeBanner.fromJson(response.data as Map<String, dynamic>);
  }

  /// Takes a banner off the rail. The row stays — a banner that ran is part of the record — so
  /// this is reversible by setting it active again.
  Future<void> withdraw(String id) => _dio.delete<void>('/api/banners/$id');

  static Map<String, dynamic> _body(String title, String? subtitle, BannerLinkKind linkKind,
      String? linkTarget, int position, bool active) {
    // A destination of NONE must carry no target: the service enforces it with a CHECK, and
    // sending a stale target with NONE would be rejected rather than silently ignored.
    final bool linked = linkKind != BannerLinkKind.none;
    return <String, dynamic>{
      'title': title,
      'subtitle': subtitle,
      'linkKind': linkKind.wireValue,
      'linkTarget': linked ? linkTarget : null,
      'position': position,
      'active': active,
    };
  }

  // ---------------------------------------------------------------- artwork

  /// Uploads a banner's artwork: presign, PUT the bytes straight to storage, confirm.
  ///
  /// Same three steps as every other image in the platform — the bytes never pass through the
  /// backend, so a large upload does not occupy a request thread.
  Future<HomeBanner> uploadBannerImage({
    required String bannerId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final Map<String, dynamic> upload = await _presign(
        '/api/banners/$bannerId/image/presign', bytes, contentType);
    final Response<dynamic> confirmed = await _dio.post<dynamic>(
        '/api/banners/$bannerId/image/${upload['fileId']}/confirm');
    return HomeBanner.fromJson(confirmed.data as Map<String, dynamic>);
  }

  /// Uploads the picture a category shows in the customer app's home strip.
  Future<CategoryChip> uploadCategoryImage({
    required String categoryId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final Map<String, dynamic> upload = await _presign(
        '/api/categories/$categoryId/image/presign', bytes, contentType);
    final Response<dynamic> confirmed = await _dio.post<dynamic>(
        '/api/categories/$categoryId/image/${upload['fileId']}/confirm');
    return CategoryChip.fromJson(confirmed.data as Map<String, dynamic>);
  }

  /// Tags a category as standing for a vertical, which is what puts it in the home strip. Passing
  /// null takes it back out.
  Future<CategoryChip> setVertical(String categoryId, StoreVertical? vertical) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/categories/$categoryId/vertical',
      data: <String, dynamic>{'vertical': vertical?.wireValue},
    );
    return CategoryChip.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> _presign(
      String path, Uint8List bytes, String contentType) async {
    final Response<dynamic> presign = await _dio.post<dynamic>(
      path,
      data: <String, dynamic>{'contentType': contentType},
    );
    final Map<String, dynamic> upload = presign.data as Map<String, dynamic>;
    final int maxSize = (upload['maxSizeBytes'] as num).toInt();
    if (bytes.length > maxSize) {
      throw ArgumentError('Image is ${bytes.length} bytes; the limit is $maxSize');
    }

    // A bare Dio on purpose: S3-compatible storage rejects a presigned request that also carries
    // an Authorization header, because that is two conflicting auth mechanisms on one request.
    final Dio bare = Dio();
    await bare.put<void>(
      upload['uploadUrl'] as String,
      data: Stream<List<int>>.fromIterable(<List<int>>[bytes]),
      options: Options(headers: <String, dynamic>{
        'Content-Type': contentType,
        Headers.contentLengthHeader: bytes.length,
      }),
    );
    return upload;
  }
}
