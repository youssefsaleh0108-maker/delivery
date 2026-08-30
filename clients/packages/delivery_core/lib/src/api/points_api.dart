import 'package:dio/dio.dart';

import '../models/points_models.dart';

/// Client for the points ledger — the customer's loyalty half of it.
///
/// The same endpoints serve merchants and riders (their earnings); which balance a token reads is
/// decided server-side from its roles, so there is no id here a caller could tamper with.
class PointsApi {
  PointsApi(this._dio);

  final Dio _dio;

  /// The caller's balance and, for a customer, their loyalty standing.
  Future<PointsBalance> myBalance() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/points/balance');
    return PointsBalance.fromJson(response.data as Map<String, dynamic>);
  }

  /// The most recent movements, newest first.
  Future<List<PointsEntry>> myHistory({int limit = 20}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/points/history',
      queryParameters: <String, dynamic>{'limit': limit},
    );
    return (response.data as List<dynamic>)
        .map((dynamic e) => PointsEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
