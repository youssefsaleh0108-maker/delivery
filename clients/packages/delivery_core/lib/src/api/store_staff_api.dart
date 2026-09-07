import 'package:dio/dio.dart';

import '../models/staff_models.dart';

/// Typed client for product-service's staff endpoints — who works at a shop and what they may do.
///
/// Named `StoreStaffApi`, not `StaffApi`, and the distinction is load-bearing:
/// `DeliveryProviderApi.addStaff/removeStaff` is a *carrier's* staff on order-manager. A screen
/// wired to the wrong one of these would compile, run, and administer a different company.
///
/// Every write here returns nothing. The server answers 200 with an empty body because a roster
/// change can affect other rows (a role band re-resolves everybody on that role), so the honest
/// response is "read it again" — call [roster] after a write rather than patching a member locally.
class StoreStaffApi {
  StoreStaffApi(this._dio);

  final Dio _dio;

  // ---------------------------------------------------------------- the caller's own standing

  /// Who am I here, and what may I do? The call a merchant shell makes on start-up to decide which
  /// tabs to draw.
  ///
  /// Answers for the owner too, who has no roster row: `owner: true`, every permission, no member
  /// id. A caller with no relationship to the store gets 404 rather than 403 — a stranger should
  /// not learn the shop exists — so treat a failure here as "no access", not as an outage.
  Future<StoreStaffAccess> access(String storeId) async {
    final Response<dynamic> response = await _dio.get<dynamic>('${_base(storeId)}/me');
    return StoreStaffAccess.fromJson(response.data as Map<String, dynamic>);
  }

  /// Where do I work? The login probe, made before any store id is known.
  ///
  /// Returns `member: false` rather than failing when the caller works nowhere — that is an
  /// ordinary answer for every customer on the platform.
  Future<StaffMembership> myMembership() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/stores/staff/membership');
    return StaffMembership.fromJson(response.data as Map<String, dynamic>);
  }

  /// Redeems an invite code with the caller's own token — the only way a membership is created.
  ///
  /// 409 when the caller already works somewhere: one active employment per person.
  Future<StaffMembership> acceptInvite(String code) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/stores/staff/accept',
      data: <String, dynamic>{'code': code},
    );
    return StaffMembership.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- the employer's view

  /// The whole staff screen in one call: members, pending invite codes, and the store's permission
  /// band per role. Requires MANAGE_STAFF.
  Future<StoreRoster> roster(String storeId) async {
    final Response<dynamic> response = await _dio.get<dynamic>(_base(storeId));
    return StoreRoster.fromJson(response.data as Map<String, dynamic>);
  }

  /// Issues an invite code for somebody to redeem. 8-12 characters, valid 24 hours.
  ///
  /// No account is created here and no password is set: the platform never mints an identity on a
  /// merchant's say-so. The merchant shares the code; the employee redeems it as themselves.
  Future<StaffInvite> invite(
    String storeId, {
    required StaffRole role,
    String? displayName,
    String? email,
    String? phone,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '${_base(storeId)}/invites',
      data: <String, dynamic>{
        'role': role.wireValue,
        if (displayName != null && displayName.isNotEmpty) 'displayName': displayName,
        if (email != null && email.isNotEmpty) 'email': email,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      },
    );
    return StaffInvite.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- member writes

  /// Moves somebody to a different role, which re-resolves their effective permissions against
  /// that role's band. Per-person overrides survive.
  Future<void> changeRole(String storeId, String memberId, StaffRole role) =>
      _dio.put<void>(
        '${_base(storeId)}/$memberId/role',
        data: <String, dynamic>{'role': role.wireValue},
      );

  /// Suspends or reinstates somebody. Going INACTIVE closes any open attendance shift — a person
  /// who may not act must not still be counted as on the floor.
  Future<void> setStatus(String storeId, String memberId, StaffStatus status) =>
      _dio.put<void>(
        '${_base(storeId)}/$memberId/status',
        data: <String, dynamic>{'status': status.wireValue},
      );

  /// Grants or revokes ONE permission for ONE person.
  ///
  /// A null [granted] clears the override and returns them to their role's band — the only way
  /// back to "whatever a cashier gets here" once somebody has been special-cased. 403 if the
  /// caller does not themselves hold the permission being granted.
  Future<void> setPermission(
    String storeId,
    String memberId,
    StorePermission permission, {
    required bool? granted,
  }) =>
      _dio.put<void>(
        '${_base(storeId)}/$memberId/permissions',
        data: <String, dynamic>{
          'permission': permission.wireValue,
          'granted': granted,
        },
      );

  /// Takes somebody off the roster. Soft: the row stays and any open shift is closed, because
  /// shifts and audit entries point at it and a rota that cannot name who worked a till is
  /// worthless.
  Future<void> remove(String storeId, String memberId) =>
      _dio.delete<void>('${_base(storeId)}/$memberId');

  /// Edits the store's own band for a whole role — the "edit all" column on the permissions panel.
  ///
  /// Affects every active member on that role at once, so the screen must reload the roster rather
  /// than assuming only the toggled row changed.
  Future<void> setRolePermission(
    String storeId,
    StaffRole role,
    StorePermission permission, {
    required bool granted,
  }) =>
      _dio.put<void>(
        '${_base(storeId)}/roles/${role.wireValue}/permissions',
        data: <String, dynamic>{
          'permission': permission.wireValue,
          'granted': granted,
        },
      );

  // ---------------------------------------------------------------- attendance

  /// Clocks the CALLER in. There is no member id: you can only start your own shift.
  ///
  /// 409 when a shift is already open, which the clock bar should read as "you are already on" and
  /// not as an error worth a red snackbar.
  Future<void> clockIn(String storeId) => _dio.post<void>('${_base(storeId)}/shifts');

  /// Clocks somebody out. A member ends their own; a manager may end anybody's, which is what
  /// happens when a cashier goes home without touching the app.
  Future<void> clockOut(String storeId, String memberId) =>
      _dio.delete<void>('${_base(storeId)}/$memberId/shifts');

  static String _base(String storeId) =>
      '/api/stores/${Uri.encodeComponent(storeId)}/staff';
}
