import 'package:dio/dio.dart';

/// Client for the money-transfer service — the checkout's money surface.
///
/// The RATE here is the one that binds: `/quote` turns a proposed USD split into the exact lira
/// face value at the platform rate locked server-side, and `initiate` records the approved
/// intent. The storefront's display conversion (MarketRates) shows the same figure, but this is
/// the service that promises it.
class TransferApi {
  TransferApi(this._dio);

  final Dio _dio;

  /// The locked platform rate and the rider-change promise the checkout banner prints.
  Future<TransferRate> rate() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/transfers/rate');
    final Map<String, dynamic> data = response.data as Map<String, dynamic>;
    return TransferRate(
      lbpPerUsd: (data['lbpPerUsd'] as num).toDouble(),
      riderChangeLimitLbp: (data['riderChangeLimitLbp'] as num?)?.toDouble() ?? 0,
    );
  }

  /// The methods some connector will actually carry right now.
  Future<List<String>> methods() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/transfers/methods');
    return (response.data as List<dynamic>).cast<String>();
  }

  /// Records the approved payment intent for a placed order.
  Future<void> initiate({
    required String orderId,
    required String method,
    required double amountUsd,
    double? splitUsd,
  }) async {
    await _dio.post<dynamic>('/api/transfers', data: <String, dynamic>{
      'orderId': orderId,
      'method': method,
      'amountUsd': amountUsd,
      if (splitUsd != null) 'splitUsd': splitUsd,
    });
  }
}

/// The two numbers the checkout's rate banner prints.
class TransferRate {
  const TransferRate({required this.lbpPerUsd, required this.riderChangeLimitLbp});

  final double lbpPerUsd;
  final double riderChangeLimitLbp;
}
