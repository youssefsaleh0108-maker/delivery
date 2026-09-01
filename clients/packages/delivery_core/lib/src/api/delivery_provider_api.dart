import 'package:dio/dio.dart';

import '../models/catalog_models.dart';
import '../models/provider_models.dart';

/// The register of who can carry an order, and a merchant's choice among them.
///
/// Two audiences in one client because they are one API: BACKOFFICE onboards companies and moves
/// riders between them; a merchant sees only who may carry *their* orders and manages their own
/// fleet. The server enforces that split — this is only the typed surface for it.
class DeliveryProviderApi {
  DeliveryProviderApi(this._dio);

  final Dio _dio;

  // ---------------------------------------------------------------- backoffice

  Future<Paged<DeliveryProviderInfo>> all({int page = 0, int size = 20}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/delivery-providers',
      queryParameters: <String, dynamic>{'page': page, 'size': size},
    );
    return Paged<DeliveryProviderInfo>.fromJson(
        response.data as Map<String, dynamic>, DeliveryProviderInfo.fromJson);
  }

  Future<DeliveryProviderInfo> register({
    required String slug,
    required String name,
    String? contactName,
    String? contactPhone,
    String? accountRef,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/delivery-providers',
      data: <String, dynamic>{
        'slug': slug,
        'name': name,
        'contactName': contactName,
        'contactPhone': contactPhone,
        'accountRef': accountRef,
      },
    );
    return DeliveryProviderInfo.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- carrier

  /// The delivery company the signed-in user works for.
  ///
  /// Everything a carrier can do is scoped through this rather than by id, so there is no path by
  /// which one carrier reaches another's. A user who is not carrier staff gets a 404.
  Future<DeliveryProviderInfo> myCompany() async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/delivery-providers/my-company');
    return DeliveryProviderInfo.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<String>> myRiders() async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/delivery-providers/my-company/riders');
    return ((response.data as Map<String, dynamic>)['riders'] as List<dynamic>)
        .map((dynamic r) => r as String)
        .toList();
  }

  /// How this carrier is performing, and therefore how much work they are offered.
  Future<CarrierScore> myScore() async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/delivery-providers/my-company/score');
    return CarrierScore.fromJson(response.data as Map<String, dynamic>);
  }

  Future<DeliveryProviderInfo> pauseMyCompany() =>
      _post('/api/delivery-providers/my-company/pause');

  Future<DeliveryProviderInfo> resumeMyCompany() =>
      _post('/api/delivery-providers/my-company/resume');

  /// The circles this company works (Figma 88:107). Oldest first, as the server keeps them.
  Future<List<CoverageZone>> myZones() async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/delivery-providers/my-company/zones');
    return (response.data as List<dynamic>)
        .map((dynamic j) => CoverageZone.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<CoverageZone> drawZone({
    required String name,
    required double latitude,
    required double longitude,
    required int radiusMetres,
    bool active = true,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/delivery-providers/my-company/zones',
      data: <String, dynamic>{
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'radiusMetres': radiusMetres,
        'active': active,
      },
    );
    return CoverageZone.fromJson(response.data as Map<String, dynamic>);
  }

  /// A full replace: name, pin, radius and the on/off switch travel together.
  Future<CoverageZone> redrawZone(CoverageZone zone) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/delivery-providers/my-company/zones/${zone.id}',
      data: <String, dynamic>{
        'name': zone.name,
        'latitude': zone.latitude,
        'longitude': zone.longitude,
        'radiusMetres': zone.radiusMetres,
        'active': zone.active,
      },
    );
    return CoverageZone.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> eraseZone(String zoneId) =>
      _dio.delete<void>('/api/delivery-providers/my-company/zones/$zoneId');

  /// The whole register's scores. BACKOFFICE only.
  Future<List<CarrierScore>> scores() async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/delivery-providers/scores');
    return (response.data as List<dynamic>)
        .map((dynamic j) => CarrierScore.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Attaches somebody to a delivery company so they can administer it. BACKOFFICE only.
  ///
  /// Distinct from a rider: a rider carries orders, a staff login runs the company. The same person
  /// may be both, and conflating them would put a dispatcher who never rides on the job board.
  Future<void> addStaff(String providerId, String userRef) => _dio.post<dynamic>(
      '/api/delivery-providers/$providerId/staff',
      data: <String, dynamic>{'riderRef': userRef});

  /// The logins that can administer this company. BACKOFFICE only.
  Future<List<String>> staff(String providerId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/delivery-providers/$providerId/staff');
    return ((response.data as Map<String, dynamic>)['riders'] as List<dynamic>)
        .map((dynamic r) => r as String)
        .toList();
  }

  Future<void> removeStaff(String userRef) =>
      _dio.delete<dynamic>('/api/delivery-providers/staff/$userRef');

  /// Asks the bank again about a carrier's payout account.
  ///
  /// The counterpart to registration not failing during a bank outage: an account that could not be
  /// checked when it was set can be checked now. Never throws for a refused account — that comes
  /// back as a provider whose state is still unconfirmed, with the bank's reason on it.
  Future<DeliveryProviderInfo> verifyPayout(String id) =>
      _post('/api/delivery-providers/$id/verify-payout');

  /// Carriers with a payout account nobody has confirmed.
  Future<List<DeliveryProviderInfo>> unconfirmedPayout() async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/delivery-providers/unconfirmed-payout');
    return (response.data as List<dynamic>)
        .map((dynamic j) => DeliveryProviderInfo.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<List<String>> riders(String providerId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/delivery-providers/$providerId/riders');
    return ((response.data as Map<String, dynamic>)['riders'] as List<dynamic>)
        .map((dynamic r) => r as String)
        .toList();
  }

  Future<void> assignRider(String providerId, String riderRef) {
    return _dio.post<void>('/api/delivery-providers/$providerId/riders',
        data: <String, dynamic>{'riderRef': riderRef});
  }

  /// Sends a rider back to the in-house fleet rather than leaving them with no employer.
  Future<void> releaseRider(String riderRef) =>
      _dio.delete<void>('/api/delivery-providers/riders/$riderRef');

  /// Stopped by the platform. A provider cannot undo this themselves — see [reinstate].
  Future<DeliveryProviderInfo> suspend(String id) => _post('/api/delivery-providers/$id/suspend');

  Future<DeliveryProviderInfo> reinstate(String id) =>
      _post('/api/delivery-providers/$id/reinstate');

  // ---------------------------------------------------------------- merchant

  /// Who could carry this merchant's orders: the open companies, plus their own fleet.
  Future<List<DeliveryProviderInfo>> available() async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/delivery-providers/available');
    return (response.data as List<dynamic>)
        .map((dynamic j) => DeliveryProviderInfo.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// The merchant's own fleet, created on first ask. Idempotent.
  Future<DeliveryProviderInfo> myFleet() => _post('/api/delivery-providers/mine');

  Future<DeliveryPolicy> policy() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/delivery-providers/policy');
    return DeliveryPolicy.fromJson(response.data as Map<String, dynamic>);
  }

  /// Chooses a carrier. A null id hands the decision back to the platform.
  Future<DeliveryPolicy> choose({String? preferredProviderId, bool allowFallback = true}) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/delivery-providers/policy',
      data: <String, dynamic>{
        'preferredProviderId': preferredProviderId,
        'allowFallback': allowFallback,
      },
    );
    return DeliveryPolicy.fromJson(response.data as Map<String, dynamic>);
  }

  /// A provider taking itself out of rotation. A merchant may only pause the fleet they own.
  Future<DeliveryProviderInfo> pause(String id) => _post('/api/delivery-providers/$id/pause');

  Future<DeliveryProviderInfo> resume(String id) => _post('/api/delivery-providers/$id/resume');

  Future<DeliveryProviderInfo> _post(String path) async {
    final Response<dynamic> response = await _dio.post<dynamic>(path);
    return DeliveryProviderInfo.fromJson(response.data as Map<String, dynamic>);
  }
}
