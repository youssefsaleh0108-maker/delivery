/// Who works at a shop, what they are allowed to do, and who is on the floor right now.
///
/// Mirrors product-service's `StoreStaffController` and `StaffMembershipController` — staff was
/// deliberately folded into product-service rather than given a service of its own, because the
/// thing being authorised (a store) already lives there.
///
/// Two ideas are kept apart on purpose:
/// * [StaffMember] / [StoreRoster] — the employer's view. Everybody who works here.
/// * [StoreStaffAccess] / [StaffMembership] — the caller's own view. What *I* may do here.
///
/// The owner is never a [StaffMember]: ownership is `stores.merchant_id == sub`, not a row, so
/// there is no way to demote or delete an owner out of their own shop. [StoreStaffAccess.owner]
/// is how the owner appears on the client, holding every permission with no member id.
library;

/// The job a member does at a shop. Exactly the backend's three — OWNER is absent by design.
enum StaffRole {
  manager('MANAGER', 'Manager'),
  cashier('CASHIER', 'Cashier'),
  stockkeeper('STOCKKEEPER', 'Stockkeeper');

  const StaffRole(this.wireValue, this.label);

  final String wireValue;

  /// English fallback. Never render this — go through `labelIn(DeliveryStrings)`.
  final String label;

  /// Unknown wire values fall to [cashier]: least privilege, so a role this build has never heard
  /// of cannot be mistaken for a manager.
  static StaffRole fromWire(String? value) {
    for (final StaffRole role in StaffRole.values) {
      if (role.wireValue == value) {
        return role;
      }
    }
    return StaffRole.cashier;
  }

  /// Null rather than a guess, for the places where "no role" is a real answer — the owner's
  /// membership row does not exist.
  static StaffRole? maybeFromWire(String? value) {
    for (final StaffRole role in StaffRole.values) {
      if (role.wireValue == value) {
        return role;
      }
    }
    return null;
  }
}

/// What a shop member is allowed to do — the wire vocabulary, exactly seven values.
///
/// This is what pos-, inventory- and reporting-service enforce against. An eighth value would mean
/// changing every consumer, so [fromWire] returns **null** for anything it does not recognise and
/// callers filter with `whereType` rather than substituting a default: silently inventing a
/// permission is the one failure mode worth being loud about.
enum StorePermission {
  posSales('POS_SALES', 'Sell at the register'),
  posRefundsVoids('POS_REFUNDS_VOIDS', 'Refunds and voids'),
  modifyInventoryPricing('MODIFY_INVENTORY_PRICING', 'Edit products and stock'),
  manageOrders('MANAGE_ORDERS', 'Manage delivery orders'),
  viewReports('VIEW_REPORTS', 'View reports'),
  accessSettings('ACCESS_SETTINGS', 'Change store settings'),
  manageStaff('MANAGE_STAFF', 'Manage staff');

  const StorePermission(this.wireValue, this.label);

  final String wireValue;

  /// English fallback. Never render this — go through `labelIn(DeliveryStrings)`.
  final String label;

  static StorePermission? fromWire(String? value) {
    for (final StorePermission permission in StorePermission.values) {
      if (permission.wireValue == value) {
        return permission;
      }
    }
    return null;
  }

  /// Parses a wire list, dropping anything this build does not know.
  static Set<StorePermission> setFromJson(Object? value) => <StorePermission>{
        ...(value as List<dynamic>? ?? <dynamic>[])
            .map((dynamic p) => StorePermission.fromWire(p as String?))
            .whereType<StorePermission>(),
      };

  /// Everything — what an owner holds by definition and without a row.
  static Set<StorePermission> get all => StorePermission.values.toSet();
}

/// Whether a member may still act. Distinct from removal, which stamps `removedAt`.
enum StaffStatus {
  active('ACTIVE', 'Active'),
  inactive('INACTIVE', 'Inactive');

