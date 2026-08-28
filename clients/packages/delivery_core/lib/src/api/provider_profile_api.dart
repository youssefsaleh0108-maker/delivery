import 'package:dio/dio.dart';

import '../models/onboarding_models.dart';
import '../models/provider_profile_models.dart';

/// Client for a delivery company's own settings — logo, dispatch regions, operating hours.
///
/// Every CARRIER write is ownership-checked server-side against who actually runs [providerId]
/// (403 otherwise); BACKOFFICE may read any company but writes nothing here.
class ProviderProfileApi {
  ProviderProfileApi(this._dio);

  final Dio _dio;

  /// The company's profile. CARRIER (own company) or BACKOFFICE (any, read-only).
  ///
  /// A company that never saved settings gets the empty shape, never a 404 — render the empty
  /// form, not an error.
  Future<ProviderProfile> profile(String providerId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/onboarding/providers/$providerId/profile');
    return ProviderProfile.fromJson(response.data as Map<String, dynamic>);
  }

  /// Saves the whole form. CARRIER only.
  ///
  /// PUT semantics on purpose: what is sent replaces what was stored, so a deleted region stays
  /// deleted and a day left out of [operatingHours] is closed that day. Both fields are required
  /// and may be empty. Deep validation — day names, `HH:mm`, open before close, region cap — is
  /// server-side and refuses with 422.
  Future<ProviderProfile> save(
    String providerId, {
    required List<String> dispatchRegions,
    required Map<String, DayHours> operatingHours,
  }) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/onboarding/providers/$providerId/profile',
      data: <String, dynamic>{
        'dispatchRegions': dispatchRegions,
        'operatingHours': ProviderProfile.hoursToJson(operatingHours),
      },
    );
    return ProviderProfile.fromJson(response.data as Map<String, dynamic>);
  }

  /// Step 1 of the logo upload: asks for a one-shot upload slot. CARRIER only.
  ///
  /// The same three-step dance as document uploads — presign, PUT the bytes straight to
  /// [DocumentUploadTicket.uploadUrl] (never through this service, and with exactly the signed
  /// content type), then [confirmLogo] with the ticket's file id.
  Future<DocumentUploadTicket> presignLogo(String providerId, String contentType) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/onboarding/providers/$providerId/profile/logo/presign',
      data: <String, dynamic>{'contentType': contentType},
    );
    return DocumentUploadTicket.fromJson(response.data as Map<String, dynamic>);
  }

  /// Step 3: tells the service the PUT landed. CARRIER only. Returns the profile with the new
  /// `logoUrl`; a storage problem is a 422 whose message tells the user to upload again.
  Future<ProviderProfile> confirmLogo(String providerId, String fileId) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/onboarding/providers/$providerId/profile/logo/confirm',
      data: <String, dynamic>{'fileId': fileId},
    );
    return ProviderProfile.fromJson(response.data as Map<String, dynamic>);
  }
}
