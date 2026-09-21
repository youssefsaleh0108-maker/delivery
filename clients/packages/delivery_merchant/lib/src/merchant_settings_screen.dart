import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'merchant_analytics_screen.dart';
import 'merchant_payout_screen.dart';
import 'merchant_statement_screen.dart';

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
/// Shop Analytics is live: Order Manager aggregates a shop's own daily series now, and the row
/// opens [MerchantAnalyticsScreen] as soon as the host hands over an [AggregatesApi].
///
/// Payment & Bank details is live too, and the note that used to sit here is worth keeping as a
/// correction. It said no merchant payout or bank record exists anywhere on the platform, reading
/// the accounting service — whose payout side really is rider cash-outs only — and concluding
/// there was nothing to show. The record was in onboarding all along: every partner gives an
/// account holder and an IBAN on the wizard's bank step, and the endpoint that reads it back
/// resolves the application from the caller's token rather than from a role. See
/// [MerchantPayoutScreen]. The frame's `Linked` status text beside the row is still *not*
/// reproduced — the record carries its own verification state, and that is what the page shows
/// rather than a word that would always say the same thing.
///
/// Your statement is the newest row and the only one the Figma frame does not draw: it opens
/// [MerchantStatementScreen], which is the ledger's own answer to "what am I owed". It appears only
/// when the host wires the client — see [statements] for why that is a hidden row rather than a
/// "Soon" one.
///
/// Every remaining "Soon" chip on this screen is now a statement about the *host's* wiring — a
/// null [aggregates], [documents] or [onNotificationSettings] — and not about the platform.
class MerchantSettingsScreen extends StatelessWidget {
  const MerchantSettingsScreen({
    super.key,
    required this.locale,
    required this.accountName,
    this.accountContact,
    this.onEditAccount,
    this.onShopProfile,
    this.onShareShop,
    this.onShopMessages,
    this.shopMessagesUnread,
    this.onServiceOrders,
    this.onServiceOffers,
    this.onCategories,
    this.onStaff,
    this.onStockCount,
    this.onCatalogScan,
    this.onNotificationSettings,
    this.aggregates,
    this.documents,
    this.statements,
    this.onDemandRadar,
    this.onSwitchToShopping,
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

  /// Opens the shop's page, its QR code and its printable poster — `ShopShareScreen` in this
  /// package. Absent, not disabled, when the host has not wired it, like the rows below: which
  /// shop's page this is comes from "shops you own", so it is an owner's row and an employee
  /// should not see a door they cannot open.
  final VoidCallback? onShareShop;

  /// Opens the shop's conversations with customers ([ShopInboxScreen]). Right under the shop's own
  /// profile, because both are the shop as customers meet it. Absent, not disabled, when the host has
  /// no chat client — the same contract as the management rows below.
  final VoidCallback? onShopMessages;

  /// How many customer messages are unread, drawn on the messages row while above zero — the one
  /// sign on this screen that a customer wrote. The host keeps it current (`ShopUnreadCount`); null
  /// draws no number, because an unknown count is not a zero.
  final ValueListenable<int?>? shopMessagesUnread;

  /// A services shop's queue and its offers, for an owner who also runs a goods shop and so works in
  /// the goods shell. Under the shop's own rows, because a service order is a customer waiting. Null
  /// hides each row: an owner of one kind of shop has nowhere else to go.
  final VoidCallback? onServiceOrders;
  final VoidCallback? onServiceOffers;

  /// The merchant suite's three management pages, hung off Settings rather than given a tab
  /// each: a shop reorganises its shelves and its roster a few times a year, not a few times a
  /// day, and the nav is for the few-times-a-day things. Each row is absent, not disabled, when
  /// its host does not wire it — the same contract the statement row keeps — so an employee
  /// without the permission never sees a door they cannot open.
  final VoidCallback? onCategories;
  final VoidCallback? onStaff;
  final VoidCallback? onStockCount;

  /// Merchant Blitz: builds the catalogue from shelf photos. Absent, not disabled, when unwired —
  /// the host leaves it null for anyone the server would refuse, which is everyone but the owner.
  final VoidCallback? onCatalogScan;

  /// Opens the host's notification preferences. Null marks the row as not yet available rather
  /// than hiding it, because the frame draws it.
  final VoidCallback? onNotificationSettings;

  /// Opens Shop Analytics. Optional only because a host that has not wired the daily-series
  /// client cannot open a screen that is nothing but the series; when it is null the row keeps the
  /// design's "Soon" chip rather than leading to an empty page.
  final AggregatesApi? aggregates;

  /// The onboarding documents-and-payout client, behind the Payment & Bank details row. Null
  /// leaves that row marked as not yet available, which is now a statement about the host's
  /// wiring rather than about the platform.
  final DocumentsApi? documents;

  /// The counterparty-statements client, behind the Statement row.
  ///
  /// Null *hides* the row rather than marking it "Soon", which is the opposite of what the two
  /// rows above do — and deliberately. Those rows are drawn on the Figma frame, so their absence
  /// would be a regression against a design somebody signed off; this one is not on the frame at
  /// all, so a host that has not wired it is simply a host that does not offer the page. A "Soon"
  /// chip on a row the design never drew would promise a shop something no roadmap has agreed.
  final StatementsApi? statements;

  /// Opens the Demand Radar, beside Shop Analytics.
  ///
  /// A host callback rather than a client, because the radar needs the shop's id and only the host
  /// knows it. Null hides the row, like the statement row and for the same reason: the settings
  /// frame does not draw it, so an unwired host simply does not offer it. The host wires it for the
  /// owner only.
  final VoidCallback? onDemandRadar;

  /// Takes an owner who is also a customer to the customer app — the shop's half of the role switch.
  /// Null hides the row: an account with no customer role has nowhere to switch to.
  final VoidCallback? onSwitchToShopping;

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
          // Beside Shop Profile, because it is about the same shop and a merchant looking for
          // "where do customers find me" looks here first. Its own row rather than a corner of the
          // profile screen: it is the one thing on this list a merchant opens to show somebody
          // else, often with a customer standing in front of them.
          if (onShareShop != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            _MenuRow(
              icon: Icons.qr_code_2,
              title: t.merchShareTitle,
              onTap: onShareShop,
            ),
          ],
          if (onShopMessages != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            _MenuRow(
              icon: Icons.forum_outlined,
              title: t.chatShopInboxTitle,
              onTap: onShopMessages,
              count: shopMessagesUnread,
            ),
          ],
          if (onServiceOrders != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            _MenuRow(
              icon: Icons.assignment_outlined,
              title: t.svcServiceOrdersRow,
              onTap: onServiceOrders,
            ),
          ],
          if (onServiceOffers != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            _MenuRow(
              icon: Icons.design_services_outlined,
              title: t.svcServiceOffersRow,
              onTap: onServiceOffers,
            ),
          ],
          if (onCategories != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            _MenuRow(
              icon: Icons.category_outlined,
              title: t.navCategories,
              onTap: onCategories,
            ),
          ],
          if (onStockCount != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            _MenuRow(
              icon: Icons.fact_check_outlined,
              title: t.invCountTitle,
              onTap: onStockCount,
            ),
          ],
          if (onCatalogScan != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            _MenuRow(
              icon: Icons.document_scanner_outlined,
              title: t.blitzSettingsRow,
              onTap: onCatalogScan,
            ),
          ],
          if (onStaff != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            _MenuRow(
              icon: Icons.badge_outlined,
              title: t.navStaff,
              onTap: onStaff,
            ),
          ],
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          // Live. The chip that stood here rested on "no payout or bank record exists anywhere in
          // the platform yet", and the record was there the whole time — filed against the
          // application, read back from the token, role-blind. See [MerchantPayoutScreen].
          _MenuRow(
            icon: Icons.credit_card,
            title: t.merchbPaymentBankDetails,
            onTap: documents == null ? null : () => _openPayout(context),
            soonLabel: documents == null ? t.merchbSoon : null,
          ),
          // Sits directly under the bank row because the two answer halves of the same question —
          // that one is which account is on file, this one is what the figure against it is.
          if (statements != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            _MenuRow(
              icon: Icons.receipt_long_outlined,
              title: MerchantStatementWords.of(context).title,
              onTap: () => _openStatement(context),
            ),
          ],
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          _MenuRow(
            icon: Icons.notifications_none,
            title: t.merchbNotificationSettings,
            onTap: onNotificationSettings,
            soonLabel: onNotificationSettings == null ? t.merchbSoon : null,
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          // Live now that Order Manager aggregates a shop's own daily series. Opens the screen
          // itself rather than a host callback: the page is nothing but that series, so a host
          // that has the client has everything the screen needs.
          _MenuRow(
            icon: Icons.bar_chart,
            title: t.merchbShopAnalytics,
            onTap: aggregates == null ? null : () => _openAnalytics(context),
            soonLabel: aggregates == null ? t.merchbSoon : null,
          ),
          // Beside Shop Analytics because it is the other half of the same question: that row is
          // how this shop is trading, this one is where around it people are ordering.
          if (onDemandRadar != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            _MenuRow(
              icon: Icons.radar,
              title: t.heatmapTitle,
              onTap: onDemandRadar,
            ),
          ],
          if (onSwitchToShopping != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            _MenuRow(
              icon: Icons.shopping_bag_outlined,
              title: t.svcSwitchToShopping,
              onTap: onSwitchToShopping,
            ),
          ],
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

  void _openPayout(BuildContext context) {
    final DocumentsApi? api = documents;
    if (api == null) return;
    final NavigatorState navigator = Navigator.of(context);
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => MerchantPayoutScreen(api: api, onBack: navigator.pop),
    ));
  }

  void _openStatement(BuildContext context) {
    final StatementsApi? api = statements;
    if (api == null) return;
    final NavigatorState navigator = Navigator.of(context);
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => MerchantStatementScreen(api: api, onBack: navigator.pop),
    ));
  }

  void _openAnalytics(BuildContext context) {
    final AggregatesApi? api = aggregates;
    if (api == null) return;
    final NavigatorState navigator = Navigator.of(context);
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => MerchantAnalyticsScreen(
        api: api,
        onBack: navigator.pop,
      ),
    ));
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
    this.count,
  });

  final IconData icon;

  /// Already localised by the caller.
  final String title;

  final VoidCallback? onTap;

  /// Non-null marks the row as drawn-but-not-yet-working: no chevron, no tap, a chip instead.
  final String? soonLabel;

  /// A live count drawn before the chevron while it is above zero.
  final ValueListenable<int?>? count;

  @override
  Widget build(BuildContext context) {
    final ValueListenable<int?>? count = this.count;
    if (count == null) return _card(null);
    return ValueListenableBuilder<int?>(
      valueListenable: count,
      builder: (BuildContext context, int? value, _) => _card(value),
    );
  }

  Widget _card(int? countValue) {
    final bool inert = soonLabel != null;
    final int shown = countValue ?? 0;

    return YdCard.bordered(
      onTap: inert ? null : onTap,
      child: YdListRow(
        card: false,
        icon: icon,
        title: title,
        titleColor: inert ? DeliveryColors.muted : DeliveryColors.ink,
        iconColor: inert ? DeliveryColors.faint : DeliveryColors.ink,
        onTap: inert ? null : onTap,
        trailing: inert
            ? YdComingSoon(label: soonLabel!)
            : shown > 0
                ? _CountThenChevron(count: shown)
                : null,
      ),
    );
  }
}

/// A count pill, then the chevron [YdListRow] draws only when it has no trailing widget of its own —
/// so a row carrying a count still reads as a row that opens.
class _CountThenChevron extends StatelessWidget {
  const _CountThenChevron({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Semantics(
          label: DeliveryStrings.of(context).chatShopUnreadCount(count),
          child: ExcludeSemantics(
            child: Container(
              constraints: const BoxConstraints(minWidth: 22),
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: DeliveryColors.brand,
                borderRadius: BorderRadius.circular(DeliveryRadius.pill),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: DeliveryColors.white),
              ),
            ),
          ),
        ),
        const SizedBox(width: DeliverySpacing.sm),
        Icon(rtl ? Icons.chevron_left : Icons.chevron_right, size: 14, color: DeliveryColors.faint),
      ],
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
