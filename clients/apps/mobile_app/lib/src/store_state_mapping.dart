import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

/// Bridges the wire enums onto the design system's presentational ones.
///
/// The design system depends on nothing but Flutter so it can be dropped into any client, which
/// means it cannot see `StoreAvailability`. This file is the one place the two vocabularies meet —
/// keeping it here rather than scattering `switch` statements through the screens means a new state
/// added to either side fails to compile in exactly one place.

DeliveryStoreState storeStateOf(StoreAvailability availability) => switch (availability) {
      StoreAvailability.open => DeliveryStoreState.open,
      StoreAvailability.busy => DeliveryStoreState.busy,
      StoreAvailability.closingSoon => DeliveryStoreState.closingSoon,
      StoreAvailability.closed => DeliveryStoreState.closed,
    };

/// The icon for a vertical in the switcher. Chosen to be distinguishable at 15px, which rules out
/// most of the more literal options.
IconData iconForVertical(StoreVertical vertical) => switch (vertical) {
      StoreVertical.restaurant => Icons.restaurant_rounded,
      StoreVertical.coffee => Icons.local_cafe_rounded,
      StoreVertical.grocery => Icons.local_grocery_store_rounded,
      StoreVertical.convenience => Icons.storefront_rounded,
      StoreVertical.pharmacy => Icons.local_pharmacy_rounded,
      StoreVertical.electronics => Icons.headphones_rounded,
      StoreVertical.flowersGifts => Icons.card_giftcard_rounded,
    };
