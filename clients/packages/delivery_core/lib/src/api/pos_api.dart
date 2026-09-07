import 'package:dio/dio.dart';

import '../models/catalog_models.dart';
import '../models/pos_models.dart';
import '../models/statement_models.dart';

/// Typed client for pos-service (`/api/pos`) — the till.
///
/// Two rules shape the whole file:
///
/// 1. **Every mutating sale call returns the WHOLE [PosSale].** One shape, one `setState`, no
///    client-side merging of a basket. A till that reconstructs its own totals after adding a line
///    is a till that eventually disagrees with the receipt it prints.
/// 2. **The client never prices anything.** Quantities and identifiers go up; money comes down.
///    The single exception is [addOpenItem], which is why the server gates it on a permission.
///
/// **The service is not deployed yet** — screens must degrade to an error state rather than assume
/// a response.
class PosApi {
  PosApi(this._dio);

  final Dio _dio;

  // ---------------------------------------------------------------- settings and registers

  /// How this shop's till behaves: VAT, receipt prefix, the cashier's discount ceiling, and the
  /// LBP rate a new sale will lock in.
  Future<PosSettings> settings(String storeId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/pos/stores/$storeId/settings');
    return PosSettings.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PosSettings> updateSettings(
    String storeId, {
    int? vatRateBp,
    bool? pricesTaxInclusive,
    String? receiptPrefix,
    String? receiptFooter,
    Money? cashierDiscountMax,
  }) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/pos/stores/$storeId/settings',
      data: <String, dynamic>{
        if (vatRateBp != null) 'vatRateBp': vatRateBp,
        if (pricesTaxInclusive != null) 'pricesTaxInclusive': pricesTaxInclusive,
        if (receiptPrefix != null) 'receiptPrefix': receiptPrefix,
        if (receiptFooter != null) 'receiptFooter': receiptFooter,
        if (cashierDiscountMax != null) 'cashierDiscountMax': cashierDiscountMax.amount,
      },
    );
    return PosSettings.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<PosRegister>> registers(String storeId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/pos/stores/$storeId/registers');
    return (response.data as List<dynamic>)
        .map((dynamic r) => PosRegister.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<PosRegister> createRegister(String storeId, {required String name}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/pos/stores/$storeId/registers',
      data: <String, dynamic>{'name': name},
    );
    return PosRegister.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- shifts

  /// Opens a drawer. Both floats are what the cashier says is physically in it — the shift's
  /// variance at close is measured against these, so a wrong number here is a wrong number all
  /// day. 409 when the register already has somebody on it.
  Future<PosShift> openShift(
    String storeId,
    String registerId, {
    required Money openingFloat,
    int openingFloatLbp = 0,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/pos/stores/$storeId/registers/$registerId/shifts',
      data: <String, dynamic>{
        'openingFloat': openingFloat.amount,
        'openingFloatLbp': openingFloatLbp,
      },
    );
    return PosShift.fromJson(response.data as Map<String, dynamic>);
  }

  /// Closes the drawer against a physical count. Both currencies are counted separately and each
  /// gets its own variance; converting one into the other would invent a discrepancy.
  Future<PosShift> closeShift(
    String shiftId, {
    required Money counted,
    required int countedLbp,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/pos/shifts/$shiftId/close',
      data: <String, dynamic>{'counted': counted.amount, 'countedLbp': countedLbp},
    );
    return PosShift.fromJson(response.data as Map<String, dynamic>);
  }

  /// The shift this cashier is on, or null when they are not on one.
  ///
  /// 404 is the ordinary answer, not a failure — a merchant who has not opened a drawer yet is the
  /// normal morning state.
  Future<PosShift?> currentShift(String storeId) async {
    final Map<String, dynamic>? body =
        await _maybe('/api/pos/stores/$storeId/shifts/current');
    return body == null ? null : PosShift.fromJson(body);
  }

  Future<Paged<PosShift>> shifts(String storeId, {int page = 0, int size = 20}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/pos/stores/$storeId/shifts',
      queryParameters: <String, dynamic>{'page': page, 'size': size},
    );
    return Paged<PosShift>.fromJson(
        response.data as Map<String, dynamic>, PosShift.fromJson);
  }

  // ---------------------------------------------------------------- the basket

  /// Opens a sale, locking the LBP rate and the VAT rate for its whole life.
  ///
  /// Call this on the first Add, never in `initState`: a register that exists before a cashier
  /// touches it is an open sale nobody meant to start, and the shell builds tabs eagerly.
  Future<PosSale> openSale(
    String storeId, {
    String? registerId,
    String? shiftId,
    String? customerPhone,
    String? note,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/pos/stores/$storeId/sales',
      data: <String, dynamic>{
        if (registerId != null) 'registerId': registerId,
        if (shiftId != null) 'shiftId': shiftId,
        if (customerPhone != null && customerPhone.isNotEmpty) 'customerPhone': customerPhone,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
    return PosSale.fromJson(response.data as Map<String, dynamic>);
  }

  /// The cashier's own basket from before the app restarted, or null when there is none.
  ///
  /// An OPEN sale older than 24 hours is refused at checkout — its snapshotted rate is stale — so
  /// a resumed basket is not automatically a chargeable one.
  Future<PosSale?> resumeOpen(String storeId) async {
    final Map<String, dynamic>? body = await _maybe('/api/pos/stores/$storeId/sales/open');
    return body == null ? null : PosSale.fromJson(body);
  }

  /// Adds a catalogue line. Exactly one identifier — [productId] from a tap, [sku] or [barcode]
  /// from a scanner — refused synchronously otherwise.
  ///
  /// The server resolves and prices the product and snapshots its name, so a price edited later
  /// does not rewrite a sale that already happened.
  Future<PosSale> addLine(
    String saleId, {
    String? productId,
    String? sku,
    String? barcode,
    int qty = 1,
    List<String> optionIds = const <String>[],
  }) async {
    final int identifiers = <String?>[productId, sku, barcode]
        .where((String? value) => value != null)
        .length;
    if (identifiers != 1) {
      throw ArgumentError('Add a line by exactly one of productId, sku or barcode');
    }
    if (qty < 1) {
      throw ArgumentError('Quantity must be at least 1; use removeLine to take a line off');
    }
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/pos/sales/$saleId/lines',
      data: <String, dynamic>{
        if (productId != null) 'productId': productId,
        if (sku != null) 'sku': sku,
        if (barcode != null) 'barcode': barcode,
        'qty': qty,
        if (optionIds.isNotEmpty) 'optionIds': optionIds,
      },
    );
    return PosSale.fromJson(response.data as Map<String, dynamic>);
  }

  /// Rings up something not in the catalogue at a price typed on the spot.
  ///
  /// The ONE place a price comes from the client, which is why the server gates it on a permission
  /// the ordinary cashier does not hold.
  Future<PosSale> addOpenItem(
    String saleId, {
    required String name,
    required Money unitPrice,
    int qty = 1,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/pos/sales/$saleId/lines',
      data: <String, dynamic>{
        'qty': qty,
        'openItem': <String, dynamic>{'name': name, 'unitPrice': unitPrice.amount},
      },
    );
    return PosSale.fromJson(response.data as Map<String, dynamic>);
  }

  /// Sets a line's quantity. Zero removes it, which is what the stepper's last decrement means.
  Future<PosSale> setQty(String saleId, String lineId, int qty) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/pos/sales/$saleId/lines/$lineId',
      data: <String, dynamic>{'qty': qty},
    );
    return PosSale.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PosSale> removeLine(String saleId, String lineId) async {
    final Response<dynamic> response =
        await _dio.delete<dynamic>('/api/pos/sales/$saleId/lines/$lineId');
    return PosSale.fromJson(response.data as Map<String, dynamic>);
  }

  /// Takes money off the sale. Above the store's cashier ceiling this needs POS_REFUNDS_VOIDS —
  /// the same grant as un-selling, because a large discount is the same hole in the drawer.
  Future<PosSale> discount(String saleId, {required Money amount, String? note}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/pos/sales/$saleId/discount',
      data: <String, dynamic>{
        'amount': amount.amount,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
    return PosSale.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- settling

  /// Takes the money. Tenders are applied in order and must settle the total EXACTLY — anything
  /// left outstanding is a 422 and NOTHING is written.
  ///
  /// [idempotencyKey] is required and travels as a header. Generate it ONCE per checkout attempt
  /// and reuse it on every retry: replaying the same key returns the stored response instead of
  /// charging twice, and a fresh key on a retry is exactly how a customer pays twice for one
  /// basket. The same key with a *different* body is a 409.
  Future<PosSale> checkout(
    String saleId, {
    required List<PosTender> tenders,
    ReceiptChannel channel = ReceiptChannel.none,
    String? contact,
    required String idempotencyKey,
  }) async {
    if (tenders.isEmpty) {
      throw ArgumentError('Checkout needs at least one tender');
    }
    if (idempotencyKey.isEmpty) {
      throw ArgumentError('Checkout needs an idempotency key so a retry cannot charge twice');
    }
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/pos/sales/$saleId/checkout',
      data: <String, dynamic>{
        'tenders': tenders.map((PosTender t) => t.toJson()).toList(),
        'receipt': <String, dynamic>{
          'channel': channel.wireValue,
          if (contact != null && contact.isNotEmpty) 'contact': contact,
        },
      },
      options: Options(headers: <String, dynamic>{'Idempotency-Key': idempotencyKey}),
    );
    return PosSale.fromJson(response.data as Map<String, dynamic>);
  }

  /// Cancels a sale outright. An open one needs only POS_SALES; reversing a completed one needs
  /// POS_REFUNDS_VOIDS, and once its shift is closed the server refuses — a refund is the only
  /// honest way to move money out of a reconciled drawer.
  Future<PosSale> voidSale(String saleId, {required String reason}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/pos/sales/$saleId/void',
      data: <String, dynamic>{'reason': reason},
    );
    return PosSale.fromJson(response.data as Map<String, dynamic>);
  }

  /// Sends part of a sale back. The server computes the money: unit prices, the pro-rata share of
  /// any discount, and the pro-rata tax, in integer cents with the remainder pushed onto the last
  /// line so the parts sum to the whole.
  Future<PosRefund> refund(
    String saleId, {
    required List<PosRefundLine> lines,
    required PosTenderMethod method,
    bool restock = true,
    String? reason,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('A refund needs at least one line');
    }
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/pos/sales/$saleId/refunds',
      data: <String, dynamic>{
        'lines': lines.map((PosRefundLine l) => l.toJson()).toList(),
        'method': method.wireValue,
        'restock': restock,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
    return PosRefund.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- reading back

  Future<PosSale> read(String saleId) async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/pos/sales/$saleId');
    return PosSale.fromJson(response.data as Map<String, dynamic>);
  }

  /// The receipt as the server rendered it. Every figure on it is the server's — a reprint is a
  /// reproduction, not a recalculation.
  Future<PosReceipt> receipt(String saleId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/pos/sales/$saleId/receipt');
    return PosReceipt.fromJson(response.data as Map<String, dynamic>);
  }

  /// The printable thermal-width HTML for a receipt. A URL, not bytes: printing opens it.
  String receiptHtmlUrl(String saleId) => '/api/pos/sales/$saleId/receipt.html';

  /// The receipts archive. Server-side range limit is 92 days.
  Future<Paged<PosSaleSummary>> sales(
    String storeId, {
    DateTime? from,
    DateTime? to,
    PosSaleStatus? status,
    String? cashierRef,
    int page = 0,
    int size = 20,
  }) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/pos/stores/$storeId/sales',
      queryParameters: <String, dynamic>{
        if (from != null) 'from': _isoDate(from),
        if (to != null) 'to': _isoDate(to),
        if (status != null) 'status': status.wireValue,
        if (cashierRef != null) 'cashierRef': cashierRef,
        'page': page,
        'size': size,
      },
    );
    return Paged<PosSaleSummary>.fromJson(
        response.data as Map<String, dynamic>, PosSaleSummary.fromJson);
  }

  /// What the till took over a window — 1, 7 or 30 days.
  Future<PosSummary> summary(String storeId, {int days = 1}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/pos/stores/$storeId/summary',
      queryParameters: <String, dynamic>{'days': days},
    );
    return PosSummary.fromJson(response.data as Map<String, dynamic>);
  }

  /// A GET whose 404 is an answer rather than a failure. Everything else still throws — a 500
  /// silently read as "no shift" would hide an outage behind an empty screen.
  Future<Map<String, dynamic>?> _maybe(String path) async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(path);
      final Object? body = response.data;
      return body is Map<dynamic, dynamic> ? body.cast<String, dynamic>() : null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  /// `yyyy-MM-dd` from the date the merchant actually picked — deliberately not UTC, which would
  /// move a day's takings into the previous day for a reader east of Greenwich.
  static String _isoDate(DateTime value) => '${value.year.toString().padLeft(4, '0')}'
      '-${value.month.toString().padLeft(2, '0')}'
      '-${value.day.toString().padLeft(2, '0')}';
}
