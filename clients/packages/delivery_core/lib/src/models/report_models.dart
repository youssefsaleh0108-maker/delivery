/// What the shop actually sold — reporting-service (`/api/reports`).
///
/// One read model over both channels: a walk-in sale and a delivered YouDrop order are the same
/// event to a merchant counting a day's takings, and the split between them is a dimension
/// ([SaleSource]) rather than two screens.
///
/// Deltas ("+18%") are the one number computed on the client, by [ReportTotals.deltaPercent], and
/// it returns **null** rather than a figure whenever the comparison is meaningless. The screen
/// renders "—" for null; it never invents a percentage.
library;

import 'statement_models.dart';

/// Which channel a sale came through.
enum SaleSource {
  delivery('DELIVERY', 'YouDrop'),
  pos('POS', 'Walk-in');

  const SaleSource(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static SaleSource fromWire(String? value) {
    for (final SaleSource source in SaleSource.values) {
      if (source.wireValue == value) {
        return source;
      }
    }
    return SaleSource.delivery;
  }
}

/// A sale's standing in the ledger, after any money went back.
enum SaleFactStatus {
  completed('COMPLETED', 'Completed'),
  partiallyRefunded('PARTIALLY_REFUNDED', 'Partly refunded'),
  refunded('REFUNDED', 'Refunded'),
  voided('VOIDED', 'Voided');

  const SaleFactStatus(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static SaleFactStatus fromWire(String? value) {
    for (final SaleFactStatus status in SaleFactStatus.values) {
      if (status.wireValue == value) {
        return status;
      }
    }
    return SaleFactStatus.completed;
  }
}

/// Which way a metric moved against the comparison period.
enum MetricDirection {
  up('UP'),
  down('DOWN'),
  flat('FLAT');

  const MetricDirection(this.wireValue);

  final String wireValue;
}

/// The four figures every report block is built from.
///
/// [netRevenue] is what the shop kept: gross less refunds. [goodsRevenue] excludes delivery fees,
/// which are the platform's, not the merchant's — showing them as shop income is the single most
/// common way a merchant report lies.
class ReportTotals {
  const ReportTotals({
    this.goodsRevenue = const Money('0.00'),
    this.grossValue = const Money('0.00'),
    this.refunded = const Money('0.00'),
    this.netRevenue = const Money('0.00'),
    this.averageOrderValue = const Money('0.00'),
    this.orders = 0,
    this.itemsSold = 0,
  });

  final Money goodsRevenue;
  final Money grossValue;
  final Money refunded;
  final Money netRevenue;
  final Money averageOrderValue;
  final int orders;
  final int itemsSold;

  static const ReportTotals zero = ReportTotals();

  bool get isEmpty => orders == 0 && itemsSold == 0;

  /// The percentage change of one figure against the same figure last period, or null when there
  /// is nothing to compare with.
  ///
  /// Null in three cases, all of which must render as "—": no previous period, a previous value
  /// the client could not read, and a previous value of zero — "up from nothing" is not a
  /// percentage, and dividing by it invents infinity.
  static double? deltaPercent(Money? now, Money? before) {
    final int? current = now?.minorUnits;
    final int? previous = before?.minorUnits;
    if (current == null || previous == null || previous == 0) {
      return null;
    }
    return (current - previous) / previous * 100;
  }

  /// The same for a plain count.
  static double? deltaPercentOf(int? now, int? before) {
    if (now == null || before == null || before == 0) {
      return null;
    }
    return (now - before) / before * 100;
  }

  static MetricDirection directionOf(double? delta) {
    if (delta == null || delta == 0) {
      return MetricDirection.flat;
    }
    return delta > 0 ? MetricDirection.up : MetricDirection.down;
  }

  factory ReportTotals.fromJson(Map<String, dynamic> json) => ReportTotals(
        goodsRevenue: Money.parse(json['goodsRevenue']) ?? const Money('0.00'),
        grossValue: Money.parse(json['grossValue']) ?? const Money('0.00'),
        refunded: Money.parse(json['refunded']) ?? const Money('0.00'),
        netRevenue: Money.parse(json['netRevenue']) ?? const Money('0.00'),
        averageOrderValue: Money.parse(json['averageOrderValue']) ?? const Money('0.00'),
        orders: (json['orders'] as num?)?.toInt() ?? 0,
        itemsSold: (json['itemsSold'] as num?)?.toInt() ?? 0,
      );
}

/// One bar on the daily-revenue chart. The server zero-fills, so a quiet Tuesday is a zero bar and
/// not a gap.
class SalesByDay {
  const SalesByDay({
    required this.day,
    this.netRevenue = const Money('0.00'),
    this.orders = 0,
    this.itemsSold = 0,
  });

