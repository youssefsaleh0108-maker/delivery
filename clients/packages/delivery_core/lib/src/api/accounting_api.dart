import 'package:dio/dio.dart';

import '../models/accounting_models.dart';
import '../models/carrier_cash_models.dart';
import '../models/statement_models.dart' show Money;
import 'carrier_cash_api.dart';

/// Client for the reconciliation API — BACKOFFICE only (Phase 4).
///
/// Read-only, deliberately. There is no method to re-post or adjust a transaction because there is
/// no such endpoint: money moves as a consequence of an order, never because someone pressed a
/// button in a browser. Recovering a stuck settlement is an operator task with an audit trail, not
/// a UI affordance.
class AccountingApi {
  AccountingApi(this._dio);

  final Dio _dio;

  /// A delivery company's own cash routes, over the same connection.
  ///
  /// CARRIER only on the server, and a separate client so nothing about this class's BACKOFFICE
  /// routes can be reached through it by mistake. Offered here so the portal shell can hand a
  /// carrier page its client without growing its API bundle.
  CarrierCashApi get carrierCash => CarrierCashApi(_dio);

  /// Cash held by delivery companies, and by their riders for them. BACKOFFICE only.
  ///
  /// A company's [CarrierCashHolding.held] is what a payment is recorded against with [remit]; its
  /// riders' [CarrierCashHolding.withRiders] is owed to the company until it records a hand-over,
  /// and is shown beside the company's figure, never added to it.
  Future<List<CarrierCashHolding>> carriersFloat() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/accounting/float/carriers');
    final Map<String, dynamic> body = response.data as Map<String, dynamic>;
    return (body['carriers'] as List<dynamic>? ?? <dynamic>[])
        .map((dynamic c) => CarrierCashHolding.fromJson(c as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<ReconciliationSummary> summary() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/accounting/summary');
    return ReconciliationSummary.fromJson(response.data as Map<String, dynamic>);
  }

  /// Everything not in a terminal state — the work list.
  Future<List<AccountingTransaction>> unsettled({int limit = 100}) =>
      _list('/api/accounting/unsettled', <String, dynamic>{'limit': limit});

  Future<List<AccountingTransaction>> byStatus(SettlementStatus status, {int limit = 100}) =>
      _list('/api/accounting/transactions',
          <String, dynamic>{'status': status.wire, 'limit': limit});

  /// Every leg of one order's settlement — how a single dispute gets investigated.
  Future<List<AccountingTransaction>> forOrder(String orderId) =>
      _list('/api/accounting/orders/$orderId', null);

  /// What was sent to the bank and what came back. The end of the trail after "it says FAILED".
  /// Who is currently holding platform cash, largest first.
  ///
  /// The collection list. Every row is money taken from a customer that has not reached a bank
  /// account yet, and the age of the oldest entry is the part worth watching.
  Future<List<CashHolder>> cashFloat() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/accounting/float');
    return (response.data as List<dynamic>)
        .map((dynamic j) => CashHolder.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Records that a holder has banked everything they were carrying.
  ///
  /// Everything, not an amount: a partial hand-over would need a collection to be half-discharged,
  /// which the ledger cannot express yet. Returns what the remittance covered.
  ///
  /// [expected] is the figure the operator counted against. A delivery company's balance grows with
  /// every hand-over at its hub, so when it is given and the balance has moved, nothing is recorded
  /// and this throws [CashAmountChanged]. [requestKey] makes a double press answer with the first
  /// remittance. Called with neither, it banks everything exactly as it always did.
  Future<Remittance> remit(
    String holderRef, {
    Money? expected,
    CashMethod? method,
    String? requestKey,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      if (expected != null) 'expectedAmount': expected.amount,
      if (method != null) 'method': method.wire,
      if (requestKey != null) 'requestKey': requestKey,
    };
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        '/api/accounting/float/${Uri.encodeComponent(holderRef)}/remit',
        data: body.isEmpty ? null : body,
      );
      return Remittance.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw CarrierCashApi.amountChangedOr(e);
    }
  }

  Future<List<SyncLogEntry>> syncLog(String transactionId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/accounting/transactions/$transactionId/sync-log');
    return (response.data as List<dynamic>)
        .map((dynamic e) => SyncLogEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<AccountingTransaction>> _list(String path, Map<String, dynamic>? query) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>(path, queryParameters: query);
    return (response.data as List<dynamic>)
        .map((dynamic e) => AccountingTransaction.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
