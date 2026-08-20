import 'package:dio/dio.dart';

import '../models/delivery_rate.dart';

/// Reads per-provider delivery rates — BACKOFFICE only (Phase 6).
///
/// Read-only by design. Nothing here changes a provider; that stays on the Connector Settings API
/// so every change to where messages go keeps going through one audited path.
class DeliveryRateApi {
  DeliveryRateApi(this._dio);

  final Dio _dio;

  Future<List<ProviderDeliveryRate>> rates({int windowHours = 24}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/notification-rates',
      queryParameters: <String, dynamic>{'windowHours': windowHours},
    );
    return (response.data as List<dynamic>)
        .map((dynamic e) => ProviderDeliveryRate.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Just the channel a cutover is happening on, which is all the Settings screen needs.
  Future<List<ProviderDeliveryRate>> forChannel(String channel, {int windowHours = 24}) async {
    final List<ProviderDeliveryRate> all = await rates(windowHours: windowHours);
    return all.where((ProviderDeliveryRate r) => r.channel == channel).toList();
  }
}