  /// Parsed with `DateTime.parse` and NOT converted to local time: this is the server's own label
  /// for a calendar day, and shifting it by a timezone moves takings into the previous day.
  final DateTime day;

  final Money netRevenue;
  final int orders;
  final int itemsSold;

  factory SalesByDay.fromJson(Map<String, dynamic> json) => SalesByDay(
        day: DateTime.parse(json['day'] as String),
        netRevenue: Money.parse(json['netRevenue']) ?? const Money('0.00'),
        orders: (json['orders'] as num?)?.toInt() ?? 0,
        itemsSold: (json['itemsSold'] as num?)?.toInt() ?? 0,
      );
}

/// The spec's name for the same point.
typedef ReportDayPoint = SalesByDay;

/// One wedge of the Sales by Category donut.
class SalesByCategory {
  const SalesByCategory({
    this.categoryId,
    this.categoryName,
    this.netRevenue = const Money('0.00'),
    this.itemsSold = 0,
    this.orders = 0,
    this.share = 0,
  });

  final String? categoryId;

  /// Null for products in no category. Render `t.repUncategorised`, never an empty label.
  final String? categoryName;

  final Money netRevenue;
  final int itemsSold;
  final int orders;

  /// 0..1 of the period's net revenue, computed by the server so the wedges always sum to one.
  final double share;

  factory SalesByCategory.fromJson(Map<String, dynamic> json) => SalesByCategory(
        categoryId: json['categoryId'] as String?,
        categoryName: json['categoryName'] as String?,
        netRevenue: Money.parse(json['netRevenue']) ?? const Money('0.00'),
        itemsSold: (json['itemsSold'] as num?)?.toInt() ?? 0,
        orders: (json['orders'] as num?)?.toInt() ?? 0,
        share: (json['share'] as num?)?.toDouble() ?? 0,
      );
}

/// The spec's name for the same wedge.
typedef CategorySlice = SalesByCategory;

/// A row of Top Performing Products.
class ReportProductRow {
  const ReportProductRow({
    required this.productName,
    this.productId,
    this.categoryId,
    this.categoryName,
    this.qty = 0,
    this.netRevenue = const Money('0.00'),
    this.trend = const <int>[],
  });

  final String? productId;
  final String productName;
  final String? categoryId;
  final String? categoryName;
  final int qty;
  final Money netRevenue;

  /// Seven daily quantities, oldest first, zero-filled — the sparkline. Counts, not money.
  final List<int> trend;

  factory ReportProductRow.fromJson(Map<String, dynamic> json) => ReportProductRow(
        productId: json['productId'] as String?,
        productName: json['productName'] as String? ?? '',
        categoryId: json['categoryId'] as String?,
        categoryName: json['categoryName'] as String?,
        qty: (json['qty'] as num?)?.toInt() ?? 0,
        netRevenue: Money.parse(json['netRevenue']) ?? const Money('0.00'),
        trend: (json['trend'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic v) => (v as num?)?.toInt() ?? 0)
            .toList(),
      );
}

/// Walk-in against YouDrop.
class SourceSlice {
  const SourceSlice({
    required this.source,
    this.netRevenue = const Money('0.00'),
    this.orders = 0,
    this.share = 0,
  });

  final SaleSource source;
  final Money netRevenue;
  final int orders;
  final double share;

  factory SourceSlice.fromJson(Map<String, dynamic> json) => SourceSlice(
        source: SaleSource.fromWire(json['source'] as String?),
        netRevenue: Money.parse(json['netRevenue']) ?? const Money('0.00'),
        orders: (json['orders'] as num?)?.toInt() ?? 0,
        share: (json['share'] as num?)?.toDouble() ?? 0,
      );
}

/// Cash against card against wallet.
///
/// [method] is the raw wire word rather than an enum: it spans two services' vocabularies (the
/// till's tenders and a delivery order's payment methods), and a report that dropped an unknown one
/// would quietly under-report the day's takings.
class MethodSlice {
  const MethodSlice({
    required this.method,
    this.netRevenue = const Money('0.00'),
    this.orders = 0,
    this.share = 0,
  });

