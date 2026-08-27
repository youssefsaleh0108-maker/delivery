package com.delivery.product.api.dto;

import java.math.BigDecimal;
import java.util.List;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;

import com.delivery.product.api.dto.StoreDtos.StoreCardResponse;
import com.delivery.product.service.CrossSellService;

/**
 * Coordinates, address search and the "near me" rail.
 *
 * <p>Same rule as the rest of the API: nothing here accepts an owner id. Which store a merchant may
 * move is decided from their token, in the service, not from anything in a body.
 */
public final class GeoDtos {

    private GeoDtos() {
    }

    // ---------------------------------------------------------------- requests

    /**
     * Where a merchant is putting their shop.
     *
     * <p>The bean-validation bounds duplicate {@link com.delivery.product.domain.GeoPoint}'s, and
     * both are wanted. These produce a per-field 400 with a message naming {@code latitude} —
     * something a form can highlight. The value object is the invariant itself, and it also guards
     * the callers that never see this record: the geocoder, and anything written later.
     *
     * <p>What is <em>not</em> duplicated is the (0, 0) rule. It is a statement about the pair rather
     * than about either field, so it lives in one place — the value object — and surfaces as a
     * message rather than a field error.
     */
    public record LocationRequest(
            @NotNull @DecimalMin("-90.0") @DecimalMax("90.0") BigDecimal latitude,
            @NotNull @DecimalMin("-180.0") @DecimalMax("180.0") BigDecimal longitude) {
    }

    // ---------------------------------------------------------------- responses

    /**
     * One candidate from the address picker.
     *
     * @param label     the line to show. Text from an open map database — see the note on
     *                  {@code GeocodingProvider}; render it as text, never as markup.
     * @param confident whether the provider called this an exact match rather than a near one, so a
     *                  picker can present a guess as a guess
     */
    public record PlaceResponse(
            String label,
            BigDecimal latitude,
            BigDecimal longitude,
            String kind,
            boolean confident) {
    }

    /**
     * A search result set, and who produced it.
     *
     * <p>{@code provider} is on the response deliberately. A pin dropped by the free dev geocoder
     * and one dropped by a paid provider are not equally trustworthy, and a client should be able to
     * see which it is looking at rather than assume.
     */
    public record PlaceSearchResponse(
            String provider,
            List<PlaceResponse> results) {
    }

    /** The address at a point, or nothing when the provider knows of none there. */
    public record ReverseGeocodeResponse(
            String provider,
            String label,
            BigDecimal latitude,
            BigDecimal longitude,
            String locality,
            String countryCode) {
    }

    /**
     * A store on the "near me" rail.
     *
     * <p>The card is nested rather than flattened so this stays additive: the storefront's existing
     * card shape is reused exactly, and a client that already renders one needs no changes to render
     * this.
     *
     * @param distanceMetres straight-line metres, rounded. Not the driven distance — no route is
     *                       computed here — and whole metres because the pin it is measured from was
     *                       dropped by hand and does not justify a decimal.
     */
    public record NearbyStoreResponse(
            StoreCardResponse store,
            BigDecimal latitude,
            BigDecimal longitude,
            long distanceMetres) {
    }

    /**
     * One suggestion on the cross-sell rail, with how it was arrived at.
     *
     * <p>{@code basis} is not decoration and clients should not ignore it.
     * {@code BOUGHT_TOGETHER} is counted from delivered baskets and {@code ordersTogether} is that
     * real count. {@code SAME_AISLE} is another product from the same shop with {@code ordersTogether}
     * null — no popularity was measured, and none is being claimed.
     */
    public record CrossSellResponse(
            CatalogDtos.ProductResponse product,
            CrossSellService.Basis basis,
            Long ordersTogether) {
    }
}
