import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// One selectable role (Figma `role-card-order` 40:1096 and its deliver / sell twins).
///
/// A white card that takes a brand outline and a brand-tinted icon tile when it is the chosen one,
/// so the selection reads at a glance without a separate radio. The Popular pill is drawn only on
/// the role the design badges.
///
/// Its own file because two screens ask the same question in the same words and should look the
/// same doing it: the Create Account screen, and the sheet that asks a Google user whether they are
/// a customer, a rider or a seller before the browser opens. It used to be private to the first;
/// a second copy for the sheet would have been two cards that drift.
class RoleOptionCard extends StatelessWidget {
  const RoleOptionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.popular = false,
  });

  final IconData icon;

  /// Already localised by the caller.
  final String title;

  /// Already localised by the caller.
  final String subtitle;

  final bool selected;
  final bool popular;

  /// Null draws the card inert — while a sign-in is in flight, say.
  final VoidCallback? onTap;

  static const double _radius = 16;

  @override
  Widget build(BuildContext context) {
    final BorderRadius corners = BorderRadius.circular(_radius);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: DeliveryColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: corners,
          side: BorderSide(
            color: selected ? DeliveryColors.brand : DeliveryColors.borderFaint,
            width: selected ? 2 : 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(DeliverySpacing.md),
            child: Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? DeliveryColors.brandSoft
                        : DeliveryColors.borderFaint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 24,
                    color:
                        selected ? DeliveryColors.brand : DeliveryColors.muted,
                  ),
                ),
                const SizedBox(width: DeliverySpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: DeliveryColors.ink,
                                height: 1.2,
                              ),
                            ),
                          ),
                          if (popular) ...<Widget>[
                            const SizedBox(width: DeliverySpacing.sm),
                            const _PopularBadge(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: DeliveryColors.muted,
                          height: 1.35,
                        ),
                      ),
                    ],
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

/// The brand-tinted "Popular" pill on the first role (Figma `badge` 63:40).
class _PopularBadge extends StatelessWidget {
  const _PopularBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: DeliveryColors.brandSoft,
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
      ),
      child: Text(
        DeliveryStrings.of(context).authRolePopular.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: DeliveryColors.brand,
          letterSpacing: 0.5,
          height: 1.1,
        ),
      ),
    );
  }
}
