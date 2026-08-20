/// Per-provider delivery rates (Phase 6).
library;

/// How one provider performed on one channel over a window.
///
/// The gate on a vendor cutover: during a canary ramp two providers are live on the same channel,
/// and comparing them is the whole point of running a ramp at all.
class ProviderDeliveryRate {
  const ProviderDeliveryRate({
    required this.channel,
    required this.provider,
    required this.total,
    required this.sent,
    required this.failed,
    required this.inFlight,
    required this.windowHours,
    this.successRate,
    this.avgSecondsToSend,
    this.delivered = 0,
    this.undelivered = 0,
    this.awaitingReceipt = 0,
    this.deliveryRate,
    this.avgSecondsToDeliver,
  });

  final String channel;
  final String provider;
  final int total;
  final int sent;
  final int failed;
  final int inFlight;

  /// 0–100, or null when nothing has completed yet.
  ///
  /// Null rather than zero, deliberately, all the way from the server: "no data" and "everything
  /// failed" must never look the same on a screen someone is using to decide whether to keep a
  /// vendor live.
  final double? successRate;

  final double? avgSecondsToSend;
  final int windowHours;

  /// Carrier confirmed arrival.
  final int delivered;

  /// Carrier confirmed it never arrived — the number [successRate] cannot see.
  final int undelivered;

  /// Accepted by the provider, no carrier receipt yet.
  final int awaitingReceipt;

  /// 0–100 over CONFIRMED outcomes only, or null when no receipt has ever arrived.
  ///
  /// Distinct from [successRate], and the distinction is the point: that one says what a provider
  /// ACCEPTED, this says what a carrier actually DELIVERED. A vendor can accept everything and
  /// deliver very little. Null when no receipts exist at all, which is the normal state for a vendor
  /// whose callbacks are not configured — and must read as "unknown", never as 0%.
  final double? deliveryRate;

  final double? avgSecondsToDeliver;

  bool get hasData => successRate != null;

  /// Whether any carrier receipt has been seen for this provider.
  ///
  /// Drives the "not measured" wording. Without it a provider with no DLR configuration would show
  /// an empty delivery column that reads as bad news rather than as no news.
  bool get hasDeliveryData => deliveryRate != null;

  bool get isDeliveryHealthy =>
      deliveryRate != null && deliveryRate! >= healthyThreshold;

  /// Below this a ramp should be rolled back rather than continued.
  ///
  /// A threshold in the client is only a prompt — nothing enforces it — but having the number in
  /// one place beats each reader deciding for themselves what "looks bad" means.
  static const double healthyThreshold = 95.0;

  bool get isHealthy => successRate != null && successRate! >= healthyThreshold;

  factory ProviderDeliveryRate.fromJson(Map<String, dynamic> json) => ProviderDeliveryRate(
        channel: json['channel'] as String? ?? '',
        provider: json['provider'] as String? ?? 'unknown',
        total: (json['total'] as num?)?.toInt() ?? 0,
        sent: (json['sent'] as num?)?.toInt() ?? 0,
        failed: (json['failed'] as num?)?.toInt() ?? 0,
        inFlight: (json['inFlight'] as num?)?.toInt() ?? 0,
        successRate: (json['successRate'] as num?)?.toDouble(),
        avgSecondsToSend: (json['avgSecondsToSend'] as num?)?.toDouble(),
        windowHours: (json['windowHours'] as num?)?.toInt() ?? 24,
        delivered: (json['delivered'] as num?)?.toInt() ?? 0,
        undelivered: (json['undelivered'] as num?)?.toInt() ?? 0,
        awaitingReceipt: (json['awaitingReceipt'] as num?)?.toInt() ?? 0,
        deliveryRate: (json['deliveryRate'] as num?)?.toDouble(),
        avgSecondsToDeliver: (json['avgSecondsToDeliver'] as num?)?.toDouble(),
      );
}
