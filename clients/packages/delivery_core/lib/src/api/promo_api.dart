import 'package:dio/dio.dart';

import '../models/promo_models.dart';

/// Client for the Order Manager promotions API.
///
/// Note what is missing, because the server is explicit about it: there is no method that
/// *applies* a code. Applying happens as part of placing the order — see the `promoCode` parameter
/// on `OrderApi.place` — so a discount can never be applied twice, or applied and then have the
/// basket changed under it.
class PromoApi {
  PromoApi(this._dio);

  final Dio _dio;

  // ---------------------------------------------------------------- customer

  /// What a code would be worth on this basket, before the customer commits to it.
  ///
  /// [subtotal] and [deliveryFee] are advisory and not trusted: they only decide what number the
  /// Discounts line shows while the customer is still typing. The discount actually applied is
  /// recomputed at placement from the basket the server priced itself.
  ///
  /// The race with the last redemption is accepted — the order then fails with "fully redeemed"
  /// rather than being placed at a price the customer did not agree to.
  Future<PromoQuote> quote(String code, {required double subtotal, double? deliveryFee}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/promotions/validate',
      data: <String, dynamic>{
        'code': code,
        'subtotal': subtotal,
        if (deliveryFee != null) 'deliveryFee': deliveryFee,
      },
    );
    return PromoQuote.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- backoffice

  /// The whole register. BACKOFFICE only.
  Future<List<PromoCodeDetails>> codes() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/promotions');
    return (response.data as List<dynamic>)
        .map((dynamic e) => PromoCodeDetails.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PromoCodeDetails> code(String id) async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/promotions/$id');
    return PromoCodeDetails.fromJson(response.data as Map<String, dynamic>);
  }

  /// Mints a code. BACKOFFICE only — this is the platform giving away money.
  ///
  /// [value] is percent for [PromoKind.percentOff], money for [PromoKind.amountOff], and ignored
  /// for [PromoKind.freeDelivery]. Null starts/ends run now/forever; null caps are unlimited.
  Future<PromoCodeDetails> createCode({
    required String code,
    required PromoKind kind,
    double? value,
    double? minSubtotal,
    DateTime? startsAt,
    DateTime? endsAt,
    int? maxRedemptions,
    int? maxPerCustomer,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/promotions',
      data: <String, dynamic>{
        'code': code,
        'kind': kind.wire,
        if (value != null) 'value': value,
        if (minSubtotal != null) 'minSubtotal': minSubtotal,
        if (startsAt != null) 'startsAt': startsAt.toUtc().toIso8601String(),
        if (endsAt != null) 'endsAt': endsAt.toUtc().toIso8601String(),
        if (maxRedemptions != null) 'maxRedemptions': maxRedemptions,
        if (maxPerCustomer != null) 'maxPerCustomer': maxPerCustomer,
      },
    );
    return PromoCodeDetails.fromJson(response.data as Map<String, dynamic>);
  }

  /// Takes a code out of circulation. Deactivate rather than delete, and there is deliberately no
  /// delete on the server: what was already given away survives the promotion being switched off.
  Future<PromoCodeDetails> deactivate(String id) async {
    final Response<dynamic> response =
        await _dio.post<dynamic>('/api/promotions/$id/deactivate');
    return PromoCodeDetails.fromJson(response.data as Map<String, dynamic>);
  }
}
