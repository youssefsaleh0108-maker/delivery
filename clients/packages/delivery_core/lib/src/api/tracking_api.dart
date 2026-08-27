import 'package:dio/dio.dart';

import '../models/tracking_models.dart';

/// Client for the Order Tracking ETA, duty and presence APIs.
///
/// The order-scoped position calls stayed on [OrderApi] where the screens already reach them; this
/// class holds what the tracking service added since — the ETA, and everything about a *rider*
/// rather than a delivery. The split mirrors the server's own two controllers.
///
/// Every write path here is `me`: the rider id comes from the token, and there is no request shape
/// in which a rider names somebody else.
class TrackingApi {
  TrackingApi(this._dio);

  final Dio _dio;

  // ---------------------------------------------------------------- eta

  /// How far the rider still has to go and when they are expected.
  ///
  /// Always a body, never a 204 — the interesting cases are the ones with no number in them. When
  /// [OrderEta.available] is false, [OrderEta.reason] says why and the screen renders that
  /// sentence rather than a spinner. Never invent a number the server did not send.
  ///
  /// Authorised like the live position: customer, merchant or assigned rider of this order, or
  /// backoffice. Anyone else gets the same 404 an unknown order gets.
  Future<OrderEta> eta(String orderId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/tracking/orders/$orderId/eta');
    return OrderEta.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- duty

  /// Goes on or off duty.
  ///
  /// Returns the resulting presence rather than nothing, and the app should render
  /// [RiderPresence.state] from it: a rider who went on duty before their phone had a GPS fix
  /// comes back [PresenceState.stale], and telling them so beats showing them as available for
  /// work they will not receive.
  Future<RiderPresence> setDuty(DutyState state) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/tracking/riders/me/duty',
      data: <String, dynamic>{'state': state.wire},
    );
    return RiderPresence.fromJson(response.data as Map<String, dynamic>);
  }

  /// The rider's own state, for an app that has just been reopened.
  ///
  /// Null when they have never declared duty or pinged — nothing has happened, which is not the
  /// same as an invented "off duty" row. The toggle renders its resting state.
  Future<RiderPresence?> myPresence() async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/tracking/riders/me/duty',
      options: Options(validateStatus: (int? s) => s != null && s < 300),
    );
    if (response.statusCode == 204 || response.data == null) {
      return null;
    }
    return RiderPresence.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- location

  /// Reports where this rider is while holding no job.
  ///
  /// The order-scoped ping cannot serve the roster between deliveries — it needs an order id and
  /// there isn't one. Fire-and-forget like that ping: a dropped fix is replaced by the next one.
  Future<void> ping(double lat, double lng, {double? accuracyM}) async {
    await _dio.post<dynamic>(
      '/api/tracking/riders/me/ping',
      data: <String, dynamic>{
        'lat': lat,
        'lng': lng,
        if (accuracyM != null) 'accuracyM': accuracyM,
      },
    );
  }

  /// Where one rider is.
  ///
  /// The server narrows this sharply — self, backoffice, the employing fleet, or a customer with
  /// a live order in that rider's hands — and answers 404 to everybody else, identically to a
  /// rider who does not exist.
  Future<RiderPresence> riderLocation(String riderId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/tracking/riders/$riderId/location');
    return RiderPresence.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- consoles

  /// The fleet roster the Backoffice and carrier consoles poll.
  ///
  /// A carrier's scope comes from their own membership row and [carrierId] is ignored for them
  /// entirely; Backoffice may name one, and sees every fleet when they do not.
  ///
  /// [onDutyOnly] filters on the *declared* state on purpose: a rider who declared duty and then
  /// went quiet is precisely who a dispatcher needs to see. They come back
  /// [PresenceState.stale].
  Future<List<RiderPresence>> roster({String? carrierId, bool onDutyOnly = true}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/tracking/riders/roster',
      queryParameters: <String, dynamic>{
        if (carrierId != null) 'carrierId': carrierId,
        'onDutyOnly': onDutyOnly,
      },
    );
    return (response.data as List<dynamic>)
        .map((dynamic e) => RiderPresence.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
