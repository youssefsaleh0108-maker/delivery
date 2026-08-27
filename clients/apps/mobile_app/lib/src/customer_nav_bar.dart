import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// The customer's bottom bar: five flat destinations, as the redesign draws them.
///
/// Figma `bottom-nav`, node 3:107 — Home, Orders, Butler, Basket, Account, in that order, on a
/// white 64px row with a 1px top border and 20px side padding. Each destination is a 24px icon
/// wrapper holding a 20px glyph over an 11px label, active in brand SemiBold and inactive in
/// [DeliveryColors.faint]; the basket carries the brand count badge.
///
/// This replaces the raised centre basket. That bar was a deliberate argument — the basket is the
/// one destination somebody reaches for mid-thought, so make it findable without looking — and the
/// owner's design answers it differently: five equal destinations, with the basket third from the
/// end rather than in the middle. Applied as designed. The consequence for callers is the tab
/// *order*, which changed with it: the constants below are the single place that order is written
/// down, and [CustomerShell] builds its stack from them.
///
/// The geometry itself lives in [YdBottomNav], shared with the rider and merchant shells so the
/// three bars cannot drift.
class CustomerNavBar extends StatelessWidget {
  const CustomerNavBar({
    super.key,
    required this.index,
    required this.basketCount,
    required this.onSelected,
  });

  /// The tab order, named. Every jump between tabs goes through one of these rather than through a
  /// literal — a checkout that jumped to "3" was correct only for as long as Orders stayed there,
  /// and it did not.
  static const int homeIndex = 0;
  static const int ordersIndex = 1;
  static const int butlerIndex = 2;
  static const int basketIndex = 3;
  static const int accountIndex = 4;

  /// How many destinations there are. The shell asserts its stack against this.
  static const int tabCount = 5;

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
        YdBottomNavItem(
          icon: Icons.receipt_long_outlined,
          activeIcon: Icons.receipt_long,
          label: t.navOrders,
        ),
        // The frame's Butler glyph is a briefcase — the concierge's bag, not a bicycle. The bar
        // used to draw a bike here, which is the rider's vehicle rather than the errand service.
        YdBottomNavItem(
          icon: Icons.work_outline_rounded,
          activeIcon: Icons.work_rounded,
          label: t.navButler,
        ),
        YdBottomNavItem(
          icon: Icons.shopping_bag_outlined,
          activeIcon: Icons.shopping_bag,
          label: t.navBasket,
          badgeCount: basketCount,
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
