import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'rider_job_card.dart';

/// The rider-specific sections of Figma `rider-settings` (3:1591), as parts rather than a screen.
///
/// They live here, separately, because the design draws one Driver Settings page but the app has a
/// shared settings screen that every role reaches — language and fingerprint unlock are the same
/// two questions whoever is asking. So these are the rider's *extra* blocks, consumable from the
/// rider shell's Settings tab and from `settings_screen.dart` alike, and neither owns the other.
///
/// Most of what the design puts here has no backend: a rider's account carries no vehicle, no
/// documents, no bank details, no rating, and there is no presence service for a duty toggle to
/// switch. Each is drawn where the design puts it and marked inert, because a settings page padded
/// with switches that are not wired to anything is worse than a short one.

/// `profile-card`: who the rider is, at the top of their own settings.
///
/// The design shows a photographed avatar, a vehicle-and-plate line and a lifetime rating. The
/// account carries none of the three — the onboarding application stores a name, an email and a
/// phone and nothing about a vehicle — so the avatar is drawn from initials, and the two lines
/// underneath say so instead of inventing a motorcycle.
class RiderProfileCard extends StatelessWidget {
  const RiderProfileCard({super.key, required this.name, this.subtitle});

  final String name;

  /// A real second line if the caller has one (an email, a reference). Null draws the inert
  /// vehicle row the design asks for.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return YdCard(
      child: Row(
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: DeliveryColors.brandSoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              _initials(name),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: DeliveryColors.brand,
                height: 1,
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: DeliverySpacing.xs),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DeliveryColors.muted,
                      height: 1.3,
                    ),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.two_wheeler_outlined,
                          size: 14, color: DeliveryColors.faint),
                      const SizedBox(width: DeliverySpacing.xs),
                      Text(
                        t.riderVehicleProfile,
                        style: const TextStyle(
                          fontSize: 12,
                          color: DeliveryColors.muted,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(width: DeliverySpacing.sm),
                      YdComingSoon(label: t.riderComingSoon),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}

/// The compact radius-12 row the design uses for the duty toggle and the language row.
///
/// Not [YdListRow]: that one is a radius-16 card with a chevron, and this is the shorter shell the
/// rider settings body puts its two switch-ish rows in.
class RiderSettingRow extends StatelessWidget {
  const RiderSettingRow({
    super.key,
    required this.icon,
    required this.label,
    required this.trailing,
    this.subtitle,
    this.tint = DeliveryColors.background,
    this.iconColour = DeliveryColors.ink,
    this.onTap,
  });

  final IconData icon;
  final String label;

  /// A muted 11px second line under the label — the duty row's "last seen" fact. Null draws the
  /// single-line row every other caller has always had.
  final String? subtitle;

  final Widget trailing;
  final Color tint;
  final Color iconColour;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget row = Padding(
      padding: const EdgeInsets.all(DeliverySpacing.md),
      child: Row(
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: iconColour),
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: DeliveryColors.muted,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          trailing,
        ],
      ),
    );

    return Semantics(
      button: onTap != null,
      child: Material(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? row : InkWell(onTap: onTap, child: row),
      ),
    );
  }
}

/// `availability-card`: the online/offline switch, wired to the presence API.
///
/// A view, not a caller: the screen that owns the timers and the simulated GPS fix
/// (`rider_home_screen.dart`) owns the presence too, and hands this card the server's last answer.
/// The switch renders what the rider *declared* and the tag beside it what the platform *believes*
/// — a rider who declared duty and then went quiet is [PresenceState.stale], and the card says
/// "signal lost" instead of showing them as available for work they will not receive.
class RiderDutyToggleCard extends StatelessWidget {
  const RiderDutyToggleCard({
    super.key,
    this.wired = false,
    this.presence,
    this.busy = false,
    this.onChanged,
  });

  /// Whether a presence API was handed to the shell at all. False keeps the pre-wiring inert
  /// rendering, chip and all, rather than a switch that would silently do nothing.
  final bool wired;

  /// The server's last answer. Null while it has not answered yet — also the answer a rider who
  /// has never declared duty gets (a 204, not an invented OFF_DUTY).
  final RiderPresence? presence;

  /// True while a declaration is in flight; the switch refuses input rather than lying about
  /// where it will land.
  final bool busy;

