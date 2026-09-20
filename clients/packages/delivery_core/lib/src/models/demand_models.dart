/// What the merchant Demand Radar reads: how busy the areas around a shop are, and what those areas
/// looked for and could not find.
///
/// Levels, never counts. Order Manager groups orders by the delivery area the customer picked,
/// shows an area only once at least [DemandDensity.minimumCustomers] different customers ordered
/// there in the window, and says how busy it is relative to the busiest area shown. There is no
/// number on a [DemandZone] to display, and that is the endpoint's design rather than an omission
/// here: a count would let a shop subtract its own orders and read off its neighbours' trade.
///
/// The unmet half ([UnmetDemand]) answers the same way. Product Service records each customer item
/// search against a neighbourhood — never an account, a session or a pin — shows a word only once at
/// least [UnmetDemand.minimumSearches] different searches asked for it in a week, and says roughly
/// how many rather than exactly ([UnmetTerm.about]). So there is no exact figure on a term to
/// display either, and for the same reason.
library;

/// How busy one area is, relative to the busiest area shown.
enum DemandLevel {
  high,
  medium,
  low,

  /// A level this build does not know yet. Kept rather than failing the whole map, and drawn with
  /// no level named — never guessed up or down.
  unknown;

  static DemandLevel parse(Object? raw) => switch (raw) {
        'HIGH' => DemandLevel.high,
        'MEDIUM' => DemandLevel.medium,
        'LOW' => DemandLevel.low,
        _ => DemandLevel.unknown,
      };
}

/// One area that reached the privacy floor.
class DemandZone {
  const DemandZone({
    required this.zoneId,
    required this.name,
    required this.level,
    this.region,
    this.centerLat,
    this.centerLng,
  });

  final String zoneId;
  final String name;
  final String? region;

  /// Roughly the middle of the area, both or neither. Null when the back office has not placed it,
  /// in which case the area is listed but cannot be drawn.
  final double? centerLat;
  final double? centerLng;

  final DemandLevel level;

  bool get isPlaced => centerLat != null && centerLng != null;

  factory DemandZone.fromJson(Map<String, dynamic> json) {
    final double? lat = (json['centerLat'] as num?)?.toDouble();
    final double? lng = (json['centerLng'] as num?)?.toDouble();
    final bool whole = lat != null && lng != null;
    return DemandZone(
      zoneId: json['zoneId'] as String,
      name: json['name'] as String,
      region: json['region'] as String?,
      centerLat: whole ? lat : null,
      centerLng: whole ? lng : null,
      level: DemandLevel.parse(json['level']),
    );
  }
}

/// The demand around one shop, over one rolling window.
class DemandDensity {
  const DemandDensity({
    required this.storeId,
    required this.windowMinutes,
    required this.minimumCustomers,
    required this.areasAround,
    required this.zones,
    this.region,
    this.generatedAt,
  });

  final String storeId;

  /// The city label: the region most of the shop's areas name. Data, never a translated string.
  final String? region;

  /// The window the server actually used, after clamping.
  final int windowMinutes;

  final DateTime? generatedAt;

  /// How many different customers an area needs before it is shown at all.
  final int minimumCustomers;

  /// How many areas make up the shop's neighbourhood, shown or not. Zero means the platform does not
  /// know where the shop is yet (no pin, no delivery areas) — a different thing to say than "not
  /// enough orders".
  final int areasAround;

  /// The areas that reached the floor, busiest first.
  final List<DemandZone> zones;

  bool get hasNeighbourhood => areasAround > 0;

  /// The shown areas the map can draw.
  List<DemandZone> get placed => zones.where((DemandZone z) => z.isPlaced).toList();

