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

// --------------------------------------------------------------------- notification preferences

/// One of the four buckets a notification belongs to, mirroring `NotificationCategory`.
enum NotificationCategory {
  /// Progress on an order the user placed, is preparing, or is delivering.
  orderUpdates('ORDER_UPDATES', 'Order updates'),

  /// Messages between a customer, a rider and a merchant.
  chat('CHAT', 'Chat'),

  /// Marketing. Off unless the user turns it on — consent is not implied by signing up.
  promotions('PROMOTIONS', 'Promotions'),

  /// Security and account integrity. Always delivered; no preference can suppress it, and the
  /// server sends its rows locked.
  account('ACCOUNT', 'Account and security');

  const NotificationCategory(this.wire, this.label);

  final String wire;
  final String label;

  /// Null for a category this build does not know — the row still renders from its wire string.
  static NotificationCategory? fromWire(String? value) {
    for (final NotificationCategory c in NotificationCategory.values) {
      if (c.wire == value) return c;
    }
    return null;
  }
}

/// How a notification reaches somebody, mirroring `NotificationCommand`'s channel constants.
///
/// Ordered as the settings screen reads them — the channels that interrupt someone first, because
/// those are the ones a user opening the screen is usually looking for.
enum NotificationChannel {
  push('PUSH', 'Push'),
  inApp('IN_APP', 'In-app'),
  email('EMAIL', 'Email'),
  sms('SMS', 'SMS');

  const NotificationChannel(this.wire, this.label);

  final String wire;
  final String label;

  /// Null for a channel this build does not know.
  static NotificationChannel? fromWire(String? value) {
    for (final NotificationChannel c in NotificationChannel.values) {
      if (c.wire == value) return c;
    }
    return null;
  }
}

/// One cell of the settings grid, mirroring `NotificationPreferenceService.Setting`.
///
/// The server returns the complete grid with defaults filled in, so a client never invents a
/// default of its own.
class NotificationPreference {
  const NotificationPreference({
    required this.categoryWire,
    required this.channelWire,
    required this.enabled,
    required this.locked,
    required this.userChosen,
    this.category,
    this.channel,
  });

  /// The typed pair, or null for a value this build does not know. The wire strings below are
  /// always present and are what [NotificationPrefsApi.update] sends back.
  final NotificationCategory? category;
  final NotificationChannel? channel;

  final String categoryWire;
  final String channelWire;

  final bool enabled;

  /// The toggle must render disabled: the server refuses to turn this off (account-critical
  /// messages). [enabled] stays true on locked rows.
  final bool locked;

  /// Whether this value is the user's own choice rather than the default — how a screen can say
  /// "you turned this off" instead of guessing.
  final bool userChosen;

  factory NotificationPreference.fromJson(Map<String, dynamic> json) => NotificationPreference(
        category: NotificationCategory.fromWire(json['category'] as String?),
        channel: NotificationChannel.fromWire(json['channel'] as String?),
        categoryWire: json['category'] as String? ?? '',
        channelWire: json['channel'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? false,
        locked: json['locked'] as bool? ?? false,
        userChosen: json['userChosen'] as bool? ?? false,
      );
}

/// One change the user made on the settings screen — only what was touched, never the whole grid.
///
/// Partial on purpose, mirroring the server's `PreferenceUpdate`: two devices open on the settings
/// screen must not have the second save silently revert the first.
class NotificationPreferenceChange {
  const NotificationPreferenceChange({
    required this.category,
    required this.channel,
    required this.enabled,
  });

  NotificationPreferenceChange.of(
      NotificationCategory category, NotificationChannel channel, {required bool enabled})
      : this(category: category.wire, channel: channel.wire, enabled: enabled);

  /// Wire strings rather than enums, so a row that arrived with an unknown category can still be
  /// toggled back exactly as it was named.
  final String category;
  final String channel;
  final bool enabled;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'category': category,
        'channel': channel,
        'enabled': enabled,
      };
}
