package com.delivery.product.api.dto;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalTime;
import java.util.List;
import java.util.UUID;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreOffer;

/**
 * Request and response shapes for the storefront API.
 *
 * <p>As with {@link CatalogDtos}, no request record carries a {@code merchantId}. Ownership comes
 * from the caller's validated token; accepting it in a body would let any merchant write into
 * another merchant's storefront.
 */
public final class StoreDtos {

    private StoreDtos() {
    }

    // ---------------------------------------------------------------- responses

    /**
     * A store as a customer sees it.
     *
     * <p>{@code availability} is computed per request rather than stored — see
     * {@link Store#availabilityAt}. {@code favorite} is resolved against the calling customer, so
     * the same store serialises differently for two different viewers; that is intended, and it is
     * why this is a view model rather than the entity.
     */
    public record StoreResponse(
            UUID id,
            String slug,
            String name,
            Store.Vertical vertical,
            String tagline,
            String description,
            List<String> tags,
            BigDecimal rating,
            int ratingCount,
            BigDecimal deliveryFee,
            BigDecimal minOrder,
            int etaMinMinutes,
            int etaMaxMinutes,
            Store.Availability availability,
            /** Wall-clock closing time for the window the store is currently in; null when closed. */
            LocalTime closesAt,
            /** Full-size logo. For the shop header, where it is drawn as a large badge. */
            String logoUrl,
            /**
             * Full-size cover. <strong>For the hero</strong> — the shop page draws this full-bleed
             * behind its header, which is the one place the whole photo is worth its bytes.
             */
            String coverUrl,
            /**
             * The logo at 320 px on the long edge. For any list-sized use. Falls back to
             * {@link #logoUrl()} when no derivative exists, and is null only when
             * {@code logoUrl} is.
             */
            String logoThumbUrl,
            /**
             * The cover at 320 px on the long edge. <strong>For list surfaces</strong> — the
             * storefront grid and the favourites rail. Falls back to {@link #coverUrl()} when no
             * derivative exists, and is null only when {@code coverUrl} is.
             */
            String coverThumbUrl,
            String address,
            /**
             * The map pin, or null when the merchant has not dropped one.
             *
             * <p>Both null together or both set together — the store enforces that, and V20's CHECK
             * constraints stand behind it — so a client can test either one and trust the other.
             * Null is the normal state for a shop that trades by delivery area alone; it means "no
             * map for this one", not "an error occurred".
             */
            BigDecimal latitude,
            BigDecimal longitude,
            boolean favorite,
            List<OfferResponse> offers,
            Store.Status status,
            Instant createdAt,
            /** District identity, or null when the shop never declared one. */
            String neighborhood,
            /** The Backoffice-granted dekkane trust badge. */
            boolean verifiedLocal,
            /** What the lights are doing. UNKNOWN draws no chip. */
            Store.PowerStatus powerStatus,
            String powerNote,
            /** When the merchant last declared — what "auto-updated" honestly means. */
            Instant powerUpdatedAt) {
    }

    /** The card shape: everything a storefront grid needs and nothing it does not. */
    public record StoreCardResponse(
            UUID id,
            String slug,
            String name,
            Store.Vertical vertical,
            String tagline,
            List<String> tags,
            BigDecimal rating,
            int ratingCount,
            BigDecimal deliveryFee,
            BigDecimal minOrder,
            int etaMinMinutes,
            int etaMaxMinutes,
            Store.Availability availability,
            /** Full-size logo, kept for clients already reading it. */
            String logoUrl,
            /**
             * Full-size cover, kept for clients already reading it.
             *
             * <p>A card is a list surface, so {@link #coverThumbUrl()} is what a grid should draw.
             * This one is still the right choice when a card's picture is being promoted into a
             * hero — the shop page opens from a card and reuses it behind its header.
             */
            String coverUrl,
            /** The logo at 320 px on the long edge; falls back to {@link #logoUrl()}. */
            String logoThumbUrl,
            /**
             * The cover at 320 px on the long edge. <strong>What a storefront grid should
             * draw.</strong> Falls back to {@link #coverUrl()} when no derivative exists.
             */
            String coverThumbUrl,
            boolean favorite,
            /** The single best promotion, for the ribbon on the card. Null when there is none. */
            OfferResponse topOffer,
            String neighborhood,
            boolean verifiedLocal,
            Store.PowerStatus powerStatus,
            String powerNote) {
    }

    public record OfferResponse(
            UUID id,
            UUID storeId,
            StoreOffer.Kind kind,
            String title,
            String subtitle,
            BigDecimal value,
            BigDecimal minSubtotal,
            Instant endsAt) {
    }

    /** One aisle in a store, with how many things are actually in it. */
    public record AisleResponse(
            UUID categoryId,
            String name,
            long productCount) {
    }

    public record HoursResponse(
            int dayOfWeek,
            LocalTime opensAt,
            LocalTime closesAt) {
    }

    public record ReviewResponse(
            java.util.UUID id,
            java.util.UUID storeId,
            java.util.UUID orderId,
            int rating,
            String comment,
            Instant createdAt,
            /** True when the review belongs to the caller, so the app can offer Edit. */
            boolean mine) {
    }

    // ---------------------------------------------------------------- requests

    public record ReviewRequest(
            @jakarta.validation.constraints.NotNull java.util.UUID orderId,
            @Min(1) @Max(5) int rating,
            @Size(max = 2000) String comment) {
    }

    public record StoreRequest(
            @NotBlank @Size(max = 160) String name,
            @NotNull Store.Vertical vertical,
            @Size(max = 240) String tagline,
            @Size(max = 4000) String description,
            List<@Size(max = 40) String> tags,
            @Size(max = 64) String timezone,
            @Size(max = 400) String address,
            /** District identity for the hyperlocal browse. Free text; the chips are distinct values. */
            @Size(max = 80) String neighborhood) {
    }

    /** The merchant's power declaration — what the lights are doing, and the one-liner under it. */
    public record PowerRequest(
            @NotNull Store.PowerStatus status,
            @Size(max = 160) String note) {
    }

    public record CommercialsRequest(
            @NotNull @DecimalMin("0.00") @Digits(integer = 10, fraction = 2) BigDecimal deliveryFee,
            @NotNull @DecimalMin("0.00") @Digits(integer = 10, fraction = 2) BigDecimal minOrder,
            @Min(1) @Max(1440) int etaMinMinutes,
            @Min(1) @Max(1440) int etaMaxMinutes) {
    }

    public record HoursRequest(
            @Min(1) @Max(7) int dayOfWeek,
            @NotNull LocalTime opensAt,
            @NotNull LocalTime closesAt) {
    }

    /**
     * Marks a store as behind on orders.
     *
     * <p>A duration, not a boolean. "Busy" set as a flag is forgotten and left on; expressed as
     * minutes it clears itself, which is what a kitchen actually wants.
     */
    public record BusyRequest(
            @Min(1) @Max(480) int minutes) {
    }

    public record OfferRequest(
            @NotNull StoreOffer.Kind kind,
            @NotBlank @Size(max = 160) String title,
            @Size(max = 240) String subtitle,
            @Digits(integer = 10, fraction = 2) BigDecimal value,
            @DecimalMin("0.00") @Digits(integer = 10, fraction = 2) BigDecimal minSubtotal) {
    }
}