  /// Called with the state the rider asked for. The card never assumes the tap worked — the
  /// owner re-renders it with whatever the server said.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    if (!wired) {
      return RiderSettingRow(
        icon: Icons.power_settings_new_rounded,
        tint: DeliveryColors.brandSoft,
        iconColour: DeliveryColors.brand,
        label: t.riderActiveDuty,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            YdComingSoon(label: t.riderComingSoon),
            const SizedBox(width: DeliverySpacing.sm),
            IgnorePointer(
              child: ExcludeSemantics(
                child: Switch.adaptive(
                  value: true,
                  onChanged: (_) {},
                  activeThumbColor: DeliveryColors.white,
                  activeTrackColor: DeliveryColors.brand,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final bool declaredOn = presence?.dutyState == DutyState.onDuty;
    final bool stale = presence?.state == PresenceState.stale;

    return RiderSettingRow(
      icon: Icons.power_settings_new_rounded,
      tint: DeliveryColors.brandSoft,
      iconColour: DeliveryColors.brand,
      label: t.riderActiveDuty,
      subtitle: _subtitle(context, t),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (stale)
            RiderTag(
              label: t.presenceSignalLost,
              color: DeliveryAccent.caution.color,
              background: DeliveryAccent.caution.tint,
            )
          else if (presence != null)
            RiderTag(
              label: declaredOn ? t.dutyOnDuty : t.dutyOffDuty,
              color: declaredOn
                  ? DeliveryAccent.positive.color
                  : DeliveryColors.muted,
              background: declaredOn
                  ? DeliveryAccent.positive.tint
                  : DeliveryColors.background,
            ),
          const SizedBox(width: DeliverySpacing.sm),
          Switch.adaptive(
            value: declaredOn,
            onChanged:
                busy || onChanged == null ? null : (bool on) => onChanged!(on),
            activeThumbColor: DeliveryColors.white,
            activeTrackColor: DeliveryColors.brand,
          ),
        ],
      ),
    );
  }

  /// The last-seen line: when the platform last heard from this device, or the honest sentence
  /// for a rider it has never heard from at all.
  String? _subtitle(BuildContext context, DeliveryStrings t) {
    if (presence == null) return t.riderDutyNotYetDeclared;
    final DateTime? seen = presence!.lastSeenAt;
    if (seen == null) return null;
    final String? age = riderAgeLabel(t, seen);
    return age == null ? null : t.riderLastSeen(age);
  }
}

/// `lang-card`: the language row, showing what is set and opening the place it is changed.
class RiderLanguageRow extends StatelessWidget {
  const RiderLanguageRow({
    super.key,
    required this.value,
    required this.onTap,
  });

  /// The current language, written in its own script.
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RiderSettingRow(
      icon: Icons.language_rounded,
      label: DeliveryStrings.of(context).riderAppLanguage,
      onTap: onTap,
      trailing: Text(
        value,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: DeliveryColors.brand,
          height: 1.2,
        ),
      ),
    );
  }
}

/// One row inside [RiderPreferencesGroup].
class RiderPreference {
  const RiderPreference({
    required this.icon,
    required this.label,
    this.onTap,
    this.inert = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// Draws the "coming soon" chip in place of the chevron.
  final bool inert;
}

/// `preferences`: one clipped white group, rows divided by hairlines.
///
/// The design lists Documents & Licenses, Bank Account Details, Notification Preferences and
/// Help & Live Chat Support. Only the shape of the group is load-bearing here — the caller decides
/// which rows go in it and which of them lead anywhere.
class RiderPreferencesGroup extends StatelessWidget {
  const RiderPreferencesGroup({super.key, required this.rows});

  final List<RiderPreference> rows;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool rtl = Directionality.of(context) == TextDirection.rtl;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < rows.length; i++) ...<Widget>[
            if (i > 0) const RiderHairline(),
            Semantics(
              button: rows[i].onTap != null,
              enabled: !rows[i].inert,
              child: InkWell(
                onTap: rows[i].inert ? null : rows[i].onTap,
                child: Padding(
                  padding: const EdgeInsets.all(DeliverySpacing.md),
                  child: Row(
                    children: <Widget>[
                      Icon(rows[i].icon,
                          size: 18, color: DeliveryColors.ink),
                      const SizedBox(
                          width: DeliverySpacing.md - DeliverySpacing.xs),
                      Expanded(
                        child: Text(
                          rows[i].label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: DeliveryColors.ink,
                            height: 1.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: DeliverySpacing.sm),
                      if (rows[i].inert)
                        YdComingSoon(label: t.riderComingSoon)
                      else
                        Icon(
                          rtl ? Icons.chevron_left : Icons.chevron_right,
                          size: 16,
                          color: DeliveryColors.faint,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `logout-btn`: the outlined destructive button that ends the session.
class RiderLogOutButton extends StatelessWidget {
  const RiderLogOutButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: RiderButton(
        label: DeliveryStrings.of(context).signOut,
        style: RiderButtonStyle.outlined,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        verticalPadding: 14,
        onPressed: onPressed,
      ),
    );
  }
}
