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

  /// The windows the screen offers, and the only ones the server answers: anything else is a 400.
  /// Each answer is the snapshot for the window's last fixed boundary — the quarter hour for the
  /// hour, the hour for the day, midnight UTC for the week — so asking more often changes nothing.
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