  const StaffStatus(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static StaffStatus fromWire(String? value) {
    for (final StaffStatus status in StaffStatus.values) {
      if (status.wireValue == value) {
        return status;
      }
    }
    return StaffStatus.inactive;
  }
}

/// One person on the roster, as the employer sees them.
class StaffMember {
  const StaffMember({
    required this.id,
    required this.displayName,
    required this.role,
    required this.status,
    this.email,
    this.phone,
    this.permissions = const <StorePermission>{},
    this.overrides = const <StorePermission, bool>{},
    this.onShift = false,
    this.lastSeenAt,
    this.addedAt,
  });

  final String id;
  final String displayName;
  final StaffRole role;
  final StaffStatus status;
  final String? email;
  final String? phone;

  /// EFFECTIVE permissions: the store's band for the role with this person's overrides applied,
  /// resolved by the server. Render toggles from this, never from role defaults.
  final Set<StorePermission> permissions;

  /// Only the deliberate per-person exceptions, so a screen can show "changed from the Cashier
  /// default" and offer a way back. Absent from the map means "whatever the role gets".
  final Map<StorePermission, bool> overrides;

  /// Clocked in right now. Attendance, not authorisation.
  final bool onShift;
  final DateTime? lastSeenAt;
  final DateTime? addedAt;

  bool can(StorePermission permission) => permissions.contains(permission);

  bool get isActive => status == StaffStatus.active;

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
        id: json['id'] as String,
        displayName: json['displayName'] as String? ?? '',
        role: StaffRole.fromWire(json['role'] as String?),
        status: StaffStatus.fromWire(json['status'] as String?),
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        permissions: StorePermission.setFromJson(json['permissions']),
        overrides: _overridesFromJson(json['overrides']),
        onShift: json['onShift'] as bool? ?? false,
        lastSeenAt: DateTime.tryParse(json['lastSeenAt'] as String? ?? ''),
        addedAt: DateTime.tryParse(json['addedAt'] as String? ?? ''),
      );

  static Map<StorePermission, bool> _overridesFromJson(Object? value) {
    final Map<String, dynamic> raw =
        (value as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{}).cast<String, dynamic>();
    final Map<StorePermission, bool> overrides = <StorePermission, bool>{};
    raw.forEach((String key, dynamic granted) {
      final StorePermission? permission = StorePermission.fromWire(key);
      if (permission != null && granted is bool) {
        overrides[permission] = granted;
      }
    });
    return overrides;
  }
}

/// An unredeemed invite code. The ONLY way a membership is created: the platform never mints an
/// account on a merchant's say-so, so the employee redeems this with their own token.
class StaffInvite {
  const StaffInvite({
    required this.code,
    required this.role,
    this.displayName,
    this.email,
    this.expiresAt,
  });

  final String code;
  final StaffRole role;
  final String? displayName;
  final String? email;
  final DateTime? expiresAt;

  /// Codes live 24 hours. Unknown expiry is treated as still valid — refusing to show a code
  /// because the field was missing helps nobody.
  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());

  factory StaffInvite.fromJson(Map<String, dynamic> json) => StaffInvite(
        code: json['code'] as String,
        role: StaffRole.fromWire(json['role'] as String?),
        displayName: json['displayName'] as String?,
        email: json['email'] as String?,
        expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
      );
}

/// Everything the staff screen draws in one response: the people, the codes still outstanding, and
/// the store's own permission band per role.
class StoreRoster {
  const StoreRoster({
    this.members = const <StaffMember>[],
    this.invites = const <StaffInvite>[],
    this.roleBands = const <StaffRole, Set<StorePermission>>{},
  });

  final List<StaffMember> members;

  /// Pending only — the server does not return redeemed codes.
  final List<StaffInvite> invites;

  /// What this store grants each role before per-person overrides. Editable by MANAGE_STAFF, which
  /// is why it travels with the roster instead of being a client-side constant.
  final Map<StaffRole, Set<StorePermission>> roleBands;

  Set<StorePermission> bandFor(StaffRole role) =>
      roleBands[role] ?? const <StorePermission>{};

  List<StaffMember> get onShift =>
      members.where((StaffMember m) => m.onShift).toList(growable: false);

  bool get isEmpty => members.isEmpty && invites.isEmpty;

