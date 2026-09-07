import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'order_detail_screen.dart'
    show MerchantScreenHeader, merchantChipRadius, merchantMaxContentWidth, merchantTimeAgo;

/// Who works at this shop and what each of them may do — Figma `merchant-staff`
/// (94:4770 phone / 94:5948 web).
///
/// This is the one new merchant screen whose backend already exists: [StoreStaffApi] is live in
/// product-service, so everything here is a real call and every refusal here is a real 403.
///
/// Four things are load-bearing:
///
/// * **The owner is not a roster row.** Ownership is `stores.merchant_id == sub`, not a
///   `staff_members` record, so there is nothing to demote, suspend or delete. The owner card is
///   drawn first, badged, holding all seven permissions, and is deliberately inert — see
///   [_ownerCard]. A screen that offered an "Owner" role would be offering something the server
///   cannot store.
/// * **Adding somebody mints a code, not an account.** The platform never creates an identity on a
///   merchant's say-so: [StoreStaffApi.invite] returns a short code the shopkeeper reads out, and
///   the employee redeems it with their own token. So the "Add Employee" action ends on a code to
///   share, not on a "we emailed them" — see [_InviteDialog] and [_InviteCodeDialog].
/// * **Every write returns nothing.** A role-band edit re-resolves every active member on that
///   role, so the honest response is "read it again": each write is followed by a silent
///   [StoreStaffApi.roster] rather than by patching a row locally.
/// * **A refusal names the permission it wanted.** product-service answers 403 with the missing
///   permission in the problem body; [_refusalMessage] pulls it out so the merchant is told
///   *which* capability they are short of rather than "something went wrong".
///
/// Presence is polled every 30 seconds, and a failed poll never wipes the list — a shop looking at
/// who is on the floor should not lose the answer because one request timed out.
///
/// One widget, two hosts. Below [_StaffScreenState._wideWidth] the roster and the permissions band
/// stack in a single scroller; above it they sit side by side, exactly as 94:5948 draws them.
/// Everything measures this widget's own [BoxConstraints], never the window: the portal's rail can
/// leave a desktop as narrow as a handset.
class StaffScreen extends StatefulWidget {
  const StaffScreen({
    super.key,
    this.api,
    this.storeId,
    required this.access,
  });

  /// product-service's staff endpoints. Nullable only so a host with no client to hand still
  /// compiles and gets [_unavailable] instead of a crash; in practice this is always supplied.
  final StoreStaffApi? api;

  /// The shop being administered. Null or empty means the caller is not attached to a shop yet,
  /// which is an ordinary state for somebody who has just been sent an invite code — the screen
  /// then offers the join flow rather than an error.
  final String? storeId;

  /// The caller's own standing, resolved once by the host. UI-only: the server enforces every one
  /// of these again on every call. It decides whether write affordances are drawn at all.
  final MerchantAccess access;

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  /// Below this the page is on a phone: one column, and the header's refresh control gives way to
  /// the pull gesture.
  static const double _phoneWidth = 600;

  /// Above this the permissions band moves out of the scroller and into its own column, which is
  /// 94:5948's layout. 980 rather than 900: at 900 the roster column left of a 400px panel is
  /// narrower than a phone, which is worse than stacking.
  static const double _wideWidth = 980;

  /// The frame's permissions rail.
  static const double _panelWidth = 400;

  /// Room under the last row for the floating invite button.
  static const double _fabClearance = 88;

  static const Duration _pollInterval = Duration(seconds: 30);

  /// The last roster that loaded. Kept across a failed poll on purpose.
  StoreRoster? _roster;

  /// Only ever rendered when there is no [_roster] to show instead.
  Object? _error;

  bool _loading = false;
  Timer? _poll;

  /// Which role's defaults the permissions panel is showing. Null is the Owner column, which is
  /// read-only because there is no owner band to edit — the owner holds everything by definition.
  StaffRole? _band = StaffRole.manager;

  /// In-flight writes, keyed by whatever they touch, so a second tap cannot race the first.
  final Set<String> _busy = <String>{};

  bool get _canManage => widget.access.can(StorePermission.manageStaff);

