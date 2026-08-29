import 'package:dio/dio.dart';

import '../models/auto_approval_models.dart';

/// Whether the platform reads applications or waves them through — BACKOFFICE only.
///
/// This was an environment variable and a container restart until it grew these two endpoints, which
/// is why it is worth saying what the API is *for*: turning a kind on here means somebody with a
/// verified email address becomes a live rider or shop with nobody reading their papers. The
/// endpoints are the deliberate act, and the response carries who did it — an operator asking "who
/// opened this" gets an answer instead of a git blame on a deployment manifest.
class AutoApprovalApi {
  AutoApprovalApi(this._dio);

  final Dio _dio;

  static const String _path = '/api/onboarding/admin/auto-approval';

  Future<AutoApprovalSettings> get() async {
    final Response<dynamic> response = await _dio.get<dynamic>(_path);
    return AutoApprovalSettings.fromJson(response.data as Map<String, dynamic>);
  }

  /// Sets all three at once.
  ///
  /// Every kind is named on every call because the contract requires all three and takes no nulls:
  /// there is no "leave that one alone" on the wire, so a caller changing one switch has to send
  /// what the other two currently are. Making them required arguments is what stops a caller
  /// silently sending `false` for a kind it simply had not thought about — which would turn a gate
  /// back on, or off, behind somebody's back.
  ///
  /// Returns the server's own view afterwards, including the new [AutoApprovalSettings.lastChangedBy]
  /// and each kind's source now reading `PORTAL`. Callers render that rather than what they sent.
  Future<AutoApprovalSettings> update({
    required bool rider,
    required bool merchant,
    required bool carrier,
  }) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      _path,
      data: <String, dynamic>{'rider': rider, 'merchant': merchant, 'carrier': carrier},
    );
    return AutoApprovalSettings.fromJson(response.data as Map<String, dynamic>);
  }
}