  factory StoreRoster.fromJson(Map<String, dynamic> json) => StoreRoster(
        members: (json['members'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic m) => StaffMember.fromJson(m as Map<String, dynamic>))
            .toList(),
        invites: (json['invites'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic i) => StaffInvite.fromJson(i as Map<String, dynamic>))
            .toList(),
        roleBands: _bandsFromJson(json['roleBands']),
      );

  static Map<StaffRole, Set<StorePermission>> _bandsFromJson(Object? value) {
    final Map<String, dynamic> raw =
        (value as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{}).cast<String, dynamic>();
    final Map<StaffRole, Set<StorePermission>> bands = <StaffRole, Set<StorePermission>>{};
    raw.forEach((String key, dynamic permissions) {
      final StaffRole? role = StaffRole.maybeFromWire(key);
      if (role != null) {
        bands[role] = StorePermission.setFromJson(permissions);
      }
    });
    return bands;
  }
}

/// The caller's own standing in one store — the answer to "which tabs do I draw?".
///
/// UI-only. The server enforces every one of these on every call; this exists so a cashier is not
/// shown a Reports tab that will only 403 when tapped.
class StoreStaffAccess {
  const StoreStaffAccess({
    required this.member,
    required this.owner,
    this.memberId,
    this.role,
    this.permissions = const <StorePermission>{},
  });

  /// The shop's owner: every permission, no member id, cannot be removed.
  const StoreStaffAccess.owner()
      : member = false,
        owner = true,
        memberId = null,
        role = null,
        permissions = const <StorePermission>{};

  /// Somebody with no relationship to this store. Draws nothing.
  const StoreStaffAccess.none()
      : member = false,
        owner = false,
        memberId = null,
        role = null,
        permissions = const <StorePermission>{};

  /// An employee with a roster row.
  const StoreStaffAccess.staff({
    required String this.memberId,
    required StaffRole this.role,
    required this.permissions,
  })  : member = true,
        owner = false;

  /// Whether the caller holds a `staff_members` row here. False for the owner, who has none.
  final bool member;
  final bool owner;
  final String? memberId;

  /// Null for the owner — ownership is not a role.
  final StaffRole? role;

  /// Empty for the owner; [can] short-circuits before reading it.
  final Set<StorePermission> permissions;

  bool get isOwner => owner;

  bool get isStaff => member && !owner;

  /// True when the caller has any standing here at all. False means the shop should not even be
  /// named — the server answers 404 rather than 403 for exactly this reason.
  bool get hasAccess => owner || member;

  bool can(StorePermission permission) => owner || permissions.contains(permission);

  /// The effective set, with the owner's implicit everything spelled out — for a panel that draws
  /// seven toggles and must show the owner's as all-on.
  Set<StorePermission> get effectivePermissions =>
      owner ? StorePermission.all : permissions;

  factory StoreStaffAccess.fromJson(Map<String, dynamic> json) => StoreStaffAccess(
        member: json['member'] as bool? ?? false,
        owner: json['owner'] as bool? ?? false,
        memberId: json['memberId'] as String?,
        role: StaffRole.maybeFromWire(json['role'] as String?),
        permissions: StorePermission.setFromJson(json['permissions']),
      );
}

/// The spec's name for the same capability view, kept so screens can read either.
typedef MerchantAccess = StoreStaffAccess;

/// Where do I work? The login probe, answered without a store id because the employee does not
/// know one yet.
///
/// `member: false` rather than a 404 — "you are not staff anywhere" is an ordinary answer.
class StaffMembership {
  const StaffMembership({
    required this.member,
    this.storeId,
    this.memberId,
    this.role,
    this.status,
    this.displayName,
  });

  final bool member;
  final String? storeId;
  final String? memberId;
  final StaffRole? role;
  final StaffStatus? status;
  final String? displayName;

  bool get isEmployed => member && storeId != null;

  factory StaffMembership.fromJson(Map<String, dynamic> json) => StaffMembership(
        member: json['member'] as bool? ?? false,
        storeId: json['storeId'] as String?,
        memberId: json['memberId'] as String?,
        role: StaffRole.maybeFromWire(json['role'] as String?),
        status: json['status'] == null
            ? null
            : StaffStatus.fromWire(json['status'] as String?),
        displayName: json['displayName'] as String?,
      );
}
