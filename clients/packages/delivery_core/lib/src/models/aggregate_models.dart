/// The tier-split daily trade series mirroring the Order Manager `/daily` endpoints.
///
/// Like [MerchantSummary]'s counters, nothing here is recomputed in the app — the app holds one
/// page of orders, so anything it added up would be a total of the twenty most recent. What IS
/// client arithmetic, by design, is any day-on-day or week-on-week comparison: the server sends the
/// series and no precomputed percentages.
library;

/// One tier's slice of one day.
class TierTrade {
  const TierTrade({
    required this.orders,
    required this.delivered,
    required this.gross,
  });

  /// Orders placed that day, regardless of how they ended up.
  final int orders;

  /// Of everything that day, the orders that reached a door.
  final int delivered;

  /// The sum of `totalAmount` over DELIVERED orders. Zero when nothing was delivered.
  final double gross;

  factory TierTrade.fromJson(Map<String, dynamic> json) => TierTrade(
        orders: (json['orders'] as num?)?.toInt() ?? 0,
        delivered: (json['delivered'] as num?)?.toInt() ?? 0,
        gross: (json['gross'] as num?)?.toDouble() ?? 0,
      );

  static const TierTrade zero = TierTrade(orders: 0, delivered: 0, gross: 0);
}

/// One day, split by delivery tier.
///
/// The server zero-fills: both tiers are always present, even on a day when nothing happened, so
/// no reader ever checks for a missing key. The tolerant fallbacks below are for a malformed body,
/// not an expected shape.
class TierTradeDay {
  const TierTradeDay({
    required this.day,
    required this.standard,
    required this.express,
  });

  /// A plain date the server already resolved in the business's zone — kept as the label it chose
  /// rather than shifted by the viewer's offset.
  final DateTime day;

  final TierTrade standard;
  final TierTrade express;

  /// The day regardless of tier, for a chart that does not split.
  int get orders => standard.orders + express.orders;
  int get delivered => standard.delivered + express.delivered;
  double get gross => standard.gross + express.gross;

  factory TierTradeDay.fromJson(Map<String, dynamic> json) => TierTradeDay(
        day: DateTime.parse(json['day'] as String),
        standard: json['standard'] is Map<String, dynamic>
            ? TierTrade.fromJson(json['standard'] as Map<String, dynamic>)
            : TierTrade.zero,
        express: json['express'] is Map<String, dynamic>
            ? TierTrade.fromJson(json['express'] as Map<String, dynamic>)
            : TierTrade.zero,
      );
}

/// The whole window, mirroring the `/daily` `Series` response.
///
/// [days] is complete: exactly [windowDays] entries, ascending, zero-filled — a chart draws every
/// bar straight from it without inventing gaps or padding its own zeros.
class TierTradeSeries {
  const TierTradeSeries({
    required this.windowDays,
    required this.days,
  });

  final int windowDays;
  final List<TierTradeDay> days;

  factory TierTradeSeries.fromJson(Map<String, dynamic> json) => TierTradeSeries(
        windowDays: (json['windowDays'] as num?)?.toInt() ?? 14,
        days: (json['days'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic d) => TierTradeDay.fromJson(d as Map<String, dynamic>))
            .toList(),
      );
}
