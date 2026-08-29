import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/catalog_models.dart';
import '../util/image_prep.dart';
// OptionGroup and its drafts live with the storefront models, because the customer side reads the
// same structure this writes.
import '../models/store_models.dart';

/// Typed client for the Product Service, reached through the API Gateway.
class CatalogApi {
  CatalogApi(this._dio);

  final Dio _dio;

  // ---------------------------------------------------------------- catalog

  Future<Paged<Product>> browse({
    String? categoryId,
    String? search,
    int page = 0,
    int size = 20,
  }) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/products',
      queryParameters: <String, dynamic>{
        if (categoryId != null) 'categoryId': categoryId,
        if (search != null && search.isNotEmpty) 'search': search,
        'page': page,
        'size': size,
      },
    );
    return Paged<Product>.fromJson(
        response.data as Map<String, dynamic>, Product.fromJson);
  }

  /// The Merchant Portal's list — the caller's own products, in any status.
  Future<Paged<Product>> myProducts({int page = 0, int size = 20}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/products/mine',
      queryParameters: <String, dynamic>{'page': page, 'size': size},
    );
    return Paged<Product>.fromJson(
        response.data as Map<String, dynamic>, Product.fromJson);
  }

  Future<Product> read(String id) async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/products/$id');
    return Product.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Product> create(Product product) async {
    final Response<dynamic> response =
        await _dio.post<dynamic>('/api/products', data: product.toRequestJson());
    return Product.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Product> update(String id, Product product) async {
    final Response<dynamic> response =
        await _dio.put<dynamic>('/api/products/$id', data: product.toRequestJson());
    return Product.fromJson(response.data as Map<String, dynamic>);
  }

  /// Fails with 422 if the product has no images — the service refuses to publish a blank listing.
  Future<Product> publish(String id) async {
    final Response<dynamic> response = await _dio.post<dynamic>('/api/products/$id/publish');
    return Product.fromJson(response.data as Map<String, dynamic>);
  }

  /// Replaces the product's whole option structure — the merchant's side of what a customer sees
  /// as "Choose a size".
  ///
  /// A REPLACE, not a merge, because the server's endpoint is: whatever is sent becomes the
  /// product's options, and a group left out is deleted. Callers must send the complete set they
  /// want to end up with, which is why the editor loads the existing groups first.
  ///
  /// The server assigns every id. A group being edited has one and an unsaved one does not, and
  /// neither is sent — sending an id would invite a client to claim an option row it does not own.
  Future<List<OptionGroup>> setProductOptions(
    String productId,
    List<OptionGroupDraft> groups,
  ) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/products/$productId/options',
      data: groups.map((OptionGroupDraft g) => g.toRequestJson()).toList(),
    );
    return (response.data as List<dynamic>)
        .map((dynamic json) => OptionGroup.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Archive, not delete. Past orders still reference the product.
  Future<Product> archive(String id) async {
    final Response<dynamic> response = await _dio.delete<dynamic>('/api/products/$id');
    return Product.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<Category>> categories() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/categories');
    return (response.data as List<dynamic>)
        .map((dynamic json) => Category.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// BACKOFFICE only. Categories are platform-wide taxonomy, not per-merchant — a merchant calling
  /// this gets 403, and a duplicate name under the same parent gets 409.
  Future<Category> createCategory({required String name, String? parentId}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/categories',
      data: <String, dynamic>{'name': name, 'parentId': parentId},
    );
    return Category.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- images

  /// Uploads one product image, following the three-step flow from Section 5.
  ///
  /// The bytes go straight from here to MinIO and never touch the backend, which is why the
  /// backend's request size limits are irrelevant to a 10 MB photo.
  Future<void> uploadImage({
    required String productId,
    required Uint8List bytes,
    required String contentType,
    int maxBytes = ImagePrep.defaultMaxBytes,
  }) async {
    // 0. Shrink an oversized photo BEFORE anything else, and presign for what will actually be
    // sent. A phone camera hands back several megabytes; a product thumbnail needs a fraction of
    // that, and downscaling here means a shop on mobile data is not pushing the original — the
    // upload that used to time out now completes. Re-encoding a resized image makes it JPEG, so the
    // presign has to be told that type rather than the picked one, which is why this happens first.
    final PreparedImage prepared = ImagePrep.forUpload(bytes, contentType, maxBytes: maxBytes);
    final Uint8List sending = prepared.bytes;

    // 1. Ask the service for a one-shot URL. It checks that this merchant owns the product.
    final Response<dynamic> presign = await _dio.post<dynamic>(
      '/api/products/$productId/images/presign',
      data: <String, dynamic>{'contentType': prepared.contentType},
    );
    final Map<String, dynamic> upload = presign.data as Map<String, dynamic>;
    final String uploadUrl = upload['uploadUrl'] as String;
    final String fileId = upload['fileId'] as String;
    final int maxSize = (upload['maxSizeBytes'] as num).toInt();

    if (sending.length > maxSize) {
      // After preparation this should never fire — the cap is well under the server's — but a photo
      // that could not be brought under the ceiling is refused here rather than at MinIO, where the
      // failure would be an opaque 403 on the signed URL.
      throw ArgumentError('Image is ${sending.length} bytes; the limit is $maxSize');
    }

    // 2. PUT straight to MinIO.
    //
    // A SEPARATE Dio instance, deliberately. The app's client carries an Authorization header and
    // a correlation id; S3-compatible storage rejects a presigned request that also presents an
    // Authorization header, because that is two conflicting auth mechanisms on one request. The
    // URL must be used exactly as issued — its signature covers the host and query string.
    final Dio bare = Dio();
    await bare.put<void>(
      uploadUrl,
      data: Stream<List<int>>.fromIterable(<List<int>>[sending]),
      options: Options(
        headers: <String, dynamic>{
          'Content-Type': prepared.contentType,
          Headers.contentLengthHeader: sending.length,
        },
      ),
    );

    // 3. Tell the service the bytes landed. Until this returns, the image is not attached to the
    // product — the service verifies the object exists and re-checks its size.
    await _dio.post<void>('/api/products/$productId/images/$fileId/confirm');
  }

  Future<void> removeImage({required String productId, required String objectKey}) {
    return _dio.delete<void>(
      '/api/products/$productId/images',
      queryParameters: <String, dynamic>{'objectKey': objectKey},
    );
  }
}
