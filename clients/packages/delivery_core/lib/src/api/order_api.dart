import 'package:dio/dio.dart';

import '../models/catalog_models.dart';
import '../models/order_models.dart';
import '../models/provider_models.dart';
import '../models/summary_models.dart';

/// Client for the Order Manager and Order Tracking APIs (Phase 2).
///
/// Every method here maps to one endpoint. Note there is no client-side authorisation logic: which
/// list a role may read, and which transition it may make, is decided by the services. The client
/// renders what it is given — see [DeliveryOrder.availableActions].
class OrderApi {
  OrderApi(this._dio);

  final Dio _dio;

  // ---------------------------------------------------------------- customer

  Future<DeliveryOrder> place({
    required List<({String productId, int qty, List<String> optionIds})> items,
    required String deliveryAddress,
    String? contactPhone,
    String? notes,
    /// The area the address is in, when the customer picked one.
    ///
    /// Optional: an address saved before areas existed has none, and the server prices those at
    /// the shop's flat fee rather than refusing them.
    String? deliveryZoneId,

    /// How the customer intends to pay. Cash is the only method the app offers, and also what the
    /// server assumes when this is absent — sent explicitly all the same, so the order records a
    /// choice the customer actually made rather than a default nobody saw.
    PaymentMethod paymentMethod = PaymentMethod.cash,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/orders',
      data: <String, dynamic>{
        'items': items
            .map((({String productId, int qty, List<String> optionIds}) i) =>
                <String, dynamic>{
                  'productId': i.productId,
                  'qty': i.qty,
                  if (i.optionIds.isNotEmpty) 'optionIds': i.optionIds,
                })
            .toList(),
        'deliveryAddress': deliveryAddress,
        if (deliveryZoneId != null) 'deliveryZoneId': deliveryZoneId,
        if (contactPhone != null && contactPhone.isNotEmpty) 'contactPhone': contactPhone,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'paymentMethod': paymentMethod.wire,
      },
    );
    return DeliveryOrder.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Paged<DeliveryOrder>> mine({int page = 0, int size = 20}) =>
      _page('/api/orders/mine', page, size);

  // ---------------------------------------------------------------- merchant

  Future<Paged<DeliveryOrder>> forMerchant({int page = 0, int size = 20}) =>
      _page('/api/orders/merchant', page, size);

  /// How the shop is trading, day by day. MERCHANT only, and always about the caller's own shop.
  Future<MerchantSummary> merchantSummary({int days = 14}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
        '/api/orders/merchant/summary', queryParameters: <String, dynamic>{'days': days});
    return MerchantSummary.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- rider

  /// READY orders no rider has claimed. Oldest first — the longest wait goes out next.
  Future<Paged<DeliveryOrder>> available({int page = 0, int size = 20}) =>
      _page('/api/orders/available', page, size);

  Future<Paged<DeliveryOrder>> assigned({int page = 0, int size = 20}) =>
      _page('/api/orders/assigned', page, size);

  // ---------------------------------------------------------------- backoffice

  /// Everything the caller's delivery company has carried or is carrying. CARRIER only.
  Future<Paged<DeliveryOrder>> forCarrier({int page = 0, int size = 20}) =>
      _page('/api/orders/carrier', page, size);

  /// What the company has earned and what the work in flight is worth. CARRIER only.
  Future<CarrierEarnings> carrierEarnings() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/orders/carrier/earnings');
    return CarrierEarnings.fromJson(response.data as Map<String, dynamic>);
  }

  /// The same company's work day by day, for the dashboard. CARRIER only.
  Future<CarrierSummary> carrierSummary({int days = 14}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
        '/api/orders/carrier/summary', queryParameters: <String, dynamic>{'days': days});
    return CarrierSummary.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Paged<DeliveryOrder>> all({OrderStatus? status, int page = 0, int size = 20}) =>
      _page('/api/orders', page, size,
          extra: status == null ? null : <String, dynamic>{'status': status.wire});

  Future<OrderStats> stats() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/orders/stats');
    return OrderStats.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- shared

  Future<DeliveryOrder> read(String orderId) async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/orders/$orderId');
    return DeliveryOrder.fromJson(response.data as Map<String, dynamic>);
  }

  /// Applies one of the actions the server offered on this order.
  ///
  /// Driven by [OrderAction] rather than a free-text path so a screen cannot invent a transition
  /// the service never advertised.
  Future<DeliveryOrder> act(String orderId, OrderAction action, {String? reason}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/orders/$orderId/${action.path}',
      data: action == OrderAction.cancel
          ? <String, dynamic>{'reason': reason ?? ''}
          : null,
    );
    return DeliveryOrder.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- tracking

  /// The rider's latest position, or null when nothing has been reported yet.
  ///
  /// 204 means "you may watch this, but there is no fix yet" — distinct from 404, which means the
  /// order is unknown or not yours.
  Future<RiderPosition?> currentPosition(String orderId) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/tracking/orders/$orderId',
      options: Options(validateStatus: (int? s) => s != null && s < 300),
    );
    if (response.statusCode == 204 || response.data == null) {
      return null;
    }
    return RiderPosition.fromJson(response.data as Map<String, dynamic>);
  }

  /// Reports this rider's position. Fire-and-forget: a dropped ping is replaced by the next one.
  Future<void> ping(String orderId, double lat, double lng, {double? accuracyM}) async {
    await _dio.post<dynamic>(
      '/api/tracking/orders/$orderId/ping',
      data: <String, dynamic>{
        'lat': lat,
        'lng': lng,
        if (accuracyM != null) 'accuracyM': accuracyM,
      },
    );
  }

  Future<List<RiderPosition>> trackHistory(String orderId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/tracking/orders/$orderId/history');
    return (response.data as List<dynamic>)
        .map((dynamic e) => RiderPosition.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------- internals

  Future<Paged<DeliveryOrder>> _page(String path, int page, int size,
      {Map<String, dynamic>? extra}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      path,
      queryParameters: <String, dynamic>{'page': page, 'size': size, ...?extra},
    );
    return Paged<DeliveryOrder>.fromJson(
      response.data as Map<String, dynamic>,
      (Map<String, dynamic> json) => DeliveryOrder.fromJson(json),
    );
  }
}