  final String method;
  final Money netRevenue;
  final int orders;
  final double share;

  factory MethodSlice.fromJson(Map<String, dynamic> json) => MethodSlice(
        method: json['method'] as String? ?? '',
        netRevenue: Money.parse(json['netRevenue']) ?? const Money('0.00'),
        orders: (json['orders'] as num?)?.toInt() ?? 0,
        share: (json['share'] as num?)?.toDouble() ?? 0,
      );
}

/// A period's trading, whole — everything the reports screen draws in one response.
class SalesReport {
  const SalesReport({
    required this.storeId,
    required this.from,
    required this.to,
    this.totals = ReportTotals.zero,
    this.previous,
    this.byDay = const <SalesByDay>[],
    this.byCategory = const <SalesByCategory>[],
    this.topProducts = const <ReportProductRow>[],
    this.bySource = const <SourceSlice>[],
    this.byPaymentMethod = const <MethodSlice>[],
    this.generatedAt,
  });

  final String storeId;
  final DateTime from;
  final DateTime to;
  final ReportTotals totals;

  /// The same window immediately before this one, when `compare` was asked for. Null otherwise,
  /// and every delta is then "—".
  final ReportTotals? previous;

  final List<SalesByDay> byDay;
  final List<SalesByCategory> byCategory;
  final List<ReportProductRow> topProducts;
  final List<SourceSlice> bySource;
  final List<MethodSlice> byPaymentMethod;
  final DateTime? generatedAt;

  /// Nothing traded in this window — the empty state, and the offer to backfill history.
  bool get isEmpty => totals.orders == 0;

  /// The delta for one of the four headline metrics, or null when it cannot be stated.
  double? deltaOf(Money Function(ReportTotals) pick) =>
      ReportTotals.deltaPercent(pick(totals), previous == null ? null : pick(previous!));

  factory SalesReport.fromJson(Map<String, dynamic> json) => SalesReport(
        storeId: json['storeId'] as String? ?? '',
        from: DateTime.parse(json['from'] as String),
        to: DateTime.parse(json['to'] as String),
        totals: json['totals'] == null
            ? ReportTotals.zero
            : ReportTotals.fromJson(json['totals'] as Map<String, dynamic>),
        previous: json['previous'] == null
            ? null
            : ReportTotals.fromJson(json['previous'] as Map<String, dynamic>),
        byDay: (json['byDay'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic d) => SalesByDay.fromJson(d as Map<String, dynamic>))
            .toList(),
        byCategory: (json['byCategory'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic c) => SalesByCategory.fromJson(c as Map<String, dynamic>))
            .toList(),
        topProducts: (json['topProducts'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic p) => ReportProductRow.fromJson(p as Map<String, dynamic>))
            .toList(),
        bySource: (json['bySource'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic s) => SourceSlice.fromJson(s as Map<String, dynamic>))
            .toList(),
        byPaymentMethod: (json['byPaymentMethod'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic m) => MethodSlice.fromJson(m as Map<String, dynamic>))
            .toList(),
        generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? ''),
      );
}

/// Today at a glance, with yesterday beside it for the delta chips.
class DashboardStats {
  const DashboardStats({
    this.today = ReportTotals.zero,
    this.yesterday,
    this.walkInTransactions = 0,
    this.walkInCash = const Money('0.00'),
    this.walkInCard = const Money('0.00'),
    this.deliveryOrders = 0,
    this.deliveryRevenue = const Money('0.00'),
    this.lowStockCount = 0,
  });

  final ReportTotals today;

  /// Null when the shop did not trade yesterday or the service cannot say — every delta is "—".
  final ReportTotals? yesterday;

  final int walkInTransactions;
  final Money walkInCash;
  final Money walkInCard;
  final int deliveryOrders;
  final Money deliveryRevenue;

  /// Mirrored here so the dashboard's four cards come from one call. Zero when inventory-service
  /// has nothing to say — which is indistinguishable from a healthy shelf, and deliberately so:
  /// the alerts screen is the authority.
  final int lowStockCount;

  static const DashboardStats empty = DashboardStats();

  Money get revenue => today.netRevenue;

  int get orders => today.orders;

  int get itemsSold => today.itemsSold;

