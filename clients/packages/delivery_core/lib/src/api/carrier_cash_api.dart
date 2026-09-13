import 'dart:math';

import 'package:dio/dio.dart';

import '../models/carrier_cash_models.dart';
import '../models/statement_models.dart' show Money;

/// A delivery company's own cash. CARRIER only.
///
/// There is no company parameter anywhere on this client, and that is the point: whose cash comes
/// back is decided by the caller's token, server-side, exactly as for the carrier's statement. A
/// rider ref only ever addresses a rider WITHIN the caller's company; one who has never carried
/// cash for it answers 404.
///
/// Reached through [AccountingApi.carrierCash] rather than built from its own Dio, so the portal
/// shell can offer it without another field on its API bundle.
class CarrierCashApi {
  CarrierCashApi(this._dio);

  final Dio _dio;

  static const String _base = '/api/accounting/carrier/cash';

  /// The reconciliation page for [day] (today, server-side, when null). Balances are always as of
  /// now; only the collected, earned and handed-over figures are the day's.
  Future<CarrierCashOverview> overview({DateTime? day}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      _base,
      queryParameters: <String, dynamic>{if (day != null) 'day': isoDate(day)},
    );
    return CarrierCashOverview.fromJson(response.data as Map<String, dynamic>);
  }

  /// One rider's settlement page. 404 for a rider who never carried cash for this company.
  Future<RiderCashSettlement> rider(String riderRef) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('$_base/riders/${Uri.encodeComponent(riderRef)}');
    return RiderCashSettlement.fromJson(response.data as Map<String, dynamic>);
  }

  /// The company's hand-overs from every rider, newest first.
  Future<List<CashHandover>> history({int limit = 50}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '$_base/handovers',
      queryParameters: <String, dynamic>{'limit': limit},
    );
    final Map<String, dynamic> body = response.data as Map<String, dynamic>;
    return (body['handovers'] as List<dynamic>? ?? <dynamic>[])
        .map((dynamic h) => CashHandover.fromJson(h as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// What the company owes the platform now, what its riders still hold, and what it has paid.
  Future<CarrierCashOwed> owed() async {
    final Response<dynamic> response = await _dio.get<dynamic>('$_base/owed');
    return CarrierCashOwed.fromJson(response.data as Map<String, dynamic>);
  }

  /// Records that a rider handed the company everything they hold for it.
  ///
  /// [expected] is the figure the person at the counter confirmed. If the rider's balance is
  /// anything else by the time this lands, nothing is recorded and this throws [CashAmountChanged]
  /// with the current figure. [requestKey] makes a double press harmless: the same key answers with
  /// the first hand-over, marked [HandoverReceipt.replayed]. Make one with [newRequestKey] per
  /// confirmation, not per press.
  ///
  /// This clears a rider's balance and cannot be undone, so nothing should call it without an
  /// explicit human confirmation.
  Future<HandoverReceipt> recordHandover(
    String riderRef, {
    required Money expected,
    required String requestKey,
    CashMethod method = CashMethod.cash,
    String? note,
  }) async {
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        '$_base/riders/${Uri.encodeComponent(riderRef)}/handovers',
        data: <String, dynamic>{
          // The server's own string, untouched. Never a number.
          'expectedAmount': expected.amount,
          'method': method.wire,
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          'requestKey': requestKey,
        },
      );
      return HandoverReceipt.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw amountChangedOr(e);
    }
  }

  /// An idempotency key for one confirmation: 32 hex characters from the secure generator.
  static String newRequestKey() {
    final Random random = Random.secure();
    return List<String>.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// A 409 AMOUNT_CHANGED as a [CashAmountChanged]; anything else unchanged.
  static Object amountChangedOr(DioException e) {
    final Object? data = e.response?.data;
    if (e.response?.statusCode == 409 &&
        data is Map<String, dynamic> &&
        data['code'] == 'AMOUNT_CHANGED') {
      return CashAmountChanged(Money.parse(data['current']));
    }
    return e;
  }

  /// `yyyy-MM-dd` from the calendar day the caller picked — never via UTC, which moves the day for
  /// anybody east of Greenwich.
  static String isoDate(DateTime value) => '${value.year.toString().padLeft(4, '0')}'
      '-${value.month.toString().padLeft(2, '0')}'
      '-${value.day.toString().padLeft(2, '0')}';
}
