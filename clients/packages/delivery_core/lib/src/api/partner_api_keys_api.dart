import 'package:dio/dio.dart';

import '../models/partner_key_models.dart';

/// Client for a carrier's machine credentials — the keys their dispatch software presents on
/// `X-API-Key` instead of a person signing in.
///
/// All three calls are the HUMAN side: role CARRIER, ordinary JWT auth, and always scoped to the
/// caller's own company (resolved from their user id — no provider id travels in any request).
/// A CARRIER who belongs to no company gets 404 on every one of them.
class PartnerApiKeysApi {
  PartnerApiKeysApi(this._dio);

  final Dio _dio;

  /// Mints a key.
  ///
  /// The response is the ONLY place the full secret ever appears — it is hashed server-side and
  /// not stored, so the screen shows it once with copy-now UX and there is no way to fetch it
  /// again. [label] is a human name for the key ("dispatch box"), ≤80 chars, optional.
  Future<PartnerApiKeyCreated> create({String? label}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/partner-keys',
      data: label == null || label.isEmpty ? null : <String, dynamic>{'label': label},
    );
    return PartnerApiKeyCreated.fromJson(response.data as Map<String, dynamic>);
  }

  /// Every key the company ever minted, newest first — revoked ones included and flagged, because
  /// the listing is the record of what existed, not just what works. Never carries a secret.
  Future<List<PartnerApiKey>> list() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/partner-keys');
    return (response.data as List<dynamic>)
        .map((dynamic k) => PartnerApiKey.fromJson(k as Map<String, dynamic>))
        .toList();
  }

  /// Revokes a key, effective immediately.
  ///
  /// Idempotent — revoking a revoked key succeeds quietly. Another company's key, like an unknown
  /// id, is a 404: keys are not enumerable across companies.
  Future<void> revoke(String id) async {
    await _dio.delete<dynamic>('/api/partner-keys/$id');
  }
}
