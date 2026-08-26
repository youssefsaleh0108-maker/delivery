import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

import 'console_chrome.dart';

/// One row in the console's dark rail.
class ConsoleNavEntry {
  const ConsoleNavEntry({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// One console a signed-in account can switch to, as it appears under the wordmark.
///
/// The design draws exactly one console per file — `BACKOFFICE`, `CARRIER HUB` — because it was
/// drawn as separate products. This app merged them behind one Keycloak client, so an account
/// holding several realm roles needs a way across; see [ConsoleSidebar.areas].
class ConsoleArea {
  const ConsoleArea({required this.wordmark, required this.logoIcon});

  /// Rubik Medium 10, uppercase, 1px tracking, crimson. Pass it already spelled how it should read
  /// — this is not upper-cased for you, because "Carrier Hub" and "CARRIER HUB" are different
  /// decisions and the design made one of them.
  final String wordmark;

  /// The glyph in the 32px brand tile. The design uses a package for Backoffice and a truck for
  /// the Carrier Hub — the console's subject, not the company mark.
  final IconData logoIcon;
}

/// The 260px dark rail every console screen mounts beside.
///
/// Figma `sidebar` (3:2488 / 3:3430): [DeliveryColors.shell] ground, 16 across and 24 down, a logo
/// block over the nav list at the top and the user card pinned to the bottom.
///
/// The rail is the whole of the app's navigation — there is no router and no URL, so this widget's
/// [selectedIndex] is the app's location. It is deliberately dumb about what those destinations
/// are: `portal_shell.dart` owns that list, and this owns how it looks.
class ConsoleSidebar extends StatelessWidget {
  const ConsoleSidebar({
    super.key,
    required this.area,
    required this.entries,
    required this.selectedIndex,
    required this.onSelected,
    required this.userName,
    required this.userRole,
    this.areas = const <ConsoleArea>[],
    this.areaIndex = 0,
    this.onAreaSelected,
    this.accountMenu,
  });

  /// The console currently being shown — its wordmark and its logo glyph.
  final ConsoleArea area;

  final List<ConsoleNavEntry> entries;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// The footer card's two lines.
  final String userName;
  final String userRole;

  /// Every console this account can reach. One entry (the common case) renders exactly the design:
  /// a plain wordmark. More than one turns the wordmark into a menu — see the class doc on
  /// [ConsoleArea].
  final List<ConsoleArea> areas;
  final int areaIndex;
  final ValueChanged<int>? onAreaSelected;

  /// Sits at the end of the footer card. The design's footer is user information and nothing else;
  /// the portal's global actions — language, sign out — have no other home once the crimson AppBar
  /// that used to carry them is gone, so they hang here.
  final Widget? accountMenu;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ConsoleMetrics.sidebarWidth,
      color: DeliveryColors.shell,
      padding: const EdgeInsets.symmetric(
        horizontal: DeliverySpacing.md,
        vertical: DeliverySpacing.lg,
      ),
      child: Column(
        // Stretch, not start: the nav rows and the footer card are full-bleed inside the rail's
        // 16px gutters, which is what gives the active row its band rather than a tag.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Logo(
            area: area,
            areas: areas,
            areaIndex: areaIndex,
            onAreaSelected: onAreaSelected,
          ),
          const SizedBox(height: DeliverySpacing.xl),
          // Scrolls rather than overflows: the Backoffice console has eleven destinations against
          // the design's six, and a short laptop window would otherwise clip the last of them.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int i = 0; i < entries.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(height: DeliverySpacing.xs),
                    _NavItem(
                      entry: entries[i],
                      selected: i == selectedIndex,
                      onTap: () => onSelected(i),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: DeliverySpacing.md),
          _UserCard(name: userName, role: userRole, trailing: accountMenu),
        ],
      ),
    );
  }
}

/// The 32px brand tile, the YouDrop wordmark, and the console's name under it.
class _Logo extends StatelessWidget {
  const _Logo({
    required this.area,
    required this.areas,
    required this.areaIndex,
    required this.onAreaSelected,
  });

  final ConsoleArea area;
  final List<ConsoleArea> areas;
  final int areaIndex;
  final ValueChanged<int>? onAreaSelected;

  @override
  Widget build(BuildContext context) {
    final bool switchable = areas.length > 1 && onAreaSelected != null;

    const TextStyle wordmarkStyle = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w500,
      color: DeliveryColors.brand,
      letterSpacing: 1,
    );

    final Widget wordmark = Text(area.wordmark.toUpperCase(), style: wordmarkStyle);

    return Padding(
      padding: const EdgeInsets.only(left: DeliverySpacing.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: DeliveryColors.brand,
              borderRadius: BorderRadius.circular(DeliveryRadius.sm),
            ),
            child: Icon(area.logoIcon, size: 18, color: DeliveryColors.white),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'YouDrop',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.white,
                  height: 1.2,
                ),
              ),
              if (!switchable)
                wordmark
              else
                // The one place this rail departs from the frames, and it is forced: the design is
                // two products, this is one app, and an account with both roles has to be able to
                // cross between them.
                PopupMenuButton<int>(
                  tooltip: 'Switch console',
                  initialValue: areaIndex,
                  onSelected: onAreaSelected,
                  position: PopupMenuPosition.under,
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
                    for (int i = 0; i < areas.length; i++)
                      PopupMenuItem<int>(
                        value: i,
                        child: Row(
                          children: <Widget>[
                            Icon(areas[i].logoIcon,
                                size: 16, color: DeliveryColors.muted),
                            const SizedBox(width: DeliverySpacing.sm),
                            Text(areas[i].wordmark),
                          ],
                        ),
                      ),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      wordmark,
                      const SizedBox(width: 2),
                      const Icon(Icons.expand_more,
                          size: 12, color: DeliveryColors.brand),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One nav row: 12px all round, radius 8, and — when active — a raised ground plus the 4x20 crimson
/// bar hard against the rail's left edge.
class _NavItem extends StatelessWidget {
  const _NavItem({required this.entry, required this.selected, required this.onTap});

  final ConsoleNavEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color foreground =
        selected ? DeliveryColors.white : DeliveryColors.onShellMuted;

    return Material(
      color: selected ? DeliveryColors.shellRaised : Colors.transparent,
      borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        hoverColor: DeliveryColors.shellRaised.withValues(alpha: 0.6),
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
              child: Row(
                children: <Widget>[
                  Icon(entry.icon, size: 18, color: foreground),
                  const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
                  Expanded(
                    child: Text(
                      entry.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Positioned(
                left: 0,
                top: 10,
                child: _ActiveBar(),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActiveBar extends StatelessWidget {
  const _ActiveBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: 20,
      decoration: BoxDecoration(
        color: DeliveryColors.brand,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// The footer card: who is signed in, and what they are.
class _UserCard extends StatelessWidget {
  const _UserCard({required this.name, required this.role, this.trailing});

  final String name;
  final String role;
  final Widget? trailing;

  /// Up to two letters off the display name.
  ///
  /// The design puts a photograph here. Nothing in the token issued by Keycloak carries one, and
  /// inventing an avatar service to fill a 36px circle is not worth a network dependency — so the
  /// circle is drawn in the brand and lettered instead.
  static String initialsOf(String name) {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final String only = parts.first;
      return only.substring(0, only.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
      decoration: BoxDecoration(
        color: DeliveryColors.shellRaised,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: DeliveryColors.brand,
              shape: BoxShape.circle,
            ),
            child: Text(
              initialsOf(name),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: DeliveryColors.white,
              ),
            ),
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.white,
                  ),
                ),
                Text(
                  role,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DeliveryColors.onShellMuted,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
