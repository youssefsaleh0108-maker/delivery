import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';


import 'address_sheet.dart';
import 'delivery_address.dart';

/// The account: who you are, where you get things delivered, and the way out.
///
/// How the app *behaves* lives in [SettingsScreen] instead — language is a property of the app,
/// not of the person, and mixing the two makes both harder to find.
///
/// The profile is read from the token's own claims rather than fetched — the name and email are
/// already in the JWT, signed, and an account screen should not need a round trip to say who you
/// are.
class AccountScreen extends StatelessWidget {
  const AccountScreen({
    super.key,
    required this.session,
    required this.addresses,
    required this.zoneApi,
    required this.onSignOut,
  });

  final AuthSession session;
  final DeliveryAddressStore addresses;

  /// Offered to the address sheet so a customer can say which area they are in.
  final DeliveryZoneApi zoneApi;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return AnimatedBuilder(
      // Only the address: a language change rebuilds the whole app from the root, so listening
      // for it here would be redundant.
      animation: addresses,
      builder: (BuildContext context, _) => Scaffold(
        backgroundColor: DeliveryColors.background,
        appBar: AppBar(
          backgroundColor: DeliveryColors.brand,
          foregroundColor: DeliveryColors.white,
          elevation: 0,
          title: Text(DeliveryStrings.of(context).account,
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: ListView(
          padding: const EdgeInsets.all(DeliverySpacing.md),
          children: <Widget>[
            _profileCard(t),
            const SizedBox(height: DeliverySpacing.md),
            _card(DeliveryStrings.of(context).deliverTo, <Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_outlined, color: DeliveryColors.muted),
                title: Text(
                  addresses.isSet
                      ? addresses.selected!.display
                      : DeliveryStrings.of(context).setDeliveryAddress,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                ),
                subtitle: addresses.selected?.notes == null
                    ? null
                    : Text(addresses.selected!.notes!,
                        style: const TextStyle(fontSize: 12.5)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showAddressSheet(context, addresses, zoneApi: zoneApi),
              ),
            ]),
            const SizedBox(height: DeliverySpacing.lg),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final bool? confirmed = await showDialog<bool>(
                    context: context,
                    builder: (BuildContext context) => AlertDialog(
                      title: Text(DeliveryStrings.of(context).signOut),
                      content: Text(DeliveryStrings.of(context).signOutConfirm),
                      actions: <Widget>[
                        TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: Text(DeliveryStrings.of(context).keepIt)),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: FilledButton.styleFrom(
                              backgroundColor: DeliveryColors.brand),
                          child: Text(DeliveryStrings.of(context).signOut),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) await onSignOut();
                },
                icon: const Icon(Icons.logout_rounded, size: 19),
                style: OutlinedButton.styleFrom(
                  foregroundColor: DeliveryColors.brand,
                  side: const BorderSide(color: DeliveryColors.brandLine),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(DeliveryRadius.md)),
                ),
                label: Text(DeliveryStrings.of(context).signOut,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: DeliverySpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _profileCard(DeliveryStrings t) {
    final AuthSession s = session;
    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.md),
      decoration: BoxDecoration(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
        boxShadow: DeliveryShadows.card,
      ),
      child: Row(
        children: <Widget>[
          // Reuses the store monogram: same deterministic colour-from-name treatment, so a person
          // and a shop are rendered by one piece of code.
          StoreMonogram(name: s.displayName, size: 56),
          const SizedBox(width: DeliverySpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(s.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                if (s.email != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(s.email!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, color: DeliveryColors.muted)),
                ],
                const SizedBox(height: DeliverySpacing.sm),
                Wrap(
                  spacing: DeliverySpacing.xs + 2,
                  children: <Widget>[
                    for (final DeliveryRole role in s.roles)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: DeliveryColors.brandSoft,
                          borderRadius: BorderRadius.circular(DeliveryRadius.pill),
                        ),
                        child: Text(
                          role.name.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: DeliveryColors.brand),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DeliverySpacing.md),
      decoration: BoxDecoration(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
        boxShadow: DeliveryShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: DeliverySpacing.xs),
          ...children,
        ],
      ),
    );
  }
}