  factory DemandDensity.fromJson(Map<String, dynamic> json) {
    final String region = (json['region'] as String? ?? '').trim();
    return DemandDensity(
      storeId: json['storeId'] as String,
      region: region.isEmpty ? null : region,
      windowMinutes: (json['windowMinutes'] as num?)?.toInt() ?? 60,
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? ''),
      minimumCustomers: (json['minimumCustomers'] as num?)?.toInt() ?? 5,
      areasAround: (json['areasAround'] as num?)?.toInt() ?? 0,
      zones: (json['zones'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic j) => DemandZone.fromJson(j as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Why a word counts as unmet.
enum UnmetKind {
  /// Every search for it came back with no shop at all.
  none,

  /// It came back, but only with shops further than [UnmetDemand.farMetres].
  far,

  /// A reason this build does not know yet. Kept rather than failing the whole list, and drawn
  /// without a reason named — never guessed at.
  unknown;

  static UnmetKind parse(Object? raw) => switch (raw) {
        'NONE' => UnmetKind.none,
        'FAR' => UnmetKind.far,
        _ => UnmetKind.unknown,
      };
}

/// One word a neighbourhood looked for and did not find nearby.
class UnmetTerm {
  const UnmetTerm({
    required this.areaId,
    required this.term,
    required this.kind,
    required this.about,
    required this.rank,
    required this.alreadySold,
    this.areaName,
    this.region,
  });

  final String areaId;

  /// The neighbourhood that asked. Null only if the area register has since lost its name.
  final String? areaName;
  final String? region;

  /// The word as it was searched for, already folded: lower case, accents and Arabic letter
  /// families normalised. Shown as it arrives — it is what customers typed, not a product name the
  /// platform chose.
  final String term;

  final UnmetKind kind;

  /// Roughly how many searches asked for it, rounded down to a round number by the server. There is
  /// no exact count to show and that is deliberate: a precise figure invites a merchant to subtract
  /// week from week until what is left is one household.
  final int about;

  /// 1 is the word the most searches asked for, in that area, that week, of that kind.
  final int rank;

  /// True when the merchant's own shops already list something matching it — worth saying rather
  /// than hiding, because it usually means out of stock, paused, or named something nobody types.
  final bool alreadySold;

  factory UnmetTerm.fromJson(Map<String, dynamic> json) {
    final String area = (json['areaName'] as String? ?? '').trim();
    final String region = (json['region'] as String? ?? '').trim();
    return UnmetTerm(
      areaId: json['areaId'] as String? ?? '',
      areaName: area.isEmpty ? null : area,
      region: region.isEmpty ? null : region,
      term: (json['term'] as String? ?? '').trim(),
      kind: UnmetKind.parse(json['kind']),
      about: (json['about'] as num?)?.toInt() ?? 0,
      rank: (json['rank'] as num?)?.toInt() ?? 1,
      alreadySold: json['alreadySold'] as bool? ?? false,
    );
  }
}

/// One week of unmet words.
class UnmetWeek {
  const UnmetWeek({required this.weekStart, required this.terms});

  /// Monday 00:00 in the platform's zone. Data, never a formatted date.
  final DateTime? weekStart;

  /// Best first: the most-wanted, then nothing-at-all before merely-far-away.
  final List<UnmetTerm> terms;

  bool get isEmpty => terms.isEmpty;

  factory UnmetWeek.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const UnmetWeek(weekStart: null, terms: <UnmetTerm>[]);
    return UnmetWeek(
      weekStart: DateTime.tryParse(json['weekStart'] as String? ?? ''),
      terms: (json['terms'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic j) => UnmetTerm.fromJson(j as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// What the areas around one shop looked for and could not find, this week and last.
class UnmetDemand {
  const UnmetDemand({
    required this.storeId,
    required this.areasAround,
    required this.minimumSearches,
    required this.farMetres,
    required this.thisWeek,
    required this.lastWeek,
    this.region,
  });

  final String storeId;

  /// The city label: the region most of the shop's areas name.
  final String? region;

  /// How many areas make up the shop's neighbourhood at all. Zero means the platform does not know
  /// where the shop is yet — a different thing to say than "nothing went unanswered".
  final int areasAround;

  /// How many different searches a word needs in a week before anybody is told about it.
  final int minimumSearches;

  /// What "the nearest shop was far away" meant, in metres.
  final int farMetres;

  final UnmetWeek thisWeek;
  final UnmetWeek lastWeek;

  bool get hasNeighbourhood => areasAround > 0;

  bool get isEmpty => thisWeek.isEmpty && lastWeek.isEmpty;

  factory UnmetDemand.fromJson(Map<String, dynamic> json) {
    final String region = (json['region'] as String? ?? '').trim();
    return UnmetDemand(
      storeId: json['storeId'] as String? ?? '',
      region: region.isEmpty ? null : region,
      areasAround: (json['areasAround'] as num?)?.toInt() ?? 0,
      minimumSearches: (json['minimumSearches'] as num?)?.toInt() ?? 5,
      farMetres: (json['farMetres'] as num?)?.toInt() ?? 2000,
      thisWeek: UnmetWeek.fromJson(json['thisWeek'] as Map<String, dynamic>?),
      lastWeek: UnmetWeek.fromJson(json['lastWeek'] as Map<String, dynamic>?),
    );
  }
}