  bool get _wired {
    final String? storeId = widget.storeId;
    return widget.api != null && storeId != null && storeId.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    if (_wired) {
      unawaited(_load());
      _poll = Timer.periodic(_pollInterval, (Timer _) => unawaited(_load(silent: true)));
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Reads the roster.
  ///
  /// [silent] is the 30s presence poll: it leaves the visible list alone on failure, because a
  /// dropped poll is not news and blanking the floor plan over one is a worse lie than a stale
  /// "on shift". A silent failure is only promoted to an error state when there is nothing on
  /// screen yet to preserve.
  Future<bool> _load({bool silent = false}) async {
    final StoreStaffApi? api = widget.api;
    final String? storeId = widget.storeId;
    if (api == null || storeId == null || storeId.isEmpty) {
      return false;
    }
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final StoreRoster roster = await api.roster(storeId);
      if (!mounted) return true;
      setState(() {
        _roster = roster;
        _error = null;
        _loading = false;
      });
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _loading = false;
        if (!silent || _roster == null) {
          _error = error;
        }
      });
      return false;
    }
  }

  /// The same read, finishing only when the request does — [RefreshIndicator] keeps spinning until
  /// its future completes.
  ///
  /// A pull that fails over a list that is already on screen keeps the list and says so in a
  /// snackbar: the alternative is a gesture that spins, stops, and leaves no trace of having been
  /// refused.
  Future<void> _refresh() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool had = _roster != null;
    final bool ok = await _load(silent: had);
    if (!ok && had && mounted) {
      _say(t.staffCouldNotLoad);
    }
  }

  /// Runs one write, then re-reads the roster because the server's answer to a write is empty.
  ///
  /// Returns whether it succeeded, so a caller that has to close a sheet afterwards can tell.
  Future<bool> _write(
    DeliveryStrings t, {
    required String key,
    required Future<void> Function() action,
    required String fallback,
    String? success,
  }) async {
    if (_busy.contains(key)) {
      return false;
    }
    setState(() => _busy.add(key));
    try {
      await action();
      await _load(silent: true);
      if (mounted && success != null) {
        _say(success);
      }
      return true;
    } catch (error) {
      if (mounted) {
        _say(_refusalMessage(error, t, fallback: fallback));
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _busy.remove(key));
      }
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < _phoneWidth;
        final bool wide = constraints.maxWidth >= _wideWidth;

        return Scaffold(
          backgroundColor: DeliveryColors.background,
          // No AppBar: the framing belongs to whichever app is hosting this.
          floatingActionButton: _canManage && _roster != null && _wired
              ? FloatingActionButton.extended(
                  onPressed: () => unawaited(_openInvite(t)),
                  backgroundColor: DeliveryColors.brand,
                  foregroundColor: DeliveryColors.white,
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: Text(t.staffInvite),
                )
              : null,
          body: Column(
            children: <Widget>[
              MerchantScreenHeader(
                title: t.staffTitle,
                subtitle: t.staffSubtitle,
                // The refresh button only exists where there is no pull gesture to replace it.
                trailing: narrow || !_wired
                    ? null
                    : IconButton(
                        onPressed: _loading ? null : () => unawaited(_load()),
                        icon: const Icon(Icons.refresh, size: 20),
                        color: DeliveryColors.ink,
                        tooltip: t.refresh,
                      ),
              ),
              Expanded(child: _body(t, narrow: narrow, wide: wide)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(DeliveryStrings t, {required bool narrow, required bool wide}) {
    if (!_wired) {
      return _unattached(t);
    }
    final StoreRoster? roster = _roster;
    if (roster == null) {
      if (_loading) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(DeliverySpacing.xl),
            child: CircularProgressIndicator(color: DeliveryColors.brand),
          ),
        );
      }
      final Object? error = _error;
      if (error != null) {
        return YdEmptyState(
          icon: Icons.cloud_off_rounded,
          title: t.staffCouldNotLoad,
          message: _refusalMessage(error, t, fallback: t.somethingWentWrong),
          action: YdPillButton.secondary(
            label: t.tryAgain,
            onPressed: () => unawaited(_load()),
            size: YdPillButtonSize.compact,
            expand: false,
          ),
        );
      }
      return const SizedBox.shrink();
    }

    final Widget roll = _rosterList(t, roster, narrow: narrow, wide: wide);
    if (!wide) {
      return roll;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: roll),
        const VerticalDivider(width: 1, thickness: 1, color: DeliveryColors.border),
        SizedBox(
          width: _panelWidth,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(DeliverySpacing.lg),
            child: _permissionsPanel(t, roster),
          ),
        ),
      ],
    );
  }

  /// Nobody's shop: either the host had no store id, or the caller has not joined one yet.
  ///
  /// A dead end would be wrong here — the whole point of an invite code is that somebody holding
  /// one has nowhere to type it until this screen offers the field.
  Widget _unattached(DeliveryStrings t) {
    if (widget.api == null) {
      return YdEmptyState(
        icon: Icons.badge_outlined,
        title: t.staffCouldNotLoad,
        message: t.staffEmptyHint,
      );
    }
    return YdEmptyState(
      icon: Icons.storefront_outlined,
      title: t.staffNoShopYet,
      message: t.staffInviteCodeHint,
      action: YdPillButton(
        label: t.staffAcceptJoin,
        onPressed: () => unawaited(_openAccept(t)),
        size: YdPillButtonSize.compact,
        expand: false,
      ),
    );
  }

  Widget _rosterList(
    DeliveryStrings t,
    StoreRoster roster, {
    required bool narrow,
    required bool wide,
  }) {
    // Above [_wideWidth] the permissions band has a column of its own beside this one, so it must
    // not also be appended to the bottom of the scroller.
    final bool withPanel = !wide;
    final List<Widget> children = <Widget>[
      _ownerCard(t),
      const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
      if (roster.members.isEmpty)
        YdCard.bordered(
          child: YdEmptyState(
            icon: Icons.groups_outlined,
            title: t.staffEmpty,
            message: t.staffEmptyHint,
            padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.md),
          ),
        )
      else
        for (final StaffMember member in roster.members) ...<Widget>[
          _memberCard(t, member, wide: wide),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        ],
      const SizedBox(height: DeliverySpacing.md),
      _invitesSection(t, roster),
      if (withPanel) ...<Widget>[
        const SizedBox(height: DeliverySpacing.lg),
        _permissionsPanel(t, roster),
      ],
    ];

    final Widget scroller = ListView(
      // Always scrollable, or the pull-to-refresh below is dead on exactly the state where a
      // merchant most wants to retry.
      physics: narrow ? const AlwaysScrollableScrollPhysics() : null,
      padding: EdgeInsets.fromLTRB(
        DeliverySpacing.lg,
        DeliverySpacing.lg,
        DeliverySpacing.lg,
        // Clears the floating button and then the gesture bar under it. `paddingOf`, not
        // `viewPaddingOf`: a host that already wrapped this in a SafeArea has spent the inset.
        _fabClearance + MediaQuery.paddingOf(context).bottom,
      ),
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: merchantMaxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );

    if (!narrow) {
      return scroller;
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      color: DeliveryColors.brand,
      child: scroller,
    );
  }

  // ------------------------------------------------------------------------------------ people

  /// The owner, first and inert.
  ///
  /// There is no roster row behind this card, so there is nothing to open: no role to change, no
  /// status to suspend, no permissions to edit. Naming that plainly ([DeliveryStrings.staffCannotEditOwner])
  /// is better than drawing seven switches that would all refuse.
  Widget _ownerCard(DeliveryStrings t) {
    final bool isMe = widget.access.isOwner;
    return YdCard.bordered(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Avatar(label: isMe ? t.staffYou : t.staffRoleOwner, accent: DeliveryColors.brand),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Wrap(
                  spacing: DeliverySpacing.sm,
                  runSpacing: DeliverySpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(
                      isMe ? t.staffYou : t.staffRoleOwner,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.ink,
                        height: 1.25,
                      ),
                    ),
                    YdBadge.brand(label: t.staffOwnerBadge, uppercase: false),
                  ],
                ),
                const SizedBox(height: DeliverySpacing.xs),
                Text(
                  t.staffCannotEditOwner,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DeliveryColors.muted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One employee: who they are, what they do, and whether they are on the floor.
  Widget _memberCard(DeliveryStrings t, StaffMember member, {required bool wide}) {
    final bool isMe = widget.access.memberId != null && widget.access.memberId == member.id;
    final bool busy = _busy.contains(member.id);

    return YdCard.bordered(
      // Tappable only for somebody who may actually change something. A row that opens a sheet of
      // dead switches is a worse answer than a row that does not open.
      onTap: _canManage ? () => unawaited(_openMember(t, member, wide: wide)) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Avatar(
            label: member.displayName,
            accent: member.isActive ? DeliveryColors.brand : DeliveryColors.faint,
            dimmed: !member.isActive,
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Wrap(
                  spacing: DeliverySpacing.sm,
                  runSpacing: DeliverySpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(
                      member.displayName.trim().isEmpty ? member.role.labelIn(t) : member.displayName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.ink,
                        height: 1.25,
                      ),
                    ),
                    if (isMe) YdBadge.brand(label: t.staffYou, uppercase: false),
                  ],
                ),
                const SizedBox(height: DeliverySpacing.xs),
                Text(
                  member.role.labelIn(t),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.muted,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: DeliverySpacing.sm),
                Wrap(
                  spacing: DeliverySpacing.sm,
                  runSpacing: DeliverySpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    _statusBadge(t, member),
                    if (member.lastSeenAt != null)
                      Text(
                        t.staffLastSeen(merchantTimeAgo(member.lastSeenAt, t)),
                        style: const TextStyle(
                          fontSize: 11,
                          color: DeliveryColors.faint,
                          height: 1.3,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: DeliverySpacing.sm),
                // pos-service is not deployed, so every figure here would be $0.00 — and a column
                // of zeroes reads as "nobody sold anything", not as "there is no register yet".
                Text(
                  '${t.staffSalesToday}: ${t.staffNoPosSalesYet}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: DeliveryColors.faint,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(top: DeliverySpacing.xs),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.brand),
              ),
            )
          else if (_canManage)
            const Icon(Icons.chevron_right, size: 20, color: DeliveryColors.faint),
        ],
      ),
    );
  }

  /// Attendance and standing in one pill.
  ///
  /// Three states, in the order they matter to somebody looking at the shop floor: on shift beats
  /// merely active, and suspended overrides both — a suspended member cannot be on shift, because
  /// the server closes the shift when it suspends them.
  Widget _statusBadge(DeliveryStrings t, StaffMember member) {
    if (!member.isActive) {
      return YdBadge.accent(
        label: member.status.labelIn(t),
        accent: DeliveryAccent.critical,
        uppercase: false,
      );
    }
    if (member.onShift) {
      return YdBadge.accent(
        label: t.staffOnShift,
        accent: DeliveryAccent.positive,
        icon: Icons.circle,
        uppercase: false,
      );
    }
    return YdBadge.accent(
      label: t.staffOffShift,
      accent: DeliveryAccent.neutral,
      uppercase: false,
    );
  }

  // ----------------------------------------------------------------------------------- invites

  Widget _invitesSection(DeliveryStrings t, StoreRoster roster) {
    final List<StaffInvite> pending = roster.invites;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        YdSectionHeader(title: t.staffPendingInvites),
        const SizedBox(height: DeliverySpacing.sm),
        if (pending.isEmpty)
          YdCard.bordered(
            child: Text(
              t.staffNoPendingInvites,
              style: const TextStyle(fontSize: 13, color: DeliveryColors.faint, height: 1.35),
            ),
          )
        else
          for (final StaffInvite invite in pending) ...<Widget>[
            _inviteRow(t, invite),
            const SizedBox(height: DeliverySpacing.sm),
          ],
      ],
    );
  }

  Widget _inviteRow(DeliveryStrings t, StaffInvite invite) {
    final DateTime? expiresAt = invite.expiresAt;
    return YdCard.bordered(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _CodeText(code: invite.code, dimmed: invite.isExpired),
                const SizedBox(height: DeliverySpacing.xs),
                Wrap(
                  spacing: DeliverySpacing.sm,
                  runSpacing: DeliverySpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(
                      invite.displayName?.trim().isNotEmpty ?? false
                          ? '${invite.displayName} · ${invite.role.labelIn(t)}'
                          : invite.role.labelIn(t),
                      style: const TextStyle(
                        fontSize: 12,
                        color: DeliveryColors.muted,
                        height: 1.3,
                      ),
                    ),
                    if (expiresAt != null)
                      Text(
                        t.staffInviteExpires(_when(context, expiresAt)),
                        style: TextStyle(
                          fontSize: 11,
                          color: invite.isExpired
                              ? DeliveryAccent.critical.color
                              : DeliveryColors.faint,
                          height: 1.3,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          IconButton(
            onPressed: () => _copy(t, invite.code),
            icon: const Icon(Icons.copy_rounded, size: 18),
            color: DeliveryColors.brand,
            tooltip: t.staffInviteShare,
          ),
        ],
      ),
    );
  }

  Future<void> _copy(DeliveryStrings t, String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) {
      _say(t.staffInviteCopied);
    }
  }

  /// "Add Employee": mints a code, then puts it on screen to be read out.
  Future<void> _openInvite(DeliveryStrings t) async {
    final StoreStaffApi? api = widget.api;
    final String? storeId = widget.storeId;
    if (api == null || storeId == null || storeId.isEmpty) {
      return;
    }
    final StaffInvite? invite = await showDialog<StaffInvite>(
      context: context,
      builder: (BuildContext context) => _InviteDialog(api: api, storeId: storeId),
    );
    if (!mounted || invite == null) {
      return;
    }
    await _load(silent: true);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => _InviteCodeDialog(
        invite: invite,
        onCopy: () => unawaited(_copy(t, invite.code)),
      ),
    );
  }

  /// The other end of the same code: somebody who was given one and has nowhere else to type it.
  Future<void> _openAccept(DeliveryStrings t) async {
    final StoreStaffApi? api = widget.api;
    if (api == null) {
      return;
    }
    final StaffMembership? joined = await showDialog<StaffMembership>(
      context: context,
      builder: (BuildContext context) => _AcceptInviteDialog(api: api),
    );
    if (!mounted || joined == null) {
      return;
    }
    // The host owns the store id this screen was given, so it has to re-resolve the membership
    // before the roster can be read. Saying so is honest; silently showing an empty shop is not.
    _say(t.staffJoined(joined.displayName ?? joined.storeId ?? ''));
  }

  // ------------------------------------------------------------------------------- permissions

  /// The role-defaults band: seven switches, one column per role, plus a read-only Owner column.
  ///
  /// These are the *store's* band for a role, not a platform constant — [StoreRoster.roleBands]
  /// travels with the roster for exactly that reason, and editing one re-resolves every active
  /// member on that role, which is why [_write] always re-reads rather than patching.
  Widget _permissionsPanel(DeliveryStrings t, StoreRoster roster) {
    final StaffRole? role = _band;
    final Set<StorePermission> band =
        role == null ? StorePermission.all : roster.bandFor(role);

    return YdCard.bordered(
      padding: const EdgeInsets.all(DeliverySpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          YdSectionHeader(
            title: t.staffEditPermissions,
            subtitle: role == null ? t.staffCannotEditOwner : t.staffRoleDefaults,
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          // Wrap, not a Row: four chips do not fit a 380px phone on one line, and they must not
          // be allowed to overflow a 400px rail either.
          Wrap(
            spacing: DeliverySpacing.sm,
            runSpacing: DeliverySpacing.sm,
            children: <Widget>[
              YdChip(
                label: t.staffRoleOwner,
                selected: role == null,
                onTap: () => setState(() => _band = null),
              ),
              for (final StaffRole option in StaffRole.values)
                YdChip(
                  label: option.labelIn(t),
                  selected: role == option,
                  onTap: () => setState(() => _band = option),
                ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.sm),
          if (!_canManage)
            Padding(
              padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
              child: Text(
                t.staffNoPermission,
                style: TextStyle(
                  fontSize: 12,
                  color: DeliveryAccent.caution.color,
                  height: 1.35,
                ),
              ),
            ),
          for (final StorePermission permission in StorePermission.values)
            _PermissionRow(
              title: permission.labelIn(t),
              subtitle: permission.descriptionIn(t),
              value: band.contains(permission),
              // The owner column is a statement of fact, not a control.
              onChanged: role == null || !_canManage
                  ? null
                  : (bool granted) => unawaited(_setBand(t, role, permission, granted)),
              busy: role != null && _busy.contains(_bandKey(role, permission)),
            ),
        ],
      ),
    );
  }

  static String _bandKey(StaffRole role, StorePermission permission) =>
      '${role.wireValue}:${permission.wireValue}';

  Future<void> _setBand(
    DeliveryStrings t,
    StaffRole role,
    StorePermission permission,
    bool granted,
  ) async {
    final StoreStaffApi? api = widget.api;
    final String? storeId = widget.storeId;
    if (api == null || storeId == null) {
      return;
    }
    await _write(
      t,
      key: _bandKey(role, permission),
      action: () => api.setRolePermission(storeId, role, permission, granted: granted),
      fallback: t.staffCouldNotLoad,
    );
  }

  // ------------------------------------------------------------------------------ member sheet

  /// One person's own panel: their role, their standing, and their seven switches.
  ///
  /// A sheet on a phone and a dialog on a desk, because a 400px-tall bottom sheet stuck to the
  /// bottom of a 1400px browser window is a phone control somebody forgot to redraw.
  Future<void> _openMember(
    DeliveryStrings t,
    StaffMember member, {
    required bool wide,
  }) async {
    final StoreStaffApi? api = widget.api;
    final String? storeId = widget.storeId;
    if (api == null || storeId == null || storeId.isEmpty) {
      return;
    }

    final Widget panel = _MemberPanel(
      api: api,
      storeId: storeId,
      member: member,
      canManage: _canManage,
      isSelf: widget.access.memberId == member.id,
    );

    final bool? changed = wide
        ? await showDialog<bool>(
            context: context,
            builder: (BuildContext context) => Dialog(
              backgroundColor: DeliveryColors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DeliveryRadius.sheet),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
                child: panel,
              ),
            ),
          )
        : await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            backgroundColor: DeliveryColors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(DeliveryRadius.sheet)),
            ),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.9,
            ),
            builder: (BuildContext context) => panel,
          );

    if ((changed ?? false) && mounted) {
      await _load(silent: true);
    }
  }
}

