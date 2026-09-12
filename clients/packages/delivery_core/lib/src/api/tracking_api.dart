import 'package:dio/dio.dart';

import '../models/attendance_models.dart';
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

  /// The rider's own hours online, day by day. DELIVERY only; the rider is the token subject.
  ///
  /// [days] is 1..30 and out of range is a 400 — this service refuses rather than clamping, unlike
  /// the order-manager daily series. The response carries ONLY dates with on-duty time
  /// ([HoursOnline.days] can be empty); the screen draws its own zeros across the window.
  Future<HoursOnline> myDutyHours({int days = 7}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/tracking/riders/me/duty/hours',
      queryParameters: <String, dynamic>{'days': days},
    );
    return HoursOnline.fromJson(response.data as Map<String, dynamic>);
  }

  /// One rider's hours online, by their Keycloak subject. BACKOFFICE (any rider) or CARRIER
  /// (their own fleet, resolved from the caller's membership — never the request).
  ///
  /// For a carrier, a foreign rider and an unknown rider return the IDENTICAL 404 — riders are not
  /// enumerable across fleets, so a 404 here means "nobody you can see", nothing more. A CARRIER
  /// with no company gets 403. History starts at the feature's migration; nothing is backfilled.
  Future<HoursOnline> riderDutyHours(String riderId, {int days = 7}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/tracking/riders/$riderId/duty/hours',
      queryParameters: <String, dynamic>{'days': days},
    );
    return HoursOnline.fromJson(response.data as Map<String, dynamic>);
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

  // ---------------------------------------------------------------- attendance (Riders HR)
  //
  // Scoped exactly like [riderDutyHours]: BACKOFFICE reads any rider, a CARRIER only its own fleet
  // (resolved from its token), and a foreign rider is the same 404 as an unknown one. Every write
  // is CARRIER only, and the fleet written to is never a parameter.

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';

  static String _month(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  /// One rider's calendar month, every day judged against their schedule, with the totals.
  Future<RiderAttendance> riderAttendance(String riderId, {required DateTime month}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/tracking/riders/$riderId/attendance',
      queryParameters: <String, dynamic>{'month': _month(month)},
    );
    return RiderAttendance.fromJson(response.data as Map<String, dynamic>);
  }

  /// One rider's duty sessions over at most 31 days, whole (a session crossing an edge is listed
  /// once, not clipped).
  Future<List<DutySessionView>> riderDutySessions(String riderId,
      {required DateTime from, required DateTime to}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/tracking/riders/$riderId/duty/sessions',
      queryParameters: <String, dynamic>{'from': _day(from), 'to': _day(to)},
    );
    final Map<String, dynamic> body = response.data as Map<String, dynamic>;
    return (body['sessions'] as List<dynamic>? ?? <dynamic>[])
        .map((dynamic s) => DutySessionView.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  /// The caller's whole fleet for one month, totals only — what a pay run reads.
  Future<FleetAttendance> fleetAttendance({required DateTime month}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/tracking/carrier/attendance',
      queryParameters: <String, dynamic>{'month': _month(month)},
    );
    return FleetAttendance.fromJson(response.data as Map<String, dynamic>);
  }

  /// The caller's company's shifts, retired ones included and marked.
  Future<List<ShiftTemplate>> shifts() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/tracking/carrier/shifts');
    return (response.data as List<dynamic>)
        .map((dynamic s) => ShiftTemplate.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  /// A new shift. Its hours cannot be edited afterwards — see [ShiftTemplate].
  ///
  /// [weekdays] are ISO weekdays, [DateTime.monday]..[DateTime.sunday].
  Future<ShiftTemplate> createShift({
    required String name,
    required String startTime,
    required String endTime,
    required List<int> weekdays,
    int? lateGraceMinutes,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/tracking/carrier/shifts',
      data: <String, dynamic>{
        'name': name,
        'startTime': startTime,
        'endTime': endTime,
        'days': <String>[for (final int d in weekdays) ShiftTemplate.weekdayWire[d - 1]],
        if (lateGraceMinutes != null) 'lateGraceMinutes': lateGraceMinutes,
      },
    );
    return ShiftTemplate.fromJson(response.data as Map<String, dynamic>);
  }

  /// Retires a shift. 409 while riders are still on it — the body's `riders` says how many.
  Future<ShiftTemplate> retireShift(String shiftId) async {
    final Response<dynamic> response =
        await _dio.delete<dynamic>('/api/tracking/carrier/shifts/$shiftId');
    return ShiftTemplate.fromJson(response.data as Map<String, dynamic>);
  }

  /// Who in the fleet is on which shift, today and from later dates.
  Future<List<ShiftAssignment>> shiftAssignments() async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/tracking/carrier/shift-assignments');
    return (response.data as List<dynamic>)
        .map((dynamic a) => ShiftAssignment.fromJson(a as Map<String, dynamic>))
        .toList();
  }

  /// Puts a rider on [shiftId] from [effectiveFrom] (today when null), or — with a null
  /// [shiftId] — takes them off their schedule. Never backdated; the server refuses a past date.
  /// Answers with the rider's schedule from today.
  Future<List<ShiftAssignment>> assignShift(String riderId,
      {String? shiftId, DateTime? effectiveFrom}) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/tracking/riders/$riderId/shift-assignment',
      data: <String, dynamic>{
        'shiftId': shiftId,
        if (effectiveFrom != null) 'effectiveFrom': _day(effectiveFrom),
      },
    );
    return (response.data as List<dynamic>)
        .map((dynamic a) => ShiftAssignment.fromJson(a as Map<String, dynamic>))
        .toList();
  }

  /// Records or replaces the office's entry for one day. Clock times (`HH:mm`) only with
  /// [AttendanceEntryKind.present], and both or neither.
  Future<ManualAttendanceEntry> recordAttendanceEntry(
    String riderId, {
    required DateTime date,
    required AttendanceEntryKind status,
    String? clockIn,
    String? clockOut,
    String? note,
  }) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/tracking/riders/$riderId/attendance/entries/${_day(date)}',
      data: <String, dynamic>{
        'status': status.wire,
        if (clockIn != null) 'clockIn': clockIn,
        if (clockOut != null) 'clockOut': clockOut,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
    return ManualAttendanceEntry.fromJson(response.data as Map<String, dynamic>);
  }

  /// Withdraws the office's entry for a day; the day goes back to what the app recorded.
  Future<void> withdrawAttendanceEntry(String riderId, DateTime date) async {
    await _dio.delete<dynamic>('/api/tracking/riders/$riderId/attendance/entries/${_day(date)}');
  }
}
