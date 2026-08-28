/// A delivery company's own settings — logo, dispatch regions, operating hours — mirroring the
/// onboarding-service provider-profile shapes.
library;

/// One day's opening window, mirroring the profile's `{ "open": "HH:mm", "close": "HH:mm" }`.
///
/// Both ends are the server's own `HH:mm` strings, kept as strings on purpose: they are labels in
/// the company's trading day, not instants, and turning them into DateTimes would pin them to a
/// zone nobody chose. The server validates the format and `open < close`; the client just carries
/// them.
class DayHours {
  const DayHours({required this.open, required this.close});

  /// `HH:mm`, 24-hour.
  final String open;

  /// `HH:mm`, 24-hour, strictly after [open].
  final String close;

  factory DayHours.fromJson(Map<String, dynamic> json) => DayHours(
        open: json['open'] as String? ?? '',
        close: json['close'] as String? ?? '',
      );

  /// The PUT sends these back exactly as they came — the one model here that must serialise.
  Map<String, dynamic> toJson() => <String, dynamic>{'open': open, 'close': close};
}

/// The whole profile, mirroring `ProfileView`.
///
/// A company that never saved settings gets this shape with everything empty, never a 404 — so a
/// screen renders the empty form rather than an error.
class ProviderProfile {
  const ProviderProfile({
    required this.providerId,
    required this.dispatchRegions,
    required this.operatingHours,
    this.logoUrl,
    this.updatedBy,
    this.updatedAt,
  });

  /// The day keys the server uses, in week order — for iterating a form that must show all seven
  /// days even though [operatingHours] only carries the open ones.
  static const List<String> weekDays = <String>[
    'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY',
  ];

  final String providerId;

  /// Where the logo is served from, or null when none has been uploaded yet.
  final String? logoUrl;

  /// The regions the company dispatches to. Empty when never set.
  final List<String> dispatchRegions;

  /// Keyed by upper-case day name ([weekDays]). A day absent from the map is CLOSED that day —
  /// absence is meaningful, not missing data.
  final Map<String, DayHours> operatingHours;

  /// Who last saved and when. Both null on the never-saved empty shape.
  final String? updatedBy;
  final DateTime? updatedAt;

  factory ProviderProfile.fromJson(Map<String, dynamic> json) => ProviderProfile(
        providerId: json['providerId'] as String,
        logoUrl: json['logoUrl'] as String?,
        dispatchRegions: (json['dispatchRegions'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic r) => r as String)
            .toList(),
        operatingHours: _hours(json['operatingHours']),
        updatedBy: json['updatedBy'] as String?,
        updatedAt: _time(json['updatedAt']),
      );

  static Map<String, DayHours> _hours(dynamic value) {
    if (value is! Map) return const <String, DayHours>{};
    return <String, DayHours>{
      for (final MapEntry<dynamic, dynamic> e in value.entries)
        if (e.value is Map)
          e.key.toString(): DayHours.fromJson((e.value as Map).cast<String, dynamic>()),
    };
  }

  /// The hours map as the PUT wants it — a closed day simply absent.
  static Map<String, dynamic> hoursToJson(Map<String, DayHours> hours) => <String, dynamic>{
        for (final MapEntry<String, DayHours> e in hours.entries) e.key: e.value.toJson(),
      };

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}
