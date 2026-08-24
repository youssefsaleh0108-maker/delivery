import 'package:dio/dio.dart';

import '../models/onboarding_models.dart';

/// The reviewer's side of joining the platform.
///
/// Applying is open to anybody and lives on the public website; everything here needs BACKOFFICE.
/// The split is the point: one endpoint creates a request for review and nothing else, and these
/// are the ones that create an account, a delivery company and a commercial relationship.
class OnboardingApi {
  OnboardingApi(this._dio);

  final Dio _dio;

  // ------------------------------------------------------------------ applying

  /// The delivery companies somebody could apply to ride for. No token: they have no account yet.
  Future<List<HiringCompany>> hiringCompanies() async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/delivery-providers/hiring');
    return (response.data as List<dynamic>)
        .map((dynamic c) => HiringCompany.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  /// Sends a one-time code. Returns when it expires, which is all the server says.
  Future<DateTime> requestCode(String channel, String destination) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
        '/api/onboarding/verifications',
        data: <String, dynamic>{'channel': channel, 'destination': destination});
    return DateTime.parse((response.data as Map<String, dynamic>)['expiresAt'] as String);
  }

  /// Answers it. The destination comes back normalised, and that is the spelling to submit.
  Future<({String token, String destination})> confirmCode(
      String channel, String destination, String code) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
        '/api/onboarding/verifications/confirm',
        data: <String, dynamic>{'channel': channel, 'destination': destination, 'code': code});
    final Map<String, dynamic> body = response.data as Map<String, dynamic>;
    return (token: body['token'] as String, destination: body['destination'] as String);
  }

  /// Creates a shopper's own account.
  ///
  /// Not an application: a shopper is not reviewed, so this returns having already created the
  /// account rather than a reference to follow. The caller signs in immediately afterwards with
  /// the credentials just chosen.
  ///
  /// The token is the same proof the reviewed path uses, from [confirmCode] on this address. It is
  /// what stops the endpoint creating accounts on addresses the caller does not own.
  Future<void> signUp({
    required String email,
    required String verificationToken,
    required String firstName,
    String? lastName,
    required String password,
  }) async {
    await _dio.post<dynamic>('/api/onboarding/signup', data: <String, dynamic>{
      'email': email,
      'verificationToken': verificationToken,
      'firstName': firstName,
      'lastName': lastName,
      'password': password,
    });
  }

  /// Applies to ride, either for one delivery company or for MyDelivery itself.
  ///
  /// [companyId] null means the second of those: no company is named, so the application is the
  /// platform's own to decide and lands in the backoffice queue rather than a company's.
  Future<String> applyAsRider({
    required String name,
    required String email,
    required String emailVerificationToken,
    String? companyId,
    String? phone,
    String? phoneVerificationToken,
    String? notes,
  }) async {
    final Response<dynamic> response =
        await _dio.post<dynamic>('/api/onboarding/applications', data: <String, dynamic>{
      'kind': 'RIDER',
      // The application record wants a business name; for a rider that is simply who they are.
      'businessName': name,
      'contactName': name,
      'contactEmail': email,
      'emailVerificationToken': emailVerificationToken,
      'contactPhone': phone,
      'phoneVerificationToken': phoneVerificationToken,
      'targetProviderId': companyId,
      'notes': notes,
    });
    return (response.data as Map<String, dynamic>)['reference'] as String;
  }

  /// Applies to sell on MyDelivery.
  ///
  /// No company is named and none may be: a shop is asking the platform for terms, and a merchant
  /// carrying a delivery company would turn up in that company's applicant list.
  Future<String> applyAsMerchant({
    required String businessName,
    required String contactName,
    required String email,
    required String emailVerificationToken,
    String? phone,
    String? phoneVerificationToken,
    String? notes,
  }) async {
    final Response<dynamic> response =
        await _dio.post<dynamic>('/api/onboarding/applications', data: <String, dynamic>{
      'kind': 'MERCHANT',
      'businessName': businessName,
      'contactName': contactName,
      'contactEmail': email,
      'emailVerificationToken': emailVerificationToken,
      'contactPhone': phone,
      'phoneVerificationToken': phoneVerificationToken,
      'notes': notes,
    });
    return (response.data as Map<String, dynamic>)['reference'] as String;
  }

  /// Chooses a passcode at the end of an application, so the applicant can sign in and watch it.
  ///
  /// Open, like the application itself: the account being created is the one they would otherwise
  /// need in order to call this. The reference is what stands in for a token.
  Future<void> createApplicantAccount({
    required String reference,
    required String password,
  }) async {
    await _dio.post<dynamic>(
      '/api/onboarding/applications/$reference/account',
      data: <String, dynamic>{'password': password},
    );
  }

  /// The signed-in applicant's own application, by their token rather than a reference.
  ///
  /// Null when they have none — including an approved partner whose application is behind them,
  /// which is how the app knows to stop showing the pending screen.
  Future<OnboardingApplication?> mine() async {
    try {
      final Response<dynamic> response =
          await _dio.get<dynamic>('/api/onboarding/applications/mine');
      return OnboardingApplication.fromJson(response.data as Map<String, dynamic>);
    } on DioException {
      return null;
    }
  }

  /// Following your own application with the reference you were given, and nothing else.
  Future<OnboardingApplication?> byReference(String reference) async {
    try {
      final Response<dynamic> response = await _dio
          .get<dynamic>('/api/onboarding/applications/by-reference/$reference');
      return OnboardingApplication.fromJson(response.data as Map<String, dynamic>);
    } on DioException {
      return null;
    }
  }

  // ------------------------------------------------------------------ reviewing

  /// What is waiting to be looked at, oldest first — a three-day wait should not lose to today.
  Future<List<OnboardingApplication>> queue() async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/onboarding/applications');
    return (response.data as List<dynamic>)
        .map((dynamic a) => OnboardingApplication.fromJson(a as Map<String, dynamic>))
        .toList();
  }

  /// Everything ever applied for, newest first. The decided ones are the record of what was done.
  Future<List<OnboardingApplication>> all() async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/onboarding/applications/all');
    return (response.data as List<dynamic>)
        .map((dynamic a) => OnboardingApplication.fromJson(a as Map<String, dynamic>))
        .toList();
  }

  /// One delivery company's own rider applicants.
  ///
  /// The company id travels in the path and is checked by the server against its record of who
  /// runs what — a carrier cannot read a competitor's applicants by editing it.
  Future<List<OnboardingApplication>> forCompany(String providerId, {bool all = false}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
        '/api/onboarding/applications/for-company/$providerId',
        queryParameters: <String, dynamic>{'all': all});
    return (response.data as List<dynamic>)
        .map((dynamic a) => OnboardingApplication.fromJson(a as Map<String, dynamic>))
        .toList();
  }

  Future<OnboardingApplication> hire(String providerId, String id) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
        '/api/onboarding/applications/for-company/$providerId/$id/approve');
    return OnboardingApplication.fromJson(response.data as Map<String, dynamic>);
  }

  Future<OnboardingApplication> turnDown(String providerId, String id, String reason) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
        '/api/onboarding/applications/for-company/$providerId/$id/reject',
        data: <String, dynamic>{'reason': reason});
    return OnboardingApplication.fromJson(response.data as Map<String, dynamic>);
  }

  Future<OnboardingApplication> approve(String id) async {
    final Response<dynamic> response =
        await _dio.post<dynamic>('/api/onboarding/applications/$id/approve');
    return OnboardingApplication.fromJson(response.data as Map<String, dynamic>);
  }

  /// A rejection has to say why. The server refuses an empty reason, and so does the screen.
  Future<OnboardingApplication> reject(String id, String reason) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
        '/api/onboarding/applications/$id/reject',
        data: <String, dynamic>{'reason': reason});
    return OnboardingApplication.fromJson(response.data as Map<String, dynamic>);
  }
}
