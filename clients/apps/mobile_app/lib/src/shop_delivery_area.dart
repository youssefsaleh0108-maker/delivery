import 'dart:math' as math;

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';

import 'delivery_address.dart';
import 'order_placement.dart';

/// Where a shop delivers, as the rules that accept or refuse an order define it: what the shop
/// page's "Delivery area" control summarises and its map draws.
///
/// Two rules, and an address has to pass both:
///
/// * **The circle.** The shop's pin and its delivery radius ([Store.deliveryRadiusMetres]). Every
///   checkout on the phone refuses an address outside it before sending ([isOutsideDeliveryRadius])
///   — only when the address has a pin too, because an address typed by hand has no point to
///   measure. A radius with no pin binds nothing, so it is no circle here either.
/// * **The areas.** A shop that has priced areas ([Store.deliveryZones]) goes to those and no
///   others; an address names its area from the picker. Order Manager refuses any other area at
///   placement (product-service `DeliveryZoneService.termsFor`) — only when the address names one,
///   because an address with no area is served at the shop's flat fee.
///
/// An area is a NAME, not a shape. Its centre, where the back office placed it, is roughly the
/// middle of the neighbourhood and is never a boundary: nothing decides by distance from it. So the
/// map writes each placed area's name at its centre and lists the areas in words, and it never
/// draws a region around a centre that no rule has.
///
/// The inside/outside answer ([verdictFor]) is computed from those same two rules — the circle
/// through the very function checkout calls — so the map cannot call an address inside that
/// checkout would refuse, nor outside one it would accept.
///
/// **Retired areas judge but are not shown.** The shop still serves an area the back office has
/// retired from the picker ([DeliveryZone.active] false), and an address saved in it before still
/// orders there, so [verdictFor] and [limitsByArea] read every area ([zones]). But no customer can
/// pick a retired area any more, so the control counts, the map names and the words list only the
/// areas still in the picker ([shownZones]).
class ShopDeliveryArea {
  const ShopDeliveryArea._(this.store);

  /// The shop's delivery area, or null when there is nothing true to draw:
  ///
  /// * the store read did not say which areas the shop serves ([Store.deliveryZones] null — a
  ///   server from before it did). A circle drawn alone could be only half the area, and "inside"
  ///   would then be a guess;
  /// * the shop has neither a circle nor any area a customer can pick ([shownZones]) — no areas
  ///   at all, where it goes wherever the platform does and a map of "everywhere" is not a
  ///   delivery area, or only retired ones, which nobody can choose any more and which are never
  ///   shown;
  /// * [offersDeliver] is not true for a [StoreVertical.services] shop. A service provider delivers
  ///   only through offers that say so; a pickup-only provider has no delivery area to show, and
  ///   null — its offers unknown — shows none rather than guess.
  static ShopDeliveryArea? of(Store store, {bool? offersDeliver}) {
    if (store.vertical == StoreVertical.services && offersDeliver != true) return null;
    if (store.deliveryZones == null) return null;
    final ShopDeliveryArea area = ShopDeliveryArea._(store);
    return area.hasCircle || area.shownZones.isNotEmpty ? area : null;
  }

  final Store store;

  /// Whether the shop's circle binds: a radius around a pin.
  bool get hasCircle => store.deliveryRadiusMetres != null && store.hasPin;

  /// The circle's radius; only meaningful when [hasCircle].
  int get radiusMetres => store.deliveryRadiusMetres!;

  /// Every area the shop delivers to, retired ones included, in the picker's order: what order
  /// placement accepts, so what [verdictFor] judges by. Empty when areas do not limit it. Never
  /// drawn as it is — see [shownZones].
  List<DeliveryZone> get zones => store.deliveryZones ?? const <DeliveryZone>[];

  /// Whether the shop goes only to [zones]. True for a shop whose areas are all retired too: order
  /// placement still refuses every other area there.
  bool get limitsByArea => zones.isNotEmpty;

  /// The areas a customer is shown — counted in [summary], listed under the map, named on it: those
  /// still in the picker. A retired area stays in [zones] for the verdict, but nobody can choose it
  /// for an address any more, so listing it would offer a place the address sheet does not.
  List<DeliveryZone> get shownZones =>
      zones.where((DeliveryZone zone) => zone.active).toList(growable: false);

  /// The [shownZones] the map can write a name for: those the back office has placed.
  List<DeliveryZone> get placedZones =>
      shownZones.where((DeliveryZone zone) => zone.isPlaced).toList(growable: false);

  /// "3.0" — the radius in kilometres to one decimal, as checkout's own refusal words it
  /// ([DeliveryStrings.custOutsideDeliveryArea]), so the two never disagree about the number.
  String get radiusKm => (radiusMetres / 1000).toStringAsFixed(1);

  /// The one-line summary under the control's title: how far, how many areas, or both.
  String summary(DeliveryStrings t) => <String>[
        if (hasCircle) t.dareaWithinKm(radiusKm),
        if (shownZones.isNotEmpty) t.dareaAreasCount(shownZones.length),
      ].join(' · ');

  /// Whether [address] is inside this area, by the same two rules checkout applies.
  ///
  /// [DeliveryAreaVerdict.outside] when a rule that can be checked refuses it;
  /// [DeliveryAreaVerdict.inside] when at least one can be checked and none refuses it — exactly
  /// when checkout would let it through on where it is; [DeliveryAreaVerdict.unknown] when neither
  /// can be checked (no address, or one with no pin for a circle and no area for the areas), which
  /// the map then says nothing about rather than guessing.
  DeliveryAreaVerdict verdictFor(DeliveryAddress? address) {
    if (address == null) return DeliveryAreaVerdict.unknown;
    final bool? inCircle =
        hasCircle && address.hasPoint ? !isOutsideDeliveryRadius(store.toCard(), address) : null;
    final String? zoneId = address.zoneId;
    final bool? inAreas = limitsByArea && zoneId != null
        ? zones.any((DeliveryZone zone) => zone.id == zoneId)
        : null;
    if (inCircle == false || inAreas == false) return DeliveryAreaVerdict.outside;
    if (inCircle == true || inAreas == true) return DeliveryAreaVerdict.inside;
    return DeliveryAreaVerdict.unknown;
  }

  /// The points the map has to show, to frame its camera on: the circle's four extremes (so the
  /// whole ring is in view, not just its centre), the shop's pin, and every area it names
  /// ([placedZones] — never a retired one). Empty when there is nothing to put on a map at all —
  /// areas nobody has placed, around a shop with no pin.
  List<(double, double)> get framePoints {
    final List<(double, double)> points = <(double, double)>[
      if (store.hasPin) (store.latitude!, store.longitude!),
      for (final DeliveryZone zone in placedZones) (zone.centerLat!, zone.centerLng!),
    ];
    if (hasCircle) {
      final double lat = store.latitude!;
      final double lng = store.longitude!;
      // Metres to degrees: a degree of latitude is ~111.32 km everywhere, a degree of longitude
      // shrinks with the cosine of the latitude. Plenty for framing a camera.
      final double dLat = radiusMetres / 111320;
      final double dLng = radiusMetres / (111320 * math.cos(lat * math.pi / 180));
      points.addAll(<(double, double)>[
        (lat + dLat, lng),
        (lat - dLat, lng),
        (lat, lng + dLng),
        (lat, lng - dLng),
      ]);
    }
    return points;
  }
}

/// Where the customer's address stands against a shop's delivery area.
enum DeliveryAreaVerdict {
  inside,
  outside,

  /// Nothing can be concluded: no address, or none of what the rules check is known about it.
  unknown,
}
