import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// The customer's bottom bar: six flat destinations, as the services frames draw it.
///
/// Figma `bottom-nav`, extended by the services marketplace (126:285) — Home, Butler, Basket,
/// Services, Orders, Account, in that order, on a white 64px row with a 1px top border and 20px side
/// padding. Each destination is a 24px icon wrapper holding a 20px glyph over an 11px label, active in
/// brand SemiBold and inactive in [DeliveryColors.faint]; the basket keeps the cart glyph and the
/// brand count badge.
///
/// The consequence for callers is the tab *order*: the constants below are the single place that
/// order is written down, and [CustomerShell] builds its stack from them. Services took the fourth
/// seat, so Orders and Account each moved one along — every jump that names them by constant followed
/// without a change.
///
/// The geometry itself lives in [YdBottomNav], shared with the rider and merchant shells so the
/// three bars cannot drift. Six items get about 46dp each on a 320dp phone, and a label that does
/// not fit ellipsises rather than overflowing.
class CustomerNavBar extends StatelessWidget {
  const CustomerNavBar({
    super.key,
    required this.index,
    required this.basketCount,
    required this.onSelected,
  });

  /// The tab order, named. Every jump between tabs goes through one of these rather than through a
  /// literal — a checkout that jumped to "3" was correct only for as long as Orders stayed there,
  /// and it did not, twice.
  static const int homeIndex = 0;
  static const int butlerIndex = 1;
  static const int basketIndex = 2;
  static const int servicesIndex = 3;
  static const int ordersIndex = 4;
  static const int accountIndex = 5;

  /// How many destinations there are. The shell asserts its stack against this.
  static const int tabCount = 6;

  final int index;

  /// Drives the badge on the basket. Zero draws no badge — a zero is noise on a control that
  /// should read as ready.
  final int basketCount;

  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return YdBottomNav(
      currentIndex: index,
      onTap: onSelected,
      items: <YdBottomNavItem>[
        YdBottomNavItem(
          icon: Icons.home_outlined,
          activeIcon: Icons.home_rounded,
          label: t.navHome,
        ),
        // The services frames give Butler a truck — the errand is something carried for you — and
        // hand the briefcase it used to wear to Services.
        YdBottomNavItem(
          icon: Icons.local_shipping_outlined,
          activeIcon: Icons.local_shipping_rounded,
          label: t.navButler,
        ),
        // The design's `nav-tab-Basket` draws a CART, not the bag the storefront cards use — the
        // bag is a shop's, the cart is yours.
        YdBottomNavItem(
          icon: Icons.shopping_cart_outlined,
          activeIcon: Icons.shopping_cart,
          label: t.navBasket,
          badgeCount: basketCount,
        ),
        YdBottomNavItem(
          icon: Icons.work_outline_rounded,
          activeIcon: Icons.work_rounded,
          label: t.svcNavServices,
        ),
        YdBottomNavItem(
          icon: Icons.receipt_long_outlined,
          activeIcon: Icons.receipt_long,
          label: t.navOrders,
        ),
        YdBottomNavItem(
          icon: Icons.person_outline_rounded,
          activeIcon: Icons.person_rounded,
          label: t.navAccount,
        ),
      ],
    );
  }
}
