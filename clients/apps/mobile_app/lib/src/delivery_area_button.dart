import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'delivery_address.dart';
import 'delivery_area_map_screen.dart';
import 'shop_delivery_area.dart';

/// How the "Delivery area" control sits on the page it is dropped into.
enum DeliveryAreaButtonStyle {
  /// A white band with a hairline under it, for a page built of full-width white bands — the
  /// standard shop page under its stat strip, a service provider's page under its identity.
  strip,

  /// A card inset by the page gutter, for the dekkane page, whose hero is an inset card too.
  card,
}

/// The shop page's "Delivery area" control: the map glyph, the words, a one-line summary of the
/// area ("Within 3.0 km of the shop · 4 areas") and a chevron, opening [DeliveryAreaMapScreen].
///
/// It draws nothing at all — not a disabled row — whenever [ShopDeliveryArea.of] finds nothing true
/// to show: before the full store has arrived, for a shop that neither drew a circle nor priced an
/// area, for a store read that did not say which areas the shop serves, and for a service provider
/// none of whose offers is delivered. A control is only drawn when the map behind it has a real
/// area to show.
///
/// Its own file, and one line on each page that shows it, so a page's other work never has to
/// merge around it.
class DeliveryAreaButton extends StatelessWidget {
  const DeliveryAreaButton({
    super.key,
    required this.store,
    this.addresses,
    this.offersDeliver,
    this.style = DeliveryAreaButtonStyle.strip,
  });

  /// The full store, or null while it is still loading — a card carries no areas, so nothing is
  /// drawn from one.
  final Store? store;

  /// Where the customer's chosen address comes from, for the map's "inside/outside" line. Null
  /// draws the area without an address, which is all a page with no address book can offer.
  final DeliveryAddressStore? addresses;

  /// For a service provider: whether any of its offers is delivered. See [ShopDeliveryArea.of].
  final bool? offersDeliver;

  final DeliveryAreaButtonStyle style;

  @override
  Widget build(BuildContext context) {
    final Store? shop = store;
    final ShopDeliveryArea? area =
        shop == null ? null : ShopDeliveryArea.of(shop, offersDeliver: offersDeliver);
    if (area == null) return const SizedBox.shrink();

    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool card = style == DeliveryAreaButtonStyle.card;
    final Widget row = YdListRow(
      icon: Icons.map_outlined,
      title: t.dareaButton,
      subtitle: area.summary(t),
      tileColor: DeliveryColors.brandSoft,
      iconColor: DeliveryColors.brand,
      card: card,
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => DeliveryAreaMapScreen(area: area, addresses: addresses),
      )),
    );

    if (card) {
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
            DeliverySpacing.md, 0, DeliverySpacing.md, DeliverySpacing.md),
        child: row,
      );
    }
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: DeliverySpacing.md, vertical: DeliverySpacing.sm),
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: row,
    );
  }
}
