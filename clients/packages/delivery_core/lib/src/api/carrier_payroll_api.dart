import 'package:dio/dio.dart';

import '../models/carrier_cash_models.dart' show CashMethod;
import '../models/carrier_payroll_models.dart';
import '../models/statement_models.dart' show Money;
import 'carrier_cash_api.dart' show CarrierCashApi;

/// A delivery company's payroll for its own riders. CARRIER only.
///
/// There is no company parameter anywhere, as on [CarrierCashApi]: whose payroll comes back is the
/// caller's token's to decide, server-side. A rider is only ever named on a run they already have a
/// payslip on.
///
/// Reads throw what Dio throws, so a page tells "no company" from "try again" exactly as the cash
/// pages do. Writes throw [PayrollRefused] when the server refused with a reason — its code is what a
/// page words — and Dio's exception for anything else.
///
/// Nothing here moves money. A payment is recorded after the company paid, outside YouDrop.
class CarrierPayrollApi {
  CarrierPayrollApi(this._dio);

  final Dio _dio;

  static const String _base = '/api/accounting/carrier/payroll';

  /// The rules in force, the ones scheduled, their history and the days new rules could start.
  Future<PayPolicyPage> policy() async {
    final Response<dynamic> response = await _dio.get<dynamic>('$_base/policy');
    return PayPolicyPage.fromJson(response.data as Map<String, dynamic>);
  }

  /// Saves a new version of the rules, starting on [effectiveFrom].
  ///
  /// Amounts go as the text the person typed, never a number; the server refuses anything that is
  /// not to the cent rather than rounding it.
  Future<PayPolicy> savePolicy({
    required DateTime effectiveFrom,
    required PayCycle payCycle,
    required String perDeliveryRate,
    String? hourlyRate,
    required bool payManualHours,
    required String overtimeMultiplier,
    required String lateDeduction,
    required String absenceDeduction,
  }) =>
      _write(
        () => _dio.post<dynamic>('$_base/policy', data: <String, dynamic>{
          'effectiveFrom': CarrierCashApi.isoDate(effectiveFrom),
          'payCycle': payCycle.wire,
          'perDeliveryRate': perDeliveryRate,
          if (hourlyRate != null) 'hourlyRate': hourlyRate,
          'payManualHours': payManualHours,
          'overtimeMultiplier': overtimeMultiplier,
          'lateDeduction': lateDeduction,
          'absenceDeduction': absenceDeduction,
        }),
        PayPolicy.fromJson,
      );

