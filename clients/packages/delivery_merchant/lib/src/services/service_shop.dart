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

/// Whether an offer belongs on the provider's own lists: every offer but one its provider archived.
///
/// An offer YouDrop took down is archived too, but it stays listed, saying so and why. Left out, a
/// take-down looked like the offer had simply vanished, with nothing to tell the provider what to fix.
bool svcListsOffer(Product offer) => offer.status != ProductStatus.archived || offer.isTakenDown;

/// What the provider is told about an offer YouDrop holds: that it was taken down, and back office's
/// reason when it gave one.
String svcTakenDownWords(Product offer, DeliveryStrings t) {
  final String? reason = offer.moderation?.reason;
  return reason == null
      ? t.svcOfferTakenDown
      : '${t.svcOfferTakenDown} · ${t.svcOfferTakenDownReason(reason)}';
}

/// The `code` a refusal names in its body — Product Service's PRODUCT_CHANGED or OFFER_TAKEN_DOWN — or
/// null when it names none.
String? svcRefusalCode(DioException error) {
  final Object? body = error.response?.data;
  if (body is Map && body['code'] is String) return body['code'] as String;
  return null;
}

/// The offer as the server holds it now, or null when it cannot be read just now.
Future<Product?> svcReadOffer(CatalogApi api, String id) async {
  try {
    return await api.read(id);
  } catch (_) {
    return null;
  }
}

/// Pauses a live offer or puts a paused one back on sale, saying what came of it. Answers the offer as
/// it now stands, or null when nothing is known to have changed.
///
/// A resume the server would refuse is refused here first, in the provider's language, where the
/// reason is knowable: no photo, or delivery offered by a shop that reaches nobody. The server's own
/// refusal is a sentence in English meant for logs.
///
/// An offer YouDrop holds is neither paused nor resumed — the server refuses both until back office
/// restores it — so the provider is told that instead. And a 409 or 422 may mean the offer on screen is
/// not the offer on the server, so it is read again: YouDrop took it down meanwhile, or another save
/// changed it (PRODUCT_CHANGED). The provider is told which, never to set delivery areas that are not
/// the problem.
Future<Product?> svcToggleOffer(
  BuildContext context,
  CatalogApi api,
  Product offer, {
  bool? deliveryReach,
}) async {
  final DeliveryStrings t = DeliveryStrings.of(context);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  void say(String message) => messenger.showSnackBar(SnackBar(content: Text(message)));

  if (offer.isTakenDown) {
    say(svcTakenDownWords(offer, t));
    return null;
  }
  final bool pausing = offer.status == ProductStatus.active;
  final bool offersDelivery = offer.service?.fulfilmentModes.includesDelivery ?? false;

  if (!pausing && !svcHasPhoto(offer)) {
    say(t.svcPhotoRequired);
    return null;
  }
  if (!pausing && offersDelivery && deliveryReach == false) {
    say(t.svcDeliveryNeedsAreas);
    return null;
  }

  try {
    final Product moved = pausing ? await api.pause(offer.id) : await api.resume(offer.id);
    say(pausing ? t.svcOfferPausedDone : t.svcOfferResumedDone);
    return moved;
  } on DioException catch (e) {
    final int? status = e.response?.statusCode;
    if (status == 409 || status == 422) {
      final String? code = svcRefusalCode(e);
      final Product? now = await svcReadOffer(api, offer.id);
      if (now != null && now.isTakenDown) {
        say(svcTakenDownWords(now, t));
        return now;
      }
      if (code == 'PRODUCT_CHANGED' || code == 'OFFER_TAKEN_DOWN') {
        say(code == 'PRODUCT_CHANGED' ? t.svcOfferChangedElsewhere : t.svcOfferTakenDown);
        return now;
      }
    }
    say(switch (status) {
      // Still awaiting approval: resuming is publishing, and publishing waits for it.
      403 => t.svcPublishAfterApproval,
      422 => offersDelivery && deliveryReach != true ? t.svcDeliveryNeedsAreas : t.svcOfferRefused,
      _ => t.thatDidNotGoThrough,
    });
    return null;
  } catch (_) {
    say(t.thatDidNotGoThrough);
    return null;
  }
}
