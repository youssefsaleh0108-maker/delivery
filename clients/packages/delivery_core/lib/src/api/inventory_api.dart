import 'package:dio/dio.dart';

import '../models/catalog_models.dart';
import '../models/inventory_models.dart';

/// Typed client for inventory-service (`/api/inventory`).
///
/// Named `InventoryApi` rather than `StockApi` to match the path it talks to. Reads need any
/// membership; adjustments, receipts and counts need MODIFY_INVENTORY_PRICING, which the server
/// enforces — this client never decides.
///
/// **The service is not deployed yet.** Every call here will fail until it is, so screens must
/// render an error state rather than assuming a response; that is why nothing in this file throws
/// away a `DioException`.
class InventoryApi {
  InventoryApi(this._dio);

  final Dio _dio;

  // ---------------------------------------------------------------- items

  /// The inventory list. Filtering is SERVER-side — stock questions need the database, so a chip
  /// change refetches rather than filtering the page already loaded.
  Future<Paged<InventoryItem>> items({
    InventoryFilter filter = InventoryFilter.all,
    String? search,
    String? categoryId,
    String? storeId,
    int page = 0,
    int size = 20,
  }) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/inventory/items',
      queryParameters: <String, dynamic>{
        'filter': filter.wireValue,
        if (search != null && search.isNotEmpty) 'search': search,
        if (categoryId != null) 'categoryId': categoryId,
        if (storeId != null) 'storeId': storeId,
        'page': page,
        'size': size,
      },
    );
    return Paged<InventoryItem>.fromJson(
        response.data as Map<String, dynamic>, InventoryItem.fromJson);
  }

  /// The counts above the list.
  Future<ItemsSummary> summary({String? storeId}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/inventory/items/summary',
      queryParameters: <String, dynamic>{if (storeId != null) 'storeId': storeId},
    );
    return ItemsSummary.fromJson(response.data as Map<String, dynamic>);
  }

  Future<InventoryItem> item(String productId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/inventory/items/$productId');
    return InventoryItem.fromJson(response.data as Map<String, dynamic>);
  }

  /// The scanner path: find one item by the code on the packet.
  ///
  /// Exactly one of [sku]/[barcode], refused synchronously otherwise — a lookup with neither
  /// matches everything, and a lookup with both is two different questions.
  Future<InventoryItem> lookup({String? sku, String? barcode, String? storeId}) async {
    if ((sku == null) == (barcode == null)) {
      throw ArgumentError('Look up by exactly one of sku or barcode');
    }
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/inventory/items/lookup',
      queryParameters: <String, dynamic>{
        if (sku != null) 'sku': sku,
        if (barcode != null) 'barcode': barcode,
        if (storeId != null) 'storeId': storeId,
      },
    );
    return InventoryItem.fromJson(response.data as Map<String, dynamic>);
  }

  /// Turns tracking on or off for one product, and sets the level at which it starts shouting.
  ///
  /// Null means unchanged, so a screen can send one field without reading the other first.
  /// Enabling tracking on a product with no level row creates one at zero on hand — which reads as
  /// "out of stock" until somebody receives goods, and that is the honest state.
  Future<InventoryItem> updateItemSettings(
    String productId, {
    bool? tracked,
    int? lowStockThreshold,
  }) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/inventory/items/$productId/settings',
      data: <String, dynamic>{
        if (tracked != null) 'tracked': tracked,
        if (lowStockThreshold != null) 'lowStockThreshold': lowStockThreshold,
      },
    );
    return InventoryItem.fromJson(response.data as Map<String, dynamic>);
  }

  /// Moves a level: [delta] to add or subtract, [setTo] to state the shelf's true count.
  ///
  /// Exactly one of them, refused synchronously — sending both would be two conflicting statements
  /// about one shelf, and the server would have to guess which the merchant meant.
  ///
  /// [idempotencyKey] travels as a header and makes a retry safe: a replay returns the ORIGINAL
  /// movement rather than adjusting the shelf twice. Generate it once per user action, not per
  /// attempt, or the retry defeats itself.
  Future<StockAdjustment> adjust(
    String productId, {
    int? delta,
    int? setTo,
    required AdjustmentReason reason,
    String? note,
    String? idempotencyKey,
  }) async {
    if ((delta == null) == (setTo == null)) {
      throw ArgumentError('Adjust with exactly one of delta or setTo');
    }
    if (delta == 0) {
      throw ArgumentError('A delta of zero is not an adjustment');
    }
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/inventory/items/$productId/adjustments',
      data: <String, dynamic>{
        if (delta != null) 'delta': delta,
        if (setTo != null) 'setTo': setTo,
        'reason': reason.wireValue,
        if (note != null && note.isNotEmpty) 'note': note,
      },
      options: idempotencyKey == null
          ? null
          : Options(headers: <String, dynamic>{'Idempotency-Key': idempotencyKey}),
    );
    return StockAdjustment.fromJson(response.data as Map<String, dynamic>);
  }

  /// The audit trail for one product, newest first.
  Future<Paged<StockMovement>> movements(String productId,
      {int page = 0, int size = 20}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/inventory/items/$productId/movements',
      queryParameters: <String, dynamic>{'page': page, 'size': size},
    );
    return Paged<StockMovement>.fromJson(
        response.data as Map<String, dynamic>, StockMovement.fromJson);
  }

  // ---------------------------------------------------------------- alerts

  Future<StockAlerts> alerts({String? storeId}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/inventory/alerts',
      queryParameters: <String, dynamic>{if (storeId != null) 'storeId': storeId},
    );
    return StockAlerts.fromJson(response.data as Map<String, dynamic>);
  }

  /// Just the counts — for a nav badge, which should not fetch every low row to draw a number.
  Future<AlertSummary> alertSummary({String? storeId}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/inventory/alerts/summary',
      queryParameters: <String, dynamic>{if (storeId != null) 'storeId': storeId},
    );
    return AlertSummary.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- settings

  Future<InventorySettings> settings() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/inventory/settings');
    return InventorySettings.fromJson(response.data as Map<String, dynamic>);
  }

  Future<InventorySettings> updateSettings({bool? alertsEnabled, bool? whatsappAlerts}) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/inventory/settings',
      data: <String, dynamic>{
        if (alertsEnabled != null) 'alertsEnabled': alertsEnabled,
        if (whatsappAlerts != null) 'whatsappAlerts': whatsappAlerts,
      },
    );
    return InventorySettings.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- stock counts

  /// Opens a counting session. 409 when one is already open — two people counting the same shelf
  /// into two sessions is how a variance becomes fiction.
  Future<StockCount> startCount({
    required String name,
    String? categoryId,
    String? storeId,
    List<String> productIds = const <String>[],
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/inventory/counts',
      data: <String, dynamic>{
        'name': name,
        if (categoryId != null) 'categoryId': categoryId,
        if (storeId != null) 'storeId': storeId,
        if (productIds.isNotEmpty) 'productIds': productIds,
      },
    );
    return StockCount.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Paged<StockCountSummary>> counts({
    StockCountStatus? status,
    int page = 0,
    int size = 20,
  }) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/inventory/counts',
      queryParameters: <String, dynamic>{
        if (status != null) 'status': status.wireValue,
        'page': page,
        'size': size,
      },
    );
    return Paged<StockCountSummary>.fromJson(
        response.data as Map<String, dynamic>, StockCountSummary.fromJson);
  }

  Future<StockCount> count(String id) async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/inventory/counts/$id');
    return StockCount.fromJson(response.data as Map<String, dynamic>);
  }

  /// Records one line. Null [counted] clears it back to uncounted, which is not the same as zero:
  /// zero says the shelf is empty, null says nobody has looked.
  Future<StockCountLine> recordLine(String countId, String productId, int? counted) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/inventory/counts/$countId/lines/$productId',
      data: <String, dynamic>{'counted': counted},
    );
    return StockCountLine.fromJson(response.data as Map<String, dynamic>);
  }

  /// Records many lines at once — the scanner path.
  ///
  /// A run of forty items sent one at a time trips the shared gateway rate limit (average 20,
  /// burst 40) and the tail of the count is silently lost. Batch anything over a handful.
  Future<StockCount> recordLines(String countId, Map<String, int> counted) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/inventory/counts/$countId/lines',
      data: <String, dynamic>{
        'lines': counted.entries
            .map((MapEntry<String, int> e) =>
                <String, dynamic>{'productId': e.key, 'counted': e.value})
            .toList(),
      },
    );
    return StockCount.fromJson(response.data as Map<String, dynamic>);
  }

  /// Applies the count: one movement per counted line whose variance is not zero. Lines nobody
  /// counted are SKIPPED, never zeroed.
  Future<StockCount> submitCount(String id) async {
    final Response<dynamic> response =
        await _dio.post<dynamic>('/api/inventory/counts/$id/submit');
    return StockCount.fromJson(response.data as Map<String, dynamic>);
  }

  Future<StockCount> cancelCount(String id) async {
    final Response<dynamic> response =
        await _dio.post<dynamic>('/api/inventory/counts/$id/cancel');
    return StockCount.fromJson(response.data as Map<String, dynamic>);
  }

  /// Pulls the caller's catalogue into inventory-service and returns how many rows it took.
  ///
  /// The repair path for a shop whose products predate the service. An inventory tab that is empty
  /// while the catalogue is not looks broken; call this once, then reload.
  Future<int> sync() async {
    final Response<dynamic> response = await _dio.post<dynamic>('/api/inventory/sync');
    final Map<String, dynamic> body =
        (response.data as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{}).cast<String, dynamic>();
    return (body['imported'] as num?)?.toInt() ?? 0;
  }
}
