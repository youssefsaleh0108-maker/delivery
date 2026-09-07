/// What is on the shelf — inventory-service (`/api/inventory`).
///
/// The catalogue says what a shop sells; this says how many are left. They are separate services
/// on purpose: a price change and a stock movement have nothing to do with each other, and a till
/// decrementing a count must not be able to write a price.
///
/// Two numbers are never computed here. `available` (on hand minus reserved) and a count line's
/// `variance` are SERVER-computed, because two clients doing the same subtraction at different
/// moments is how a shelf ends up with two truths.
library;

import 'catalog_models.dart';
import 'statement_models.dart';

/// The chip strip above the inventory list. Server-side filtering — stock questions need the
/// database, so changing a chip refetches rather than filtering the loaded page.
enum InventoryFilter {
  all('ALL', 'All'),
  lowStock('LOW', 'Low stock'),
  outOfStock('OUT', 'Out of stock'),
  active('ACTIVE', 'Active'),
  hidden('HIDDEN', 'Hidden');

  const InventoryFilter(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static InventoryFilter fromWire(String? value) {
    for (final InventoryFilter filter in InventoryFilter.values) {
      if (filter.wireValue == value) {
        return filter;
      }
    }
    return InventoryFilter.all;
  }
}

/// How bad the shelf is, decided by the server against the item's own threshold.
///
/// Client code must not re-derive this from `available` vs `lowStockThreshold`: the server also
/// weighs whether the item is tracked at all, and an untracked item is never an alert.
enum StockSeverity {
  ok('OK', 'In stock'),
  warning('WARNING', 'Low'),
  critical('CRITICAL', 'Critical'),
  out('OUT', 'Out of stock');

  const StockSeverity(this.wireValue, this.label);

  final String wireValue;
  final String label;

  /// Unknown severities read as [ok] — an unrecognised word must not paint a healthy shelf red.
  static StockSeverity fromWire(String? value) {
    for (final StockSeverity severity in StockSeverity.values) {
      if (severity.wireValue == value) {
        return severity;
      }
    }
    return StockSeverity.ok;
  }

  bool get isAlerting => this != StockSeverity.ok;
}

/// Why a level moved. The audit vocabulary — every row in the movement ledger has one.
enum MovementKind {
  receipt('RECEIPT', 'Received'),
  adjustment('ADJUSTMENT', 'Adjusted'),
  count('COUNT', 'Stock count'),
  sale('SALE', 'Sold'),
  returned('RETURN', 'Returned'),
  orderReserve('ORDER_RESERVE', 'Reserved for an order'),
  orderRelease('ORDER_RELEASE', 'Released'),
  orderFulfil('ORDER_FULFIL', 'Order fulfilled');

  const MovementKind(this.wireValue, this.label);

  final String wireValue;
  final String label;

  /// Unknown kinds read as [adjustment]: the neutral row, so a future movement type still renders
  /// its delta honestly rather than being dropped from the audit trail.
  static MovementKind fromWire(String? value) {
    for (final MovementKind kind in MovementKind.values) {
      if (kind.wireValue == value) {
        return kind;
      }
    }
    return MovementKind.adjustment;
  }
}

/// The six reasons the adjust sheet offers. Required on every manual adjustment — an unexplained
/// stock change is indistinguishable from theft.
enum AdjustmentReason {
  received('RECEIVED', 'Received'),
  damaged('DAMAGED', 'Damaged'),
  expired('EXPIRED', 'Expired'),
  theft('THEFT', 'Theft or loss'),
  correction('CORRECTION', 'Correction'),
  other('OTHER', 'Other');

  const AdjustmentReason(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static AdjustmentReason fromWire(String? value) {
    for (final AdjustmentReason reason in AdjustmentReason.values) {
      if (reason.wireValue == value) {
        return reason;
      }
    }
    return AdjustmentReason.other;
  }
}

enum StockCountStatus {
  open('OPEN', 'In progress'),
  submitted('SUBMITTED', 'Submitted'),
  cancelled('CANCELLED', 'Cancelled');

