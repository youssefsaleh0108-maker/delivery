/// An area a customer picks from a list.
///
/// Not a coordinate. Addresses in this market are landmarks and floor numbers, so the reliable way
/// to know where an order is going is to ask — which is what every local delivery app does.
class DeliveryZone {
  const DeliveryZone({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.active,
    this.region,
  });

  final String id;
  final String name;

  /// Groups areas in the picker — "Beirut", "Mount Lebanon".
  final String? region;

  final int sortOrder;

  /// Retired areas stay resolvable for the addresses that name them, but leave the picker.
  final bool active;

  factory DeliveryZone.fromJson(Map<String, dynamic> json) => DeliveryZone(
        id: json['id'] as String,
        name: json['name'] as String,
        region: json['region'] as String?,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 100,
        active: json['active'] as bool? ?? true,
      );
}

/// What one shop charges to reach one area.
class ZoneCoverage {
  const ZoneCoverage({
    required this.zoneId,
    required this.zoneName,
    required this.deliveryFee,
    required this.etaExtraMinutes,
    this.region,
    this.minOrder,
  });

  final String zoneId;
  final String zoneName;
  final String? region;
  final double deliveryFee;

  /// Null means "use the shop's own minimum" rather than "no minimum".
  final double? minOrder;

  /// Added to both ends of the shop's ETA: a further area genuinely takes longer.
  final int etaExtraMinutes;

  factory ZoneCoverage.fromJson(Map<String, dynamic> json) => ZoneCoverage(
        zoneId: json['zoneId'] as String,
        zoneName: json['zoneName'] as String,
        region: json['region'] as String?,
        deliveryFee: (json['deliveryFee'] as num).toDouble(),
        minOrder: (json['minOrder'] as num?)?.toDouble(),
        etaExtraMinutes: (json['etaExtraMinutes'] as num?)?.toInt() ?? 0,
      );
}

/// A shop's terms for a particular area.
class ZoneTerms {
  const ZoneTerms({
    required this.storeId,
    required this.served,
    required this.deliveryFee,
    required this.minOrder,
    required this.etaMinMinutes,
    required this.etaMaxMinutes,
  });

  final String storeId;

  /// False when the shop prices by area and does not serve this one. An order there is refused.
  final bool served;

  final double deliveryFee;
  final double minOrder;
  final int etaMinMinutes;
  final int etaMaxMinutes;

  factory ZoneTerms.fromJson(Map<String, dynamic> json) => ZoneTerms(
        storeId: json['storeId'] as String,
        served: json['served'] as bool? ?? true,
        deliveryFee: (json['deliveryFee'] as num?)?.toDouble() ?? 0,
        minOrder: (json['minOrder'] as num?)?.toDouble() ?? 0,
        etaMinMinutes: (json['etaMinMinutes'] as num?)?.toInt() ?? 0,
        etaMaxMinutes: (json['etaMaxMinutes'] as num?)?.toInt() ?? 0,
      );
}