// ------------------------------------------------------------------------------- shared parts

/// The circular initials badge every roster row leads with.
///
/// Initials rather than a photo: the staff API carries no avatar, and a grey silhouette repeated
/// eight times tells a shopkeeper nothing about which row is which.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.label, required this.accent, this.dimmed = false});

  /// Already localised or a person's own name — only its first letters are drawn.
  final String label;
  final Color accent;
  final bool dimmed;

  static const double _size = 44;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dimmed ? DeliveryColors.borderFaint : DeliveryColors.brandSoft,
        shape: BoxShape.circle,
      ),
      child: Text(
        _initials(label),
        maxLines: 1,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: accent,
          height: 1.2,
        ),
      ),
    );
  }

  /// Up to two leading characters. Runes rather than [String.substring] so a name that starts with
  /// a surrogate pair is not cut in half.
  static String _initials(String name) {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return '?';
    }
    String head(String word) => String.fromCharCodes(word.runes.take(1)).toUpperCase();
    return parts.length == 1 ? head(parts.first) : '${head(parts.first)}${head(parts[1])}';
  }
}

/// A [YdBadge]-shaped note whose text is allowed to wrap.
///
/// [YdBadge] lays its label out in a `Row(mainAxisSize: min)`, which is right for the one- and
/// two-word states it was drawn for and wrong for a whole sentence: at 380dp the permission column
/// is 240px wide, and "Changed for this person" is wider than that in English, so the badge
/// overflows rather than wrapping. Same geometry, one fewer flex.
class _WrappingNote extends StatelessWidget {
  const _WrappingNote({required this.label, required this.accent});

