import 'package:dio/dio.dart';

import '../models/catalog_models.dart';
import '../models/order_models.dart';
import '../models/provider_models.dart';
import '../models/rating_models.dart';
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

    /// How the customer intends to pay. Cash is what the server assumes when this is absent —
    /// sent explicitly all the same, so the order records a choice the customer actually made
    /// rather than a default nobody saw. Non-cash methods need [paymentInstrumentToken] and
    /// authorise against whatever provider is configured — the DEV one until a real credential
    /// exists, which the offering screen must label as a test payment.
    PaymentMethod paymentMethod = PaymentMethod.cash,

    /// A promo code, exactly as the customer typed it. The code and nothing else — what it is
    /// worth is decided server-side against the server's own subtotal, and comes back on the
    /// order as `discountAmount` and the canonical `promoCode`.
    String? promoCode,

    /// The payment processor's opaque handle for a card or wallet, minted by its own SDK on the
    /// customer's device. Null on a cash order. Never a card number — the platform stays out of
    /// PCI scope by never seeing one.
    String? paymentInstrumentToken,

    /// The map pin for [deliveryAddress], as the address picker resolved it. Both or neither —
    /// the server drops half a pair rather than route to the wrong hemisphere. Without a pin the
    /// order is placed and delivered exactly as before; what it does not get is a live ETA.
    double? deliveryLatitude,
    double? deliveryLongitude,
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
        if (promoCode != null && promoCode.isNotEmpty) 'promoCode': promoCode,
        if (paymentInstrumentToken != null && paymentInstrumentToken.isNotEmpty)
          'paymentInstrumentToken': paymentInstrumentToken,
        if (deliveryLatitude != null && deliveryLongitude != null) ...<String, dynamic>{
          'deliveryLatitude': deliveryLatitude,
          'deliveryLongitude': deliveryLongitude,
        },
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

  // ---------------------------------------------------------------- rider ratings

  /// Rates the rider on a delivered order. CUSTOMER only; the service then decides whether this
  /// order was the caller's, delivered, and not already rated — 409 when it was.
  ///
  /// [stars] is 1–5; [text] is optional and stripped of markup server-side.
  Future<RiderRatingEntry> rateRider(String orderId, int stars, {String? text}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/orders/$orderId/rating',
      data: <String, dynamic>{
        'score': stars,
        if (text != null && text.isNotEmpty) 'comment': text,
      },
    );
    return RiderRatingEntry.fromJson(response.data as Map<String, dynamic>);
  }

  /// What the caller left on their own order, or null when they have not rated it — how the
  /// screen knows to show stars already given rather than offer to rate again.
  Future<RiderRatingEntry?> orderRating(String orderId) async {
    try {
      final Response<dynamic> response =
          await _dio.get<dynamic>('/api/orders/$orderId/rating');
      return RiderRatingEntry.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  /// A rider's aggregate — the number next to their name on a tracking screen. Open to any
  /// authenticated caller; carries no comments and no individual scores.
  ///
  /// Render [RiderStanding.average] null as "new", never as zero.
  Future<RiderStanding> riderRating(String riderId) async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/riders/$riderId/rating');
    return RiderStanding.fromJson(response.data as Map<String, dynamic>);
  }

  /// A rider's own standing, addressed by their token rather than an id they would have to know
  /// the spelling of. DELIVERY only.
  Future<RiderStanding> myRiderRating() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/riders/me/rating');
    return RiderStanding.fromJson(response.data as Map<String, dynamic>);
  }

  /// The written comments about a rider. BACKOFFICE only — free text about a named individual is
  /// not part of the public score.
  Future<Paged<RiderRatingComment>> riderRatingComments(String riderId,
      {int page = 0, int size = 20}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/riders/$riderId/rating/comments',
      queryParameters: <String, dynamic>{'page': page, 'size': size},
    );
    return Paged<RiderRatingComment>.fromJson(
        response.data as Map<String, dynamic>, RiderRatingComment.fromJson);
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
