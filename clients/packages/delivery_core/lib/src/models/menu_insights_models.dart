/// What a shop's own menu has been doing: how often it was opened, when in the day, and what came
/// back out of it as an order.
///
/// Two kinds of figure live here and they are shaped differently on purpose.
///
/// **Opens are bands over a floor.** Product Service counts opens of the public menu page in
/// counters that hold no visit, no timestamp and nothing about a reader, publishes nothing until a
/// window clears [MenuInsights.minimumOpens], and rounds down what it does publish. So there is no
/// exact figure to display and [MenuOpens.enough] exists to say which silence a shop is in — too
/// few readers to report is not the same thing as none, and a screen that drew a zero for the first
/// would be saying something the server did not.
///
/// **Sales are exact**, because they are the shop's own delivered orders, which it filled itself
/// and already has on its receipts. A floor there would protect nobody.
///
/// Two of the design's figures are deliberately absent rather than zero. There is no QR-scan count:
/// a shop's printed counter code encodes the page's plain address, so a scan of it and a tapped
/// link are the same request and the platform cannot tell them apart — [MenuInsights.fromTableCodes]
/// is the real number, and it is only table cards. There is no per-item view count: the public page
/// is one document holding the whole menu, so every item on it is read exactly as often as every
/// other.
library;

/// A count as the server is willing to say it.
class MenuOpens {
  const MenuOpens({required this.about, required this.enough});

  /// Rounded DOWN to a round number, or zero when [enough] is false. Never the count itself, and
  /// never to be shown without the word "about" — the server never says more than happened, so a
  /// screen that presented this as exact would be overstating in the other direction.
  final int about;

  /// Whether the floor was cleared at all.
  ///
  /// FALSE IS NOT ZERO. It means "too few to say anything about". A screen must word it as such
  /// rather than drawing a 0, which reads as "nobody".
  final bool enough;

  bool get isEmpty => !enough;

  static const MenuOpens none = MenuOpens(about: 0, enough: false);

  factory MenuOpens.fromJson(Map<String, dynamic> json) => MenuOpens(
        about: (json['about'] as num?)?.toInt() ?? 0,
        enough: json['enough'] as bool? ?? false,
      );
}

/// A quarter of the shop's own day.
///
/// Four, and never hours. The server keeps no finer grain than this and could not answer for one:
/// "someone opened your menu at 19:00" is a sentence about a person, and a quiet shop is where it
/// would be truest.
enum MenuDayPart {
  morning,
  midday,
  evening,
  night,

  /// A part this build does not know. Kept rather than failing the whole chart, and drawn unnamed.
  unknown;

  static MenuDayPart parse(Object? raw) => switch (raw) {
        'MORNING' => MenuDayPart.morning,
        'MIDDAY' => MenuDayPart.midday,
        'EVENING' => MenuDayPart.evening,
        'NIGHT' => MenuDayPart.night,
        _ => MenuDayPart.unknown,
      };
}

/// One bar of the when-in-the-day chart.
class MenuDayPartOpens {
  const MenuDayPartOpens({required this.part, required this.opens});

  final MenuDayPart part;
  final MenuOpens opens;

  factory MenuDayPartOpens.fromJson(Map<String, dynamic> json) => MenuDayPartOpens(
        part: MenuDayPart.parse(json['part']),
        opens: MenuOpens.fromJson(
            (json['opens'] as Map<String, dynamic>?) ?? const <String, dynamic>{}),
      );
}

/// One item the shop actually delivered in the window.
class MenuBestSeller {
  const MenuBestSeller({
    required this.productId,
    required this.name,
    required this.baskets,
    required this.units,
  });

  final String productId;
  final String name;

  /// How many delivered orders contained it. This is what the list is ranked on: a customer who
  /// bought six in one order is one order that wanted it, not six.
  final int baskets;

  /// How many of it went out altogether.
  final int units;

  factory MenuBestSeller.fromJson(Map<String, dynamic> json) => MenuBestSeller(
        productId: json['productId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        baskets: (json['baskets'] as num?)?.toInt() ?? 0,
        units: (json['units'] as num?)?.toInt() ?? 0,
      );
}

/// One shop's menu over a window of its own days.
class MenuInsights {
  const MenuInsights({
    required this.storeId,
    required this.from,
    required this.to,
    required this.days,
    required this.opens,
    required this.fromTableCodes,
    required this.shape,
    required this.bestSellers,
    required this.minimumOpens,
    this.countingSince,
  });

  final String storeId;

  /// The window, in the shop's own calendar, both ends inclusive.
  final DateTime from;
  final DateTime to;

  /// How many days the server actually used. It clamps rather than refusing, so this is the number
  /// a heading should read — not the one that was asked for.
  final int days;

  /// Every open of the menu in the window.
  final MenuOpens opens;

  /// The subset that arrived through a code printed on one of the shop's tables.
  ///
  /// NOT QR scans, and the difference is not pedantry: the shop's counter code carries no marker,
  /// so a scan of it is indistinguishable from a link. A shop with no table codes sees nothing
  /// here and that is true rather than missing.
  final MenuOpens fromTableCodes;

  /// The four parts of the day, in the order a day runs.
  final List<MenuDayPartOpens> shape;

  /// What was delivered, exact, best first. Empty for a shop whose delivered orders all predate
  /// the projection this is read from — which cannot be backfilled, so "nothing yet" is honest.
  final List<MenuBestSeller> bestSellers;

  /// The first day this shop has any counter for, or null when it has none.
  ///
  /// Lets a screen say "counting started on the 3rd" instead of implying a quiet month a shop
  /// never had.
  final DateTime? countingSince;

  /// How many opens a window or a part of the day needs before anything about it is published, so
  /// a screen can explain a panel it is not drawing.
  final int minimumOpens;

  /// True when the whole opens half of the screen has nothing to say.
  bool get openTrackingIsQuiet => !opens.enough;

  factory MenuInsights.fromJson(Map<String, dynamic> json) => MenuInsights(
        storeId: json['storeId'] as String? ?? '',
        from: DateTime.parse(json['from'] as String),
        to: DateTime.parse(json['to'] as String),
        days: (json['days'] as num?)?.toInt() ?? 0,
        opens: MenuOpens.fromJson(
            (json['opens'] as Map<String, dynamic>?) ?? const <String, dynamic>{}),
        fromTableCodes: MenuOpens.fromJson(
            (json['fromTableCodes'] as Map<String, dynamic>?) ?? const <String, dynamic>{}),
        shape: <MenuDayPartOpens>[
          for (final dynamic part in (json['shape'] as List<dynamic>? ?? const <dynamic>[]))
            MenuDayPartOpens.fromJson(part as Map<String, dynamic>),
        ],
        bestSellers: <MenuBestSeller>[
          for (final dynamic item in (json['bestSellers'] as List<dynamic>? ?? const <dynamic>[]))
            MenuBestSeller.fromJson(item as Map<String, dynamic>),
        ],
        countingSince: json['countingSince'] == null
            ? null
            : DateTime.parse(json['countingSince'] as String),
        minimumOpens: (json['minimumOpens'] as num?)?.toInt() ?? 0,
      );
}
