import 'package:dio/dio.dart';

import '../models/checkout_tracking_models.dart';

/// Client for Order Tracking's checkout map: every order of a multi-shop checkout on one map.
///
/// Separate from `TrackingApi` because the subject is a customer's purchase rather than one
/// delivery, and so is the audience: only the checkout's own customer (and the back office) may
/// read it. Another customer, a sibling order's merchant and the rider all get the 404 an unknown
/// checkout gets.
class CheckoutTrackingApi {
  CheckoutTrackingApi(this._dio);

  final Dio _dio;

  /// The checkout's map: shop pins, the door, each order's status and estimate, riders once
  /// assigned, and the expected routes with how the server says to draw them.
  ///
  /// The server computes a checkout at most once every few seconds and shares the answer, so
  /// polling faster than that only returns the same view.
  Future<CheckoutTracking> view(String checkoutId) async {
    final Response<dynamic> response = await _dio
        .get<dynamic>('/api/tracking/checkouts/${Uri.encodeComponent(checkoutId)}');
    return CheckoutTracking.fromJson(response.data as Map<String, dynamic>);
  }
}
