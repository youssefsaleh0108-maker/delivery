/// How trade is going, for whoever is asking.
///
/// The counters here are computed on the server and not recomputed in the app. That is not laziness
/// about arithmetic: the app holds one page of orders, so anything it added up would be a total of
/// the twenty most recent, which looks exactly like a real total and changes when you page.
library;

/// One day.
///
/// [money] is the goods for a shop and the delivery fee for a carrier, on delivered orders only.
class TradingDay {
  const TradingDay({
    required this.day,
    required this.orders,
    required this.delivered,
    required this.money,
    required this.waived,
  });

  final DateTime day;
  final int orders;
  final int delivered;
  final double money;

  /// The part of [money] the platform waived its cut on.
  final double waived;

  factory TradingDay.fromJson(Map<String, dynamic> json) => TradingDay(
        // A plain date, with no time and no zone: the server has already decided which day each
        // order belongs to, in the zone the business trades in. Parsing it as a local DateTime
        // keeps the label the server chose instead of shifting it by the viewer's offset.
        day: DateTime.parse(json['day'] as String),
        orders: (json['orders'] as num?)?.toInt() ?? 0,
        delivered: (json['delivered'] as num?)?.toInt() ?? 0,
        money: (json['money'] as num?)?.toDouble() ?? 0,
        waived: (json['waived'] as num?)?.toDouble() ?? 0,
      );
}

/// The window added up.
class TradingTotals {
  const TradingTotals({
    required this.orders,
    required this.delivered,
    required this.money,
    required this.waived,
  });

  final int orders;
  final int delivered;
  final double money;
  final double waived;

  factory TradingTotals.fromJson(Map<String, dynamic> json) => TradingTotals(
        orders: (json['orders'] as num?)?.toInt() ?? 0,
        delivered: (json['delivered'] as num?)?.toInt() ?? 0,
        money: (json['money'] as num?)?.toDouble() ?? 0,
        waived: (json['waived'] as num?)?.toDouble() ?? 0,
      );
}

/// A shop's best seller.
class TopProduct {
  const TopProduct({required this.name, required this.qty, required this.revenue});

  final String name;
  final int qty;
  final double revenue;

  factory TopProduct.fromJson(Map<String, dynamic> json) => TopProduct(
        name: json['name'] as String? ?? '',
        qty: (json['qty'] as num?)?.toInt() ?? 0,
        revenue: (json['revenue'] as num?)?.toDouble() ?? 0,
      );
}

/// How the shop is trading, and what is waiting for them right now.
class MerchantSummary {
  const MerchantSummary({
    required this.windowDays,
    required this.days,
    required this.today,
    required this.yesterday,
    required this.window,
    required this.platformFees,
    required this.savedByOffers,
    required this.commissionPercentage,
    required this.awaitingYou,
    required this.preparing,
    required this.readyForPickup,
    required this.onTheWay,
    required this.topProducts,
  });

  final int windowDays;
  final List<TradingDay> days;
  final TradingDay today;
  final TradingDay yesterday;
  final TradingTotals window;

  /// What the platform charged on delivered sales in the window.
  final double platformFees;

  /// What it chose not to charge, because an offer was running.
  final double savedByOffers;
  final double commissionPercentage;

  /// Orders placed and not yet accepted — the only figure here that is a job rather than a fact.
  final int awaitingYou;
  final int preparing;
  final int readyForPickup;
  final int onTheWay;

  final List<TopProduct> topProducts;

  factory MerchantSummary.fromJson(Map<String, dynamic> json) => MerchantSummary(
        windowDays: (json['windowDays'] as num?)?.toInt() ?? 14,
        days: (json['days'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic d) => TradingDay.fromJson(d as Map<String, dynamic>))
            .toList(),
        today: TradingDay.fromJson(json['today'] as Map<String, dynamic>),
        yesterday: TradingDay.fromJson(json['yesterday'] as Map<String, dynamic>),
        window: TradingTotals.fromJson(json['window'] as Map<String, dynamic>),
        platformFees: (json['platformFees'] as num?)?.toDouble() ?? 0,
        savedByOffers: (json['savedByOffers'] as num?)?.toDouble() ?? 0,
        commissionPercentage: (json['commissionPercentage'] as num?)?.toDouble() ?? 0,
        awaitingYou: (json['awaitingYou'] as num?)?.toInt() ?? 0,
        preparing: (json['preparing'] as num?)?.toInt() ?? 0,
        readyForPickup: (json['readyForPickup'] as num?)?.toInt() ?? 0,
        onTheWay: (json['onTheWay'] as num?)?.toInt() ?? 0,
        topProducts: (json['topProducts'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic p) => TopProduct.fromJson(p as Map<String, dynamic>))
            .toList(),
      );

  /// Everything somebody has to act on, in one number for the rail badge.
  int get needsYou => awaitingYou;
}

/// The same for a delivery company, on the fee they carry rather than the goods.
class CarrierSummary {
  const CarrierSummary({
    required this.windowDays,
    required this.days,
    required this.today,
    required this.yesterday,
    required this.window,
    required this.earned,
    required this.savedByOffers,
    required this.cutPercentage,
  });

  final int windowDays;
  final List<TradingDay> days;
  final TradingDay today;
  final TradingDay yesterday;
  final TradingTotals window;

  /// What the company keeps on the window's finished work, after the platform's cut.
  final double earned;
  final double savedByOffers;
  final double cutPercentage;

  factory CarrierSummary.fromJson(Map<String, dynamic> json) => CarrierSummary(
        windowDays: (json['windowDays'] as num?)?.toInt() ?? 14,
        days: (json['days'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic d) => TradingDay.fromJson(d as Map<String, dynamic>))
            .toList(),
        today: TradingDay.fromJson(json['today'] as Map<String, dynamic>),
        yesterday: TradingDay.fromJson(json['yesterday'] as Map<String, dynamic>),
        window: TradingTotals.fromJson(json['window'] as Map<String, dynamic>),
        earned: (json['earned'] as num?)?.toDouble() ?? 0,
        savedByOffers: (json['savedByOffers'] as num?)?.toDouble() ?? 0,
        cutPercentage: (json['cutPercentage'] as num?)?.toDouble() ?? 0,
      );
}
