import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/catalog_models.dart';
import '../models/report_models.dart';

/// Typed client for reporting-service (`/api/reports`) — what the shop sold, across both channels.
///
/// Named `ReportsApi` to match the path. Reads require VIEW_REPORTS; [backfill] is owner-only in
/// this phase, because it replays order-manager's merchant endpoint with the caller's own bearer
/// and that endpoint refuses a staff token.
///
/// **The service is not deployed yet** — screens must render an error or empty state rather than
/// assuming a response.
class ReportsApi {
  ReportsApi(this._dio);

  final Dio _dio;

  /// The server's own ceiling, mirrored here so an impossible range fails where it was written
  /// rather than arriving later as a network error the screen draws beside genuine ones.
  static const int maxRangeDays = 92;

  /// Today at a glance, with yesterday beside it for the delta chips.
  Future<DashboardStats> dashboard(String storeId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/reports/stores/$storeId/dashboard');
    return DashboardStats.fromJson(response.data as Map<String, dynamic>);
  }

  /// A period's trading, whole.
  ///
  /// [compare] asks for the immediately preceding window as `previous`, which is what every delta
  /// chip is computed from; without it they all render "—". [top] is clamped 1..20 by the server.
  Future<SalesReport> sales(
    String storeId, {
    required DateTime from,
    required DateTime to,
    bool compare = true,
    SaleSource? source,
    int top = 5,
  }) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/reports/stores/$storeId/sales',
      queryParameters: <String, dynamic>{
        ..._range(from, to),
        'compare': compare,
        if (source != null) 'source': source.wireValue,
        'top': top,
      },
    );
    return SalesReport.fromJson(response.data as Map<String, dynamic>);
  }

  /// The receipts archive: every sale, either channel, newest first.
  ///
  /// [search] matches a reference prefix or an item name, which is how a merchant finds "the order
  /// with the birthday cake" without knowing its number.
  Future<Paged<LedgerEntry>> ledger(
    String storeId, {
    DateTime? from,
    DateTime? to,
    String? search,
    SaleSource? source,
    SaleFactStatus? status,
    int page = 0,
    int size = 20,
  }) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/reports/stores/$storeId/ledger',
      queryParameters: <String, dynamic>{
        if (from != null && to != null) ..._range(from, to),
        if (search != null && search.isNotEmpty) 'search': search,
        if (source != null) 'source': source.wireValue,
        if (status != null) 'status': status.wireValue,
        'page': page,
        'size': size,
      },
    );
    return Paged<LedgerEntry>.fromJson(
        response.data as Map<String, dynamic>, LedgerEntry.fromJson);
  }

  /// One archived sale with its items.
  Future<LedgerEntry> ledgerEntry(String storeId, String id) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/reports/stores/$storeId/ledger/$id');
    return LedgerEntry.fromJson(response.data as Map<String, dynamic>);
  }

  /// The period as a sectioned CSV, UTF-8 with a BOM so a Lebanese merchant's Excel opens the
  /// Arabic product names as Arabic rather than mojibake.
  ///
  /// Bytes rather than a URL because the response needs the caller's bearer, and a link the browser
  /// follows on its own carries no Authorization header.
  Future<Uint8List> exportCsv(
    String storeId, {
    required DateTime from,
    required DateTime to,
    SaleSource? source,
  }) async {
    final Response<List<int>> response = await _dio.get<List<int>>(
      '/api/reports/stores/$storeId/sales/export',
      queryParameters: <String, dynamic>{
        ..._range(from, to),
        if (source != null) 'source': source.wireValue,
      },
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
  }

  /// Replays this shop's delivered orders and catalogue into the reporting store.
  ///
  /// The recovery path for a merchant who traded before the service existed: the outbox is not
  /// replayable, so without this their history simply is not there. Idempotent, and limited to one
  /// run per store per ten minutes (409 otherwise).
  Future<BackfillRun> backfill(String storeId) async {
    final Response<dynamic> response =
        await _dio.post<dynamic>('/api/reports/stores/$storeId/backfill');
    return BackfillRun.fromJson(response.data as Map<String, dynamic>);
  }

  /// The inclusive range as two query parameters, refusing what the server would refuse.
  ///
  /// Raised synchronously, before the async gap: an inverted range is two date pickers wired the
  /// wrong way round, and that should throw where it was written rather than arriving later as a
  /// failed future the screen renders next to real network errors.
  static Map<String, dynamic> _range(DateTime from, DateTime to) {
    final DateTime start = _dayOf(from);
    final DateTime end = _dayOf(to);
    if (end.isBefore(start)) {
      throw ArgumentError('Report range is inverted: $from is after $to');
    }
    // Inclusive, so a single day spans zero days of difference.
    final int days = end.difference(start).inDays + 1;
    if (days > maxRangeDays) {
      throw ArgumentError('Report range is $days days; the server allows $maxRangeDays');
    }
    return <String, dynamic>{'from': _isoDate(from), 'to': _isoDate(to)};
  }

  /// Midnight UTC of the same calendar day, used only for counting days. UTC so a range crossing a
  /// daylight-saving change is not 93 days and one hour.
  static DateTime _dayOf(DateTime value) => DateTime.utc(value.year, value.month, value.day);

  /// `yyyy-MM-dd` from the date the merchant actually picked.
  static String _isoDate(DateTime value) => '${value.year.toString().padLeft(4, '0')}'
      '-${value.month.toString().padLeft(2, '0')}'
      '-${value.day.toString().padLeft(2, '0')}';
}
