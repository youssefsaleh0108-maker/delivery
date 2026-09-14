import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// The services shop a provider stands in, read from the shops they own.
///
/// `StoreApi.mine` rather than the storefront's read by id: the storefront leaves a services shop out
/// of every read that does not ask for services, and a provider's own screens have to see their shop
/// whether or not it is listed. With no [storeId], the owner's services shop; null when there is none.
Future<Store?> svcFindShop(StoreApi stores, String? storeId) async {
  final List<Store> owned = (await stores.mine(size: 20)).content;
  for (final Store store in owned) {
    if (storeId != null ? store.id == storeId : store.vertical == StoreVertical.services) {
      return store;
    }
  }
  return null;
}

/// Whether customers can have [shop]'s work delivered: it has delivery areas, or a pin to deliver from
/// — Product Service's own rule for publishing an offer that can be delivered.
///
/// Null when that cannot be told: no pin, and no zones client to ask or a read that failed. The form
/// then lets the provider choose, and the server decides at publishing.
Future<bool?> svcDeliveryReach(Store shop, DeliveryZoneApi? zones) async {
  if (shop.latitude != null && shop.longitude != null) return true;
  if (zones == null) return null;
  try {
    return (await zones.coverage(shop.id)).isNotEmpty;
  } catch (_) {
    return null;
  }
}

/// Whether an offer has the photo publishing needs.
bool svcHasPhoto(Product offer) => offer.imageRefs.isNotEmpty || offer.imageUrls.isNotEmpty;

/// Pauses a live offer or puts a paused one back on sale, saying what came of it. Answers the offer as
/// it now stands, or null when nothing changed.
///
/// A resume the server would refuse is refused here first, in the provider's language, where the
/// reason is knowable: no photo, or delivery offered by a shop that reaches nobody. The server's own
/// refusal is a sentence in English meant for logs.
Future<Product?> svcToggleOffer(
  BuildContext context,
  CatalogApi api,
  Product offer, {
  bool? deliveryReach,
}) async {
  final DeliveryStrings t = DeliveryStrings.of(context);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final bool pausing = offer.status == ProductStatus.active;
  final bool offersDelivery = offer.service?.fulfilmentModes.includesDelivery ?? false;

  if (!pausing && !svcHasPhoto(offer)) {
    messenger.showSnackBar(SnackBar(content: Text(t.svcPhotoRequired)));
    return null;
  }
  if (!pausing && offersDelivery && deliveryReach == false) {
    messenger.showSnackBar(SnackBar(content: Text(t.svcDeliveryNeedsAreas)));
    return null;
  }

  try {
    final Product moved = pausing ? await api.pause(offer.id) : await api.resume(offer.id);
    messenger.showSnackBar(
        SnackBar(content: Text(pausing ? t.svcOfferPausedDone : t.svcOfferResumedDone)));
    return moved;
  } on DioException catch (e) {
    final String message = switch (e.response?.statusCode) {
      // Still awaiting approval: resuming is publishing, and publishing waits for it.
      403 => t.svcPublishAfterApproval,
      422 => offersDelivery && deliveryReach != true ? t.svcDeliveryNeedsAreas : t.svcOfferRefused,
      _ => t.thatDidNotGoThrough,
    };
    messenger.showSnackBar(SnackBar(content: Text(message)));
    return null;
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(t.thatDidNotGoThrough)));
    return null;
  }
}
