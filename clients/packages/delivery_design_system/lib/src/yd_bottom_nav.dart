import 'package:flutter/material.dart';

import 'tokens.dart';

/// One destination on [YdBottomNav].
class YdBottomNavItem {
  const YdBottomNavItem({
    required this.icon,
    this.activeIcon,
    required this.label,
    this.badgeCount,
  });

  final IconData icon;

  /// Optional filled variant shown when the item is active.
  final IconData? activeIcon;

  /// Localised label supplied by the caller.
  final String label;

  /// Shows the design's numeric badge (brand circle, white bold digits) when non-null and > 0.
  final int? badgeCount;
}

/// The redesign's flat 64px bottom tab bar (Figma `bottom-nav`, e.g. nodes 3:107, 3:753).
///
/// White, 1px top border, 20px side padding; each item is an icon over an 11px label —
/// active = brand SemiBold, inactive = faint Regular, exactly as the frames draw it. Bottom
/// safe-area inset is added below the 64px row (the drawn home indicator is the device's own).
class YdBottomNav extends StatelessWidget {
  const YdBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<YdBottomNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(top: BorderSide(color: DeliveryColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 20),
            child: Row(
              children: <Widget>[
                for (int i = 0; i < items.length; i++)
                  Expanded(
                    child: _YdBottomNavTab(
                      item: items[i],
                      active: i == currentIndex,
                      onTap: () => onTap(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _YdBottomNavTab extends StatelessWidget {
  const _YdBottomNavTab({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final YdBottomNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = active ? DeliveryColors.brand : DeliveryColors.faint;
    final int? count = item.badgeCount;

    return Semantics(
      selected: active,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                SizedBox.square(
                  dimension: 24,
                  child: Icon(
                    active ? (item.activeIcon ?? item.icon) : item.icon,
                    size: 22,
                    color: color,
                  ),
                ),
                if (count != null && count > 0)
                  PositionedDirectional(
                    top: -4,
                    end: -6,
                    child: Container(
                      height: 16,
                      constraints: const BoxConstraints(minWidth: 16),
                      padding: const EdgeInsetsDirectional.symmetric(horizontal: 5),
                      decoration: const BoxDecoration(
                        color: DeliveryColors.brand,
                        borderRadius:
                            BorderRadius.all(Radius.circular(DeliveryRadius.pill)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: DeliveryColors.white,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: DeliverySpacing.xs),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.1,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
