package com.delivery.product.api.dto;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import com.delivery.product.domain.CatalogScan;
import com.delivery.product.domain.CatalogScanItem;
import com.delivery.product.domain.CatalogScanPhoto;

/**
 * Merchant Blitz request and response shapes.
 *
 * <p>As with every catalogue request: no merchant id anywhere. It is the caller's token, never a
 * field — and the one id a client may name, the store, is checked against the caller's own stores.
 */
public final class CatalogScanDtos {

    private CatalogScanDtos() {
    }

    /** Which of the caller's stores to fill. Optional: a merchant with one store never says. */
    public record CreateScanRequest(UUID storeId) {
    }

    public record ScanResponse(
            UUID id,
            UUID storeId,
            CatalogScan.Status status,
            /** Which provider produced the lines: FAKE, or CLAUDE. Null until a scan completes. */
            String provider,
            /**
             * True when the lines are sample data from the FAKE provider, not a reading of these
             * photos. Clients must say so on screen — see FakeVisionProvider.
             */
            boolean sample,
            /** Why it failed, as a code to word in the merchant's language. Null unless FAILED. */
            CatalogScan.FailureCode failureCode,
            int maxPhotos,
            int attemptsLeft,
            int scansLeftToday,
            List<PhotoResponse> photos,
            List<ItemResponse> items,
            Instant createdAt,
            Instant completedAt) {
    }

    public record PhotoResponse(
            UUID fileId,
            int position,
            CatalogScanPhoto.Status status,
            /** Loadable once the upload is confirmed; null while it is still pending. */
            String imageUrl) {
    }

    public record ItemResponse(
            UUID id,
            /** The file id of the photo this line was read from, matching a {@link PhotoResponse}. */
            UUID photoFileId,
            String name,
            String brand,
            String size,
            UUID categoryId,
            BigDecimal confidence,
            /** The provider's GUESS at a shelf price, in USD. Never a price the merchant set. */
            BigDecimal priceGuess,
            /** The price the merchant set, once they have. */
            BigDecimal price,
            BoxResponse box,
            CatalogScanItem.Status status,
            /** The DRAFT product an accepted line became. */
            UUID productId) {
    }

    /** Fractions of the photo's width and height, top-left origin. */
    public record BoxResponse(BigDecimal left, BigDecimal top, BigDecimal width, BigDecimal height) {
    }

    /** A line's corrections, saved without deciding it. The product form's own limits. */
    public record ItemEditRequest(
            @NotBlank @Size(max = 200) String name,
            @DecimalMin(value = "0.01", message = "price must be greater than zero")
            @Digits(integer = 10, fraction = 2) BigDecimal price,
            UUID categoryId) {
    }

    /** One line to accept as a DRAFT product, with the name, price and section the merchant chose. */
    public record AcceptRequest(
            @NotNull UUID itemId,
            @NotBlank @Size(max = 200) String name,
            @NotNull @DecimalMin(value = "0.01", message = "price must be greater than zero")
            @Digits(integer = 10, fraction = 2) BigDecimal price,
            UUID categoryId) {
    }

    /**
     * The review, applied in one request — all or nothing.
     *
     * <p>Capped at the most lines a scan can have, so one call can decide a whole scan and no more.
     */
    public record CommitRequest(
            @Size(max = 120) List<@Valid @NotNull AcceptRequest> accept,
            @Size(max = 120) List<@NotNull UUID> reject) {
    }
}