  const StockCountStatus(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static StockCountStatus fromWire(String? value) {
    for (final StockCountStatus status in StockCountStatus.values) {
      if (status.wireValue == value) {
        return status;
      }
    }
    return StockCountStatus.open;
  }

  bool get isOpen => this == StockCountStatus.open;
}

/// One product as the inventory list draws it: the catalogue facts it needs plus the shelf.
///
/// Money is [Money] — the same 2-decimal server string the rest of the platform uses. The legacy
/// `Product.price` double is not touched, and the two never meet in one formatter.
class InventoryItem {
  const InventoryItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.status,
    this.storeId,
    this.sku,
    this.barcode,
    this.categoryId,
    this.listImageUrl,
    this.tracked = false,
    this.onHand = 0,
    this.reserved = 0,
    this.available = 0,
    this.lowStockThreshold = 0,
    this.severity = StockSeverity.ok,
    this.updatedAt,
  });

  final String productId;
  final String name;
  final Money price;
  final ProductStatus status;
  final String? storeId;
  final String? sku;
  final String? barcode;
  final String? categoryId;
  final String? listImageUrl;

  /// Whether the merchant asked inventory to police this product. An untracked row shows a dash,
  /// not a zero — "we are not counting this" and "there are none" are different facts.
  final bool tracked;

  final int onHand;

  /// Held for accepted delivery orders that have not been handed over yet.
  final int reserved;

  /// SERVER-computed `onHand - reserved`. Never recomputed here.
  final int available;

  final int lowStockThreshold;
  final StockSeverity severity;
  final DateTime? updatedAt;

  /// Not on the storefront — draft or archived. Distinct from being out of stock.
  bool get hidden => status != ProductStatus.active;

  factory InventoryItem.fromJson(Map<String, dynamic> json) => InventoryItem(
        productId: (json['productId'] ?? json['id']) as String,
        name: json['name'] as String? ?? '',
        price: Money.parse(json['price']) ?? const Money('0.00'),
        status: ProductStatus.fromWire(json['status'] as String?),
        storeId: json['storeId'] as String?,
        sku: json['sku'] as String?,
        barcode: json['barcode'] as String?,
        categoryId: json['categoryId'] as String?,
        listImageUrl: json['listImageUrl'] as String?,
        tracked: json['tracked'] as bool? ?? false,
        onHand: (json['onHand'] as num?)?.toInt() ?? 0,
        reserved: (json['reserved'] as num?)?.toInt() ?? 0,
        available: (json['available'] as num?)?.toInt() ?? 0,
        lowStockThreshold: (json['lowStockThreshold'] as num?)?.toInt() ?? 0,
        severity: StockSeverity.fromWire(json['severity'] as String?),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      );
}

/// The spec's other name for the same row, so a screen written against either compiles.
typedef StockLevel = InventoryItem;

/// One line of the audit ledger: what moved, by how much, and who moved it.
class StockMovement {
  const StockMovement({
    required this.id,
    required this.kind,
    required this.delta,
    this.reason,
    this.reservedDelta = 0,
    this.onHandAfter = 0,
    this.note,
    this.actorRef,
    this.occurredAt,
    this.sourceKind,
    this.sourceId,
  });

  final String id;
  final MovementKind kind;

  /// Signed. Negative is stock leaving.
  final int delta;

  final AdjustmentReason? reason;
  final int reservedDelta;

  /// The level after this movement was applied — so the ledger reads as a running balance without
  /// the client adding anything up.
  final int onHandAfter;

  final String? note;
  final String? actorRef;
  final DateTime? occurredAt;

  /// What caused it: `MANUAL`, `COUNT`, `POS`, `ORDER`.
  final String? sourceKind;
  final String? sourceId;

  factory StockMovement.fromJson(Map<String, dynamic> json) => StockMovement(
        id: json['id'] as String,
        kind: MovementKind.fromWire(json['kind'] as String?),
        delta: (json['delta'] as num?)?.toInt() ?? 0,
        reason: json['reason'] == null
            ? null
            : AdjustmentReason.fromWire(json['reason'] as String?),
        reservedDelta: (json['reservedDelta'] as num?)?.toInt() ?? 0,
        onHandAfter: (json['onHandAfter'] as num?)?.toInt() ?? 0,
        note: json['note'] as String?,
        actorRef: json['actorRef'] as String?,
        occurredAt: DateTime.tryParse(json['occurredAt'] as String? ?? ''),
        sourceKind: json['sourceKind'] as String?,
        sourceId: json['sourceId'] as String?,
      );
}

/// What one adjustment did: the item as it now stands, and the ledger row that got it there.
///
/// Both halves in one response so the list can be updated without a second fetch, and so a replayed
/// idempotency key returns the ORIGINAL movement rather than inventing a second one.
class StockAdjustment {
  const StockAdjustment({required this.item, this.movement});

