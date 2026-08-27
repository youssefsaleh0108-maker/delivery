import 'package:dio/dio.dart';

import '../models/rider_money_models.dart';

/// Client for the Accounting rider-earnings API: the Earnings screen, tips, and cash-outs.
///
/// Whose money you see is decided by the token, never by a parameter — every self-service call
/// below names nobody. The Backoffice half at the bottom does name a rider, because paying
/// somebody is by definition an operator acting on another person's behalf, and the server gates
/// those by role.
class RiderMoneyApi {
  RiderMoneyApi(this._dio);

  final Dio _dio;

  // ---------------------------------------------------------------- rider

  /// Everything the Earnings screen needs in one call: today, this week, the chart series and the
  /// balance — from one moment, so the arithmetic on screen adds up.
  ///
  /// [zone] is an IANA timezone id for bucketing the days; omitted, the server uses its default.
  Future<RiderEarnings> earnings({int days = 7, String? zone}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/rider/earnings',
      queryParameters: <String, dynamic>{'days': days, if (zone != null) 'zone': zone},
    );
    return RiderEarnings.fromJson(response.data as Map<String, dynamic>);
  }

  /// Just the day-by-day series, for a screen that only draws the chart.
  Future<List<EarningsDay>> series({int days = 7, String? zone}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/rider/earnings/series',
      queryParameters: <String, dynamic>{'days': days, if (zone != null) 'zone': zone},
    );
    return (response.data as List<dynamic>)
        .map((dynamic e) => EarningsDay.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The recent jobs and what each one paid. Render [RiderJob.payableBy] with each figure — a
  /// line the rider's company owes must not read as money the platform will hand over.
  Future<List<RiderJob>> recentJobs({int limit = 20}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/rider/earnings/jobs',
      queryParameters: <String, dynamic>{'limit': limit},
    );
    return (response.data as List<dynamic>)
        .map((dynamic e) => RiderJob.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// What the platform owes, what can be taken out, and any request already in flight.
  Future<RiderBalance> balance() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/rider/balance');
    return RiderBalance.fromJson(response.data as Map<String, dynamic>);
  }

  /// Asks for the balance in money. The money is held the moment this succeeds.
  ///
  /// A 409 means a request is already open — good news wearing an error status, and the screen
  /// should say "already on its way" rather than render a form error. A 400 carries the server's
  /// reason (below the minimum, more than is available).
  Future<CashOut> requestCashOut(double amount, {String? payoutNote}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/rider/cash-outs',
      data: <String, dynamic>{
        'amount': amount,
        if (payoutNote != null && payoutNote.isNotEmpty) 'payoutNote': payoutNote,
      },
    );
    return CashOut.fromJson(response.data as Map<String, dynamic>);
  }

  /// The rider's own cash-out history, newest first.
  Future<List<CashOut>> myCashOuts({int limit = 20}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/rider/cash-outs',
      queryParameters: <String, dynamic>{'limit': limit},
    );
    return (response.data as List<dynamic>)
        .map((dynamic e) => CashOut.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------- customer

  /// Tips the rider who delivered an order. CUSTOMER only, and only on their own delivered order.
  ///
  /// [TipMethod.cash] records notes already handed over at the door. [TipMethod.online] is
  /// refused by the server until a payment processor is configured — do not offer it while the
  /// build has none.
  Future<TipReceipt> tip(String orderId, double amount,
      {TipMethod method = TipMethod.cash}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/rider/tips',
      data: <String, dynamic>{
        'orderId': orderId,
        'amount': amount,
        'method': method.wire,
      },
    );
    return TipReceipt.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- backoffice

  /// Everything waiting on a payout, oldest first — the operator has been keeping somebody
  /// waiting. BACKOFFICE only.
  Future<List<CashOut>> cashOutQueue({int limit = 50}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/rider/cash-outs/queue',
      queryParameters: <String, dynamic>{'limit': limit},
    );
    return (response.data as List<dynamic>)
        .map((dynamic e) => CashOut.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Records that the money was handed over. BACKOFFICE only.
  Future<CashOut> payCashOut(String id, {String? note}) => _decide(id, 'pay', note);

  /// Refuses the request; the held money goes back to the balance. BACKOFFICE only.
  Future<CashOut> rejectCashOut(String id, {String? note}) => _decide(id, 'reject', note);

  Future<CashOut> _decide(String id, String action, String? note) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/rider/cash-outs/$id/$action',
      data: note == null ? null : <String, dynamic>{'note': note},
    );
    return CashOut.fromJson(response.data as Map<String, dynamic>);
  }
}
