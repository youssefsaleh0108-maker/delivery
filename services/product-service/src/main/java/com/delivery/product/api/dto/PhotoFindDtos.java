package com.delivery.product.api.dto;

import java.util.List;
import java.util.UUID;

import com.delivery.product.api.dto.CatalogDtos.ProductResponse;
import com.delivery.product.api.dto.PhotoSearchDtos.UnderstoodResponse;

/**
 * A merchant finding a product in their own catalogue by photo.
 *
 * <p>The photo travels as a multipart part straight to the service, as a customer's does, and is
 * dropped when the answer comes back.
 */
public final class PhotoFindDtos {

    private PhotoFindDtos() {
    }

    /**
     * One of the merchant's own products the photo matched, in any status.
     *
     * @param matchedBy {@code BARCODE} when the code was equal, {@code NAME} otherwise
     */
    public record PhotoFindMatchResponse(ProductResponse product, String matchedBy) {
    }

    /**
     * What "Add as a new product" starts from.
     *
     * @param barcode null when a product in these shops already carries it
     * @param categoryId a section of the shop whose name the photo's keywords named exactly, or null
     */
    public record PhotoFindSuggestionResponse(String name, String barcode, UUID categoryId) {
    }

    /**
     * @param provider        which reader answered: {@code CLAUDE}, or {@code FAKE}
     * @param sample          true when these are sample lines rather than a reading of the photo, as
     *                        a Merchant Blitz scan says it; the client labels them
     * @param matches         at most five, the barcode's first
     * @param suggestion      null when the photo showed no product
     * @param findsLeftToday  the merchant's finds left over the rolling day
     */
    public record PhotoFindResponse(
            String provider,
            boolean sample,
            UnderstoodResponse understood,
            List<PhotoFindMatchResponse> matches,
            PhotoFindSuggestionResponse suggestion,
            int findsLeftToday) {
    }
}
