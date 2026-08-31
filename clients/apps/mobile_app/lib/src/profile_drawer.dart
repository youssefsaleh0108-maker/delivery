import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'address_sheet.dart';
import 'biometric_lock.dart';
import 'delivery_address.dart';
import 'help_support_screen.dart';
import 'notification_inbox.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart' show AppLanguageRow;

/// The profile side menu (Figma `profile-side-menu` 75:129): the account's face and everything
/// about the account, slid over whichever tab is open.
///
/// This absorbs what the Account tab used to hold — the tab itself now shows Rewards & Points —
/// so the drawer is the customer's whole settings surface: the avatar with its camera badge, the
/// account rows, the EN/AR toggle, notifications, support, and the way out. Opened from the home
/// header's avatar.
///
/// Two rows the frame draws are not pretended into life: Payment Methods states what checkout
/// takes rather than opening a management screen (there are no stored instruments to manage), and
/// Vouchers & Promos waits for the voucher engine behind the rewards screen. The biometric row is
/// kept although the frame omits it — it is the only thing between a picked-up phone and
/// somebody's order history.
class ProfileDrawer extends StatefulWidget {
  const ProfileDrawer({
    super.key,
    required this.session,
    required this.addresses,
    required this.zoneApi,
    required this.onSignOut,
    this.locale,
    this.inbox,
    this.onOpenOrders,
    this.profileApi,
  });

  final AuthSession session;
  final DeliveryAddressStore addresses;
  final DeliveryZoneApi zoneApi;
  final Future<void> Function() onSignOut;
  final LocaleController? locale;
  final NotificationInbox? inbox;
  final VoidCallback? onOpenOrders;
  final ProfileApi? profileApi;

  @override
  State<ProfileDrawer> createState() => _ProfileDrawerState();
}

class _ProfileDrawerState extends State<ProfileDrawer> {
  final BiometricLock _biometrics = BiometricLock();
  bool? _biometricsEnabled;
  bool _biometricsAvailable = false;
  bool _biometricsWorking = false;

  String? _avatarUrl;
  bool _avatarBusy = false;

  @override
  void initState() {
    super.initState();
    _loadBiometrics();
    _loadAvatar();
  }

  Future<void> _loadBiometrics() async {
    final bool available = await _biometrics.isAvailable;
    final bool enabled = await _biometrics.isEnabledFor(widget.session.subject);
    if (!mounted) return;
    setState(() {
      _biometricsAvailable = available;
      _biometricsEnabled = enabled;
    });
  }

