import 'package:dio/dio.dart';

import '../models/aggregate_models.dart';

/// Client for the Order Manager tier-split daily series — the same shape at three scopes.
///
/// One method per scope rather than a scope parameter, because the scopes are different roles on
/// different paths and a screen only ever holds one of them: the Backoffice draws the platform,
/// a shop draws itself, a delivery company draws itself.
///
/// [days] is clamped server-side to 1..30 with no 400 — asking for 90 quietly returns 30. Compare
/// the duty-hours endpoint, which refuses out-of-range instead.
class AggregatesApi {
  AggregatesApi(this._dio);

  final Dio _dio;

  /// The whole platform, day by day. BACKOFFICE only.
  Future<TierTradeSeries> platformDaily({int days = 14}) =>
      _series('/api/orders/daily', days);

  /// The caller's own shop, day by day. MERCHANT only; the shop is the token subject.
  Future<TierTradeSeries> merchantDaily({int days = 14}) =>
      _series('/api/orders/merchant/daily', days);

  /// The caller's own delivery company, day by day. CARRIER only; 404 when they are staff of no
  /// company.
  Future<TierTradeSeries> carrierDaily({int days = 14}) =>
      _series('/api/orders/carrier/daily', days);

  Future<TierTradeSeries> _series(String path, int days) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
        path, queryParameters: <String, dynamic>{'days': days});
    return TierTradeSeries.fromJson(response.data as Map<String, dynamic>);
  }
}
