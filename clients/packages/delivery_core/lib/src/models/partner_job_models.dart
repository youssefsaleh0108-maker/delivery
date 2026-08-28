/// The partner (machine) job board, mirroring the `GET /api/partner/jobs` shapes.
library;

import 'order_models.dart';

/// One job as a dispatcher's software sees it, mirroring `PartnerJobsController.JobResponse`.
///
/// Deliberately thinner than [DeliveryOrder]: no customer id, no payment detail, no line items. A
/// routing machine needs none of them, and a machine credential should see the least that does its
/// job — so this is a separate model rather than a partly-filled order, and nothing can accidentally
/// read a field the server never sent.
class PartnerJob {
  const PartnerJob({
    required this.orderId,
    required this.status,
    required this.deliveryTier,
    required this.deliveryFee,
    required this.deliveryAddress,
    this.storeName,
    this.contactPhone,
    this.placedAt,
  });

  final String orderId;
  final OrderStatus status;

  /// EXPRESS jobs are the ones to route first — the tier is here so the software can prioritise
  /// the same way the humans' board does.
  final DeliveryTier deliveryTier;

  /// The BASE delivery fee — the figure the company is paid from.
  ///
  /// The express surcharge is deliberately absent from this whole surface: it is platform revenue,
  /// and adding it to a carrier payout figure would overstate what the company is owed. There is no
  /// field here to add, which is the point.
  final double deliveryFee;

  /// Null on a Butler errand — there is no shop to collect from.
  final String? storeName;

  final String deliveryAddress;

  /// Null when the customer left no number.
  final String? contactPhone;

  final DateTime? placedAt;

  factory PartnerJob.fromJson(Map<String, dynamic> json) => PartnerJob(
        orderId: json['orderId'] as String? ?? '',
        status: OrderStatus.fromWire(json['status'] as String? ?? 'PLACED'),
        deliveryTier: DeliveryTier.fromWire(json['deliveryTier'] as String?),
        deliveryFee: (json['deliveryFee'] as num?)?.toDouble() ?? 0,
        storeName: json['storeName'] as String?,
        deliveryAddress: json['deliveryAddress'] as String? ?? '',
        contactPhone: json['contactPhone'] as String?,
        placedAt: _time(json['placedAt']),
      );

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

/// The company's board and its work in flight, in one poll.
///
/// One response for both lists because that is the shape a dispatch loop wants — "what could we
/// take, what are we carrying" is a single decision, and fetching the halves separately would let
/// them disagree. Both lists are oldest-first (the longest-waiting job is the most urgent) and
/// capped at 100 by the server.
class PartnerJobs {
  const PartnerJobs({required this.claimable, required this.active});

  /// Ready to collect and unclaimed: offered to this company, plus any order the platform could not
  /// route, which every fleet's board shows.
  final List<PartnerJob> claimable;

  /// Claimed by one of this company's riders and not yet finished.
  final List<PartnerJob> active;

  factory PartnerJobs.fromJson(Map<String, dynamic> json) => PartnerJobs(
        claimable: _jobs(json['claimable']),
        active: _jobs(json['active']),
      );

  static List<PartnerJob> _jobs(Object? value) => value is List<dynamic>
      ? value
          .whereType<Map<dynamic, dynamic>>()
          .map((Map<dynamic, dynamic> j) => PartnerJob.fromJson(j.cast<String, dynamic>()))
          .toList()
      : <PartnerJob>[];
}
