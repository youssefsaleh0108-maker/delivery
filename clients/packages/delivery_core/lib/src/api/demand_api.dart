import 'package:dio/dio.dart';

import '../models/demand_models.dart';

/// The merchant Demand Radar's read: how busy the areas around one shop are.
///
/// MERCHANT for their own shop (BACKOFFICE for any). The shop is named by id because an account can
/// hold more than one; Order Manager checks that it is the caller's and answers 404 otherwise. Which
/// areas are counted is decided on the server from the shop, so nothing sent from here can widen
/// them — and nothing personal travels in the query: a store id and a window, never a location and
/// never a customer.
class DemandApi {
  DemandApi(this._dio);

  final Dio _dio;

  /// The windows the screen offers. The server clamps anything else into 60..10080 with no error,
  /// and never goes below an hour.
  static const int lastHour = 60;
  static const int lastDay = 24 * 60;
  static const int lastWeek = 7 * 24 * 60;

  Future<DemandDensity> density({required String storeId, int windowMinutes = lastHour}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/orders/demand/density',
      queryParameters: <String, dynamic>{'storeId': storeId, 'windowMinutes': windowMinutes},
    );
    return DemandDensity.fromJson(response.data as Map<String, dynamic>);
  }
}
