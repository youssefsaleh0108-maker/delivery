import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/catalog_models.dart';
import '../models/geo_models.dart';
import '../models/store_models.dart';

/// Typed client for the storefront half of the Product Service.
class StoreApi {
  StoreApi(this._dio);

  final Dio _dio;

  // ---------------------------------------------------------------- browsing

  /// The home screen. Every filter is optional; omitted ones are simply not sent.
  Future<Paged<StoreCard>> browse({
    StoreVertical? vertical,
    String? search,
    double? maxDeliveryFee,
    int? maxEtaMinutes,
    double? minRating,
    String? neighborhood,
    int page = 0,
    int size = 20,
  }) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/stores',
      queryParameters: <String, dynamic>{
        if (vertical != null) 'vertical': vertical.wireValue,
        if (search != null && search.isNotEmpty) 'search': search,
        if (maxDeliveryFee != null) 'maxDeliveryFee': maxDeliveryFee,
        if (maxEtaMinutes != null) 'maxEtaMinutes': maxEtaMinutes,
        if (minRating != null) 'minRating': minRating,
        if (neighborhood != null) 'neighborhood': neighborhood,
        'page': page,
        'size': size,
      },
    );
    return Paged<StoreCard>.fromJson(
        response.data as Map<String, dynamic>, StoreCard.fromJson);
  }

  Future<Paged<StoreCard>> browseWith(StoreFilters filters, {int page = 0, int size = 20}) {
    return browse(
      vertical: filters.vertical,
      search: filters.search,
      maxDeliveryFee: filters.maxDeliveryFee,
      maxEtaMinutes: filters.maxEtaMinutes,
      minRating: filters.minRating,
      neighborhood: filters.neighborhood,
      page: page,
      size: size,
    );
  }

  /// The district chips for the hyperlocal browse — what shops actually declared.
  Future<List<String>> neighborhoods() async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/stores/neighborhoods');
    return (response.data as List<dynamic>).cast<String>();
  }

  /// Live shops near a point, nearest first.
  ///
  /// Shops with no pin do not appear — a merchant who has not placed themselves on a map has not
  /// told us where they are, and that gap is not filled with a guess. [NearbyStore.distanceMetres]
  /// is straight-line, not driven; say "away", not "drive".
  ///
  /// [radiusMetres] is clamped into range server-side rather than refused — a million metres is a
  /// legitimate "everything around here".
  Future<Paged<NearbyStore>> nearby(
    double lat,
    double lng, {
    int radiusMetres = 5000,
    int page = 0,
    int size = 20,
  }) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/stores/nearby',
      queryParameters: <String, dynamic>{
        'latitude': lat,
        'longitude': lng,
        'radiusMetres': radiusMetres,
        'page': page,
        'size': size,
      },
    );
    return Paged<NearbyStore>.fromJson(
        response.data as Map<String, dynamic>, NearbyStore.fromJson);
  }

  Future<Paged<StoreCard>> favorites({int page = 0, int size = 20}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/stores/favorites',
      queryParameters: <String, dynamic>{'page': page, 'size': size},
    );
    return Paged<StoreCard>.fromJson(
        response.data as Map<String, dynamic>, StoreCard.fromJson);
  }

  /// Accepts an id or a slug, so a shared link and an in-app tap use the same call.
  Future<Store> read(String idOrSlug) async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/stores/$idOrSlug');
    return Store.fromJson(response.data as Map<String, dynamic>);
  }

  /// A store's shelf, optionally narrowed to one aisle.
  Future<Paged<Product>> products(
    String storeId, {
    String? categoryId,
    String? search,
    List<String>? ids,
    int page = 0,
    int size = 20,
  }) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/stores/$storeId/products',
      queryParameters: <String, dynamic>{
        if (categoryId != null) 'categoryId': categoryId,
        if (search != null && search.isNotEmpty) 'search': search,
        // Comma-joined: Spring binds a repeated or comma-separated param to List<UUID> either way,
        // and one long query string beats N repeated keys.
        if (ids != null && ids.isNotEmpty) 'ids': ids.join(','),
        'page': page,
        'size': size,
      },
    );
    return Paged<Product>.fromJson(
        response.data as Map<String, dynamic>, Product.fromJson);
  }

  /// Only the aisles this store actually stocks.
  Future<List<Aisle>> aisles(String storeId) async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/stores/$storeId/aisles');
    return (response.data as List<dynamic>)
        .map((dynamic json) => Aisle.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Paged<Offer>> offers(String storeId, {int page = 0, int size = 20}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/stores/$storeId/offers',
      queryParameters: <String, dynamic>{'page': page, 'size': size},
    );
    return Paged<Offer>.fromJson(response.data as Map<String, dynamic>, Offer.fromJson);
  }

  /// Promotions not tied to any one shop.
  Future<Paged<Offer>> platformOffers({int page = 0, int size = 20}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/stores/offers',
      queryParameters: <String, dynamic>{'page': page, 'size': size},
    );
    return Paged<Offer>.fromJson(response.data as Map<String, dynamic>, Offer.fromJson);
  }

  // ---------------------------------------------------------------- banners and chips

  /// The home rail. Live banners only, in the order the Backoffice arranged them.
  Future<List<HomeBanner>> banners() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/banners');
    return (response.data as List<dynamic>)
        .map((dynamic j) => HomeBanner.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// The home category strip, with whatever artwork has been uploaded for each category.
  Future<List<CategoryChip>> categoryChips() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/categories/chips');
    return (response.data as List<dynamic>)
        .map((dynamic j) => CategoryChip.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------- options

  /// The questions to ask before this product can go in a basket.
  Future<List<OptionGroup>> productOptions(String productId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/products/$productId/options');
    return (response.data as List<dynamic>)
        .map((dynamic json) => OptionGroup.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Prices a selection.
  ///
  /// The catalog does the arithmetic, not the client: it is the same call Order Manager makes at
  /// checkout, so the price shown while ticking options is by construction the price charged.
  Future<PricedSelection> priceSelection(String productId, List<String> optionIds) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/products/$productId/price',
      data: <String, dynamic>{'optionIds': optionIds},
    );
    return PricedSelection.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- cross-sell

  /// The "People Also Ordered" rail, named for what the backend honestly computes: how often two
  /// products shared a *delivered* basket. Not collaborative filtering — there is no model of who
  /// the caller is.
  ///
  /// Respect [BoughtTogetherSuggestion.basis]: only [CrossSellBasis.boughtTogether] rows carry a
  /// measured count; [CrossSellBasis.sameAisle] is same-shop fill and claims nothing. Until the
  /// delivered-basket projection accumulates data, every row is the latter.
  Future<List<BoughtTogetherSuggestion>> boughtTogether(String productId, {int limit = 8}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/products/$productId/bought-together',
      queryParameters: <String, dynamic>{'limit': limit},
    );
    return (response.data as List<dynamic>)
        .map((dynamic e) => BoughtTogetherSuggestion.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------- favourites

  /// Both calls are idempotent server-side, so a double tap is harmless and the UI can update
  /// optimistically without reconciling.
  Future<void> star(String storeId) => _dio.put<void>('/api/stores/$storeId/favorite');

  Future<void> unstar(String storeId) => _dio.delete<void>('/api/stores/$storeId/favorite');

  // ---------------------------------------------------------------- merchant

  Future<Paged<Store>> mine({int page = 0, int size = 20}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/stores/mine',
      queryParameters: <String, dynamic>{'page': page, 'size': size},
    );
    return Paged<Store>.fromJson(response.data as Map<String, dynamic>, Store.fromJson);
  }

  Future<Store> updateProfile(
    String storeId, {
    required String name,
    required StoreVertical vertical,
    String? tagline,
    String? description,
    List<String> tags = const <String>[],
    String? timezone,
    String? address,
  }) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/stores/$storeId',
      data: <String, dynamic>{
        'name': name,
        'vertical': vertical.wireValue,
        'tagline': tagline,
        'description': description,
        'tags': tags,
        'timezone': timezone,
        'address': address,
      },
    );
    return Store.fromJson(response.data as Map<String, dynamic>);
  }

  /// Drops or moves the shop's map pin.
  ///
  /// Its own call rather than fields on the profile form, mirroring the server's reasoning: the
  /// profile is saved on every tagline edit, and a nullable coordinate pair there would silently
  /// clear the pin on every save by a client that does not know the fields exist. Moving a shop is
  /// its own decision.
  Future<Store> setPin(String storeId, {required double lat, required double lng}) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/stores/$storeId/location',
      data: <String, dynamic>{'latitude': lat, 'longitude': lng},
    );
    return Store.fromJson(response.data as Map<String, dynamic>);
  }

  /// Takes the shop off the map. The address text is kept — only the pin goes, and with it the
  /// shop's appearance in [nearby].
  Future<Store> clearPin(String storeId) async {
    final Response<dynamic> response =
        await _dio.delete<dynamic>('/api/stores/$storeId/location');
    return Store.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Store> updateCommercials(
    String storeId, {
    required double deliveryFee,
    required double minOrder,
    required int etaMinMinutes,
    required int etaMaxMinutes,
  }) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/stores/$storeId/commercials',
      data: <String, dynamic>{
        'deliveryFee': deliveryFee,
        'minOrder': minOrder,
        'etaMinMinutes': etaMinMinutes,
        'etaMaxMinutes': etaMaxMinutes,
      },
    );
    return Store.fromJson(response.data as Map<String, dynamic>);
  }

  /// Replaces the whole week. Hours are edited as a set, not merged — see the service.
  Future<void> setHours(String storeId, List<OpeningWindow> windows) {
    return _dio.put<void>(
      '/api/stores/$storeId/hours',
      data: windows.map((OpeningWindow w) => w.toJson()).toList(),
    );
  }

  Future<List<OpeningWindow>> hours(String storeId) async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/stores/$storeId/hours');
    return (response.data as List<dynamic>)
        .map((dynamic json) => OpeningWindow.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Fails with 422 if the store has no opening hours — availability is derived entirely from
  /// them, so a store without them could never be open.
  Future<Store> publish(String storeId) async {
    final Response<dynamic> response = await _dio.post<dynamic>('/api/stores/$storeId/publish');
    return Store.fromJson(response.data as Map<String, dynamic>);
  }

  /// The merchant draws (or clears, with null) their delivery circle.
  Future<Store> setDeliveryRadius(String storeId, int? metres) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/stores/$storeId/delivery-radius',
      data: <String, dynamic>{'metres': metres},
    );
    return Store.fromJson(response.data as Map<String, dynamic>);
  }

  /// Whether the shop's circle covers the point — what checkout asks before promising.
  Future<bool> canDeliver(String storeId,
      {required double latitude, required double longitude}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/stores/$storeId/can-deliver',
      queryParameters: <String, dynamic>{
        'latitude': latitude,
        'longitude': longitude,
      },
    );
    return (response.data as Map<String, dynamic>)['canDeliver'] as bool? ?? true;
  }

  /// The merchant declares what the lights are doing — mains, generator, or dark — with the
  /// optional one-liner the storefront prints under the chip.
  Future<Store> declarePower(String storeId, StorePowerStatus status,
      {String? note}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/stores/$storeId/power',
      data: <String, dynamic>{
        'status': status.wire,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
    return Store.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Store> suspend(String storeId) async {
    final Response<dynamic> response = await _dio.post<dynamic>('/api/stores/$storeId/suspend');
    return Store.fromJson(response.data as Map<String, dynamic>);
  }

  /// Uploads a store's logo or cover.
  ///
  /// Three steps, mirroring [CatalogApi.uploadImage]: ask for a one-shot URL, PUT the bytes
  /// straight to storage, then confirm. The bytes never pass through the backend.
  ///
  /// [slot] is `logo` or `cover`. Uploading replaces whatever was there — a store has one of each.
  Future<Store> uploadImage({
    required String storeId,
    required String slot,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final Response<dynamic> presign = await _dio.post<dynamic>(
      '/api/stores/$storeId/images/$slot/presign',
      data: <String, dynamic>{'contentType': contentType},
    );
    final Map<String, dynamic> upload = presign.data as Map<String, dynamic>;
    final int maxSize = (upload['maxSizeBytes'] as num).toInt();
    if (bytes.length > maxSize) {
      throw ArgumentError('Image is ${bytes.length} bytes; the limit is $maxSize');
    }

    // A separate, bare Dio: S3-compatible storage rejects a presigned request that also carries an
    // Authorization header, because that is two conflicting auth mechanisms on one request.
    final Dio bare = Dio();
    await bare.put<void>(
      upload['uploadUrl'] as String,
      data: Stream<List<int>>.fromIterable(<List<int>>[bytes]),
      options: Options(headers: <String, dynamic>{
        'Content-Type': contentType,
        Headers.contentLengthHeader: bytes.length,
      }),
    );

    final Response<dynamic> confirmed = await _dio.post<dynamic>(
      '/api/stores/$storeId/images/$slot/${upload['fileId']}/confirm',
    );
    return Store.fromJson(confirmed.data as Map<String, dynamic>);
  }

  Future<Store> removeImage({required String storeId, required String slot}) async {
    final Response<dynamic> response =
        await _dio.delete<dynamic>('/api/stores/$storeId/images/$slot');
    return Store.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Store> setBusy(String storeId, {required int minutes}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/stores/$storeId/busy',
      data: <String, dynamic>{'minutes': minutes},
    );
    return Store.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Store> clearBusy(String storeId) async {
    final Response<dynamic> response = await _dio.delete<dynamic>('/api/stores/$storeId/busy');
    return Store.fromJson(response.data as Map<String, dynamic>);
  }
}
