import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// Account Settings, as the 2026-08 Figma frame `merchant-settings` (3:2194) draws it.
///
/// Top to bottom: a white profile band with a 64px avatar and an `Edit` chip, a full-width language
/// row carrying the EN/AR segmented toggle, then a 24px-padded list of bordered menu rows and the
/// soft destructive "Log Out Account" button.
///
/// Host-agnostic like every other screen in this package: it builds no bottom bar and no rail, and
/// it takes the things only the host knows — who is signed in, where "Shop Profile" leads, how to
/// sign out — as parameters rather than reaching for a session singleton.
///
/// Three of the frame's affordances have no backend behind them yet and are drawn inert rather than
/// wired to something invented: the payout details row, the analytics row, and — unless the host
/// passes [onNotificationSettings] — the notifications row. Each carries the design's own
/// "Soon" chip. Note also that the frame's `Linked` status text beside the payout row is *not*
/// reproduced: there is no payout record to be linked to, and a status that is always "Linked"
/// would be a lie told in a small font.
class MerchantSettingsScreen extends StatelessWidget {
  const MerchantSettingsScreen({
    super.key,
    required this.locale,
    required this.accountName,
    this.accountContact,
    this.onEditAccount,
    this.onShopProfile,
    this.onNotificationSettings,
    this.onSignOut,
  });

  /// Drives the EN/AR toggle. The screen rebuilds with it, so the switch takes effect under the
  /// finger rather than on the next navigation.
  final LocaleController locale;

  /// Who is signed in. The host reads this off the session — this package does not own auth.
  final String accountName;

  /// The second line under the name: a phone number or an email, whichever the host has.
  final String? accountContact;

  /// The `Edit` chip on the profile band. Null draws the chip inert.
  final VoidCallback? onEditAccount;

  /// Opens the shop's own configuration — `StoreScreen` in this package.
  final VoidCallback? onShopProfile;

  /// Opens the host's notification preferences. Null marks the row as not yet available rather
  /// than hiding it, because the frame draws it.
  final VoidCallback? onNotificationSettings;

