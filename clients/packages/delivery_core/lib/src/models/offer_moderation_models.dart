/// Client-side mirrors of product-service's back-office moderation of service offers (`ModerationDtos`,
/// product-service V36).
///
/// The hold itself, as a provider reads it on their own offer, is [ProductModeration] on [Product]. This
/// file is back office's side: the list across shops, and the trail.
library;

import 'catalog_models.dart';
import 'store_models.dart';

/// Back office's status filter for the service offer list: a product's statuses, with archived split in
/// two.
///
/// Sent, never read back: a row says its offer's status and hold itself ([Product.status],
/// [Product.moderation]).
enum ServiceOfferStatusFilter {
  draft('DRAFT'),
  active('ACTIVE'),
  paused('PAUSED'),

  /// Archived by its provider. Never an offer back office took down, which [takenDown] finds.
  archived('ARCHIVED'),

  /// Taken down by back office and not yet restored.
  takenDown('TAKEN_DOWN');

  const ServiceOfferStatusFilter(this.wireValue);

  final String wireValue;
}

/// One row of back office's service offer list: the offer, as every product read returns it, and the
/// shop it sits in.
class BackofficeServiceOffer {
  const BackofficeServiceOffer({
    required this.offer,
    required this.storeId,
    this.storeName,
    this.serviceCategory,
    this.storeStatus = StoreListingStatus.draft,
  });

  /// With its terms, and with [Product.moderation] while back office holds it.
  final Product offer;

  final String storeId;

  /// Null when the server sent none, so a screen shows a dash rather than an empty cell.
  final String? storeName;

  /// Null for a category this build does not know. There is no safe stand-in (see
  /// [ServiceCategory.maybeFromWire]), so a screen hides what it cannot name.
  final ServiceCategory? serviceCategory;

  /// Whether the shop is listed. A value this build does not know reads as a draft, never as listed.
  final StoreListingStatus storeStatus;

  /// Throws when [json] carries no offer: a row without one has nothing to show or act on. Everything
  /// about the shop is read leniently, and the shop's id falls back to the offer's own.
  factory BackofficeServiceOffer.fromJson(Map<String, dynamic> json) {
    final Product offer = Product.fromJson(json['offer'] as Map<String, dynamic>);
    final Object? storeId = json['storeId'];
    final Object? category = json['serviceCategory'];
    final Object? status = json['storeStatus'];
    return BackofficeServiceOffer(
      offer: offer,
      storeId: storeId is String && storeId.isNotEmpty ? storeId : offer.storeId ?? '',
      storeName: _textOrNull(json['storeName']),
      serviceCategory: ServiceCategory.maybeFromWire(category is String ? category : null),
      storeStatus: StoreListingStatus.fromWire(status is String ? status : null),
    );
  }
}

/// What back office did to an offer.
enum OfferModerationActionKind {
  /// Took it off sale, held there until restored.
  takeDown('TAKE_DOWN'),

  /// Lifted the hold.
  restore('RESTORE'),

  /// An act this build does not know. Never read as one of the others.
  unknown(null);

  const OfferModerationActionKind(this.wireValue);

  final String? wireValue;

  static OfferModerationActionKind fromWire(Object? value) {
    for (final OfferModerationActionKind kind in values) {
      if (kind.wireValue != null && kind.wireValue == value) {
        return kind;
      }
    }
    return OfferModerationActionKind.unknown;
  }
}

/// One act in an offer's moderation trail: what back office did, why, who did it and when.
///
/// The server writes one with every take-down and restore, in the same transaction as the act, and never
/// changes it. Who acted comes from the staff member's token; no client can name them.
class OfferModerationAction {
  const OfferModerationAction({
    required this.id,
    required this.productId,
    required this.storeId,
    required this.action,
    required this.reason,
    required this.actorId,
    this.actorName,
    this.createdAt,
  });

  final String id;
  final String productId;
  final String storeId;
  final OfferModerationActionKind action;

  /// In the staff member's own words. A take-down's is what the offer's provider read.
  final String reason;

  /// The staff member's account id.
  final String actorId;

  /// Their username when they acted, or null when their token carried none. A screen falls back to
  /// [actorId].
  final String? actorName;

  /// When they acted, in local time. Null when the server sent no time this build can read.
  final DateTime? createdAt;

  /// Lenient: a field that is missing or of the wrong type reads as empty or absent, rather than failing
  /// the whole trail.
  factory OfferModerationAction.fromJson(Map<String, dynamic> json) {
    final Object? at = json['createdAt'];
    return OfferModerationAction(
      id: _text(json['id']),
      productId: _text(json['productId']),
      storeId: _text(json['storeId']),
      action: OfferModerationActionKind.fromWire(json['action']),
      reason: _text(json['reason']),
      actorId: _text(json['actorId']),
      actorName: _textOrNull(json['actorName']),
      createdAt: at is String ? DateTime.tryParse(at)?.toLocal() : null,
    );
  }
}

String _text(Object? value) => value is String ? value : '';

String? _textOrNull(Object? value) => value is String && value.trim().isNotEmpty ? value : null;
