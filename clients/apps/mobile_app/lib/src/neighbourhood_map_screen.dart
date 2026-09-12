import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'address_sheet.dart' show OsmBasemap;

/// The neighbourhood browse's map, full screen (the frame's "Expand interactive map", 112:1941):
/// the customer's pinned address and a pin for each shop the browse has loaded, every pin opening
/// that shop.
///
/// It draws the shops it is handed rather than asking the server again. The browse has already
/// fetched them around the same point, with the same chip applied, so the map and the list below it
/// are by construction the same answer — a map that re-queried could show a shop the list filtered
/// out, and the customer would reasonably wonder which one was right.
///
/// On [OsmBasemap] like every map the customer sees, so the tile source, the licence credit and the
/// dead-tiles fallback are the platform's one implementation rather than a fourth copy.
class NeighbourhoodMapScreen extends StatelessWidget {
  const NeighbourhoodMapScreen({
    super.key,
    required this.home,
    required this.shops,
    required this.onOpenShop,
  });

  /// The customer's pinned address — what every distance on the browse was measured from.
  final LatLng home;

  final List<NearbyStore> shops;

  /// Opens a shop from its pin, the same way a card on the browse does.
  final void Function(StoreCard store) onOpenShop;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(
        title: t.dekkaneMapTitle,
        onBack: () => Navigator.of(context).maybePop(),
        backSemanticLabel: t.back,
      ),
      body: OsmBasemap(
        options: MapOptions(
          initialCameraFit: CameraFit.coordinates(
            coordinates: <LatLng>[
              home,
              for (final NearbyStore shop in shops) LatLng(shop.latitude, shop.longitude),
            ],
            padding: const EdgeInsets.all(48),
            // One shop in the same building as the address would otherwise fit at the deepest zoom
            // the projection allows — a single grey street corner.
            maxZoom: 17,
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
          MarkerLayer(
            markers: <Marker>[
              Marker(
                point: home,
                width: 34,
                height: 34,
                child: Semantics(
                  label: t.custYourAddress,
                  child: const Icon(Icons.place, size: 30, color: DeliveryColors.ink),
                ),
              ),
              for (final NearbyStore shop in shops)
                Marker(
                  point: LatLng(shop.latitude, shop.longitude),
                  width: NeighbourhoodShopPin.size,
                  height: NeighbourhoodShopPin.size,
                  child: NeighbourhoodShopPin(
                    store: shop.store,
                    onTap: () => onOpenShop(shop.store),
                  ),
                ),
            ],
          ),
        ],
        fallback: const NeighbourhoodMapUnavailable(),
      ),
    );
  }
}

/// A shop on the neighbourhood map: a brand disc with the storefront glyph, named for a screen
/// reader, and dimmed when the shop has declared itself dark — the same honest-not-hidden rule the
/// list's cards follow.
class NeighbourhoodShopPin extends StatelessWidget {
  const NeighbourhoodShopPin({super.key, required this.store, this.onTap});

  final StoreCard store;
  final VoidCallback? onTap;

  static const double size = 36;

  @override
  Widget build(BuildContext context) {
    final Widget disc = Container(
      decoration: BoxDecoration(
        color: DeliveryColors.brand,
        shape: BoxShape.circle,
        border: Border.all(color: DeliveryColors.white, width: 2),
        boxShadow: YdCard.softShadow,
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.storefront_rounded, size: 18, color: DeliveryColors.white),
    );
    return Semantics(
      button: onTap != null,
      label: store.name,
      child: GestureDetector(
        onTap: onTap,
        child: store.powerStatus == StorePowerStatus.dark
            ? Opacity(opacity: 0.55, child: disc)
            : disc,
      ),
    );
  }
}

/// What stands where the map would be when the tile server cannot be reached: the page ground and
/// one sentence saying so, rather than a grey lattice of missing squares.
class NeighbourhoodMapUnavailable extends StatelessWidget {
  const NeighbourhoodMapUnavailable({super.key, this.compact = false});

  /// The 100px preview's version: the sentence alone, smaller.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Container(
      color: DeliveryColors.borderFaint,
      alignment: Alignment.center,
      padding: EdgeInsets.all(compact ? DeliverySpacing.sm : DeliverySpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (!compact) ...<Widget>[
            const Icon(Icons.map_outlined, size: 22, color: DeliveryColors.faint),
            const SizedBox(height: DeliverySpacing.sm),
          ],
          Text(
            t.custMapUnavailable,
            textAlign: TextAlign.center,
            maxLines: compact ? 2 : null,
            overflow: compact ? TextOverflow.ellipsis : null,
            style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.4),
          ),
        ],
      ),
    );
  }
}