  /// The current pay period and the ones before it, latest first.
  Future<PayPeriodsPage> periods() async {
    final Response<dynamic> response = await _dio.get<dynamic>('$_base/periods');
    return PayPeriodsPage.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PayRun> run(String runId) async {
    final Response<dynamic> response = await _dio.get<dynamic>('$_base/runs/${_seg(runId)}');
    return PayRun.fromJson(response.data as Map<String, dynamic>);
  }

  /// Starts and computes the draft for the period beginning on [periodFrom].
  Future<PayRun> start(DateTime periodFrom) => _write(
        () => _dio.post<dynamic>('$_base/runs', data: <String, dynamic>{
          'periodFrom': CarrierCashApi.isoDate(periodFrom),
        }),
        PayRun.fromJson,
      );

  /// Computes a draft again, reading hours afresh.
  Future<PayRun> recompute(String runId) => _write(
        () => _dio.post<dynamic>('$_base/runs/${_seg(runId)}/recompute'),
        PayRun.fromJson,
      );

  /// Throws a draft away.
  Future<void> discard(String runId) async {
    try {
      await _dio.delete<dynamic>('$_base/runs/${_seg(runId)}');
    } on DioException catch (e) {
      throw refusedOr(e);
    }
  }

  /// A named bonus or deduction on a rider's draft payslip.
  Future<PayRun> addLine(
    String runId, {
    required String riderRef,
    required PayLineKind kind,
    required String label,
    required String amount,
  }) =>
      _write(
        () => _dio.post<dynamic>('$_base/runs/${_seg(runId)}/lines', data: <String, dynamic>{
          'riderRef': riderRef,
          'kind': kind.wire,
          'label': label,
          'amount': amount,
        }),
        PayRun.fromJson,
      );

  Future<PayRun> removeLine(String runId, String lineId) => _write(
        () => _dio.delete<dynamic>('$_base/runs/${_seg(runId)}/lines/${_seg(lineId)}'),
        PayRun.fromJson,
      );

  /// Approves the figures of [revision] — the ones on screen.
  ///
  /// Throws [PayrollRefused] with FIGURES_CHANGED or NEEDS_ACKNOWLEDGEMENT and the run as it now is,
  /// or CASH_CHANGED; nothing is approved in any of them. Freezes the payslips and nets riders' cash
  /// for good, so nothing should call it without an explicit human confirmation.
  Future<PayRun> approve(String runId, {required int revision, bool acknowledgeMissingHours = false}) =>
      _write(
        () => _dio.post<dynamic>('$_base/runs/${_seg(runId)}/approve', data: <String, dynamic>{
          'revision': revision,
          'acknowledgeMissingHours': acknowledgeMissingHours,
        }),
        PayRun.fromJson,
      );

  /// Records that the company paid one rider. Recorded, never moved.
  Future<PayRun> markPaid(
    String runId,
    String payslipId, {
    required CashMethod method,
    String? reference,
  }) =>
      _write(
        () => _dio.post<dynamic>(
          '$_base/runs/${_seg(runId)}/payslips/${_seg(payslipId)}/paid',
          data: <String, dynamic>{
            'method': method.wire,
            if (reference != null && reference.trim().isNotEmpty) 'reference': reference.trim(),
          },
        ),
        PayRun.fromJson,
      );

  /// Records a payment that did not go through. The pay stays owed.
  Future<PayRun> markFailed(String runId, String payslipId, {required String reason}) => _write(
        () => _dio.post<dynamic>(
          '$_base/runs/${_seg(runId)}/payslips/${_seg(payslipId)}/failed',
          data: <String, dynamic>{'reason': reason},
        ),
        PayRun.fromJson,
      );

  /// Records every payslip waiting for payment as paid.
  ///
  /// [expectedTotal] is the total the confirmation showed, sent as the server's own string. If what
  /// is waiting is anything else by the time this lands, nothing is recorded and this throws
  /// [PayrollRefused] TOTAL_CHANGED with the current figure.
  Future<PayRun> payAll(
    String runId, {
    required Money expectedTotal,
    required CashMethod method,
    String? reference,
  }) =>
      _write(
        () => _dio.post<dynamic>('$_base/runs/${_seg(runId)}/pay', data: <String, dynamic>{
          'expectedTotal': expectedTotal.amount,
          'method': method.wire,
          if (reference != null && reference.trim().isNotEmpty) 'reference': reference.trim(),
        }),
        PayRun.fromJson,
      );

  /// A correction to an approved run, paid in the rider's next run.
  Future<PayRun> addCorrection(
    String runId, {
    required String riderRef,
    required PayLineKind kind,
    required String amount,
    required String reason,
  }) =>
      _write(
        () => _dio.post<dynamic>('$_base/runs/${_seg(runId)}/corrections', data: <String, dynamic>{
          'riderRef': riderRef,
          'kind': kind.wire,
          'amount': amount,
          'reason': reason,
        }),
        PayRun.fromJson,
      );

  /// A refusal the server explained, as a [PayrollRefused]; anything else unchanged.
  static Object refusedOr(DioException e) {
    final Response<dynamic>? response = e.response;
    final Object? data = response?.data;
    if (response == null || data is! Map<String, dynamic> || data['code'] is! String) return e;
    final Object? run = data['run'];
    return PayrollRefused(
      code: data['code'] as String,
      status: response.statusCode,
      message: data['error'] is String ? data['error'] as String : null,
      run: run is Map<String, dynamic> ? PayRun.fromJson(run) : null,
      current: Money.parse(data['current']),
      runId: data['runId'] is String ? data['runId'] as String : null,
    );
  }

  Future<T> _write<T>(
    Future<Response<dynamic>> Function() call,
    T Function(Map<String, dynamic>) parse,
  ) async {
    try {
      final Response<dynamic> response = await call();
      return parse(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw refusedOr(e);
    }
  }

  static String _seg(String value) => Uri.encodeComponent(value);
}
