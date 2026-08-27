/// Geocoding, "near me" and cross-sell models mirroring the Product Service geo APIs.
library;

import 'catalog_models.dart';
import 'store_models.dart';

/// One candidate from the address picker, mirroring `GeoDtos.PlaceResponse`.
class PlaceCandidate {
  const PlaceCandidate({
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.confident,
    this.kind,
  });

  /// The line to show. Text from an open map database — render it as text, never as markup.
  final String label;

  final double latitude;
  final double longitude;

  /// The provider's own category ("house", "road"…). Null when the provider gave none.
  final String? kind;

  /// Whether the provider called this an exact match rather than a near one, so a picker can
  /// present a guess as a guess.
  final bool confident;

  factory PlaceCandidate.fromJson(Map<String, dynamic> json) => PlaceCandidate(
        label: json['label'] as String? ?? '',
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        kind: json['kind'] as String?,
        confident: json['confident'] as bool? ?? false,
      );
}

/// A search result set and who produced it, mirroring `GeoDtos.PlaceSearchResponse`.
///
/// [provider] is on the response deliberately: a pin dropped by the free dev geocoder and one
/// dropped by a paid provider are not equally trustworthy, and a client should be able to see
/// which it is looking at rather than assume.
class PlaceSearchResult {
  const PlaceSearchResult({required this.provider, required this.results});

  final String provider;
  final List<PlaceCandidate> results;

  factory PlaceSearchResult.fromJson(Map<String, dynamic> json) => PlaceSearchResult(
        provider: json['provider'] as String? ?? 'UNKNOWN',
        results: (json['results'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => PlaceCandidate.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// The address at a point, mirroring `GeoDtos.ReverseGeocodeResponse`.
///
/// Only ever built from a 200 — a pin dropped in the sea comes back as a 204 and the client gets
/// null instead of this, so there is no "empty address" state to invent.
class ReverseGeocodeResult {
  const ReverseGeocodeResult({
    required this.provider,
    required this.label,
    required this.latitude,
    required this.longitude,
    this.locality,
    this.countryCode,
  });

  final String provider;

  /// The display line. Provider text — render as text, never as markup.
  final String label;

  final double latitude;
  final double longitude;

  /// Town or district, when the provider broke it out. Null otherwise.
  final String? locality;

  /// ISO country code, when known.
  final String? countryCode;

  factory ReverseGeocodeResult.fromJson(Map<String, dynamic> json) => ReverseGeocodeResult(
        provider: json['provider'] as String? ?? 'UNKNOWN',
        label: json['label'] as String? ?? '',
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        locality: json['locality'] as String?,
        countryCode: json['countryCode'] as String?,
      );
}

/// A store on the "near me" rail, mirroring `GeoDtos.NearbyStoreResponse`.
///
/// The card is nested rather than flattened, exactly as the wire has it, so a screen that already
/// renders a [StoreCard] renders this without changes.
class NearbyStore {
  const NearbyStore({
    required this.store,
    required this.latitude,
    required this.longitude,
    required this.distanceMetres,
  });

  final StoreCard store;

  /// Where the shop's pin is.
  final double latitude;
  final double longitude;

  /// Straight-line metres, rounded. Not the driven distance — no route is computed — and whole
  /// metres because the pin it is measured from was dropped by hand.
  final int distanceMetres;

  factory NearbyStore.fromJson(Map<String, dynamic> json) => NearbyStore(
        store: StoreCard.fromJson(json['store'] as Map<String, dynamic>),
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        distanceMetres: (json['distanceMetres'] as num?)?.toInt() ?? 0,
      );
}

/// How a cross-sell suggestion was arrived at, mirroring `CrossSellService.Basis`.
///
/// Not decoration, and a rail should not ignore it: [boughtTogether] was counted from delivered
/// baskets and comes with a real number; [sameAisle] is fill from the same shop with no count,
/// because nothing was measured and nothing is being claimed.
enum CrossSellBasis {
  /// Counted from delivered baskets that contained both products.
  boughtTogether('BOUGHT_TOGETHER', 'Often bought together'),

  /// Another product on the same shelf. No popularity is claimed or implied.
  sameAisle('SAME_AISLE', 'From the same shelf'),

  /// A basis this client does not know. Treated like [sameAisle]: no popularity claimed.
  unknown('UNKNOWN', 'You might also like');

  const CrossSellBasis(this.wire, this.label);

  final String wire;
  final String label;

  static CrossSellBasis fromWire(String? value) => CrossSellBasis.values.firstWhere(
        (CrossSellBasis b) => b.wire == value,
        orElse: () => CrossSellBasis.unknown,
      );
}

/// One suggestion on the "People Also Ordered" rail, mirroring `GeoDtos.CrossSellResponse`.
///
/// Named for what the backend honestly computes — item co-occurrence in delivered baskets — not
/// "recommendations": there is no model of who the caller is and no similarity between shoppers.
class BoughtTogetherSuggestion {
  const BoughtTogetherSuggestion({
    required this.product,
    required this.basis,
    this.ordersTogether,
  });

  /// The full product shape the shelf already renders.
  final Product product;

  final CrossSellBasis basis;

  /// How many delivered baskets held both products. Null for [CrossSellBasis.sameAisle], where no
  /// count exists — never render a number that is not here.
  final int? ordersTogether;

  factory BoughtTogetherSuggestion.fromJson(Map<String, dynamic> json) =>
      BoughtTogetherSuggestion(
        product: Product.fromJson(json['product'] as Map<String, dynamic>),
        basis: CrossSellBasis.fromWire(json['basis'] as String?),
        ordersTogether: (json['ordersTogether'] as num?)?.toInt(),
      );
}
