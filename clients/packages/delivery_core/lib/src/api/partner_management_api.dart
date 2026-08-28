import 'package:dio/dio.dart';

import '../models/partner_management_models.dart';

/// Client for keeping partner records straight after approval: corrections, the audit trail, and
/// the suspension switch.
///
/// Split from [OnboardingApi] the way the server splits the work: that class is about deciding
/// applications, this one is about managing partners who already exist. Two audiences share it —
/// BACKOFFICE on the plain paths for any partner, and CARRIER on the `for-company` paths for their
/// own riders only, double-checked server-side against who actually runs the company.
class PartnerManagementApi {
  PartnerManagementApi(this._dio);

  final Dio _dio;

  // ---------------------------------------------------------------- record corrections

  /// Corrects a partner's record. BACKOFFICE only. Absent fields stay unchanged; there is no way
  /// to blank a field (whitespace-only is refused).
  ///
  /// Two asymmetries the screen must reflect: changing the phone nulls `phoneVerifiedAt` — a new
  /// number is a number nobody confirmed — while changing the email keeps `emailVerifiedAt` and
  /// does NOT change the sign-in username. Every changed field writes an audit row; a no-op PATCH
  /// writes none.
  Future<PartnerRecordView> edit(
    String id, {
    String? businessName,
    String? contactName,
    String? contactEmail,
    String? contactPhone,
  }) async {
    final Response<dynamic> response = await _dio.patch<dynamic>(
      '/api/onboarding/applications/$id',
      data: <String, dynamic>{
        if (businessName != null) 'businessName': businessName,
        if (contactName != null) 'contactName': contactName,
        if (contactEmail != null) 'contactEmail': contactEmail,
        if (contactPhone != null) 'contactPhone': contactPhone,
      },
    );
    return PartnerRecordView.fromJson(response.data as Map<String, dynamic>);
  }

  /// Every correction ever made to this record, newest first. BACKOFFICE only. Empty when the
  /// record was never edited.
  Future<List<PartnerAuditEntry>> audit(String id) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/onboarding/applications/$id/audit');
    return (response.data as List<dynamic>)
        .map((dynamic e) => PartnerAuditEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------- suspension (platform)

  /// Suspends a partner. BACKOFFICE only; [reason] is required — "suspended" with no reason is
  /// not a record anybody can act on later.
  ///
  /// What it does: revokes the partner's live realm role, so committing endpoints across the
  /// platform refuse them — while sign-in keeps working, because their history stays theirs to
  /// read. Idempotent: re-suspending returns the standing unchanged and records nothing.
  Future<PartnerStanding> suspend(String id, SuspensionReason reason, {String? note}) =>
      _flip('/api/onboarding/applications/$id/suspend', reason: reason, note: note);

  /// Reinstates a partner, re-granting the role. BACKOFFICE only. Idempotent the same way.
  Future<PartnerStanding> unsuspend(String id, {String? note}) =>
      _flip('/api/onboarding/applications/$id/unsuspend', note: note);

  /// The standing plus its whole history, newest first. BACKOFFICE only.
  Future<PartnerSuspensionRecord> suspension(String id) =>
      _record('/api/onboarding/applications/$id/suspension');

  // ---------------------------------------------------------------- suspension (carrier's riders)

  /// Suspends one of the company's own riders. CARRIER only, double-gated server-side: the caller
  /// must actually run [providerId] (403 otherwise — checked against the staff record, never
  /// trusted from the URL), and [id] must be a RIDER application addressed to that company
  /// (422 otherwise). Same shapes and idempotence as the platform side.
  Future<PartnerStanding> suspendRider(
          String providerId, String id, SuspensionReason reason, {String? note}) =>
      _flip('/api/onboarding/applications/for-company/$providerId/$id/suspend',
          reason: reason, note: note);

  /// Reinstates one of the company's own riders. CARRIER only, gated as [suspendRider].
  Future<PartnerStanding> unsuspendRider(String providerId, String id, {String? note}) =>
      _flip('/api/onboarding/applications/for-company/$providerId/$id/unsuspend', note: note);

  /// A rider's standing and history, gated as [suspendRider]. CARRIER only.
  Future<PartnerSuspensionRecord> riderSuspension(String providerId, String id) =>
      _record('/api/onboarding/applications/for-company/$providerId/$id/suspension');

  // ---------------------------------------------------------------- internals

  Future<PartnerStanding> _flip(String path, {SuspensionReason? reason, String? note}) async {
    final Map<String, dynamic> body = <String, dynamic>{
      if (reason != null) 'reason': reason.wire,
      if (note != null && note.isNotEmpty) 'note': note,
    };
    final Response<dynamic> response =
        await _dio.post<dynamic>(path, data: body.isEmpty ? null : body);
    return PartnerStanding.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PartnerSuspensionRecord> _record(String path) async {
    final Response<dynamic> response = await _dio.get<dynamic>(path);
    return PartnerSuspensionRecord.fromJson(response.data as Map<String, dynamic>);
  }
}
