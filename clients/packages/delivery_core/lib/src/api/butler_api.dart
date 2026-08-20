import 'package:dio/dio.dart';

import '../models/butler_models.dart';
import '../models/catalog_models.dart';

/// Butler: the errand with no catalog behind it.
///
/// Split from [OrderApi] because a request is not an order — it is the negotiation that decides
/// whether there will be one. Only [approve] crosses that line, and it is the only call here that
/// causes anybody to be charged.
class ButlerApi {
  ButlerApi(this._dio);

  final Dio _dio;

  /// What an errand costs. Fetched before the form is shown, so the fee is never a surprise at the
  /// end — and never supplied by this client, which is the server's business.
  Future<ButlerTerms> terms() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/butler/terms');
    return ButlerTerms.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- customer

  /// "Buy me this and bring it."
  Future<ButlerRequest> requestPurchase({
    required String what,
    required String dropoffAddress,
    String? sourceHint,
    double? budgetCap,
    String? contactPhone,
  }) {
    return _submit(<String, dynamic>{
      'mode': ButlerMode.buy.wireValue,
      'what': what,
      'sourceHint': sourceHint,
      'budgetCap': budgetCap,
      'dropoffAddress': dropoffAddress,
      'contactPhone': contactPhone,
    });
  }

  /// "Move this from here to there."
  Future<ButlerRequest> requestPickup({
    required String what,
    required String pickupAddress,
    required String dropoffAddress,
    String? recipient,
    String? contactPhone,
  }) {
    return _submit(<String, dynamic>{
      'mode': ButlerMode.send.wireValue,
      'what': what,
      'pickupAddress': pickupAddress,
      'recipient': recipient,
      'dropoffAddress': dropoffAddress,
      'contactPhone': contactPhone,
    });
  }

  Future<Paged<ButlerRequest>> mine({int page = 0, int size = 20}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/butler/mine',
      queryParameters: <String, dynamic>{'page': page, 'size': size},
    );
    return Paged<ButlerRequest>.fromJson(
        response.data as Map<String, dynamic>, ButlerRequest.fromJson);
  }

  /// Agrees the price. This is the call that creates an order and charges the customer.
  Future<ButlerRequest> approve(String id) => _post('/api/butler/$id/approve');

  Future<ButlerRequest> decline(String id, {String? reason}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/butler/$id/decline',
      data: <String, dynamic>{'reason': reason},
    );
    return ButlerRequest.fromJson(response.data as Map<String, dynamic>);
  }

  /// Only possible before a shopper has spent their own money. After that the exit is [decline].
  Future<ButlerRequest> cancel(String id) => _post('/api/butler/$id/cancel');

  // ---------------------------------------------------------------- rider

  Future<Paged<ButlerRequest>> available({int page = 0, int size = 20}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/butler/available',
      queryParameters: <String, dynamic>{'page': page, 'size': size},
    );
    return Paged<ButlerRequest>.fromJson(
        response.data as Map<String, dynamic>, ButlerRequest.fromJson);
  }

  Future<Paged<ButlerRequest>> claimed({int page = 0, int size = 20}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/butler/claimed',
      queryParameters: <String, dynamic>{'page': page, 'size': size},
    );
    return Paged<ButlerRequest>.fromJson(
        response.data as Map<String, dynamic>, ButlerRequest.fromJson);
  }

  Future<ButlerRequest> claim(String id) => _post('/api/butler/$id/claim');

  /// What the goods actually cost, once the shopper has paid for them.
  Future<ButlerRequest> quote(String id, {required double goodsCost, String? receiptRef}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/butler/$id/quote',
      data: <String, dynamic>{'goodsCost': goodsCost, 'receiptRef': receiptRef},
    );
    return ButlerRequest.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- shared

  Future<ButlerRequest> read(String id) async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/butler/$id');
    return ButlerRequest.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ButlerRequest> _submit(Map<String, dynamic> body) async {
    final Response<dynamic> response = await _dio.post<dynamic>('/api/butler', data: body);
    return ButlerRequest.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ButlerRequest> _post(String path) async {
    final Response<dynamic> response = await _dio.post<dynamic>(path);
    return ButlerRequest.fromJson(response.data as Map<String, dynamic>);
  }
}