  /// True when the shop has rung up nothing at the till — the walk-in card hides rather than
  /// showing a row of zeroes.
  bool get hasWalkIns => walkInTransactions > 0;

  double? get revenueDelta =>
      ReportTotals.deltaPercent(today.netRevenue, yesterday?.netRevenue);

  double? get ordersDelta => ReportTotals.deltaPercentOf(today.orders, yesterday?.orders);

  factory DashboardStats.fromJson(Map<String, dynamic> json) => DashboardStats(
        today: json['today'] == null
            ? ReportTotals.zero
            : ReportTotals.fromJson(json['today'] as Map<String, dynamic>),
        yesterday: json['yesterday'] == null
            ? null
            : ReportTotals.fromJson(json['yesterday'] as Map<String, dynamic>),
        walkInTransactions: (json['walkInTransactions'] as num?)?.toInt() ?? 0,
        walkInCash: Money.parse(json['walkInCash']) ?? const Money('0.00'),
        walkInCard: Money.parse(json['walkInCard']) ?? const Money('0.00'),
        deliveryOrders: (json['deliveryOrders'] as num?)?.toInt() ?? 0,
        deliveryRevenue: Money.parse(json['deliveryRevenue']) ?? const Money('0.00'),
        lowStockCount: (json['lowStockCount'] as num?)?.toInt() ?? 0,
      );
}

/// One item inside a ledger entry.
class LedgerItem {
  const LedgerItem({
    required this.name,
    this.productId,
    this.qty = 0,
    this.lineTotal = const Money('0.00'),
  });

  final String? productId;
  final String name;
  final int qty;
  final Money lineTotal;

  factory LedgerItem.fromJson(Map<String, dynamic> json) => LedgerItem(
        productId: json['productId'] as String?,
        name: json['name'] as String? ?? '',
        qty: (json['qty'] as num?)?.toInt() ?? 0,
        lineTotal: Money.parse(json['lineTotal']) ?? const Money('0.00'),
      );
}

/// One sale in the receipts archive, whichever channel it came through.
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.source,
    required this.reference,
    required this.status,
    this.grossValue = const Money('0.00'),
    this.netRevenue = const Money('0.00'),
    this.itemsCount = 0,
    this.paymentMethod,
    this.occurredAt,
    this.cashierRef,
    this.customerName,
    this.items = const <LedgerItem>[],
  });

  final String id;
  final SaleSource source;

  /// What the merchant would search for: a receipt label or an order code.
  final String reference;

  final SaleFactStatus status;
  final Money grossValue;
  final Money netRevenue;
  final int itemsCount;
  final String? paymentMethod;
  final DateTime? occurredAt;
  final String? cashierRef;
  final String? customerName;
  final List<LedgerItem> items;

  bool get isRefunded =>
      status == SaleFactStatus.refunded || status == SaleFactStatus.partiallyRefunded;

  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
        id: json['id'] as String,
        source: SaleSource.fromWire(json['source'] as String?),
        reference: json['reference'] as String? ?? '',
        status: SaleFactStatus.fromWire(json['status'] as String?),
        grossValue: Money.parse(json['grossValue']) ?? const Money('0.00'),
        netRevenue: Money.parse(json['netRevenue']) ?? const Money('0.00'),
        itemsCount: (json['itemsCount'] as num?)?.toInt() ?? 0,
        paymentMethod: json['paymentMethod'] as String?,
        occurredAt: DateTime.tryParse(json['occurredAt'] as String? ?? ''),
        cashierRef: json['cashierRef'] as String?,
        customerName: json['customerName'] as String?,
        items: (json['items'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic i) => LedgerItem.fromJson(i as Map<String, dynamic>))
            .toList(),
      );
}

/// A replay of history into the reporting store, for a shop that traded before the service existed.
class BackfillRun {
  const BackfillRun({
    required this.id,
    this.ordersIngested = 0,
    this.productsIngested = 0,
    this.startedAt,
  });

  final String id;
  final int ordersIngested;
  final int productsIngested;
  final DateTime? startedAt;

  factory BackfillRun.fromJson(Map<String, dynamic> json) => BackfillRun(
        id: json['id'] as String? ?? '',
        ordersIngested: (json['ordersIngested'] as num?)?.toInt() ?? 0,
        productsIngested: (json['productsIngested'] as num?)?.toInt() ?? 0,
        startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
      );
}
