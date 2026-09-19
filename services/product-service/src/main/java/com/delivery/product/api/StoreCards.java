package com.delivery.product.api;

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import com.delivery.product.api.dto.StoreDtos.OfferResponse;
import com.delivery.product.api.dto.StoreDtos.StoreCardResponse;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreOffer;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.ProductImageService.ImageUrl;
import com.delivery.product.service.StoreService.StoreView;

/**
 * The one mapping from a shop to its card, shared by every endpoint that lists shops.
 *
 * <p>Moved out of {@link StoreController} when the item search began listing shops too, for the reason
 * {@link ProductResponses} gives about products: a field one copy gains and the other forgets is a card
 * that reads one way on Home and another way in search, for the same shop.
 */
final class StoreCards {

    private StoreCards() {
    }

    /**
     * A shop's card.
     *
     * @param starred       the caller's starred shops, read once for the whole list
     * @param offersByStore the live offers of every shop, read once for the whole list; a list costs
     *                      the same two reads however many cards it draws
     */
    static StoreCardResponse of(StoreView v, Set<UUID> starred,
                                Map<UUID, List<StoreOffer>> offersByStore,
                                ProductImageService images) {
        Store store = v.store();
        List<StoreOffer> storeOffers = offersByStore.getOrDefault(store.getId(), List.of());
        // Both sizes come out of one lookup per slot, so the storefront grid costs exactly the
        // metadata queries it did before.
        ImageUrl logo = images.resolveImage(store.getLogoRef());
        ImageUrl cover = images.resolveImage(store.getCoverRef());
        return new StoreCardResponse(
                store.getId(),
                store.getSlug(),
                store.getName(),
                store.getVertical(),
                store.getTagline(),
                store.getTags(),
                store.getRating(),
                store.getRatingCount(),
                store.getDeliveryFee(),
                store.getMinOrder(),
                store.getEtaMinMinutes(),
                store.getEtaMaxMinutes(),
                v.availability(),
                ImageUrl.fullOf(logo),
                ImageUrl.fullOf(cover),
                ImageUrl.thumbOf(logo),
                ImageUrl.thumbOf(cover),
                starred.contains(store.getId()),
                storeOffers.isEmpty() ? null : offer(storeOffers.get(0)),
                store.getNeighborhood(),
                store.isVerifiedLocal(),
                store.getPowerStatus(),
                store.getPowerNote(),
                store.getPowerUpdatedAt(),
                v.powerCurrent(),
                store.getLatitude(),
                store.getLongitude(),
                store.getDeliveryRadiusMetres(),
                store.getServiceCategory());
    }

    static OfferResponse offer(StoreOffer offer) {
        return new OfferResponse(
                offer.getId(),
                offer.getStoreId(),
                offer.getKind(),
                offer.getTitle(),
                offer.getSubtitle(),
                offer.getValue(),
                offer.getMinSubtotal(),
                offer.getEndsAt());
    }
}
