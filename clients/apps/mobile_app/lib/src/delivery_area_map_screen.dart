import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'address_sheet.dart' show OsmBasemap;
import 'delivery_address.dart';
import 'shop_delivery_area.dart';

/// Where a shop delivers, on a map: what the shop page's "Delivery area" control opens.
///
/// Drawn exactly as the rules that accept an order define the area ([ShopDeliveryArea]):
///
/// * **the circle** as a ring of the shop's delivery radius around its pin, to the metre;
/// * **the areas** in words, every one a customer can still pick ([ShopDeliveryArea.shownZones]) —
///   and, for each the back office has placed, its name written where it sits. Never a region
///   around that point: an area is decided by the name an address picks, not by distance, and a
///   drawn edge would be a rule nobody has. An area retired from the picker is neither listed nor
///   named, though an address saved in it still reads inside;
/// * **the customer's chosen address**, when it has a pin, and a plain line saying whether it is
///   inside or outside — only when that can be told by the same rules checkout applies.
///
/// A shop whose areas nobody has placed and which has no pin has nothing to put on a map; the
/// screen is then the words alone rather than a map of nowhere. On [OsmBasemap] like every map the
/// customer sees, so the tile source, the licence credit and the dead-tiles fallback are the
/// platform's one implementation.
class DeliveryAreaMapScreen extends StatelessWidget {
  const DeliveryAreaMapScreen({super.key, required this.area, this.addresses});

  final ShopDeliveryArea area;

  /// The customer's address book; its selected address is the one drawn and judged. Listened to,
  /// so choosing another address elsewhere while this is open is reflected when it is shown again.
  final DeliveryAddressStore? addresses;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final DeliveryAddressStore? book = addresses;
    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(
        title: t.dareaButton,
        subtitle: area.store.name,
        onBack: () => Navigator.of(context).maybePop(),
        backSemanticLabel: t.back,
      ),
      body: book == null
          ? _body(context, null)
          : ListenableBuilder(
              listenable: book,
              builder: (BuildContext context, _) => _body(context, book.selected),
            ),
    );
  }

  Widget _body(BuildContext context, DeliveryAddress? address) {
    final bool mapped = area.framePoints.isNotEmpty;
    final Widget details = DeliveryAreaDetails(
      area: area,
      address: address,
      verdict: area.verdictFor(address),
      mapShown: mapped,
    );
    if (!mapped) {
      return SingleChildScrollView(child: SafeArea(top: false, child: details));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: _AreaMap(area: area, address: (address?.hasPoint ?? false) ? address : null),
        ),
        // The words under the map. A long list of areas scrolls on its own rather than pushing the
        // map off a small phone.
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: DeliveryColors.white,
              border: Border(top: BorderSide(color: DeliveryColors.border)),
            ),
            child: SingleChildScrollView(child: SafeArea(top: false, child: details)),
          ),
        ),
      ],
    );
  }
}

/// The map: the ring, the placed areas' names, the shop's pin and the customer's address.
class _AreaMap extends StatelessWidget {
  const _AreaMap({required this.area, required this.address});

  final ShopDeliveryArea area;

  /// Only an address with a pin; null draws none.
  final DeliveryAddress? address;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final Store store = area.store;
    final LatLng? pin = store.hasPin ? LatLng(store.latitude!, store.longitude!) : null;
    final DeliveryAddress? home = address;
    final LatLng? door = home == null ? null : LatLng(home.latitude!, home.longitude!);

    return OsmBasemap(
      options: MapOptions(
        initialCameraFit: CameraFit.coordinates(
          coordinates: <LatLng>[
            for (final (double lat, double lng) in area.framePoints) LatLng(lat, lng),
            // The address too, however far out it is: seeing how far is the point of looking.
            if (door != null) door,
          ],
          padding: const EdgeInsets.all(40),
          // One placed area and nothing else would otherwise fit at the deepest zoom there is.
          maxZoom: 16,
        ),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.drag |
              InteractiveFlag.pinchZoom |
              InteractiveFlag.pinchMove |
              InteractiveFlag.doubleTapZoom |
              InteractiveFlag.scrollWheelZoom,
        ),
      ),
      layers: <Widget>[
        if (area.hasCircle && pin != null)
          CircleLayer(
            circles: <CircleMarker>[
              CircleMarker(
                point: pin,
                radius: area.radiusMetres.toDouble(),
                // Metres on the ground, so the ring stays the rule's size at every zoom.
                useRadiusInMeter: true,
                color: DeliveryColors.brand.withValues(alpha: 0.12),
                borderColor: DeliveryColors.brand,
                borderStrokeWidth: 2,
              ),
            ],
          ),
        MarkerLayer(
          markers: <Marker>[
            for (final DeliveryZone zone in area.placedZones)
              Marker(
                point: LatLng(zone.centerLat!, zone.centerLng!),
                width: 150,
                height: 30,
                child: Center(child: DeliveryAreaZoneName(name: zone.name)),
              ),
            if (pin != null)
              Marker(
                point: pin,
                width: 36,
                height: 36,
                child: _ShopPin(name: store.name),
              ),
            if (door != null)
              Marker(
                point: door,
                width: 34,
                height: 34,
                child: Semantics(
                  label: t.custYourAddress,
                  child: const Icon(Icons.place, size: 30, color: DeliveryColors.ink),
                ),
              ),
          ],
        ),
      ],
      fallback: const _MapUnavailable(),
    );
  }
}

