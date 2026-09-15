/// How busy the areas around a shop are — the merchant Demand Radar's one read.
///
/// Levels, never counts. Order Manager groups orders by the delivery area the customer picked,
/// shows an area only once at least [DemandDensity.minimumCustomers] different customers ordered
/// there in the window, and says how busy it is relative to the busiest area shown. There is no
/// number on a [DemandZone] to display, and that is the endpoint's design rather than an omission
/// here: a count would let a shop subtract its own orders and read off its neighbours' trade.
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
