package com.delivery.product.api.dto;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import jakarta.validation.constraints.NotNull;

import com.delivery.product.domain.Store;

/** Shapes for the customer gift hub and for the back office's choice of what it features. */
public final class GiftDtos {

    private GiftDtos() {
    }

    /**
     * One featured care bundle, as the gift hub draws it: the product, the shop it comes from, and
     * whether it could still arrive today.
     *
     * <p>Enough for the phone to open the shop or put the product in the one-shop basket without
     * another round trip — the product's own id, price and merchant, the shop's id and slug — and
     * nothing a hub card does not show. The price is the catalogue's, exactly what checkout charges.
     *
     * @param sameDayDeliverable the shop is taking orders now and the slow end of its delivery
     *                           estimate fits before it closes. Decided from the shop's own clock at
     *                           the moment of the request, never stored: false for a shop that is
     *                           shut, and the card then promises nothing rather than "today"
     */
    public record GiftBundleResponse(
            UUID productId,
            String merchantId,
            UUID storeId,
            String storeSlug,
            String storeName,
            String name,
            String description,
            BigDecimal price,
            List<String> imageUrls,
            List<String> imageThumbUrls,
            Store.Availability availability,
            boolean sameDayDeliverable) {
    }

    /**
     * The back office's switch for one product.
     *
     * <p>A {@code Boolean} rather than a {@code boolean}, so a body that forgets the field is a 400
     * instead of silently meaning "take it off the hub".
     */
    public record GiftFeaturedRequest(@NotNull Boolean featured) {
    }

    /** What the switch now says, and since when the product has been on the hub. */
    public record GiftFeaturedResponse(UUID productId, boolean giftFeatured, Instant giftFeaturedAt) {
    }
}
