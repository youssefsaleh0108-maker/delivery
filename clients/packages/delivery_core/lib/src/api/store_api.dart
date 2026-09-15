import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/catalog_models.dart';
import '../models/geo_models.dart';
import '../models/gift_models.dart';
import '../models/store_models.dart';

/// Typed client for the storefront half of the Product Service.
class StoreApi {
  StoreApi(this._dio);

  final Dio _dio;

  // ---------------------------------------------------------------- browsing

  /// The home screen. Every filter is optional; omitted ones are simply not sent.
  ///
  /// No [vertical] and no [serviceCategory] is every goods shop and no service shop — what Home asks
  /// for. [StoreVertical.services], or a [serviceCategory] on its own, lists service shops in the
  /// categories the server has open; a closed category answers an empty page even when named.
  Future<Paged<StoreCard>> browse({
    StoreVertical? vertical,
    ServiceCategory? serviceCategory,
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
        if (serviceCategory != null) 'serviceCategory': serviceCategory.wireValue,
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
      serviceCategory: filters.serviceCategory,
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

  /// The service categories the server has open, in taxonomy order —
  /// `GET /api/stores/service-categories`.
  ///
  /// What a provider may file a shop under and what the Services tab may show; a closed category is
  /// in neither. A name this app does not know, such as a category a newer server added, is left
  /// out, because there is nothing to label it with.
  Future<List<ServiceCategory>> serviceCategories() async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/stores/service-categories');
    return (response.data as List<dynamic>)
        .map((dynamic name) => ServiceCategory.maybeFromWire(name as String?))
        .whereType<ServiceCategory>()
        .toList();
  }

  /// Live shops near a point, nearest first.
  ///
  /// Shops with no pin do not appear — a merchant who has not placed themselves on a map has not
  /// told us where they are, and that gap is not filled with a guess. [NearbyStore.distanceMetres]
  /// is straight-line, not driven; say "away", not "drive".
  ///
  /// [radiusMetres] is clamped into range server-side rather than refused — a million metres is a
  /// legitimate "everything around here".
  ///
  /// The filters are the neighbourhood browse's chips, applied by the server before the page is
  /// cut, so pages stay full — within the nearest [NearbyPage.candidateLimit] shops that match. All
  /// but [openNow] narrow the database's candidates themselves; [NearbyPage.truncated] says when more
  /// shops matched than one search reads, and then [Paged.totalElements] counts only the nearest of
  /// them. Omitted filters are not sent, and no filter is the plain search.
  ///
  /// * [openNow] drops a shop whose card would read closed; busy and closing-soon stay, because
  ///   both still take orders.
  /// * [powerStatus] is what the merchant says the lights are doing NOW, and only while that
  ///   declaration still counts as now ([StoreCard.powerCurrent]). `generator` means "running on the
  ///   generator at the moment", not "owns one" — label it that way.
  /// * [neighborhood] is an exact match on the district a shop declared.
  /// * [newSinceDays] keeps shops that first listed on the platform within that many days (clamped
  ///   to 1..365 server-side) — counted from the listing, not from when the draft was created.
  /// * [verifiedLocal] keeps only shops Backoffice granted the trust badge.
  /// * [vertical] and [serviceCategory] follow [browse]: neither is every goods shop and no service
  ///   shop; [StoreVertical.services] or a category on its own is service shops in open categories.
  Future<NearbyPage> nearby(
    double lat,
    double lng, {
    int radiusMetres = 5000,
    bool openNow = false,
    StorePowerStatus? powerStatus,
    String? neighborhood,
    int? newSinceDays,
    bool verifiedLocal = false,
    StoreVertical? vertical,
    ServiceCategory? serviceCategory,
    int page = 0,
    int size = 20,
  }) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/stores/nearby',
      queryParameters: <String, dynamic>{
        'latitude': lat,
        'longitude': lng,
        'radiusMetres': radiusMetres,
        if (openNow) 'openNow': true,
        if (powerStatus != null) 'powerStatus': powerStatus.wire,
        if (neighborhood != null && neighborhood.trim().isNotEmpty) 'neighborhood': neighborhood,
        if (newSinceDays != null) 'newSinceDays': newSinceDays,
        if (verifiedLocal) 'verifiedLocal': true,
        if (vertical != null) 'vertical': vertical.wireValue,
        if (serviceCategory != null) 'serviceCategory': serviceCategory.wireValue,
        'page': page,
        'size': size,
      },
    );
    return NearbyPage.fromJson(response.data as Map<String, dynamic>);
  }

  /// The Services tab's "Popular near you" row: service shops within a few kilometres of the point,
  /// ranked by the orders they delivered in the last 30 days, most first.
  ///
  /// Cards in the server's order, each with its distance as [nearby] measures it, and never a count:
  /// the ranking is the server's, and no shop's order volume is published. Live shops in open
  /// categories only, or in the open [serviceCategory] named. Empty until enough nearby orders have
  /// been delivered, and the tab then shows services near the customer instead ([nearby] with
  /// [StoreVertical.services]). A row this build cannot read is dropped.
  Future<List<NearbyStore>> popularServices(
    double lat,
    double lng, {
    ServiceCategory? serviceCategory,
    int limit = 10,
  }) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/stores/services/popular',
      queryParameters: <String, dynamic>{
        'latitude': lat,
        'longitude': lng,
        if (serviceCategory != null) 'serviceCategory': serviceCategory.wireValue,
        'limit': limit,
      },
    );
    final Object? rows = response.data;
    if (rows is! List) {
      return const <NearbyStore>[];
    }
    return rows.map(NearbyStore.maybeFromJson).whereType<NearbyStore>().toList();
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

  // ---------------------------------------------------------------- reviews

  /// A shop's reviews, newest first — `GET /api/stores/{id}/reviews`: what a provider's page lists
  /// under its rating.
  ///
  /// [StoreReview.mine] marks the caller's own, so the app can offer Edit. A row this build cannot
  /// show is left out of the page; the counts stay the server's.
  Future<Paged<StoreReview>> reviews(String storeId, {int page = 0, int size = 20}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/stores/$storeId/reviews',
      queryParameters: <String, dynamic>{'page': page, 'size': size},
    );
    final Object? body = response.data;
    final Map<dynamic, dynamic> json = body is Map ? body : const <dynamic, dynamic>{};
    int count(String key, int fallback) {
      final Object? value = json[key];
      return value is num ? value.toInt() : fallback;
    }

    final Object? rows = json['content'];
    return Paged<StoreReview>(
      content: rows is List
          ? rows.map(StoreReview.maybeFromJson).whereType<StoreReview>().toList(growable: false)
          : const <StoreReview>[],
      page: count('page', page),
      totalElements: count('totalElements', 0),
      totalPages: count('totalPages', 0),
    );
  }

  /// The caller's own review of one of their orders — `GET /api/stores/reviews/order/{orderId}` — or
  /// null when they have not reviewed it: how a completed order knows whether to invite a rating or
  /// show the stars already given. CUSTOMER only.
  ///
  /// The server answers 204 both when the order has no review and when its review is somebody
  /// else's, so this learns nothing about an order that is not the caller's. A 200 that is not a
  /// review this build can read is thrown as a [FormatException] rather than read as "not reviewed":
  /// a screen then draws nothing about rating instead of inviting a second one.
  Future<StoreReview?> myReviewForOrder(String orderId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/stores/reviews/order/$orderId');
    if (response.statusCode == 204) {
      return null;
    }
    final StoreReview? review = StoreReview.maybeFromJson(response.data);
    if (review == null) {
      throw const FormatException('The review of this order could not be read');
    }
    return review;
  }

  /// Rates a shop for one of the caller's completed orders — `POST /api/stores/{storeId}/reviews` —
  /// and answers the review as the server stored it. CUSTOMER only.
  ///
  /// [rating] is one to five stars; anything else is refused here, before a request. [comment] is
  /// trimmed, and not sent when blank; the server holds it to 2,000 UTF-16 units.
  ///
  /// What product-service decides (`ReviewService.rate`):
  ///
  /// * **Only an order it has on record as completed** — delivered to the door, or collected at the
  ///   counter, both of which Order Manager announces as `order.delivered` — that the caller placed
  ///   at this shop. Anything else is a 404, the same for a mistyped id, an order still in
  ///   production and somebody else's order. The record is made from that event, so for a moment
  ///   after completion a genuine order can be answered 404 too; asking again shortly is right.
  /// * **One review per order, revisable.** A second review of the same order replaces the first
  ///   instead of being refused, so there is no "already reviewed" error: a screen that wants to say
  ///   so asks [myReviewForOrder] first.
  Future<StoreReview> submitReview(
    String storeId, {
    required String orderId,
    required int rating,
    String? comment,
  }) async {
    RangeError.checkValueInInterval(rating, 1, 5, 'rating');
    final String words = comment?.trim() ?? '';
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/stores/$storeId/reviews',
      data: <String, dynamic>{
        'orderId': orderId,
        'rating': rating,
        if (words.isNotEmpty) 'comment': words,
      },
    );
    final StoreReview? stored = StoreReview.maybeFromJson(response.data);
    if (stored == null) {
      throw const FormatException('The review the server stored could not be read');
    }
    return stored;
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

  /// The gift hub's featured care bundles, newest pick first — `GET /api/gift-bundles`.
  ///
  /// Live products of listed shops that the back office picked, each saying whether it could still
  /// arrive today. An empty list is an ordinary answer: the hub hides the section.
  Future<List<GiftBundle>> giftBundles() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/gift-bundles');
    return (response.data as List<dynamic>)
        .map((dynamic j) => GiftBundle.fromJson(j as Map<String, dynamic>))
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

  /// Opens a shop for the signed-in merchant — `POST /api/stores`.
  ///
  /// For a services provider this is the shop's bootstrap: the app opens it once, on the approved
  /// provider's first entry, from the application's name, category and area. The server keeps a
  /// merchant to one services shop, so asking again — a retry, a second phone — hands back the same
  /// shop rather than opening another. A goods shop opens one per call, as it always has.
  Future<Store> create({
    required String name,
    required StoreVertical vertical,
    ServiceCategory? serviceCategory,
    String? neighborhood,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/stores',
      data: <String, dynamic>{
        'name': name,
        'vertical': vertical.wireValue,
        'tags': const <String>[],
        if (neighborhood != null) 'neighborhood': neighborhood,
        if (serviceCategory != null) 'serviceCategory': serviceCategory.wireValue,
      },
    );
    return Store.fromJson(response.data as Map<String, dynamic>);
  }

  /// Saves the profile form.
  ///
  /// [neighborhood] follows the server's three-way rule: null leaves the shop's district as it is
  /// (and is not sent at all), an empty string clears it, anything else sets it. The field used to
  /// be missing here entirely while the server wrote whatever arrived — so every profile save
  /// cleared the district, and the neighbourhood browse had nothing to browse.
  Future<Store> updateProfile(
    String storeId, {
    required String name,
    required StoreVertical vertical,
    String? tagline,
    String? description,
    List<String> tags = const <String>[],
    String? timezone,
    String? address,
    String? neighborhood,
    ServiceCategory? serviceCategory,
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
        if (neighborhood != null) 'neighborhood': neighborhood,
        // Like the district, absent keeps what the shop has: a save that does not mention the
        // category cannot clear it. Only a service shop has one; the server refuses it for goods.
        if (serviceCategory != null) 'serviceCategory': serviceCategory.wireValue,
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

  /// Back office grants ([verified] true) or withdraws the Verified Local badge.
  ///
  /// BACKOFFICE only on the server — the shop's own merchant is refused too, because a badge a shop
  /// could award itself would certify nothing to its neighbours. Any store in any status, a goods shop
  /// or a service shop alike (for a service provider it is the "verified" mark on their page).
  ///
  /// Answers the store as the server now holds it, so a screen shows the badge the server stored
  /// rather than the one it asked for. A refusal (403, or 404 for an unknown id) is thrown as the
  /// `DioException` it arrives as.
  Future<Store> setVerifiedLocal(String storeId, {required bool verified}) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/stores/$storeId/verified-local',
      data: <String, dynamic>{'verified': verified},
    );
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