  final InventoryItem item;
  final StockMovement? movement;

  factory StockAdjustment.fromJson(Map<String, dynamic> json) => StockAdjustment(
        item: InventoryItem.fromJson(json['item'] as Map<String, dynamic>),
        movement: json['movement'] == null
            ? null
            : StockMovement.fromJson(json['movement'] as Map<String, dynamic>),
      );
}

/// A shelf that needs attention, with the derived numbers that say how urgently.
///
/// [velocityPerDay], [hoursOfCover] and [lastSoldAt] are null until there is a week of sales to
/// derive them from. Null renders as "—", never as zero: "we cannot tell yet" and "this never
/// sells" would otherwise look the same on the card.
class StockAlert {
  const StockAlert({
    required this.productId,
    required this.name,
    required this.severity,
    this.categoryName,
    this.listImageUrl,
    this.available = 0,
    this.lowStockThreshold = 0,
    this.velocityPerDay,
    this.hoursOfCover,
    this.lastSoldAt,
  });

  final String productId;
  final String name;
  final StockSeverity severity;
  final String? categoryName;
  final String? listImageUrl;
  final int available;
  final int lowStockThreshold;

  /// Units sold per day over the last 7 days.
  final double? velocityPerDay;

  /// How long the remaining stock lasts at that rate.
  final double? hoursOfCover;

  final DateTime? lastSoldAt;

  factory StockAlert.fromJson(Map<String, dynamic> json) => StockAlert(
        productId: (json['productId'] ?? json['id']) as String,
        name: json['name'] as String? ?? '',
        severity: StockSeverity.fromWire(json['severity'] as String?),
        categoryName: json['categoryName'] as String?,
        listImageUrl: json['listImageUrl'] as String?,
        available: (json['available'] as num?)?.toInt() ?? 0,
        lowStockThreshold: (json['lowStockThreshold'] as num?)?.toInt() ?? 0,
        velocityPerDay: (json['velocityPerDay'] as num?)?.toDouble(),
        hoursOfCover: (json['hoursOfCover'] as num?)?.toDouble(),
        lastSoldAt: DateTime.tryParse(json['lastSoldAt'] as String? ?? ''),
      );
}

/// The counts behind the alert badges.
class AlertSummary {
  const AlertSummary({this.total = 0, this.out = 0, this.critical = 0, this.warning = 0});

  final int total;
  final int out;
  final int critical;
  final int warning;

  static const AlertSummary zero = AlertSummary();

  bool get isEmpty => total == 0;

  factory AlertSummary.fromJson(Map<String, dynamic> json) => AlertSummary(
        total: (json['total'] as num?)?.toInt() ?? 0,
        out: (json['out'] as num?)?.toInt() ?? 0,
        critical: (json['critical'] as num?)?.toInt() ?? 0,
        warning: (json['warning'] as num?)?.toInt() ?? 0,
      );
}

/// The alerts screen in one response: the badge counts and the rows behind them.
class StockAlerts {
  const StockAlerts({this.summary = AlertSummary.zero, this.items = const <StockAlert>[]});

  final AlertSummary summary;
  final List<StockAlert> items;

  bool get isEmpty => items.isEmpty;

  factory StockAlerts.fromJson(Map<String, dynamic> json) => StockAlerts(
        summary: json['summary'] == null
            ? AlertSummary.zero
            : AlertSummary.fromJson(json['summary'] as Map<String, dynamic>),
        items: (json['items'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic i) => StockAlert.fromJson(i as Map<String, dynamic>))
            .toList(),
      );
}

/// The header numbers above the inventory list.
class ItemsSummary {
  const ItemsSummary({this.products = 0, this.categories = 0, this.alerts = 0});

  final int products;
  final int categories;
  final int alerts;

  static const ItemsSummary zero = ItemsSummary();

  factory ItemsSummary.fromJson(Map<String, dynamic> json) => ItemsSummary(
        products: (json['products'] as num?)?.toInt() ?? 0,
        categories: (json['categories'] as num?)?.toInt() ?? 0,
        alerts: (json['alerts'] as num?)?.toInt() ?? 0,
      );
}

/// One product inside a stock count.
///
/// [systemQty] is re-snapshotted by the server every time a line is recorded — the shelf may have
/// moved since the count opened, and the variance that matters is against what the system believed
/// at the moment of counting. [variance] is likewise the server's, not `counted - system`.
class StockCountLine {
  const StockCountLine({
    required this.productId,
    required this.name,
    this.sku,
    this.systemQty,
    this.countedQty,
    this.variance,
  });

