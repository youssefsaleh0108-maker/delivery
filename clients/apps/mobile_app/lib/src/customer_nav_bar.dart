import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// The bottom bar, with the basket raised out of it.
///
/// Five flat icons say the five destinations are equally important, and they are not: the basket is
/// the only one that carries state the customer is part-way through, and the only one they reach for
/// mid-thought while looking at a shelf. So it is bigger, round, centred and lifted clear of the
/// bar — the shape a thumb finds without the eye having to.
///
/// Built rather than themed because NavigationBar sizes every destination identically by design.
/// The whole control still lives inside one [SizedBox]: a circle drawn outside its parent's bounds
/// paints fine and then silently fails to take taps in the overhanging half.
class CustomerNavBar extends StatelessWidget {
  const CustomerNavBar({
    super.key,
    required this.index,
    required this.basketCount,
    required this.onSelected,
  });

  /// The basket's index in the shell's IndexedStack. The bar is built around it.
  static const int basketIndex = 2;

  static const double _barHeight = 62;
  static const double _buttonSize = 64;

  /// Total height: the bar, plus the part of the button standing above it, plus room for the
  /// basket's own label below the circle.
  static const double _height = 88;

  final int index;
  final int basketCount;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return SafeArea(
      top: false,
      child: SizedBox(
        height: _height,
        child: Stack(
          children: <Widget>[
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _barHeight,
              child: Container(
                decoration: BoxDecoration(
                  color: DeliveryColors.white,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(DeliveryRadius.lg + 4)),
                  boxShadow: DeliveryShadows.raised,
                ),
                child: Row(
                  children: <Widget>[
                    _tab(t.navShops, Icons.storefront_outlined, Icons.storefront, 0),
                    // Second, next to Shops: Butler is the other way into the app, not an
                    // afterthought buried past the basket.
                    _tab(t.navButler, Icons.pedal_bike_outlined, Icons.pedal_bike, 1),
                    // The gap the basket button sits in.
                    const SizedBox(width: _buttonSize + DeliverySpacing.md),
                    _tab(t.navOrders, Icons.receipt_long_outlined, Icons.receipt_long, 3),
                    _tab(t.navAccount, Icons.person_outline_rounded, Icons.person, 4),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Center(child: _basketButton(context, t)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab(String label, IconData icon, IconData selectedIcon, int at) {
    final bool selected = index == at;
    return Expanded(
      child: InkWell(
        onTap: () => onSelected(at),
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(selected ? selectedIcon : icon,
                size: 22, color: selected ? DeliveryColors.brand : DeliveryColors.muted),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? DeliveryColors.brand : DeliveryColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _basketButton(BuildContext context, DeliveryStrings t) {
    final bool selected = index == basketIndex;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onSelected(basketIndex),
            child: Container(
              width: _buttonSize,
              height: _buttonSize,
              // Explicit, and load-bearing. A fixed-size Container with no alignment hands its child
              // tight constraints, which an Icon centres itself inside — but a Badge lays its child
              // out top-start, so the moment the basket had something in it the bag jumped into the
              // corner of the circle.
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: selected
                      ? const <Color>[DeliveryColors.brandDark, DeliveryColors.brandDark]
                      : const <Color>[DeliveryColors.brand, DeliveryColors.brandDark],
                ),
                // A white ring so the circle reads as sitting *above* the bar rather than punched
                // through it, on both the bar and the page behind it.
                border: Border.all(color: DeliveryColors.white, width: 3),
                boxShadow: DeliveryShadows.raised,
              ),
              child: Badge(
                isLabelVisible: basketCount > 0,
                label: Text('$basketCount', style: const TextStyle(fontSize: 10)),
                backgroundColor: DeliveryColors.ink,
                textColor: DeliveryColors.white,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                offset: const Offset(2, -2),
                child: const Icon(Icons.shopping_bag_rounded,
                    size: 27, color: DeliveryColors.white),
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          t.navBasket,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
            color: selected ? DeliveryColors.brand : DeliveryColors.ink,
          ),
        ),
      ],
    );
  }
}
