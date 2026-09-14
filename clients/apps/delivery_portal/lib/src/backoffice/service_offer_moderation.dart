/// The seam between back office's Service offers page and the service-offer moderation client.
///
/// The client is delivery_core's `BackofficeCatalogApi`, on branch `feat/services-offer-moderation`
/// (product-service `OfferModerationController`, V36). That branch is not under this one yet, so the
/// portal is built against this file: [ServiceOfferModeration] declares the client's four methods with
/// its exact signatures, and the types those methods carry are declared here under delivery_core's own
/// names, with its fields and its JSON. Nothing else in the portal names the client, so connecting it
/// touches this file and `main.dart`, and no screen.
///
/// ## What the merge must connect
///
/// Once `feat/services-offer-moderation` is merged under this branch, replace this whole file with:
///
/// ```dart
/// import 'package:delivery_core/delivery_core.dart';
///
/// typedef ServiceOfferModeration = BackofficeCatalogApi;
///
/// extension BackofficeServiceOfferHold on BackofficeServiceOffer {
///   ProductModeration? get hold => offer.moderation;
/// }
/// ```
///
/// and in `main.dart` pass `offerModeration: BackofficeCatalogApi(_dio)` where it passes null today.
/// The types then come from delivery_core under the same names. The page reads an offer's hold only as
/// [BackofficeServiceOffer.hold], which the extension keeps. The tests' fakes `implements
/// ServiceOfferModeration` and build every row and trail entry with `fromJson`, so they compile against
/// the real client unchanged. Until then `PortalApis.offerModeration` is null and the page says
/// moderation is not connected, drawing nothing that could not work.
library;

import 'package:delivery_core/delivery_core.dart';

/// Back office's hand on service offers: every service shop's offers, taking one down with a reason,
/// restoring it, and its trail. BACKOFFICE-only on the server; any other account gets a 403.
///
/// Mirrors `BackofficeCatalogApi` exactly — see the library comment. Every act takes a reason, which the
/// server records with the staff member, named from the token, in the same transaction as the act.
abstract interface class ServiceOfferModeration {
  /// Every service shop's offers in any status, newest first, narrowed by any of [status],
  /// [serviceCategory], [storeId] and [search] (the offer's name and its shop's). A filter that is not
  /// given is not sent. `GET /api/products/services/all`.
  Future<Paged<BackofficeServiceOffer>> serviceOffers({
    ServiceOfferStatusFilter? status,
    ServiceCategory? serviceCategory,
    String? storeId,
    String? search,
    int page = 0,
    int size = 20,
  });

  /// Takes the offer down: off sale for every customer at once, and its provider cannot publish,
  /// resume or pause it until it is restored. Answers the offer as it now is.
  ///
  /// Refused with a 400 for a blank reason or one over 500 characters, a 422 for a goods product or
  /// an offer already taken down, a 404 for an unknown id, and a 409 `PRODUCT_CHANGED` when the offer
  /// changed under the act.
  Future<BackofficeServiceOffer> takeDown(String productId, {required String reason});

  /// Lifts the hold, with a reason for the trail. An offer that was on sale comes back paused, for its
  /// provider to resume. A 422 when the offer is not taken down.
  Future<BackofficeServiceOffer> restore(String productId, {required String reason});

  /// The offer's trail, newest act first. Empty for an offer back office never acted on.
  Future<List<OfferModerationAction>> moderationHistory(String productId);
}

/// Back office's status filter for the service offer list: a product's statuses, with archived split
/// in two. Sent, never read back.
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

/// One row of back office's service offer list: the offer, and the shop it sits in.
class BackofficeServiceOffer {
  const BackofficeServiceOffer({
    required this.offer,
    required this.storeId,
    this.storeName,
    this.serviceCategory,
    this.storeStatus = StoreListingStatus.draft,
    this.hold,
  });

  /// With its terms.
  final Product offer;

  final String storeId;

  /// Null when the server sent none, so a screen shows a dash rather than an empty cell.
  final String? storeName;

  /// Null for a category this build does not know; a screen hides what it cannot name.
  final ServiceCategory? serviceCategory;

  /// Whether the shop is listed. A value this build does not know reads as a draft, never as listed.
  final StoreListingStatus storeStatus;

  /// YouDrop's hold on the offer, with back office's reason, or null when there is none. In
  /// delivery_core this is `offer.moderation`; the merge keeps this name as an extension.
  final ProductModeration? hold;

  /// Throws when [json] carries no offer: a row without one has nothing to show or act on. Everything
  /// about the shop is read leniently, and the shop's id falls back to the offer's own.
  factory BackofficeServiceOffer.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> offerJson = json['offer'] as Map<String, dynamic>;
    final Product offer = Product.fromJson(offerJson);
    final Object? storeId = json['storeId'];
    final Object? category = json['serviceCategory'];
    final Object? status = json['storeStatus'];
    return BackofficeServiceOffer(
      offer: offer,
      storeId: storeId is String && storeId.isNotEmpty ? storeId : offer.storeId ?? '',
      storeName: _textOrNull(json['storeName']),
      serviceCategory: ServiceCategory.maybeFromWire(category is String ? category : null),
      storeStatus: StoreListingStatus.fromWire(status is String ? status : null),
      hold: ProductModeration.maybeFromJson(offerJson['moderation']),
    );
  }
}

/// The kind of hold YouDrop has on a service offer.
enum ProductModerationState {
  /// Back office took the offer down. It stays off sale until back office restores it.
  takenDown('TAKEN_DOWN'),

  /// A hold this build does not know. Still a hold, never read as another.
  unknown(null);

  const ProductModerationState(this.wireValue);

  final String? wireValue;

  static ProductModerationState fromWire(Object? value) {
    for (final ProductModerationState state in values) {
      if (state.wireValue != null && state.wireValue == value) {
        return state;
      }
    }
    return ProductModerationState.unknown;
  }
}

/// Back office holding a service offer off sale, as the offer's `moderation` block carries it.
class ProductModeration {
  const ProductModeration({required this.state, this.reason, this.takenDownAt});

  final ProductModerationState state;

  /// Back office's reason, in its own words. Null only when the server sent none.
  final String? reason;

  /// When the offer was taken down, in local time; null when the server sent no readable time.
  final DateTime? takenDownAt;

  /// The block, or null when [json] is not one: an offer nobody took down has none.
  static ProductModeration? maybeFromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final Object? at = json['takenDownAt'];
    return ProductModeration(
      state: ProductModerationState.fromWire(json['state']),
      reason: _textOrNull(json['reason']),
      takenDownAt: at is String ? DateTime.tryParse(at)?.toLocal() : null,
    );
  }
}

/// What back office did to an offer.
enum OfferModerationActionKind {
  takeDown('TAKE_DOWN'),
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

/// One act in an offer's moderation trail: what back office did, why, who did it and when. Written with
/// the act and never changed; who acted comes from the staff member's token.
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

  /// In the staff member's own words.
  final String reason;

  /// The staff member's account id.
  final String actorId;

  /// Their username when they acted, or null; a screen falls back to [actorId].
  final String? actorName;

  /// When they acted, in local time; null when the server sent no readable time.
  final DateTime? createdAt;

  /// Lenient: a field that is missing or of the wrong type reads as empty or absent.
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