  /// Ends the session. Null hides the button entirely — a sign-out that does nothing is worse
  /// than no sign-out at all.
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return AnimatedBuilder(
      animation: locale,
      builder: (BuildContext context, _) => Scaffold(
        backgroundColor: DeliveryColors.background,
        body: Column(
          children: <Widget>[
            YdScreenHeader(title: t.merchbAccountSettings),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.topCenter,
                child: ConstrainedBox(
                  // The frame is a phone column. On a portal pane it stays one rather than
                  // stretching a settings row the width of a monitor.
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
                    children: <Widget>[
                      _profileBand(t),
                      _languageRow(t),
                      _options(context, t),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- profile

  Widget _profileBand(DeliveryStrings t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.lg),
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: Row(
        children: <Widget>[
          // No merchant avatar exists in the data model, so the platform's monogram stands in —
          // the same one a shop with no logo gets on the storefront. Clipped to a circle, which is
          // how the frame draws this one.
          ClipOval(
            child: StoreMonogram(name: accountName, size: 64, radius: 0),
          ),
          const SizedBox(width: DeliverySpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  accountName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: DeliverySpacing.xs),
                Text(
                  accountContact == null || accountContact!.isEmpty
                      ? t.merchbRoleOwner
                      : '${t.merchbRoleOwner} • $accountContact',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: DeliveryColors.muted,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          _EditChip(label: t.edit, onPressed: onEditAccount),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- language

  Widget _languageRow(DeliveryStrings t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.lg - DeliverySpacing.xs),
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.language, size: 20, color: DeliveryColors.brand),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Text(
              t.merchbAppLanguage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.ink,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          _LanguageToggle(
            arabic: locale.isArabic,
            englishLabel: t.merchbLangShortEn,
            arabicLabel: t.merchbLangShortAr,
            englishSemanticLabel: t.english,
            arabicSemanticLabel: t.arabic,
            onChanged: (String code) => locale.setLanguage(code),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- options

  Widget _options(BuildContext context, DeliveryStrings t) {
    return Padding(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _MenuRow(
            icon: Icons.storefront_outlined,
            title: t.merchbShopProfile,
            onTap: onShopProfile,
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          // No payout or bank record exists anywhere in the platform yet.
          _MenuRow(
            icon: Icons.credit_card,
            title: t.merchbPaymentBankDetails,
            soonLabel: t.merchbSoon,
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          _MenuRow(
            icon: Icons.notifications_none,
            title: t.merchbNotificationSettings,
            onTap: onNotificationSettings,
            soonLabel: onNotificationSettings == null ? t.merchbSoon : null,
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          // Per-shop analytics are not aggregated by any service today.
          _MenuRow(
            icon: Icons.bar_chart,
            title: t.merchbShopAnalytics,
            soonLabel: t.merchbSoon,
          ),
          if (onSignOut != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            _LogOutButton(
              label: t.merchbLogOutAccount,
              onPressed: () => _confirmSignOut(context, t),
            ),
          ],
        ],
      ),
    );
  }

  /// Signing out of a phone that has no other way back in is worth one question first — the same
  /// one the customer app asks.
  Future<void> _confirmSignOut(BuildContext context, DeliveryStrings t) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: DeliveryColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
        title: Text(t.signOut),
        content: Text(t.signOutConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(foregroundColor: DeliveryColors.muted),
            child: Text(t.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.signOut),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      onSignOut?.call();
    }
  }
}

/// The frame's brand-tinted `Edit` chip.
class _EditChip extends StatelessWidget {
  const _EditChip({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final BorderRadius corners = BorderRadius.circular(DeliveryRadius.md);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: Material(
        color: DeliveryColors.brandSoft,
        borderRadius: corners,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: DeliverySpacing.md - DeliverySpacing.xs,
              vertical: 6,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: onPressed == null ? DeliveryColors.brandLine : DeliveryColors.brand,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The frame's EN/AR segmented control: a background-token track holding a white pill under the
/// active option, lifted by the redesign's card shadow.
///
/// The labels are BCP-47 tags rather than prose, but they still arrive localised — an Arabic build
/// may well want them written differently, and this package holds no strings of its own either way.
class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle({
    required this.arabic,
    required this.englishLabel,
    required this.arabicLabel,
    required this.englishSemanticLabel,
    required this.arabicSemanticLabel,
    required this.onChanged,
  });

  final bool arabic;
  final String englishLabel;
  final String arabicLabel;
  final String englishSemanticLabel;
  final String arabicSemanticLabel;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: DeliveryColors.background,
        borderRadius: BorderRadius.circular(DeliveryRadius.lg + DeliverySpacing.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _segment(
            label: englishLabel,
            semanticLabel: englishSemanticLabel,
            selected: !arabic,
            onTap: () => onChanged('en'),
          ),
          const SizedBox(width: DeliverySpacing.xs),
          _segment(
            label: arabicLabel,
            semanticLabel: arabicSemanticLabel,
            selected: arabic,
            onTap: () => onChanged('ar'),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required String label,
    required String semanticLabel,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final BorderRadius corners = BorderRadius.circular(DeliveryRadius.lg + 2);

    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: corners,
          boxShadow: selected ? YdCard.softShadow : null,
        ),
        child: Material(
          color: selected ? DeliveryColors.white : Colors.transparent,
          borderRadius: corners,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: DeliverySpacing.md,
                vertical: 6,
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? DeliveryColors.brand : DeliveryColors.muted,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One bordered menu row: a 32px icon tile, a SemiBold 14 title, and either a chevron or the
/// design's "Soon" chip where the chevron would be.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.title,
    this.onTap,
    this.soonLabel,
  });

  final IconData icon;

  /// Already localised by the caller.
  final String title;

  final VoidCallback? onTap;

  /// Non-null marks the row as drawn-but-not-yet-working: no chevron, no tap, a chip instead.
  final String? soonLabel;

  @override
  Widget build(BuildContext context) {
    final bool inert = soonLabel != null;

    return YdCard.bordered(
      onTap: inert ? null : onTap,
      child: YdListRow(
        card: false,
        icon: icon,
        title: title,
        titleColor: inert ? DeliveryColors.muted : DeliveryColors.ink,
        iconColor: inert ? DeliveryColors.faint : DeliveryColors.ink,
        onTap: inert ? null : onTap,
        trailing: inert ? YdComingSoon(label: soonLabel!) : null,
      ),
    );
  }
}

/// The frame's soft destructive button: the brand tint as a fill, the stronger tint as a hairline,
/// a 16px glyph and a SemiBold 14 brand label, centred.
class _LogOutButton extends StatelessWidget {
  const _LogOutButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final BorderRadius corners = BorderRadius.circular(DeliveryRadius.lg);

    return Semantics(
      button: true,
      child: Material(
        color: DeliveryColors.brandSoft,
        shape: RoundedRectangleBorder(
          borderRadius: corners,
          // The frame paints this border red-100; the token layer canonicalises that stray to the
          // stronger brand tint, which is what this is.
          side: const BorderSide(color: DeliveryColors.brandSoftStrong),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(Icons.logout, size: 16, color: DeliveryColors.brand),
                const SizedBox(width: DeliverySpacing.sm),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: DeliveryColors.brand,
                      height: 1.2,
                    ),
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
