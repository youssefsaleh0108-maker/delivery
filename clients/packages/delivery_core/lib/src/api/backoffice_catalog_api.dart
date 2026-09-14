import 'package:dio/dio.dart';

import '../models/catalog_models.dart';
import '../models/offer_moderation_models.dart';
import '../models/store_models.dart';

/// Back office's hand on service offers: every service shop's offers, taking one down with a reason,
/// restoring it, and its trail (product-service `OfferModerationController`, V36).
///
/// BACKOFFICE-only on the server; any other account is refused with a 403. Every act takes a reason,
/// which the server records with the actor, named from the token, in the same transaction as the act.
/// A take-down's reason is also what the offer's provider reads on their offer ([Product.moderation]).
///
/// Goods products are not here. Back office's catalogue reads them with `CatalogApi.browse`, which in
/// turn never lists a service offer.
class BackofficeCatalogApi {
  BackofficeCatalogApi(this._dio);

  final Dio _dio;

  /// Every service shop's offers in any status, newest first, narrowed by any of [status],
  /// [serviceCategory], [storeId] and [search] (matched against the offer's name and its shop's).
  ///
  /// Unlike `CatalogApi.searchServices`, this lists what no customer sees: drafts, paused and archived
  /// offers, offers of draft or suspended shops and of closed categories, and offers back office took
  /// down. A filter that is not given is not sent.
  Future<Paged<BackofficeServiceOffer>> serviceOffers({
    ServiceOfferStatusFilter? status,
    ServiceCategory? serviceCategory,
    String? storeId,
    String? search,
    int page = 0,
    int size = 20,
  }) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/products/services/all',
      queryParameters: <String, dynamic>{
        if (status != null) 'status': status.wireValue,
        if (serviceCategory != null) 'serviceCategory': serviceCategory.wireValue,
        if (storeId != null && storeId.isNotEmpty) 'storeId': storeId,
        if (search != null && search.isNotEmpty) 'search': search,
        'page': page,
        'size': size,
      },
    );
    return Paged<BackofficeServiceOffer>.fromJson(
        response.data as Map<String, dynamic>, BackofficeServiceOffer.fromJson);
  }

  /// Takes the offer down: off sale for every customer at once, and its provider cannot publish, resume
  /// or pause it until it is restored. Answers the offer as it now is, holding [Product.moderation].
  ///
  /// Refused with a 400 for a blank reason or one over 500 characters, a 422 for a goods product or an
  /// offer already taken down, and a 404 for an id that names no product.
  Future<BackofficeServiceOffer> takeDown(String productId, {required String reason}) =>
      _act(productId, 'take-down', reason);

  /// Lifts the hold, with a reason for the trail. The offer comes back as it was, except that one that
  /// was on sale comes back paused, for its provider to resume. A 422 when the offer is not taken down.
  Future<BackofficeServiceOffer> restore(String productId, {required String reason}) =>
      _act(productId, 'restore', reason);

  /// The offer's trail, newest act first. Empty for an offer back office never acted on.
  Future<List<OfferModerationAction>> moderationHistory(String productId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/products/$productId/moderation');
    final Object? acts = response.data;
    if (acts is! List) {
      return const <OfferModerationAction>[];
    }
    return acts
        .whereType<Map<String, dynamic>>()
        .map(OfferModerationAction.fromJson)
        .toList();
  }

  /// The reason travels alone: who acted is the token's to say.
  Future<BackofficeServiceOffer> _act(String productId, String act, String reason) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/products/$productId/moderation/$act',
      data: <String, dynamic>{'reason': reason},
    );
    return BackofficeServiceOffer.fromJson(response.data as Map<String, dynamic>);
  }
}
