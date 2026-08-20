import 'package:dio/dio.dart';

import '../models/offer_models.dart';

/// Fee waivers, and what they are costing. BACKOFFICE only.
class OfferApi {
  OfferApi(this._dio);

  final Dio _dio;

  /// What a basket would get. Callable by a customer — the only endpoint here that is.
  ///
  /// Consults the budget, so it will not promise a free delivery the platform can no longer afford.
  Future<OfferPreview> preview({
    required String storeId,
    required double subtotal,
    double deliveryFee = 0,
  }) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/offers/preview',
      queryParameters: <String, dynamic>{
        'storeId': storeId,
        'subtotal': subtotal,
        'deliveryFee': deliveryFee,
      },
    );
    return OfferPreview.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<FeeWaiverOffer>> all() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/offers');
    return (response.data as List<dynamic>)
        .map((dynamic j) => FeeWaiverOffer.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Separate from [all] so a dashboard can poll the budget without pulling every offer ever made.
  Future<OfferBudget> budget() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/offers/budget');
    return OfferBudget.fromJson(response.data as Map<String, dynamic>);
  }

  Future<FeeWaiverOffer> create({
    required OfferAudience audience,
    required String title,
    String? subtitle,
    double minSubtotal = 0,
    DateTime? startsAt,
    DateTime? endsAt,
    String? storeId,
    String? merchantRef,
    String? providerId,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/offers',
      data: <String, dynamic>{
        'audience': audience.wire,
        'title': title,
        'subtitle': subtitle,
        'minSubtotal': minSubtotal,
        'startsAt': startsAt?.toUtc().toIso8601String(),
        'endsAt': endsAt?.toUtc().toIso8601String(),
        'storeId': storeId,
        'merchantRef': merchantRef,
        'providerId': providerId,
      },
    );
    return FeeWaiverOffer.fromJson(response.data as Map<String, dynamic>);
  }

  /// Withdrawn, not deleted: orders already placed keep their own stamped decision, and the row is
  /// the only record of why the platform gave that money away.
  Future<FeeWaiverOffer> withdraw(String id) async {
    final Response<dynamic> response = await _dio.post<dynamic>('/api/offers/$id/withdraw');
    return FeeWaiverOffer.fromJson(response.data as Map<String, dynamic>);
  }
}