  final String productId;
  final String name;
  final String? sku;
  final int? systemQty;

  /// Null means "not counted yet" — submitting SKIPS these rather than zeroing them, which is the
  /// difference between a partial count and destroying a shelf.
  final int? countedQty;

  final int? variance;

  bool get isCounted => countedQty != null;

  factory StockCountLine.fromJson(Map<String, dynamic> json) => StockCountLine(
        productId: json['productId'] as String,
        name: json['name'] as String? ?? '',
        sku: json['sku'] as String?,
        systemQty: (json['systemQty'] as num?)?.toInt(),
        countedQty: (json['countedQty'] as num?)?.toInt(),
        variance: (json['variance'] as num?)?.toInt(),
      );
}

/// A count without its lines — the list row.
class StockCountSummary {
  const StockCountSummary({
    required this.id,
    required this.name,
    required this.status,
    this.categoryId,
    this.startedAt,
    this.submittedAt,
    this.itemsTotal = 0,
    this.itemsCounted = 0,
  });

  final String id;
  final String name;
  final StockCountStatus status;
  final String? categoryId;
  final DateTime? startedAt;
  final DateTime? submittedAt;
  final int itemsTotal;
  final int itemsCounted;

  /// 0..1 for a progress bar. Zero-safe: an empty count is not complete, it is empty.
  double get progress => itemsTotal == 0 ? 0 : itemsCounted / itemsTotal;

  factory StockCountSummary.fromJson(Map<String, dynamic> json) => StockCountSummary(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        status: StockCountStatus.fromWire(json['status'] as String?),
        categoryId: json['categoryId'] as String?,
        startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
        submittedAt: DateTime.tryParse(json['submittedAt'] as String? ?? ''),
        itemsTotal: (json['itemsTotal'] as num?)?.toInt() ?? 0,
        itemsCounted: (json['itemsCounted'] as num?)?.toInt() ?? 0,
      );
}

/// A count with its lines — the audit session screen.
class StockCount {
  const StockCount({
    required this.id,
    required this.name,
    required this.status,
    this.categoryId,
    this.startedAt,
    this.submittedAt,
    this.itemsTotal = 0,
    this.itemsCounted = 0,
    this.lines = const <StockCountLine>[],
  });

  final String id;
  final String name;
  final StockCountStatus status;
  final String? categoryId;
  final DateTime? startedAt;
  final DateTime? submittedAt;
  final int itemsTotal;
  final int itemsCounted;
  final List<StockCountLine> lines;

  double get progress => itemsTotal == 0 ? 0 : itemsCounted / itemsTotal;

  bool get isOpen => status.isOpen;

  /// Lines the merchant has counted that disagree with the system — the review list before submit.
  List<StockCountLine> get discrepancies => lines
      .where((StockCountLine l) => l.isCounted && (l.variance ?? 0) != 0)
      .toList(growable: false);

  StockCountSummary get summary => StockCountSummary(
        id: id,
        name: name,
        status: status,
        categoryId: categoryId,
        startedAt: startedAt,
        submittedAt: submittedAt,
        itemsTotal: itemsTotal,
        itemsCounted: itemsCounted,
      );

  factory StockCount.fromJson(Map<String, dynamic> json) => StockCount(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        status: StockCountStatus.fromWire(json['status'] as String?),
        categoryId: json['categoryId'] as String?,
        startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
        submittedAt: DateTime.tryParse(json['submittedAt'] as String? ?? ''),
        itemsTotal: (json['itemsTotal'] as num?)?.toInt() ?? 0,
        itemsCounted: (json['itemsCounted'] as num?)?.toInt() ?? 0,
        lines: (json['lines'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic l) => StockCountLine.fromJson(l as Map<String, dynamic>))
            .toList(),
      );
}

/// Store-wide inventory preferences.
class InventorySettings {
  const InventorySettings({this.alertsEnabled = true, this.whatsappAlerts = false});

  final bool alertsEnabled;
  final bool whatsappAlerts;

  factory InventorySettings.fromJson(Map<String, dynamic> json) => InventorySettings(
        alertsEnabled: json['alertsEnabled'] as bool? ?? true,
        whatsappAlerts: json['whatsappAlerts'] as bool? ?? false,
      );
}
