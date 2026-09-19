package com.delivery.product.api.dto;

import java.math.BigDecimal;
import java.util.List;

import com.delivery.product.api.dto.CatalogDtos.ProductResponse;
import com.delivery.product.api.dto.StoreDtos.StoreCardResponse;

/**
 * The customer item search: "which shops near me sell this?".
 *
 * <p>A POST with a JSON body rather than a GET, so the customer's position never travels in a URL,
 * where gateways, proxies and access logs keep it ({@code docs/figma-added-designs.md}).
 */
public final class ItemSearchDtos {

    private ItemSearchDtos() {
    }

    /**
     * What to look for, and around where.
     *
     * @param q         what the customer typed, 2 to 100 characters; or null when {@code terms} or
     *                  {@code barcode} say what to look for
     * @param terms     up to 3 terms in all, counting {@code q}, each 2 to 100 characters. A photo's
     *                  name, Arabic name and brand, for example, where one text box has one.
     * @param barcode   8 to 14 digits, matched exactly, or null
     * @param latitude  where the customer is, with {@code longitude}, or both null. Both null searches
     *                  every live goods shop, with no distance.
     * @param page      zero-based, 0 when absent
     * @param size      shops per page, at most 20; 10 when absent
     */
    public record ItemSearchRequest(
            String q,
            List<String> terms,
            String barcode,
            BigDecimal latitude,
            BigDecimal longitude,
            Integer page,
            Integer size) {
    }

    /**
     * One shop and the matching products it sells.
     *
     * <p>The card is the storefront's own ({@link StoreCardResponse}), nested as "near me" nests it
     * ({@link GeoDtos.NearbyStoreResponse}), so a client that draws one draws this.
     *
     * @param latitude       the shop's pin, or null for a shop with none (found only without a point)
     * @param distanceMetres straight-line metres from the point, rounded; null when the search had none
     * @param items          the shop's best matches, at most 3, best first. Each price is the product's
     *                       own, as the shop's shelf shows it.
     * @param matchedInStore how many of the shop's products matched, counting {@code items}. A client says
     *                       "N more in this shop" with the difference, and opens the shop searched for the
     *                       same words, which matches the same way.
     */
    public record ShopItemsResponse(
            StoreCardResponse store,
            BigDecimal latitude,
            BigDecimal longitude,
            Long distanceMetres,
            List<ProductResponse> items,
            int matchedInStore) {
    }

    /**
     * A page of shops: the storefront's page shape, plus what keeps it honest.
     *
     * @param truncated      true when more products matched than one search reads. The page then covers
     *                       the best {@code candidateLimit} matches, so a client with nothing to show says
     *                       "among the best 300 matches" rather than "no shop sells it".
     * @param candidateLimit how many matching products one search reads
     * @param nearby         whether the search was around a point. When false, no shop has a distance and
     *                       the list is not in distance order, and a client should say so.
     */
    public record ItemSearchPageResponse(
            List<ShopItemsResponse> content,
            int page,
            int size,
            long totalElements,
            int totalPages,
            boolean truncated,
            int candidateLimit,
            boolean nearby) {
    }
}
