import 'package:dio/dio.dart';

import '../models/partner_job_models.dart';
import '../network/api_client.dart';

/// Client for the partner job board — the machine surface behind an `X-API-Key`.
///
/// This is the other side of [PartnerApiKeysApi]: that one is a human minting credentials, this one
/// is what a credential can actually read. It is here so the carrier portal can prove a freshly
/// minted key works — "test this key" against the real endpoint, rather than a screen that mints a
/// secret and leaves the operator to find out later whether it opens anything.
///
/// The key is passed per call and never stored: the app holds it only for as long as the operator
/// has it on screen (it is shown exactly once), and a key kept in client storage would be a
/// long-lived credential sitting somewhere it was never meant to live.
class PartnerJobsApi {
  PartnerJobsApi(this._dio);

  final Dio _dio;

  /// The company's claimable and in-flight work, resolved entirely from [apiKey].
  ///
  /// Authenticated by the key ALONE — the bearer token is deliberately suppressed, because a stale
  /// session's `Authorization` header would be rejected by the JWT chain before the key filter ran.
  /// Nothing in the request names a company: the key IS the company, so there is no id to get wrong
  /// and nothing to probe anyone else's board with.
  ///
  /// Throws on 401, which is the single answer to an unknown key, a revoked key and a suspended
  /// company — the server does not distinguish them and neither should the screen.
  Future<PartnerJobs> jobs({required String apiKey}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/partner/jobs',
      options: Options(
        headers: <String, dynamic>{'X-API-Key': apiKey},
        extra: <String, dynamic>{ApiClient.skipAuth: true},
      ),
    );
    return PartnerJobs.fromJson(response.data as Map<String, dynamic>);
  }
}
