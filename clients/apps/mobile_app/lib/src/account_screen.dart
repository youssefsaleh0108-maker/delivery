import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'address_sheet.dart';
import 'biometric_lock.dart';
import 'delivery_address.dart';
import 'forgot_password_screen.dart';
import 'help_support_screen.dart';
import 'notification_inbox.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart' show AppLanguageRow;

/// The customer's Account tab, drawn as the redesign's `customer-settings` (node 3:686).
///
/// The design merges what used to be two screens — "who I am" and "how the app behaves" — into one
/// `Account Settings` page, and this is that page: a white profile block, the bordered language
/// row, and a 24px list of white radius-16 menu rows ending in the tinted destructive Log Out
/// button. [SettingsScreen] survives as the same page for the rider and merchant surfaces, which
/// have no account tab to merge it into.
///
/// The profile is read from the token's own claims rather than fetched — the name and email are
/// already in the JWT, signed, and an account screen should not need a round trip to say who you
/// are.
///
/// [locale], [inbox] and [onOpenOrders] are optional because the surfaces that build this screen
/// do not all own them. Each row that depends on one is simply not drawn when it is absent, rather
/// than drawn and dead: every one of those destinations is also reachable from the home screen, so
/// an un-wired row would be a worse copy of a control that already works.
class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    required this.session,
    required this.addresses,
    required this.zoneApi,
    required this.onSignOut,
    this.locale,
    this.inbox,
    this.onOpenOrders,
    this.prefsApi,
    this.profileApi,
  });

  final AuthSession session;
  final DeliveryAddressStore addresses;

  /// Offered to the address sheet so a customer can say which area they are in.
  final DeliveryZoneApi zoneApi;
  final Future<void> Function() onSignOut;

  /// Drives the design's EN/AR segmented toggle. Without it the language row is not drawn.
  final LocaleController? locale;

  /// The in-app inbox behind the Notifications row.
  final NotificationInbox? inbox;

  /// Jumps to the Orders tab from the Order History row.
  final VoidCallback? onOpenOrders;

  /// The per-category notification grid. Null leaves the preferences row undrawn.
  final NotificationPrefsApi? prefsApi;

  /// The account's own picture. Null keeps the monogram and hides the upload affordance — the
  /// one part of this screen that DOES need a round trip, since a selfie is not in the JWT.
  final ProfileApi? profileApi;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final BiometricLock _biometrics = BiometricLock();

  /// Null until the checks answer. The row is not drawn while it is null rather than drawn off — a
  /// switch that flicks itself on a moment after the screen opens looks like the app changing a
  /// security setting by itself.
  bool? _biometricsEnabled;
  bool _biometricsAvailable = false;

  /// True while the system prompt is out, so the row can say something is happening.
  bool _biometricsWorking = false;

  /// The presigned viewing URL for the account's picture. Null while loading or when none is set;
  /// fetched fresh each time the screen opens because the URL is short-lived by design.
  String? _avatarUrl;
  bool _avatarBusy = false;

  @override
  void initState() {
    super.initState();
    _loadBiometrics();
    _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    final ProfileApi? api = widget.profileApi;
    if (api == null) return;
    try {
      final String? url = await api.myAvatarUrl();
      if (!mounted) return;
      setState(() => _avatarUrl = url);
    } catch (_) {
      // The monogram stands. A profile picture that cannot be fetched is not worth an error bar
      // on a screen whose real content is the menu below it.
    }
  }

  /// Picks a picture and uploads it as the account's face.
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

  /// `XFile.mimeType` is null on several platforms, so fall back to the extension.
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

    // Busy while the platform call is out. Without it the switch sits there doing nothing visible
    // and the whole thing reads as hung — which is exactly what it looked like on a phone with no
    // finger enrolled, where the prompt never appears because there is nothing to match against.
    setState(() => _biometricsWorking = true);
    try {
      if (on) {
        // Proved before it is turned on, never after. Enabling on the strength of the sensor merely
        // existing is how somebody locks themselves out with a finger the phone does not recognise.
        final BiometricResult result =
            await _biometrics.authenticate(t.unlockWithFingerprint);
        if (result != BiometricResult.ok) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 6),
            content: Text(result == BiometricResult.unavailable
                ? t.fingerprintNotSetUp
                : t.couldNotVerifyYou),
          ));
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

  Future<void> _signOut() async {
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
            style: FilledButton.styleFrom(backgroundColor: DeliveryColors.brand),
            child: Text(DeliveryStrings.of(context).signOut),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.onSignOut();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return AnimatedBuilder(
      // The address store drives the "My Addresses" value; the locale controller repaints the
      // segmented toggle. Both are rebuilt from here so neither can be a tick stale.
      animation: Listenable.merge(<Listenable?>[widget.addresses, widget.locale]),
      builder: (BuildContext context, _) => Scaffold(
        backgroundColor: DeliveryColors.background,
        appBar: YdScreenHeader(title: t.custAccountSettings),
        body: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            _profileCard(t),
            if (widget.locale != null)
              AppLanguageRow(locale: widget.locale!, label: t.custAppLanguage),
            Padding(
              padding: const EdgeInsets.all(DeliverySpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final Widget row in _menuRows(t)) ...<Widget>[
                    row,
                    const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                  ],
                  _logoutButton(t),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ profile

  /// The face on the account: the uploaded selfie when there is one, the deterministic monogram
  /// when there is not — same treatment a shop gets, one piece of code rendering both. Tappable
  /// (with the small camera badge saying so) only when a [ProfileApi] was provided.
  Widget _avatar(DeliveryStrings t, AuthSession s) {
    final String? url = _avatarUrl;

    final Widget face = url == null
        ? StoreMonogram(name: s.displayName, size: 64, radius: 32)
        : ClipOval(
            child: Image.network(
              url,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              // A URL that expired or failed falls back to the monogram rather than a broken tile.
              errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                  StoreMonogram(name: s.displayName, size: 64, radius: 32),
            ),
          );

    if (widget.profileApi == null) return face;

    return Semantics(
      button: true,
      label: t.edit,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _avatarBusy ? null : _pickAvatar,
        child: Stack(
          children: <Widget>[
            face,
            // The camera badge, bottom-end of the circle — what says "this is editable".
            PositionedDirectional(
              bottom: 0,
              end: 0,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: DeliveryColors.brand,
                  shape: BoxShape.circle,
                  border: Border.all(color: DeliveryColors.white, width: 2),
                ),
                child: _avatarBusy
                    ? const Padding(
                        padding: EdgeInsets.all(4),
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: DeliveryColors.white),
                      )
                    : const Icon(Icons.photo_camera,
                        size: 11, color: DeliveryColors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileCard(DeliveryStrings t) {
    final AuthSession s = widget.session;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DeliverySpacing.lg),
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: Row(
        children: <Widget>[
          _avatar(t, s),
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
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
                if (s.email != null) ...<Widget>[
                  const SizedBox(height: DeliverySpacing.xs),
                  Text(
                    s.email!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: DeliveryColors.muted,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          // Live. What this badge gated was "editing a profile writes to Keycloak, and nothing in
          // the app does that yet" — and one thing does now: the onboarding service's
          // password-reset pair sets a new passcode on the realm account. So the badge opens what
          // can genuinely be changed, and states plainly what cannot. See [_editProfile].
          Semantics(
            button: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(DeliveryRadius.sm),
              onTap: _editProfile,
              child: Padding(
                padding: const EdgeInsetsDirectional.all(DeliverySpacing.xs),
                child: YdBadge.brand(label: t.edit, uppercase: false, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// What "Edit" can honestly offer.
  ///
  /// The passcode is real: `/api/onboarding/password-reset` sends a code to the account's own
  /// address and its `/confirm` sets the new one on Keycloak, and that is the whole flow this
  /// sheet opens — with the address locked to the signed-in account, because a signed-in session
  /// must not be a way to send reset codes to strangers.
  ///
  /// The name and the email are a different matter, and the sheet says so in a sentence rather
  /// than by showing greyed fields: the sign-up call sets them once and no endpoint on the
  /// platform changes them afterwards. Drawing a disabled "Full name" box would look like a
  /// feature that is loading.
  Future<void> _editProfile() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String? email = widget.session.email;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: DeliveryColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(DeliveryRadius.sheet)),
      ),
      builder: (BuildContext sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: DeliveryColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: DeliverySpacing.md),
              Text(
                t.custEditProfile,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.ink,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: DeliverySpacing.md),
              // No address on the token means no way to send a code to the right person, and the
              // reset endpoint is keyed on the address rather than the subject — so the row is
              // withheld rather than opening a flow that cannot finish.
              if (email != null && email.isNotEmpty)
                YdListRow(
                  icon: Icons.password_rounded,
                  title: t.authChangeYourPasscode,
                  subtitle: email,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _changePasscode(email);
                  },
                )
              else
                SoftNote(icon: Icons.info_outline, text: t.custNoEmailOnAccount),
              const SizedBox(height: DeliverySpacing.md),
              Text(
                t.custProfileFieldsFixed,
                style: const TextStyle(
                  fontSize: 12,
                  color: DeliveryColors.muted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: DeliverySpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _changePasscode(String email) async {
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ForgotPasswordScreen(
          initialEmail: email,
          // The account is known; the address is not a field to retype.
          emailFixed: true,
          signedIn: true,
        ),
      ),
    );
    if (!mounted || changed != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(DeliveryStrings.of(context).authPasscodeChanged)),
    );
  }

  // ------------------------------------------------------------------ the menu

  List<Widget> _menuRows(DeliveryStrings t) {
    return <Widget>[
      YdListRow(
        icon: Icons.place_outlined,
        title: t.custMyAddresses,
        value: _addressSummary(t),
        onTap: () => showAddressSheet(context, widget.addresses, zoneApi: widget.zoneApi),
      ),
      // Live now that checkout takes all three. Informational rather than a management screen on
      // purpose: there is nothing to add or remove yet — cash needs no setup and card/wallet run
      // against the dev provider — so the row states what checkout offers and the subtitle says
      // plainly that non-cash is a test rail. A management screen arrives with a real processor,
      // where stored instruments exist to manage.
      YdListRow(
        icon: Icons.credit_card,
        title: t.custPaymentMethods,
        value:
            '${PaymentMethod.cash.labelIn(t)} · ${PaymentMethod.card.labelIn(t)} · ${t.paymentWallet}',
        subtitle: t.paymentTestModeNote,
        trailing: const SizedBox.shrink(),
      ),
      if (widget.onOpenOrders != null)
        YdListRow(
          icon: Icons.receipt_long_outlined,
          title: t.custOrderHistory,
          onTap: widget.onOpenOrders,
        ),
      if (widget.inbox != null)
        YdListRow(
          icon: Icons.notifications_none_rounded,
          title: t.notifications,
          value: widget.inbox!.unread > 0 ? '${widget.inbox!.unread}' : null,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => NotificationsScreen(inbox: widget.inbox!),
          )),
        ),
      // The per-category grid, distinct from the inbox above: one is what arrived, the other is
      // what is allowed to arrive. Only drawn when the shell handed over the API — this page is
      // the customer's whole settings surface, so leaving the row out here would leave customers
      // no road to their preferences at all.
      if (widget.prefsApi != null)
        YdListRow(
          icon: Icons.tune,
          title: t.notifPreferences,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => NotificationPrefsScreen(api: widget.prefsApi!),
          )),
        ),
      // Kept from the settings screen this page absorbs, and deliberately not dropped for being
      // absent from the frame: it is the only thing standing between a picked-up phone and
      // somebody's order history.
      if (_biometricsAvailable && _biometricsEnabled != null)
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
      // Live: the support channels the business actually answers on, and honest answers to the
      // questions this app's own behaviour raises. There is still no ticket queue — that is a
      // staffing commitment rather than a screen — and the page does not pretend there is one.
      YdListRow(
        icon: Icons.help_outline_rounded,
        title: t.custHelpSupport,
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const HelpSupportScreen(),
        )),
      ),
    ];
  }

  /// "Home · Office" — the labels the customer gave their saved addresses, which is what the
  /// design's muted value column shows.
  String? _addressSummary(DeliveryStrings t) {
    final List<DeliveryAddress> saved = widget.addresses.recents;
    if (saved.isEmpty) return null;
    return saved
        .take(2)
        .map((DeliveryAddress a) => a.label == null || a.label!.isEmpty ? a.line : a.label!)
        .join(' · ');
  }

  // ------------------------------------------------------------------ the way out

  Widget _logoutButton(DeliveryStrings t) {
    final Color danger = DeliveryAccent.critical.color;

    return Semantics(
      button: true,
      child: Material(
        color: danger.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.lg),
          // The design's #fef2f2 fill on a #fee2e2 hairline, expressed as the critical accent at
          // the two alphas that land on those values over white.
          side: BorderSide(color: danger.withValues(alpha: 0.16)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _signOut,
          child: Padding(
            padding: const EdgeInsets.all(DeliverySpacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.logout_rounded, size: 16, color: danger),
                const SizedBox(width: DeliverySpacing.sm),
                Text(
                  t.signOut,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: danger,
                    height: 1.2,
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
