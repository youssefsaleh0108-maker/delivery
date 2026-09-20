package com.delivery.product.api.dto;

import java.util.List;

import com.delivery.product.api.dto.ItemSearchDtos.ShopItemsResponse;
import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * Search by photo: the customer's search of the shops, and what the app may offer.
 *
 * <p>The photo itself travels as a multipart part, straight to the service and never to storage; the
 * point travels as form fields beside it, in the body, never in a URL.
 */
public final class PhotoSearchDtos {

    private PhotoSearchDtos() {
    }

    /**
     * What the photo was read as — the words, not the photo — so the app can say "Looks like: Pepsi
     * 1L" and let the customer search those words instead.
     *
     * @param isProduct false for a photo of no product: every other field is then null
     * @param barcode   a GTIN whose check digit is right, or null
     */
    public record UnderstoodResponse(
            String name,
            String nameAr,
            String brand,
            String size,
            String barcode,
            @JsonProperty("isProduct") boolean isProduct) {
    }

    /**
     * What was searched, for the next page: sent back to {@code POST /api/products/search/items} as its
     * {@code terms} and {@code barcode}, with the same point, so the photo is sent once.
     */
    public record NextQueryResponse(List<String> terms, String barcode) {
    }

    /**
     * The item search's page ({@link ItemSearchDtos.ItemSearchPageResponse}), with the photo's account of
     * itself.
     *
     * @param similar         true when nothing matched the product itself and these shops sell the same
     *                        kind of thing (its keywords); the app says "No exact match"
     * @param nextQuery       what was searched; null for a photo of no product, or one with no words
     * @param photosLeftToday the customer's photo searches left over the rolling day
     */
    public record PhotoSearchResponse(
            List<ShopItemsResponse> content,
            int page,
            int size,
            long totalElements,
            int totalPages,
            boolean truncated,
            int candidateLimit,
            boolean nearby,
            UnderstoodResponse understood,
            boolean similar,
            NextQueryResponse nextQuery,
            int photosLeftToday) {
    }

    /**
     * What the app may offer this account.
     *
     * @param photoSearch     true only for a customer, with customer photo search switched on and a
     *                        real reader configured; the app draws the camera only then
     * @param photosLeftToday the photo searches left over the rolling day; 0 when there is no photo search
     * @param maxPhotoBytes   the largest photo accepted
     */
    public record PhotoCapabilitiesResponse(
            boolean photoSearch,
            int photosLeftToday,
            long maxPhotoBytes) {
    }
}
