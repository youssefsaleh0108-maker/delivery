/// Applying to offer services (Figma 126:11): what the signup form may offer, and what the
/// application said.
library;

import 'store_models.dart';

/// A curated delivery zone, as the services signup form offers it: the area a provider works in.
///
/// A zone rather than free text, because the provider's shop is filed under it and the back office
/// reads it — a typed "Mar Mikhael, Beirut" and "mar mikhael" would be two neighbourhoods.
class ServiceArea {
  const ServiceArea({required this.zoneId, required this.name});

  final String zoneId;
  final String name;

  /// Null for anything that is not a usable area — no id, or no name to show.
  static ServiceArea? fromJson(Object? json) {
    if (json is! Map) return null;
    final String? id = _text(json['zoneId']);
    final String? name = _text(json['name']);
    if (id == null || name == null) return null;
    return ServiceArea(zoneId: id, name: name);
  }

  @override
  bool operator ==(Object other) => other is ServiceArea && other.zoneId == zoneId;

  @override
  int get hashCode => zoneId.hashCode;
}

/// What the services signup form may offer, from `GET /api/onboarding/service-options`.
///
/// The same two lists the server judges an application against, so the form cannot offer an answer
/// the server would refuse.
class ServiceSignupOptions {
  const ServiceSignupOptions({required this.categories, required this.areas});

  /// The open categories this build can name, in the server's order. A category this build does not
  /// know is left out rather than offered under a guessed label — see [ServiceCategory.maybeFromWire].
  final List<ServiceCategory> categories;

  final List<ServiceArea> areas;

  factory ServiceSignupOptions.fromJson(Map<String, dynamic> json) => ServiceSignupOptions(
        categories: (json['categories'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic wire) => ServiceCategory.maybeFromWire(_text(wire)))
            .whereType<ServiceCategory>()
            .toList(),
        areas: (json['areas'] as List<dynamic>? ?? const <dynamic>[])
            .map(ServiceArea.fromJson)
            .whereType<ServiceArea>()
            .toList(),
      );
}

/// What an application to offer services said — its category and area — as the applicant's own
/// receipt carries them.
///
/// The provider's app opens its services shop from this on the first entry after approval.
class ServiceApplicationAnswers {
  const ServiceApplicationAnswers({this.categoryWire, this.zoneId, this.area});

  /// The category's wire name, kept even when this build cannot name it, so nothing is opened under a
  /// category the app merely failed to recognise.
  final String? categoryWire;

  final String? zoneId;

  /// The area's name, as the server recorded it from the zone.
  final String? area;

  /// Null when there is no category, or one this build does not know.
  ServiceCategory? get category => ServiceCategory.maybeFromWire(categoryWire);

  /// Null for anything but the receipt's services block — including the null every other
  /// application's receipt carries.
  static ServiceApplicationAnswers? fromJson(Object? json) {
    if (json is! Map) return null;
    return ServiceApplicationAnswers(
      categoryWire: _text(json['category']),
      zoneId: _text(json['zoneId']),
      area: _text(json['area']),
    );
  }
}

String? _text(Object? value) => value is String && value.trim().isNotEmpty ? value : null;
