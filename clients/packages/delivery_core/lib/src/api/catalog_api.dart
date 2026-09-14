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

  /// The Merchant Portal's list — the caller's own products, in any status or in [status] alone, from
  /// every shop the account owns or from [storeId] alone.
  ///
  /// The provider dashboard's "Active offers" is
  /// `myProducts(storeId: serviceShop.id, status: ProductStatus.active, size: 1)` read as
  /// [Paged.totalElements]: a count the server made, not the length of a page, and of that service
  /// shop's offers only, since the same account may own a goods shop too. A [storeId] the caller does
  /// not own answers 404, as an id that was never issued does.
  Future<Paged<Product>> myProducts({
    String? storeId,
    ProductStatus? status,
    int page = 0,
    int size = 20,
  }) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/products/mine',
      queryParameters: <String, dynamic>{
        if (storeId != null) 'storeId': storeId,
        if (status != null) 'status': status.wireValue,
        'page': page,
        'size': size,
      },
    );
    return Paged<Product>.fromJson(
        response.data as Map<String, dynamic>, Product.fromJson);
  }

  /// The services offer search: live offers of listed service shops in open categories.
  ///
  /// Never a goods product, a paused offer or one back office took down. A [serviceCategory] the
  /// platform has closed answers an empty page. For any signed-in caller. Back office lists every
  /// offer, in every status, with `BackofficeCatalogApi.serviceOffers`.
  ///
  /// The Services tab's "Popular near you" row is shops, not offers: [StoreApi.popularServices].
  Future<Paged<Product>> searchServices({
    String? search,
    ServiceCategory? serviceCategory,
    int page = 0,
    int size = 20,
  }) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/products/services',
      queryParameters: <String, dynamic>{
        if (search != null && search.isNotEmpty) 'search': search,
        if (serviceCategory != null) 'serviceCategory': serviceCategory.wireValue,
        'page': page,
        'size': size,
      },
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

  /// Takes a live service offer off sale for now. The provider's own offers only (404 for anyone
  /// else's); a goods product answers 422, because goods are archived instead.
  Future<Product> pause(String id) async {
    final Response<dynamic> response = await _dio.post<dynamic>('/api/products/$id/pause');
    return Product.fromJson(response.data as Map<String, dynamic>);
  }

  /// Puts a paused service offer back on sale. Fails with 422 without a photo, or for an offer that
  /// can be delivered when the shop has neither delivery areas nor a pin; with 403 while the provider
  /// is still awaiting approval, as publishing does.
  Future<Product> resume(String id) async {
    final Response<dynamic> response = await _dio.post<dynamic>('/api/products/$id/resume');
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

  /// Puts a live product on the customer gift hub, or takes it off. BACKOFFICE only; the server
  /// refuses a product that is not live (422). Answers with what the switch now says.
  Future<bool> setGiftFeatured(String id, {required bool featured}) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/products/$id/gift-featured',
      data: <String, dynamic>{'featured': featured},
    );
    return (response.data as Map<String, dynamic>)['giftFeatured'] as bool? ?? false;
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

  // ------------------------------------------------------ store categories

  /// A shop's own sections, in display order (the server sorts by `position` ascending).
  ///
  /// Distinct from [categories], which is the platform taxonomy every client shares: these rows
  /// carry a `storeId` and are written by the merchant who owns them. A shop that has never made
  /// a section gets an empty list, not a 404.
  Future<List<Category>> storeCategories(String storeId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/stores/$storeId/categories');
    return (response.data as List<dynamic>)
        .map((dynamic json) => Category.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Creates one section. `parentId` must name a PLATFORM category — a section may hang under the
  /// taxonomy, never under another shop's row. A duplicate name under the same parent is 409.
  Future<Category> createStoreCategory(
    String storeId, {
    required String name,
    String? parentId,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/stores/$storeId/categories',
      data: <String, dynamic>{'name': name, if (parentId != null) 'parentId': parentId},
    );
    return Category.fromJson(response.data as Map<String, dynamic>);
  }

  /// Renames a section, and optionally re-parents it. Sends `parentId` unconditionally, because
  /// null is the value that moves a section back to the top level.
  Future<Category> updateStoreCategory(
    String storeId,
    String categoryId, {
    required String name,
    String? parentId,
  }) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/stores/$storeId/categories/$categoryId',
      data: <String, dynamic>{'name': name, 'parentId': parentId},
    );
    return Category.fromJson(response.data as Map<String, dynamic>);
  }

  /// Rewrites the whole display order and answers with the shop's sections as they now stand.
  ///
  /// A REPLACE, the [setProductOptions] idiom: the server rewrites positions `0..n-1` in one
  /// transaction and refuses (422) a list that is not exactly the shop's section ids, each once.
  /// So callers send the complete order they want to end up with, never a single moved row.
  Future<List<Category>> reorderStoreCategories(
    String storeId,
    List<String> categoryIds,
  ) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/stores/$storeId/categories/order',
      data: <String, dynamic>{'categoryIds': categoryIds},
    );
    return (response.data as List<dynamic>)
        .map((dynamic json) => Category.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Deletes a section. 409 when it still holds products — the server will not orphan a listing,
  /// and its `detail` carries the count the screen shows.
  Future<void> deleteStoreCategory(String storeId, String categoryId) {
    return _dio.delete<void>('/api/stores/$storeId/categories/$categoryId');
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
