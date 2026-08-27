import 'package:dio/dio.dart';

import '../models/geo_models.dart';

/// Client for the address picker's back end on the Product Service.
///
/// Authenticated but role-free, exactly like the server: a customer saving a delivery address and
/// a merchant placing their shop both come through here.
///
/// Nothing here should be logged by callers either — a search term in an address picker is
/// somebody's home address.
class GeocodingApi {
  GeocodingApi(this._dio);

  final Dio _dio;

  /// Text in, places out.
  ///
  /// The server answers a query under three characters with an empty list without calling the
  /// provider at all, so the picker can fire on every keystroke without spending anybody's
  /// geocoding budget on "be".
  ///
  /// [PlaceSearchResult.provider] says who produced the pins — the free dev geocoder and a paid
  /// provider are not equally trustworthy, and the picker may say so.
  Future<PlaceSearchResult> searchPlaces(String text, {int limit = 5}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/geocoding/search',
      queryParameters: <String, dynamic>{'q': text, 'limit': limit},
    );
    return PlaceSearchResult.fromJson(response.data as Map<String, dynamic>);
  }

  /// A point in, the address at it out.
  ///
  /// Null when the provider knows of no address there — a pin dropped in the sea is a successful
  /// answer to a question (the server's 204), not an error worth retrying.
  Future<ReverseGeocodeResult?> reverse(double lat, double lng) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/geocoding/reverse',
      queryParameters: <String, dynamic>{'latitude': lat, 'longitude': lng},
      options: Options(validateStatus: (int? s) => s != null && s < 300),
    );
    if (response.statusCode == 204 || response.data == null) {
      return null;
    }
    return ReverseGeocodeResult.fromJson(response.data as Map<String, dynamic>);
  }
}