  Future<void> _setBiometrics(bool on) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    setState(() => _biometricsWorking = true);
    try {
      if (on) {
        // Proved before it is turned on, never after — see BiometricLock.
        final BiometricResult result =
            await _biometrics.authenticate(t.unlockWithFingerprint);
        if (result != BiometricResult.ok) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(result == BiometricResult.unavailable
                  ? t.fingerprintNotSetUp
                  : t.couldNotVerifyYou)));
          return;
        }
      }
      await _biometrics.setEnabledFor(widget.session.subject, on);
      if (!mounted) return;
      setState(() => _biometricsEnabled = on);
    } finally {
      if (mounted) setState(() => _biometricsWorking = false);
    }
  }

  Future<void> _loadAvatar() async {
    final ProfileApi? api = widget.profileApi;
    if (api == null) return;
    try {
      final String? url = await api.myAvatarUrl();
      if (!mounted) return;
      setState(() => _avatarUrl = url);
    } catch (_) {
      // The monogram stands.
    }
  }

  Future<void> _pickAvatar() async {
    final ProfileApi? api = widget.profileApi;
    if (api == null || _avatarBusy) return;
    final DeliveryStrings t = DeliveryStrings.of(context);

    const XTypeGroup images = XTypeGroup(
      label: 'images',
      extensions: <String>['jpg', 'jpeg', 'png', 'webp'],
    );
    final XFile? picked;
    try {
      picked = await openFile(acceptedTypeGroups: <XTypeGroup>[images]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.couldNotOpenPicker(e.toString()))));
      return;
    }
    if (picked == null) return;
    final Uint8List bytes = await picked.readAsBytes();
    if (!mounted) return;

    setState(() => _avatarBusy = true);
    try {
      final String? url = await api.uploadAvatar(
        bytes: bytes,
        contentType: _contentTypeFor(picked),
      );
      if (!mounted) return;
      setState(() {
        _avatarBusy = false;
        _avatarUrl = url;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.pictureUpdated)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _avatarBusy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.somethingWentWrong)));
    }
  }

  static String _contentTypeFor(XFile file) {
    final String? declared = file.mimeType;
    if (declared != null && declared.startsWith('image/')) {
      return declared;
    }
    final String name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  /// Closes the drawer, then runs [action] with the navigator that survives it.
  ///
  /// Two traps in one helper: pushing while the drawer is open leaves it open under the new
  /// screen, and using the drawer's own context AFTER the pop reaches for a widget that is gone.
  /// Capturing the NavigatorState first sidesteps both.
  void _go(void Function(NavigatorState nav) action) {
    final NavigatorState nav = Navigator.of(context);
    nav.pop();
    action(nav);
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final AuthSession s = widget.session;

    return Drawer(
      backgroundColor: DeliveryColors.background,
      child: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(DeliverySpacing.md),
                children: <Widget>[
                  _profileCard(t, s),
                  const SizedBox(height: DeliverySpacing.lg),
                  _sectionLabel(t.custMyAccount),
                  const SizedBox(height: DeliverySpacing.sm),
                  YdListRow(
                    icon: Icons.receipt_long_outlined,
                    title: t.custMyOrders,
                    onTap: widget.onOpenOrders == null
                        ? null
                        : () => _go((NavigatorState _) => widget.onOpenOrders!()),
                  ),
                  const SizedBox(height: DeliverySpacing.sm),
                  YdListRow(
                    icon: Icons.place_outlined,
                    title: t.custMyAddresses,
                    onTap: () => _go((NavigatorState nav) => showAddressSheet(
                        nav.context, widget.addresses,
                        zoneApi: widget.zoneApi)),
                  ),
                  const SizedBox(height: DeliverySpacing.sm),
                  // Informational, not a management screen: cash needs no setup and nothing else
                  // is stored, so the row says what checkout takes and the note says the rest.
                  YdListRow(
                    icon: Icons.credit_card,
                    title: t.custPaymentMethods,
                    value:
                        '${PaymentMethod.cash.labelIn(t)} · ${PaymentMethod.card.labelIn(t)} · ${t.paymentWallet}',
                    subtitle: t.paymentTestModeNote,
                    trailing: const SizedBox.shrink(),
                  ),
                  const SizedBox(height: DeliverySpacing.sm),
                  // Waits for the voucher engine the rewards screen's zeros wait for.
                  YdComingSoon.wrap(
                    label: t.authComingSoon,
                    child: YdListRow(
                      icon: Icons.local_activity_outlined,
                      title: t.custVouchersPromos,
                      trailing: const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(height: DeliverySpacing.lg),
                  _sectionLabel(t.custPreferences),
                  const SizedBox(height: DeliverySpacing.sm),
                  if (widget.locale != null) ...<Widget>[
                    AppLanguageRow(
                        locale: widget.locale!, label: t.custAppLanguage),
                    const SizedBox(height: DeliverySpacing.sm),
                  ],
                  if (widget.inbox != null) ...<Widget>[
                    YdListRow(
                      icon: Icons.notifications_none_rounded,
                      title: t.notifications,
                      value: widget.inbox!.unread > 0
                          ? '${widget.inbox!.unread}'
                          : null,
                      onTap: () => _go((NavigatorState nav) => nav.push(
                          MaterialPageRoute<void>(
                              builder: (_) =>
                                  NotificationsScreen(inbox: widget.inbox!)))),
                    ),
                    const SizedBox(height: DeliverySpacing.sm),
                  ],
                  if (_biometricsAvailable && _biometricsEnabled != null) ...<Widget>[
                    YdListRow(
                      icon: Icons.fingerprint,
                      title: t.biometricUnlock,
                      subtitle: t.useFingerprintNextTime,
                      trailing: _biometricsWorking
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Switch(
                              value: _biometricsEnabled!,
                              activeThumbColor: DeliveryColors.white,
                              activeTrackColor: DeliveryColors.brand,
                              onChanged: _setBiometrics,
                            ),
                    ),
                    const SizedBox(height: DeliverySpacing.sm),
                  ],
                  const SizedBox(height: DeliverySpacing.sm),
                  _sectionLabel(t.custSupport),
                  const SizedBox(height: DeliverySpacing.sm),
                  YdListRow(
                    icon: Icons.help_outline_rounded,
                    title: t.custHelpSupport,
                    onTap: () => _go((NavigatorState nav) => nav.push(
                        MaterialPageRoute<void>(
                            builder: (_) => const HelpSupportScreen()))),
                  ),
                ],
              ),
            ),
            // The way out, pinned under the list the way the frame pins it.
            Padding(
              padding: const EdgeInsets.all(DeliverySpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  YdPillButton(
                    label: t.custLogOutAccount,
                    icon: Icons.logout_rounded,
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onSignOut();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsetsDirectional.only(start: DeliverySpacing.xs),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.faint,
            letterSpacing: 0.6,
            height: 1.2,
          ),
        ),
      );

  Widget _profileCard(DeliveryStrings t, AuthSession s) {
    final String? url = _avatarUrl;
    final Widget face = url == null
        ? StoreMonogram(name: s.displayName, size: 56, radius: 28)
        : ClipOval(
            child: Image(
              image: DeliveryImages.provider(url),
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                  StoreMonogram(name: s.displayName, size: 56, radius: 28),
            ),
          );

    return YdCard.bordered(
      child: Row(
        children: <Widget>[
          Stack(
            children: <Widget>[
              face,
              if (widget.profileApi != null)
                PositionedDirectional(
                  bottom: 0,
                  end: 0,
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: DeliveryColors.brand,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: DeliveryColors.white, width: 2),
                    ),
                    child: _avatarBusy
                        ? const Padding(
                            padding: EdgeInsets.all(4),
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: DeliveryColors.white),
                          )
                        : const Icon(Icons.photo_camera,
                            size: 10, color: DeliveryColors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(width: DeliverySpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  s.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
                if (s.email != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    s.email!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12,
                        color: DeliveryColors.muted,
                        height: 1.3),
                  ),
                ],
                if (widget.profileApi != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Semantics(
                    button: true,
                    child: InkWell(
                      onTap: _avatarBusy ? null : _pickAvatar,
                      borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(Icons.edit_outlined,
                              size: 13, color: DeliveryColors.brand),
                          const SizedBox(width: 4),
                          Text(
                            t.custEditProfile,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: DeliveryColors.brand,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
