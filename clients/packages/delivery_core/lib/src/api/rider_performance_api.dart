import 'package:dio/dio.dart';

import '../models/performance_models.dart';

/// Client for the Order Manager rider-performance endpoints.
///
/// Split from [OrderApi] the way [TrackingApi] was: these are facts about a *rider* rather than an
/// order, and the class holding one endpoint per order verb was already long. Read-only by nature —
/// performance is computed from the order history, never written.
class RiderPerformanceApi {
  RiderPerformanceApi(this._dio);

  final Dio _dio;

  /// The rider's own last thirty days. DELIVERY only; the rider is the token subject.
  Future<RiderPerformance> mine() async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/orders/riders/me/performance');
    return RiderPerformance.fromJson(response.data as Map<String, dynamic>);
  }

  /// One rider's last thirty days, by their Keycloak subject.
  ///
  /// BACKOFFICE sees the rider's whole record; CARRIER sees only work done for their own company —
  /// resolved from the caller's user id, never a request field. A rider who never rode for them
  /// comes back all-zeros with a null rate, indistinguishable from a rider with no work: there is
  /// no 404 to enumerate foreign riders with. 404 only for a CARRIER who belongs to no company.
  Future<RiderPerformance> forRider(String riderId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/orders/riders/$riderId/performance');
    return RiderPerformance.fromJson(response.data as Map<String, dynamic>);
  }

  /// Per-rider delivered counts for today, in the platform's zone.
  ///
  /// BACKOFFICE is platform-wide; CARRIER is their own company only. Riders with zero deliveries
  /// are ABSENT from the list — the screen joins onto its own roster and draws the zeros itself,
  /// never treating absence as an error.
  Future<List<RiderDeliveredToday>> deliveredToday() async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/orders/riders/delivered-today');
    return (response.data as List<dynamic>)
        .map((dynamic r) => RiderDeliveredToday.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}
