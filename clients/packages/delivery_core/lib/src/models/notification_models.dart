/// Notification and connector-settings models mirroring the Phase 3 APIs.
library;

/// One message in the signed-in user's in-app inbox.
///
/// Note there is no user id here. Every endpoint that returns these is scoped to the caller's own
/// token subject, so a client never has one to send and never has one to filter on.
class InAppNotification {
  const InAppNotification({
    required this.id,
    required this.eventType,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    this.orderId,
    this.metadata = const <String, String>{},
    this.readAt,
  });

  final String id;
  final String? orderId;
  final String eventType;
  final String title;
  final String body;
  final Map<String, String> metadata;
  final bool read;
  final DateTime? readAt;
  final DateTime createdAt;

  /// Where tapping this message should go, when the server supplied a destination.
  String? get deepLink => metadata['deepLink'];

  factory InAppNotification.fromJson(Map<String, dynamic> json) => InAppNotification(
        id: json['id'] as String,
        orderId: json['orderId'] as String?,
        eventType: json['eventType'] as String? ?? 'notification',
        title: json['title'] as String? ?? 'Delivery',
        body: json['body'] as String? ?? '',
        metadata: (json['metadata'] as Map<String, dynamic>? ?? <String, dynamic>{})
            .map((String k, dynamic v) => MapEntry<String, String>(k, '$v')),
        read: json['read'] as bool? ?? false,
        readAt: _date(json['readAt']),
        createdAt: _date(json['createdAt']) ?? DateTime.now(),
      );

  InAppNotification copyWith({bool? read, DateTime? readAt}) => InAppNotification(
        id: id,
        orderId: orderId,
        eventType: eventType,
        title: title,
        body: body,
        metadata: metadata,
        read: read ?? this.read,
        readAt: readAt ?? this.readAt,
        createdAt: createdAt,
      );

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

/// A connector's runtime configuration as the Backoffice Settings screen sees it (Section 8).
///
/// [maskedSecret] is exactly that — a fixed run of asterisks the service substitutes, never the
/// credential. The real value lives in Vault at [vaultPath] and is not reachable from any API a
/// browser can call.
class ConnectorSetting {
  const ConnectorSetting({
    required this.connectorType,
    required this.provider,
    required this.availableProviders,
    required this.config,
    required this.active,
    this.vaultPath,
    this.maskedSecret,
    this.secretRotatedAt,
    this.updatedBy,
    this.updatedAt,
  });

  final String connectorType;
  final String provider;

  /// The choices the dropdown renders.
  ///
  /// Sent by the server rather than hardcoded here, so the UI cannot offer a provider the
  /// connector has no client for — and so adding one is a backend change only.
  final List<String> availableProviders;

  final Map<String, String> config;
  final String? vaultPath;
  final String? maskedSecret;
  final DateTime? secretRotatedAt;
  final bool active;
  final String? updatedBy;
  final DateTime? updatedAt;

  bool get hasCredential => vaultPath != null && maskedSecret != null;

  /// True when the provider list offers no real choice — email over SMTP, for instance.
  bool get isFixedProvider => availableProviders.length <= 1;

  factory ConnectorSetting.fromJson(Map<String, dynamic> json) => ConnectorSetting(
        connectorType: json['connectorType'] as String,
        provider: json['provider'] as String,
        availableProviders: (json['availableProviders'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic p) => '$p')
            .toList(),
        config: (json['config'] as Map<String, dynamic>? ?? <String, dynamic>{})
            .map((String k, dynamic v) => MapEntry<String, String>(k, '$v')),
        vaultPath: json['vaultPath'] as String?,
        maskedSecret: json['maskedSecret'] as String?,
        secretRotatedAt: InAppNotification._date(json['secretRotatedAt']),
        active: json['active'] as bool? ?? true,
        updatedBy: json['updatedBy'] as String?,
        updatedAt: InAppNotification._date(json['updatedAt']),
      );
}

/// One entry in a connector's change history.
///
/// This page can redirect real SMS traffic and, from Phase 4, real money, so who changed what and
/// when has to be answerable after the fact (Section 8).
class ConnectorAuditEntry {
  const ConnectorAuditEntry({
    required this.changedBy,
    required this.changedAt,
    this.oldProvider,
    this.newProvider,
  });

  final String? oldProvider;
  final String? newProvider;
  final String changedBy;
  final DateTime changedAt;

  factory ConnectorAuditEntry.fromJson(Map<String, dynamic> json) => ConnectorAuditEntry(
        oldProvider: (json['oldValue'] as Map<String, dynamic>?)?['provider'] as String?,
        newProvider: (json['newValue'] as Map<String, dynamic>?)?['provider'] as String?,
        changedBy: json['changedBy'] as String? ?? 'unknown',
        changedAt: InAppNotification._date(json['changedAt']) ?? DateTime.now(),
      );
}
