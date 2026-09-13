import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// The power chip (Figma `shop-power-status`): a dot and a word saying what the lights are doing —
/// mains in green, generator in amber, dark in grey.
///
/// Returns nothing at all for [StorePowerStatus.unknown]: a shop that never declared should not
/// wear a badge it did not earn, and most shops start there. Its words claim the present, so a
/// caller draws it only for a declaration that still counts as now ([StoreCard.powerCurrent]).
class StorePowerChip extends StatelessWidget {
  const StorePowerChip({super.key, required this.status, this.compact = false});

  final StorePowerStatus status;

  /// Dot + word only at a smaller size, for dense rows.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final (String label, Color color, Color bg) = switch (status) {
      StorePowerStatus.mains => (
          t.custPowerMains,
          DeliveryAccent.positive.color,
          DeliveryAccent.positive.color.withValues(alpha: 0.12),
        ),
      StorePowerStatus.generator => (
          t.custPowerGenerator,
          const Color(0xFFB8860B),
          const Color(0xFFFDF3D7),
        ),
      StorePowerStatus.dark => (
          t.custPowerDark,
          DeliveryColors.muted,
          DeliveryColors.border,
        ),
      StorePowerStatus.unknown => ('', Colors.transparent, Colors.transparent),
    };
    if (status == StorePowerStatus.unknown) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsetsDirectional.symmetric(
          horizontal: compact ? 7 : 9, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: compact ? 4 : 5),
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w700,
              color: color,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Whether a shop's card or pin on the neighbourhood surfaces is dimmed: it is closed right now, or
/// its merchant currently says it is dark.
///
/// Dimmed, never hidden — a customer looking for a particular shop needs to be told it is shut, not
/// left wondering why it vanished. A dark declaration too old to count as now dims nothing, for the
/// reason [DekkanePowerPill] draws nothing for it.
bool dekkaneDimmed(StoreCard store) =>
    store.availability == StoreAvailability.closed ||
    (store.powerCurrent && store.powerStatus == StorePowerStatus.dark);

/// "Updated 20 min ago" — how long ago the merchant declared what the lights are doing.
///
/// Measured on this device's clock, which can run a little ahead of or behind the server's; a
/// declaration that seems to come from the future reads "just now" rather than a negative age.
String dekkanePowerAge(DeliveryStrings t, DateTime declaredAt, {DateTime? now}) {
  final Duration age = (now ?? DateTime.now()).difference(declaredAt);
  if (age.inMinutes < 60) {
    return t.dekkanePowerUpdatedMinutes(age.isNegative ? 0 : age.inMinutes);
  }
  return t.dekkanePowerUpdatedHours(age.inHours);
}

/// The dekkane frames' power pill (112:1941 on the card, 112:2041 on the shop's hero): "⚡ Generator
/// active" in the brand, and the grey "Currently dark" for a shop that has declared it has no power.
/// [DekkanePowerAge] goes with it, saying how long ago the merchant said so.
///
/// Worded as what is happening NOW, so it is drawn only while the declaration can honestly be called
/// that ([shows]): [StoreCard.powerCurrent], which the server works out with its configured window
/// (four hours unless `delivery.product.power-declaration-fresh-for` says otherwise) — the same
/// answer the "On generator now" chip filters on. `power_status` is the merchant's latest
/// declaration, not a fact about what the shop owns. Mains and undeclared draw nothing — mains is
/// the normal state and not worth a badge on this frame, and a shop that never said should not wear
/// one it did not earn.
///
/// [solid] is the hero's version, a filled pill that survives a photograph behind it; the card's is
/// the brand-soft one.
class DekkanePowerPill extends StatelessWidget {
  const DekkanePowerPill({super.key, required this.store, this.solid = false});

  final StoreCard store;
  final bool solid;

  /// Whether a shop wears the pill at all: a current declaration of a generator, or of the dark.
  static bool shows(StoreCard store) =>
      store.powerCurrent &&
      (store.powerStatus == StorePowerStatus.generator ||
          store.powerStatus == StorePowerStatus.dark);

