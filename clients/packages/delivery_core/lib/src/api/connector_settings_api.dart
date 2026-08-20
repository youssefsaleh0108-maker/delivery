import 'package:dio/dio.dart';

import '../models/notification_models.dart';

/// Client for the Connector Settings API — BACKOFFICE only (Section 8).
///
/// There is no method here for reading or writing a credential, because there is no such endpoint.
/// Secrets live in Vault; this API exposes the provider choice, the non-secret config, and enough
/// metadata to show that a credential exists and when it last changed.
class ConnectorSettingsApi {
  ConnectorSettingsApi(this._dio);

  final Dio _dio;

  Future<List<ConnectorSetting>> list() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/settings/connectors');
    return (response.data as List<dynamic>)
        .map((dynamic e) => ConnectorSetting.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ConnectorSetting> get(String type) async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/settings/connectors/$type');
    return ConnectorSetting.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<ConnectorAuditEntry>> history(String type) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/settings/connectors/$type/history');
    return (response.data as List<dynamic>)
        .map((dynamic e) => ConnectorAuditEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Changes the active provider and non-secret config.
  ///
  /// The service rejects a provider outside the connector's list, and rejects any config key that
  /// looks like a credential, with 422. Both are re-checked there rather than trusted from here — a
  /// dropdown is a UI convention, not an enforcement point.
  Future<ConnectorSetting> update(
    String type, {
    required String provider,
    Map<String, String> config = const <String, String>{},
  }) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/settings/connectors/$type',
      data: <String, dynamic>{'provider': provider, 'config': config},
    );
    return ConnectorSetting.fromJson(response.data as Map<String, dynamic>);
  }
}