/// An area's name where the back office placed it: a dark label, not a pin and not a shape.
class DeliveryAreaZoneName extends StatelessWidget {
  const DeliveryAreaZoneName({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: DeliveryColors.ink.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: DeliveryColors.white,
          height: 1.2,
        ),
      ),
    );
  }
}

/// The shop: a brand disc with the storefront glyph, named for a screen reader.
class _ShopPin extends StatelessWidget {
  const _ShopPin({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: name,
      child: Container(
        decoration: BoxDecoration(
          color: DeliveryColors.brand,
          shape: BoxShape.circle,
          border: Border.all(color: DeliveryColors.white, width: 2),
          boxShadow: YdCard.softShadow,
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.storefront_rounded, size: 18, color: DeliveryColors.white),
      ),
    );
  }
}

/// The words under the map — and the whole screen when there is no map: the inside/outside line,
/// the circle, the areas, and what the names on the map are.
class DeliveryAreaDetails extends StatelessWidget {
  const DeliveryAreaDetails({
    super.key,
    required this.area,
    required this.address,
    required this.verdict,
    required this.mapShown,
  });

  final ShopDeliveryArea area;
  final DeliveryAddress? address;
  final DeliveryAreaVerdict verdict;

  /// Whether a map is drawn above, which is what the note about the names on it refers to.
  final bool mapShown;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final DeliveryAddress? home = address;
    // Only the areas a customer can still pick. A shop whose areas are all retired shows its circle
    // alone: no list, and no "one of these areas" with nothing under it.
    final List<DeliveryZone> listed = area.shownZones;
    return Padding(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (verdict != DeliveryAreaVerdict.unknown && home != null) ...<Widget>[
            _VerdictLine(inside: verdict == DeliveryAreaVerdict.inside, address: home),
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          ],
          if (area.hasCircle)
            Row(
              children: <Widget>[
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: DeliveryColors.brand.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: DeliveryColors.brand, width: 2),
                  ),
                ),
                const SizedBox(width: DeliverySpacing.sm),
                Expanded(
                  child: Text(
                    t.dareaCircleRule(area.radiusKm),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: DeliveryColors.ink,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          if (area.hasCircle && listed.isNotEmpty)
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          if (listed.isNotEmpty) ...<Widget>[
            Text(
              t.dareaZonesTitle,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.ink,
                height: 1.3,
              ),
            ),
            const SizedBox(height: DeliverySpacing.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final DeliveryZone zone in listed) _ZoneTag(name: zone.name),
              ],
            ),
          ],
          if (area.hasCircle && listed.isNotEmpty) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Text(t.dareaBothRules, style: _note),
          ],
          if (mapShown && area.placedZones.isNotEmpty) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Text(t.dareaZoneLabelsNote, style: _note),
          ],
        ],
      ),
    );
  }

  static const TextStyle _note = TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.35);
}

/// "Your address is inside the delivery area", with the address it is about under it.
class _VerdictLine extends StatelessWidget {
  const _VerdictLine({required this.inside, required this.address});

  final bool inside;
  final DeliveryAddress address;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final DeliveryAccent accent = inside ? DeliveryAccent.positive : DeliveryAccent.critical;
    return Container(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
      decoration: BoxDecoration(
        color: accent.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            inside ? Icons.check_circle_rounded : Icons.do_not_disturb_on_rounded,
            size: 20,
            color: accent.onTint,
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  inside ? t.dareaInside : t.dareaOutside,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: accent.onTint,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  address.display,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One area's name in the list: a label, not a chip — there is nothing to tap.
class _ZoneTag extends StatelessWidget {
  const _ZoneTag({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: DeliveryColors.background,
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
        border: Border.all(color: DeliveryColors.border),
      ),
      child: Text(
        name,
        style: const TextStyle(fontSize: 12, color: DeliveryColors.ink, height: 1.2),
      ),
    );
  }
}

/// What stands where the map would be when the tile server cannot be reached: the page ground and
/// one sentence saying so — the words below the map still say where the shop delivers.
class _MapUnavailable extends StatelessWidget {
  const _MapUnavailable();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DeliveryColors.borderFaint,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(DeliverySpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.map_outlined, size: 22, color: DeliveryColors.faint),
          const SizedBox(height: DeliverySpacing.sm),
          Text(
            DeliveryStrings.of(context).dareaMapUnavailable,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.4),
          ),
        ],
      ),
    );
  }
}