  @override
  Widget build(BuildContext context) {
    if (!shows(store)) return const SizedBox.shrink();
    final DeliveryStrings t = DeliveryStrings.of(context);
    final (String label, Color fg, Color bg, IconData? icon) = switch (store.powerStatus) {
      StorePowerStatus.generator => solid
          ? (t.dekkaneGeneratorActive, DeliveryColors.white, DeliveryColors.brand, Icons.bolt_rounded)
          : (t.dekkaneGeneratorActive, DeliveryColors.brand, DeliveryColors.brandSoft,
              Icons.bolt_rounded),
      StorePowerStatus.dark => solid
          ? (t.custPowerDark, DeliveryColors.white, DeliveryColors.muted, null)
          : (t.custPowerDark, DeliveryColors.muted, DeliveryColors.border, null),
      StorePowerStatus.mains || StorePowerStatus.unknown =>
        ('', Colors.transparent, Colors.transparent, null),
    };
    if (label.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsetsDirectional.symmetric(horizontal: solid ? 8 : 6, vertical: solid ? 4 : 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(solid ? DeliveryRadius.sm : 4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 2),
          ],
          // Shortens rather than overflows when a row gives the pill less than its words need.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: solid ? FontWeight.w700 : FontWeight.w600,
                color: fg,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// How long ago the merchant declared what [DekkanePowerPill] says — "Updated 2 hrs ago" — for the
/// line under the pill, and nothing wherever the pill is not drawn.
///
/// The age keeps even a current badge honest: a generator declared three hours ago reads as three
/// hours old. It is its own widget so a card can set it on a line of its own below the pill's row;
/// stacked inside the pill's column it widened the column in any language where it runs longer
/// than the pill, and took that width from the distance beside it.
class DekkanePowerAge extends StatelessWidget {
  const DekkanePowerAge({super.key, required this.store, this.onPhoto = false});

  final StoreCard store;

  /// White, for the hero's photograph; muted on a card.
  final bool onPhoto;

  @override
  Widget build(BuildContext context) {
    final DateTime? declaredAt = store.powerUpdatedAt;
    if (declaredAt == null || !DekkanePowerPill.shows(store)) return const SizedBox.shrink();
    return Text(
      dekkanePowerAge(DeliveryStrings.of(context), declaredAt),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: onPhoto ? DeliveryColors.white : DeliveryColors.muted,
        height: 1.2,
      ),
    );
  }
}

/// The dekkane frames' availability pill: the hero's "Open · Closes 10:00 PM" (112:2041), and on a
/// neighbourhood card's cover the "Closing soon", "Busy" or "Closed" the browse frame (112:1941)
/// never had to draw because it only drew open shops.
///
/// The fills are the accent tokens' dark stops, not the frame's bright emerald: under an 11px white
/// label the emerald measures about 2.5:1, which the token system rules out for words, and its -700
/// stop clears 4.5:1. Busy and closing-soon share the amber's; closed is the muted grey, because
/// closed is an absence, not a warning. Solid, unlike the storefront's tinted [StoreStatePill],
/// because both places this one sits are photographs.
class DekkaneStatePill extends StatelessWidget {
  const DekkaneStatePill({super.key, required this.availability, this.closesAt});

  final StoreAvailability availability;

  /// The closing time in the reader's own clock format, for an open shop's "Open · Closes 10:00 PM".
  /// Null reads the availability alone.
  final String? closesAt;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String label = availability == StoreAvailability.open && closesAt != null
        ? t.dekkaneOpenClosesAt(closesAt!)
        : availability.labelIn(t);
    final Color fill = switch (availability) {
      StoreAvailability.open => DeliveryAccent.positive.onTint,
      StoreAvailability.busy || StoreAvailability.closingSoon => DeliveryAccent.caution.onTint,
      StoreAvailability.closed => DeliveryColors.muted,
    };

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: DeliveryColors.white,
          height: 1.2,
        ),
      ),
    );
  }
}

/// The dekkane frames' "Trusted local" badge — the Backoffice-granted `verified_local`, drawn as
/// the frame draws it: brand on brand-soft, small and square-cornered, beside the shop's name.
class TrustedLocalBadge extends StatelessWidget {
  const TrustedLocalBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: DeliveryColors.brandSoft,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        DeliveryStrings.of(context).dekkaneTrustedLocal,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: DeliveryColors.brand,
          height: 1.2,
        ),
      ),
    );
  }
}
