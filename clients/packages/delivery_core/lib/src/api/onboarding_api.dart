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

  /// Applies to ride, either for one delivery company or for YouDrop itself.
  ///
  /// [companyId] null means the second of those: no company is named, so the application is the
  /// platform's own to decide and lands in the backoffice queue rather than a company's.
  ///
  /// [details] is the signup wizard's free-form answers — vehicle, work region, date of birth —
  /// the arbitrary object the server stores beside the fixed columns and a reviewer reads. See
  /// [OnboardingApplication.details] for why it exists and why it is flattened on the way back.
  Future<String> applyAsRider({
    required String name,
    required String email,
    required String emailVerificationToken,
    String? companyId,
    String? phone,
    String? phoneVerificationToken,
    String? notes,
    Map<String, dynamic>? details,
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
      'details': details,
    });
    return (response.data as Map<String, dynamic>)['reference'] as String;
  }

  /// Applies to sell on YouDrop.
  ///
  /// No company is named and none may be: a shop is asking the platform for terms, and a merchant
  /// carrying a delivery company would turn up in that company's applicant list.
  ///
  /// [details] carries the wizard's free-form answers — business type and the like. See
  /// [OnboardingApplication.details].
  /// Applies to run a delivery company on YouDrop.
  ///
  /// Same wire as the other kinds; everything the carrier wizard collects beyond the contact
  /// block — CR number, company type, fleet counts, operating hours, capabilities, coverage —
  /// rides in [details], which the application record stores for the reviewer.
  Future<String> applyAsCarrier({
    required String companyName,
    required String contactName,
    required String email,
    required String emailVerificationToken,
    String? phone,
    String? phoneVerificationToken,
    String? notes,
    Map<String, dynamic>? details,
  }) async {
    final Response<dynamic> response =
        await _dio.post<dynamic>('/api/onboarding/applications', data: <String, dynamic>{
      'kind': 'CARRIER',
      'businessName': companyName,
      'contactName': contactName,
      'contactEmail': email,
      'emailVerificationToken': emailVerificationToken,
      'contactPhone': phone,
      'phoneVerificationToken': phoneVerificationToken,
      'notes': notes,
      'details': details,
    });
    return (response.data as Map<String, dynamic>)['reference'] as String;
  }

  Future<String> applyAsMerchant({
    required String businessName,
    required String contactName,
    required String email,
    required String emailVerificationToken,
    String? phone,
    String? phoneVerificationToken,
    String? notes,
    Map<String, dynamic>? details,
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
      'details': details,
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

  /// Applies to ride or to sell as the account that is already signed in — the Google path.
  ///
  /// The open [applyAsRider] and [applyAsMerchant] take an address and a code-verified proof of it,
  /// because that applicant has no account yet. This takes neither: the server reads the address
  /// off the caller's token, and Google already proved it (the realm trusts Google's
  /// `email_verified`). Everything else is the same wizard answers, and the application lands in
  /// the same queue behind the same gates — the account gets APPLICANT beside the live role, and
  /// only auto-approval or a reviewer takes APPLICANT off.
  ///
  /// **Idempotent.** A second call — a retry, a double tap, a returning user — hands back the same
  /// application rather than making another; asking for the other kind is refused with a sentence.
  ///
  /// **Refresh afterwards.** The account's roles change on the server, not in the token this app is
  /// holding. Call [AuthService.refresh] before choosing a screen, or the app routes on the roles
  /// the account had before it asked.
  ///
  /// [businessName] is the shop's name for a seller; a rider applies in their own name and it
  /// defaults to [name]. [companyId] null rides for YouDrop itself, as on the open form.
  Future<OnboardingApplication> applyForMyAccount({
    required OnboardingKind kind,
    required String name,
    String? businessName,
    String? phone,
    String? phoneVerificationToken,
    String? notes,
    Map<String, dynamic>? details,
    String? companyId,
  }) async {
    final Response<dynamic> response =
        await _dio.post<dynamic>('/api/onboarding/applications/mine', data: <String, dynamic>{
      'kind': kind.wire,
      'businessName': businessName ?? name,
      'contactName': name,
      'contactPhone': phone,
      'phoneVerificationToken': phoneVerificationToken,
      'notes': notes,
      'details': details,
      'targetProviderId': companyId,
    });
    return OnboardingApplication.fromJson(response.data as Map<String, dynamic>);
  }

  /// Makes the signed-in account a customer — the Google path's "I want to order".
  ///
  /// Idempotent, and it grants CUSTOMER and nothing else. Like [applyForMyAccount], the role lands
  /// in Keycloak and not in the current token: refresh before routing.
  Future<void> becomeCustomer() async {
    await _dio.post<dynamic>('/api/onboarding/me/customer');
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
