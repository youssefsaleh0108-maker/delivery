import 'package:dio/dio.dart';

import '../models/accounting_models.dart';

/// Client for the reconciliation API — BACKOFFICE only (Phase 4).
///
/// Read-only, deliberately. There is no method to re-post or adjust a transaction because there is
/// no such endpoint: money moves as a consequence of an order, never because someone pressed a
/// button in a browser. Recovering a stuck settlement is an operator task with an audit trail, not
/// a UI affordance.
class AccountingApi {
  AccountingApi(this._dio);

  final Dio _dio;

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
  Future<Remittance> remit(String holderRef) async {
    final Response<dynamic> response =
        await _dio.post<dynamic>('/api/accounting/float/$holderRef/remit');
    return Remittance.fromJson(response.data as Map<String, dynamic>);
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
