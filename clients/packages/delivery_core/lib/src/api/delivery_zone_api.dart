import 'package:dio/dio.dart';

import '../models/zone_models.dart';

/// Delivery areas: the list customers pick from, and what each shop charges to reach each one.
///
/// Three audiences on one API. A customer only reads the picker. A merchant sets their own coverage
/// and prices. The Backoffice owns the list itself, because two shops calling the same
/// neighbourhood by different names would make "do you deliver to me" unanswerable.
class DeliveryZoneApi {
  DeliveryZoneApi(this._dio);

  final Dio _dio;

  /// The areas a customer can choose from. Retired ones are already excluded.
  Future<List<DeliveryZone>> picker() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/delivery-zones');
    return (response.data as List<dynamic>)
        .map((dynamic j) => DeliveryZone.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Including retired areas. BACKOFFICE only.
  Future<List<DeliveryZone>> all() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/delivery-zones/all');
    return (response.data as List<dynamic>)
        .map((dynamic j) => DeliveryZone.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Adds an area. [centerLat] and [centerLng] place it on the merchant demand map: both or
  /// neither, which the server enforces with a 400. Leaving both out adds an unplaced area.
  Future<DeliveryZone> create({
    required String name,
    String? region,
    int sortOrder = 100,
    double? centerLat,
    double? centerLng,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/delivery-zones',
      data: <String, dynamic>{
        'name': name,
        'region': region,
        'sortOrder': sortOrder,
        if (centerLat != null) 'centerLat': centerLat,
        if (centerLng != null) 'centerLng': centerLng,
      },
    );
    return DeliveryZone.fromJson(response.data as Map<String, dynamic>);
  }

  /// Edits an area's name, region and rank — and its centre only when asked to.
  ///
  /// A centre ([centerLat] and [centerLng], both or neither) moves the area on the merchant demand
  /// map, and [clearCentre] takes it off. Sending neither keeps whatever centre the area has, which is
  /// also all that a build written before centres existed ever sends: a rename from an older portal,
  /// a cached bundle or a tab left open must never wipe an area off every shop's map. A centre sent
  /// with [clearCentre] contradicts it, and the server refuses the pair. Nothing about pricing reads
  /// the centre.
  Future<DeliveryZone> rename(
    String id, {
    required String name,
    String? region,
    int sortOrder = 100,
    double? centerLat,
    double? centerLng,
    bool clearCentre = false,
  }) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/delivery-zones/$id',
      data: <String, dynamic>{
        'name': name,
        'region': region,
        'sortOrder': sortOrder,
        // Only what was asked for: an absent centre means "keep it", never "remove it".
        if (centerLat != null) 'centerLat': centerLat,
        if (centerLng != null) 'centerLng': centerLng,
        if (clearCentre) 'clearCentre': true,
      },
    );
    return DeliveryZone.fromJson(response.data as Map<String, dynamic>);
  }

  /// Takes an area out of the picker. Addresses that name it keep working.
  Future<DeliveryZone> retire(String id) => _post('/api/delivery-zones/$id/retire');

  Future<DeliveryZone> reinstate(String id) => _post('/api/delivery-zones/$id/reinstate');

  // ---------------------------------------------------------------- a shop's coverage

  /// Where this shop delivers and for how much.
  ///
  /// An empty list means the shop does not price by area at all — flat fee, everywhere. That is
  /// deliberately not the same as "delivers nowhere".
  Future<List<ZoneCoverage>> coverage(String storeId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/delivery-zones/coverage/$storeId');
    return (response.data as List<dynamic>)
        .map((dynamic j) => ZoneCoverage.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<ZoneCoverage> setCoverage(
    String storeId,
    String zoneId, {
    required double deliveryFee,
    double? minOrder,
    int etaExtraMinutes = 0,
  }) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/delivery-zones/coverage/$storeId/$zoneId',
      data: <String, dynamic>{
        'deliveryFee': deliveryFee,
        'minOrder': minOrder,
        'etaExtraMinutes': etaExtraMinutes,
      },
    );
    return ZoneCoverage.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> dropCoverage(String storeId, String zoneId) =>
      _dio.delete<dynamic>('/api/delivery-zones/coverage/$storeId/$zoneId');

  /// What a shop charges to reach an area — the quote a basket shows before checkout.
  Future<ZoneTerms> terms(String storeId, {String? zoneId}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/delivery-zones/terms/$storeId',
      queryParameters: zoneId == null ? null : <String, dynamic>{'zoneId': zoneId},
    );
    return ZoneTerms.fromJson(response.data as Map<String, dynamic>);
  }

  Future<DeliveryZone> _post(String path) async {
    final Response<dynamic> response = await _dio.post<dynamic>(path);
    return DeliveryZone.fromJson(response.data as Map<String, dynamic>);
  }
}
