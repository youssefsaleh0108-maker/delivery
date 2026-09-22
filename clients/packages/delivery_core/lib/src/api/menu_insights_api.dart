import 'package:dio/dio.dart';

import '../models/menu_insights_models.dart';

/// What a shop's menu has been doing: {@code GET /api/products/menu-insights/{storeId}}.
///
/// The shop is named by id because an account can hold more than one. Who may read it is decided
/// on the server from the roster — the shop's owner, or a member trusted with reports — and a
/// caller with no relationship to it gets the same 404 a shop that does not exist gives.
///
/// Nothing personal travels in either direction. The query is a store id and a window; the answer
/// carries no reader, no timestamp and no exact count of opens, only bands over a floor. See
/// [MenuInsights] for which of the figures are bands and which are exact, and why they differ.
class MenuInsightsApi {
  MenuInsightsApi(this._dio);

  final Dio _dio;

  /// The windows the screen offers. The server clamps anything longer rather than refusing it, so
  /// an out-of-range value comes back shortened — which is why the screen reads the length off
  /// [MenuInsights.days] instead of off what it asked for.
  static const int today = 1;
  static const int lastWeek = 7;
  static const int lastMonth = 30;

  Future<MenuInsights> forStore({required String storeId, int days = lastWeek}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/products/menu-insights/$storeId',
      queryParameters: <String, dynamic>{'days': days},
    );
    return MenuInsights.fromJson(response.data as Map<String, dynamic>);
  }
}