  /// Already localised by the caller.
  final String label;
  final DeliveryAccent accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: DeliverySpacing.sm,
        vertical: DeliverySpacing.xs,
      ),
      decoration: BoxDecoration(
        color: accent.tint,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: accent.color,
          height: 1.2,
        ),
      ),
    );
  }
}

/// An invite code, drawn to be read out loud: monospace, wide-tracked, selectable.
class _CodeText extends StatelessWidget {
  const _CodeText({required this.code, this.dimmed = false, this.large = false});

  final String code;
  final bool dimmed;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      code,
      style: TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: const <String>['Courier New', 'monospace'],
        fontSize: large ? 26 : 16,
        fontWeight: FontWeight.w700,
        letterSpacing: large ? 4 : 2,
        height: 1.3,
        color: dimmed ? DeliveryColors.faint : DeliveryColors.ink,
      ),
      // A code is a literal, not prose: it reads left-to-right even in an Arabic layout.
      textDirection: TextDirection.ltr,
    );
  }
}

/// One permission, as a row: label, the sentence explaining what it hands over, and a switch.
///
/// A [ListTile] carrying its own [Switch] rather than a [SwitchListTile], for the same two reasons
/// `delivery_screen.dart` gives: a spinner where the thumb is while the change is in flight, and
/// text that stays at full contrast when the row is disabled — the sentence a disabled row mutes
/// is the one explaining what the toggle would do.
class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.busy = false,
    this.badge,
    this.onReset,
  });

  /// Already localised by the caller.
  final String title;
  final String subtitle;

  final bool value;

  /// Null draws the row read-only — the Owner column, and anybody without MANAGE_STAFF.
  final ValueChanged<bool>? onChanged;

  final bool busy;

  /// "Changed for this person", on the rows that carry a per-member override.
  final Widget? badge;

  /// Clears that override back to the role band.
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onChanged != null && !busy;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.xs),
      child: InkWell(
        borderRadius: BorderRadius.circular(merchantChipRadius),
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DeliverySpacing.sm,
            vertical: DeliverySpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Wrap(
                      spacing: DeliverySpacing.sm,
                      runSpacing: DeliverySpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: DeliveryColors.ink,
                            height: 1.3,
                          ),
                        ),
                        if (badge != null) badge!,
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: DeliveryColors.muted,
                        height: 1.35,
                      ),
                    ),
                    if (onReset != null)
                      Padding(
                        padding: const EdgeInsets.only(top: DeliverySpacing.xs),
                        child: InkWell(
                          onTap: busy ? null : onReset,
                          child: Text(
                            DeliveryStrings.of(context).staffResetToRole,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: DeliveryColors.brand,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              SizedBox(
                width: 52,
                child: Align(
                  // Directional: the switch belongs at the reading end, which is the left in an
                  // Arabic layout.
                  alignment: AlignmentDirectional.centerEnd,
                  child: busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: DeliveryColors.brand,
                          ),
                        )
                      : Switch(
                          value: value,
                          onChanged: enabled ? onChanged : null,
                          activeThumbColor: DeliveryColors.brand,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------------------- member panel

/// Everything that can be done to one employee, in one panel.
///
/// It holds its own copy of the member and re-reads the roster after each write, because every
/// write on [StoreStaffApi] answers with an empty body and a permission change can move more than
/// the row that was touched. `Navigator.pop(true)` tells the screen behind it to reload too.
class _MemberPanel extends StatefulWidget {
  const _MemberPanel({
    required this.api,
    required this.storeId,
    required this.member,
    required this.canManage,
    required this.isSelf,
  });

  final StoreStaffApi api;
  final String storeId;
  final StaffMember member;
  final bool canManage;

  /// Whether the caller is looking at their own row. Kept because the two things a person must not
  /// do to themselves — suspend and remove — are refused by the server, and a screen that offers
  /// them anyway is offering a guaranteed 403.
  final bool isSelf;

  @override
  State<_MemberPanel> createState() => _MemberPanelState();
}

class _MemberPanelState extends State<_MemberPanel> {
  late StaffMember _member = widget.member;
  final Set<String> _busy = <String>{};
  bool _changed = false;

  Future<void> _run(
    DeliveryStrings t, {
    required String key,
    required Future<void> Function() action,
    required String fallback,
    String? success,
    bool closeAfter = false,
  }) async {
    if (_busy.contains(key)) {
      return;
    }
    // Captured before the first await: the remove path pops this panel, and a messenger looked up
    // through a deactivated context is how a confirmation toast turns into a crash.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);

    setState(() => _busy.add(key));
    try {
      await action();
      _changed = true;
      if (closeAfter) {
        navigator.pop(true);
        if (success != null) {
          messenger.showSnackBar(SnackBar(content: Text(success)));
        }
        return;
      }
      // Re-read rather than patch: a role change re-resolves the whole permission set, and this
      // panel draws that set.
      final StoreRoster roster = await widget.api.roster(widget.storeId);
      if (!mounted) return;
      final Iterable<StaffMember> found =
          roster.members.where((StaffMember m) => m.id == _member.id);
      setState(() {
        if (found.isNotEmpty) {
          _member = found.first;
        }
        _busy.remove(key);
      });
      if (success != null) {
        messenger.showSnackBar(SnackBar(content: Text(success)));
      }
      return;
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(_refusalMessage(error, t, fallback: fallback))),
      );
    }
    if (mounted) {
      setState(() => _busy.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final StaffMember member = _member;
    final bool enabled = widget.canManage;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          MerchantScreenHeader(
            title: member.displayName.trim().isEmpty
                ? member.role.labelIn(t)
                : member.displayName,
            subtitle: member.role.labelIn(t),
            trailing: IconButton(
              onPressed: () => Navigator.of(context).pop(_changed),
              icon: const Icon(Icons.close, size: 20),
              color: DeliveryColors.ink,
              tooltip: t.cancel,
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(DeliverySpacing.lg),
              children: <Widget>[
                if (!enabled)
                  Padding(
                    padding: const EdgeInsets.only(bottom: DeliverySpacing.md),
                    child: Text(
                      t.staffNoPermission,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: DeliveryAccent.caution.color,
                        height: 1.35,
                      ),
                    ),
                  ),
                YdSectionHeader(title: t.staffChangeRole),
                const SizedBox(height: DeliverySpacing.sm),
                Wrap(
                  spacing: DeliverySpacing.sm,
                  runSpacing: DeliverySpacing.sm,
                  children: <Widget>[
                    for (final StaffRole role in StaffRole.values)
                      YdChip(
                        label: role.labelIn(t),
                        selected: member.role == role,
                        onTap: !enabled || member.role == role
                            ? null
                            : () => unawaited(_run(
                                  t,
                                  key: 'role',
                                  action: () => widget.api
                                      .changeRole(widget.storeId, member.id, role),
                                  fallback: t.staffCouldNotLoad,
                                )),
                      ),
                  ],
                ),
                const SizedBox(height: DeliverySpacing.lg),
                YdSectionHeader(
                  title: t.staffEditPermissions,
                  subtitle: t.staffRoleDefaults,
                ),
                for (final StorePermission permission in StorePermission.values)
                  _PermissionRow(
                    title: permission.labelIn(t),
                    subtitle: permission.descriptionIn(t),
                    value: member.can(permission),
                    busy: _busy.contains(permission.wireValue),
                    badge: member.overrides.containsKey(permission)
                        ? _WrappingNote(
                            label: t.staffCustomised,
                            accent: DeliveryAccent.info,
                          )
                        : null,
                    onReset: enabled && member.overrides.containsKey(permission)
                        ? () => unawaited(_run(
                              t,
                              key: permission.wireValue,
                              action: () => widget.api.setPermission(
                                widget.storeId,
                                member.id,
                                permission,
                                granted: null,
                              ),
                              fallback: t.staffCouldNotLoad,
                            ))
                        : null,
                    onChanged: !enabled
                        ? null
                        : (bool granted) => unawaited(_run(
                              t,
                              key: permission.wireValue,
                              action: () => widget.api.setPermission(
                                widget.storeId,
                                member.id,
                                permission,
                                granted: granted,
                              ),
                              fallback: t.staffCouldNotLoad,
                            )),
                  ),
                const SizedBox(height: DeliverySpacing.lg),
                if (enabled) ...<Widget>[
                  if (member.onShift)
                    Padding(
                      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
                      child: YdPillButton.secondary(
                        label: t.staffClockOut,
                        icon: Icons.logout,
                        size: YdPillButtonSize.compact,
                        busy: _busy.contains('shift'),
                        onPressed: () => unawaited(_run(
                          t,
                          key: 'shift',
                          action: () =>
                              widget.api.clockOut(widget.storeId, member.id),
                          fallback: t.staffCouldNotLoad,
                          success: t.staffClockedOut,
                        )),
                      ),
                    ),
                  // Suspending or removing yourself is refused server-side — a shop must not be
                  // able to lock its own manager out mid-shift — so the two controls are simply
                  // not drawn on your own row.
                  if (!widget.isSelf) ...<Widget>[
                    YdPillButton.secondary(
                      label: member.isActive ? t.staffDeactivate : t.staffActivate,
                      icon: member.isActive
                          ? Icons.pause_circle_outline
                          : Icons.play_circle_outline,
                      size: YdPillButtonSize.compact,
                      busy: _busy.contains('status'),
                      onPressed: () => unawaited(_run(
                        t,
                        key: 'status',
                        action: () => widget.api.setStatus(
                          widget.storeId,
                          member.id,
                          member.isActive ? StaffStatus.inactive : StaffStatus.active,
                        ),
                        fallback: t.staffCouldNotLoad,
                      )),
                    ),
                    const SizedBox(height: DeliverySpacing.sm),
                    // Removal is soft on the server — the row and its shifts stay on the record —
                    // but it is still the one action here that a merchant cannot undo from this
                    // screen, so it asks first and says what survives.
                    TextButton.icon(
                      onPressed: _busy.contains('remove')
                          ? null
                          : () => unawaited(_confirmRemove(t)),
                      icon: const Icon(Icons.person_remove_alt_1_outlined, size: 18),
                      label: Text(t.staffRemove),
                      style: TextButton.styleFrom(
                        foregroundColor: DeliveryAccent.critical.color,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(DeliveryStrings t) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(t.staffRemove),
        content: Text(t.staffRemoveConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.staffRemove),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) {
      return;
    }
    await _run(
      t,
      key: 'remove',
      action: () => widget.api.remove(widget.storeId, _member.id),
      fallback: t.staffCouldNotLoad,
      success: t.staffRemoved,
      closeAfter: true,
    );
  }
}

// ------------------------------------------------------------------------------ invite dialogs

/// "Add Employee" — which mints a code, not an account.
///
/// The name, email and phone are labels for the merchant's own benefit: they ride on the invite so
/// the pending row says who the code was cut for. None of them creates an identity, and none of
/// them is sent anywhere — the merchant reads the code out.
class _InviteDialog extends StatefulWidget {
  const _InviteDialog({required this.api, required this.storeId});

  final StoreStaffApi api;
  final String storeId;

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _phone = TextEditingController();

  StaffRole _role = StaffRole.cashier;
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _create(DeliveryStrings t) async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final StaffInvite invite = await widget.api.invite(
        widget.storeId,
        role: _role,
        displayName: _name.text.trim(),
        email: _email.text.trim(),
        phone: _phone.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pop(invite);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = _refusalMessage(error, t, fallback: t.somethingWentWrong);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String? failure = _failure;

    return AlertDialog(
      backgroundColor: DeliveryColors.white,
      title: Text(t.staffInvite),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                t.staffInviteRole,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DeliveryColors.muted,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: DeliverySpacing.sm),
              Wrap(
                spacing: DeliverySpacing.sm,
                runSpacing: DeliverySpacing.sm,
                children: <Widget>[
                  for (final StaffRole role in StaffRole.values)
                    YdChip(
                      label: role.labelIn(t),
                      selected: _role == role,
                      onTap: _busy ? null : () => setState(() => _role = role),
                    ),
                ],
              ),
              const SizedBox(height: DeliverySpacing.md),
              TextField(
                controller: _name,
                enabled: !_busy,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: t.staffInviteName),
              ),
              const SizedBox(height: DeliverySpacing.sm),
              TextField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: t.staffInviteEmail),
              ),
              const SizedBox(height: DeliverySpacing.sm),
              TextField(
                controller: _phone,
                enabled: !_busy,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: t.staffInvitePhone),
              ),
              const SizedBox(height: DeliverySpacing.md),
              Text(
                t.staffInviteCodeHint,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: DeliveryColors.faint,
                  height: 1.35,
                ),
              ),
              if (failure != null) ...<Widget>[
                const SizedBox(height: DeliverySpacing.sm),
                Text(
                  failure,
                  style: TextStyle(
                    fontSize: 12,
                    color: DeliveryAccent.critical.color,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        ElevatedButton(
          onPressed: _busy ? null : () => unawaited(_create(t)),
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.white),
                )
              : Text(t.staffInviteCreate),
        ),
      ],
    );
  }
}

/// The code, once it exists — the whole point of the invite flow.
///
/// Big, selectable and copyable, with the sentence that explains what the person on the other end
/// does with it. Nothing was emailed; this dialog *is* the delivery mechanism.
class _InviteCodeDialog extends StatelessWidget {
  const _InviteCodeDialog({required this.invite, required this.onCopy});

  final StaffInvite invite;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final DateTime? expiresAt = invite.expiresAt;

    return AlertDialog(
      backgroundColor: DeliveryColors.white,
      title: Text(t.staffInviteCode),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: DeliverySpacing.md,
                vertical: DeliverySpacing.md,
              ),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: DeliveryColors.brandSoft,
                borderRadius: BorderRadius.circular(DeliveryRadius.md),
              ),
              child: _CodeText(code: invite.code, large: true),
            ),
            const SizedBox(height: DeliverySpacing.md),
            Text(
              '${invite.role.labelIn(t)}${invite.displayName?.trim().isNotEmpty ?? false ? ' · ${invite.displayName}' : ''}',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.muted,
                height: 1.3,
              ),
            ),
            if (expiresAt != null) ...<Widget>[
              const SizedBox(height: DeliverySpacing.xs),
              Text(
                t.staffInviteExpires(_when(context, expiresAt)),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: DeliveryColors.faint,
                  height: 1.3,
                ),
              ),
            ],
            const SizedBox(height: DeliverySpacing.md),
            Text(
              t.staffInviteCodeHint,
              style: const TextStyle(
                fontSize: 11.5,
                color: DeliveryColors.muted,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.done),
        ),
        ElevatedButton.icon(
          onPressed: onCopy,
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: Text(t.staffInviteShare),
        ),
      ],
    );
  }
}

