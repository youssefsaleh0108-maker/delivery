import 'dart:math' as math;

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';

import 'delivery_address.dart';

/// What every checkout on the phone shares about placing an order — the regular checkout and the
/// gift checkout today, the multi-shop basket next — so they cannot drift apart on the two things
/// that decide what the customer is told: whether the address is inside the shop's circle, and the
/// sentence for a placement the platform refused.
///
/// What is deliberately NOT here is the placement itself. Each checkout builds its own
/// [OrderSubmission] and sends it through [OrderApi.place], which carries the key, the retry rules
/// ([OrderApi.mayHavePlaced]) and the price guard for all of them.

/// Great-circle distance in metres — the haversine, enough precision for a delivery circle.
double distanceMetres(double lat1, double lng1, double lat2, double lng2) {
  const double earthRadius = 6371000;
  final double dLat = _rad(lat2 - lat1);
  final double dLng = _rad(lng2 - lng1);
  final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _rad(double deg) => deg * math.pi / 180;

/// Whether [address] is outside the delivery circle [shop] declared.
///
/// Only when the shop declared a radius and both pins exist: an address with no pin passes, because
/// the shop's areas still gate it on the server and refusing over information nobody has would
/// block real orders.
bool isOutsideDeliveryRadius(StoreCard? shop, DeliveryAddress address) {
  if (shop == null ||
      shop.deliveryRadiusMetres == null ||
      shop.latitude == null ||
      shop.longitude == null ||
      address.latitude == null ||
      address.longitude == null) {
    return false;
  }
  return distanceMetres(shop.latitude!, shop.longitude!, address.latitude!, address.longitude!) >
      shop.deliveryRadiusMetres!;
}

/// The sentence for a placement the platform answered with a refusal.
///
/// Only for a refusal — never for a send that may have placed the order, which the caller has
/// already told apart with [OrderApi.mayHavePlaced]. The server's own detail wins where it sent one,
/// because it names the actual item or shop ("Bloom & Wrap is closed…"); only the fallback is
/// translated, and a specific English sentence beats a vague Arabic one here.
String placementRefusalMessage(DioException e, DeliveryStrings t) {
  final Object? body = e.response?.data;
  final String? detail = body is Map<String, dynamic> ? body['detail'] as String? : null;
  return switch (e.response?.statusCode) {
    // An item went out of stock, the shop closed, the area is not served — or, for a gift, cash.
    422 => detail ?? t.itemNoLongerAvailable,
    // The payment provider said no and the placement rolled back: there is no order.
    402 => detail ?? t.custPaymentDeclined,
    400 => t.checkDeliveryDetails,
    _ => t.couldNotPlaceOrder,
  };
}