/// The employee's end of the same code.
///
/// Reachable only from the "you are not on a shop's team yet" state, which is exactly when
/// somebody has a code in their hand and nowhere to type it.
class _AcceptInviteDialog extends StatefulWidget {
  const _AcceptInviteDialog({required this.api});

  final StoreStaffApi api;

  @override
  State<_AcceptInviteDialog> createState() => _AcceptInviteDialogState();
}

class _AcceptInviteDialogState extends State<_AcceptInviteDialog> {
  final TextEditingController _code = TextEditingController();
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join(DeliveryStrings t) async {
    final String code = _code.text.trim();
    if (code.isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final StaffMembership membership = await widget.api.acceptInvite(code);
      if (mounted) {
        Navigator.of(context).pop(membership);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = _refusalMessage(error, t, fallback: t.staffAcceptFailed);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String? failure = _failure;

    return AlertDialog(
      backgroundColor: DeliveryColors.white,
      title: Text(t.staffAcceptTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _code,
              enabled: !_busy,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: t.staffAcceptCode),
              onSubmitted: (String _) => unawaited(_join(t)),
            ),
            const SizedBox(height: DeliverySpacing.sm),
            Text(
              t.staffInviteCodeHint,
              style: const TextStyle(
                fontSize: 11.5,
                color: DeliveryColors.faint,
                height: 1.35,
              ),
            ),
            if (failure != null) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              Text(
                failure,
                style: TextStyle(
                  fontSize: 12,
                  color: DeliveryAccent.critical.color,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        ElevatedButton(
          onPressed: _busy ? null : () => unawaited(_join(t)),
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.white),
                )
              : Text(t.staffAcceptJoin),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------------------------- helpers

/// A date and time in the reader's own locale, through [MaterialLocalizations] rather than `intl`
/// so this package stays out of the formatting dependency.
///
/// Today collapses to the time alone — an invite that expires in four hours is about the clock,
/// not about the calendar.
String _when(BuildContext context, DateTime at) {
  final MaterialLocalizations m = MaterialLocalizations.of(context);
  final DateTime local = at.toLocal();
  final DateTime now = DateTime.now();
  final String time = m.formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
  final bool today = local.year == now.year && local.month == now.month && local.day == now.day;
  return today ? time : '${m.formatMediumDate(local)} $time';
}

/// A refusal, worded so the merchant knows what they are short of.
///
/// product-service answers 403 with the missing capability in the problem body — top level on the
/// RFC 9457 document, or under `extensions` depending on the handler — and "you cannot change
/// this" alone leaves a shopkeeper with no idea which of seven switches to ask their owner for.
/// Anything else falls through to [_messageFor].
String _refusalMessage(Object error, DeliveryStrings t, {required String fallback}) {
  if (error is DioException && error.response?.statusCode == 403) {
    final StorePermission? needed = _requiredPermission(error.response?.data);
    if (needed != null) {
      return '${t.staffNoPermission} · ${needed.labelIn(t)}';
    }
    return t.staffNoPermission;
  }
  return _messageFor(error, fallback: fallback);
}

StorePermission? _requiredPermission(Object? body) {
  if (body is! Map<String, dynamic>) {
    return null;
  }
  final StorePermission? direct = StorePermission.fromWire(body['permission'] as String?);
  if (direct != null) {
    return direct;
  }
  final Object? extensions = body['extensions'];
  if (extensions is Map<String, dynamic>) {
    return StorePermission.fromWire(extensions['permission'] as String?);
  }
  return null;
}

/// Pulls the human-readable half out of an RFC 9457 problem response.
///
/// A file-private copy of `product_list_screen.dart`'s, pending the spec's promotion of it into
/// `order_detail_screen.dart` beside `merchantMoney` — done centrally, so this file does not race
/// another screen for the same edit.
String _messageFor(Object error, {required String fallback}) {
  if (error is DioException) {
    final Object? body = error.response?.data;
    if (body is Map<String, dynamic>) {
      final String? detail = body['detail'] as String?;
      final String? correlationId = body['correlationId'] as String?;
      if (detail != null) {
        return correlationId == null ? detail : '$detail (ref: $correlationId)';
      }
    }
  }
  return fallback;
}
