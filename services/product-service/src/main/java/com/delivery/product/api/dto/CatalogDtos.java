package com.delivery.product.api.dto;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import com.delivery.product.domain.Product;
import com.delivery.product.domain.ServiceTerms;
import com.delivery.product.domain.Store;

/**
 * Request and response shapes for the catalog API.
 *
 * <p>Note what is absent from every request record: {@code merchantId}. It is taken from the
 * caller's validated token, never from the body — accepting it would let any merchant write a
 * product into another merchant's catalog by changing one field (Section 3).
 */
public final class CatalogDtos {

    private CatalogDtos() {
    }

    public record ProductRequest(
            @NotBlank @Size(max = 200) String name,
            @Size(max = 4000) String description,
            @NotNull @DecimalMin(value = "0.01", message = "price must be greater than zero")
            @Digits(integer = 10, fraction = 2) BigDecimal price,
            UUID categoryId,
            /**
             * Which of the merchant's own stores to file this under. Optional: a merchant with one
             * store never needs to say. Ownership is still checked — unlike merchantId this cannot
             * simply be ignored, because a merchant may legitimately have more than one store.
             */
            UUID storeId,
            /**
             * The merchant's own code for the item, unique within the store when set. Optional:
             * blank is stored as absent, so several untagged products do not collide.
             */
            @Size(max = 64) String sku,
            /** Scanned at the till. Not unique — the same EAN legitimately appears in two stores. */
            @Size(max = 32) String barcode,
            /**
             * What a service offer promises: how it is priced, the pack, the turnaround, how the
             * customer gets the work, and whether they send a file. Replaced whole on an update.
             *
             * <p>Required for a product in a service shop and refused for any other (422). A goods
             * form that has never heard of it keeps working unchanged, and a service offer can never
             * be saved without the terms an order for it will need.
             */
            @Valid ServiceTermsRequest service) {
    }

    /** See {@link ServiceTerms} for what each term may be, and why. */
    public record ServiceTermsRequest(
            @NotNull ServiceTerms.PricingType pricingType,
            /** What one unit is called: "cards", "sqm". Needed for a pack of more, and per unit. */
            @Size(max = ServiceTerms.MAX_UNIT_LABEL_LENGTH) String unitLabel,
            /** Units in one step of the quantity stepper; one when absent, and always one per unit. */
            @Min(1) @Max(ServiceTerms.MAX_UNIT_SIZE) Integer unitSize,
            @NotNull @Min(0) @Max(ServiceTerms.MAX_TURNAROUND_HOURS) Integer turnaroundMinHours,
            @NotNull @Min(1) @Max(ServiceTerms.MAX_TURNAROUND_HOURS) Integer turnaroundMaxHours,
            @NotNull ServiceTerms.Fulfilment fulfilmentModes,
            /** NONE when absent. */
            ServiceTerms.AttachmentPolicy attachmentPolicy,
            @Size(max = ServiceTerms.MAX_INSTRUCTIONS_PROMPT_LENGTH) String instructionsPrompt) {
    }

    public record ProductResponse(
            UUID id,
            String merchantId,
            UUID storeId,
            String name,
            String description,
            BigDecimal price,
            UUID categoryId,
            List<String> imageRefs,
            /**
             * Full-size images, in display order. <strong>For detail surfaces</strong> — the
             * product hero and its gallery, where the photo is drawn at 280 dp full-bleed.
             *
             * <p>Unchanged in meaning and unchanged in name: clients already in the wild read this
             * field and know nothing about {@link #imageThumbUrls()}.
             */
            List<String> imageUrls,
            /**
             * The same images at 320 px on the long edge. <strong>For list surfaces</strong> —
             * shop-page product rows, basket lines, the merchant's product list, related-product
             * tiles — anywhere the photo is drawn at 80 dp or less.
             *
             * <p>Index-aligned with {@link #imageUrls()} and always the same length, so
             * {@code imageThumbUrls[i]} is always the small form of {@code imageUrls[i]}. An entry
             * repeats the full-size URL when no derivative exists, which is the case for every
             * image uploaded before thumbnailing and for any whose generation failed — so a client
             * can use this list unconditionally and never render a broken tile.
             */
            List<String> imageThumbUrls,
            Product.Status status,
            /** The merchant's own item code; null when the catalogue was never tagged. */
            String sku,
            /** Till-scannable code; null when unset. */
            String barcode,
            /**
             * Whether inventory-service currently believes the item is sellable. Always true for a
             * product the merchant has not opted into stock tracking, so clients can read it
             * unconditionally without knowing whether inventory is in play.
             */
            boolean inStock,
            Instant createdAt,
            Instant updatedAt,
            /**
             * Whether the back office has put this product on the customer gift hub. Public
             * curation rather than a secret: the hub itself shows every featured product.
             */
            boolean giftFeatured,
            /**
             * What a service offer promises; null for a goods product. On every read of the offer (a
             * shop's shelf, the services search, the merchant's list, a single read), so no screen
             * has to fetch the terms of the card it is drawing.
             */
            ServiceTermsResponse service,
            /**
             * The least a customer can pay for one pack of a service offer: the price plus the
             * cheapest selection each option group allows
             * ({@link com.delivery.product.domain.ProductOptionGroup#minimumDelta}), never below zero.
             * What "From $15.00" shows. A client says "From" for FROM pricing, or when this is not the
             * price; for a fixed price with no required extras the two are equal.
             *
             * <p>Null for a goods product. Goods screens never draw it, and the goods shelf is not made
             * to read every product's options for a figure nobody shows.
             */
            BigDecimal fromPrice,
            /**
             * Back office's hold on this offer, or null when there is none (V36).
             *
             * <p>What the provider's offer list and offer screen show: that YouDrop took the offer
             * down, when, and why, and so why publishing, resuming and pausing it are refused until
             * back office restores it. No customer ever receives one: a taken-down offer is ARCHIVED,
             * and only its provider can read a product that is not on sale.
             */
            ModerationResponse moderation,
            /**
             * Where this item sits inside its block of the menu (V41) — its section, or the shop's
             * unsectioned remainder.
             *
             * <p>Read-only here, like {@link #inStock()}: it is written by
             * {@code PUT /api/stores/{storeId}/categories/{categoryId}/products/order}, which takes
             * a whole block at once, and never by {@link ProductRequest}. Zero throughout a block
             * nothing has ever reordered, which leaves the name to break the tie exactly as the
             * shop page has always sorted.
             */
            short position) {
    }

    /** A taken-down offer's hold, as its provider and back office read it. See {@link Product#takeDown}. */
    public record ModerationResponse(
            State state,
            /** Back office's reason, in its own words. */
            String reason,
            Instant takenDownAt) {

        public enum State {
            /** Off sale until back office restores it. */
            TAKEN_DOWN
        }

        /** The product's hold as a response, or null when it has none. */
        public static ModerationResponse of(Product product) {
            if (!product.isTakenDown()) {
                return null;
            }
            return new ModerationResponse(State.TAKEN_DOWN, product.getTakedownReason(),
                    product.getTakenDownAt());
        }
    }

    public record ServiceTermsResponse(
            ServiceTerms.PricingType pricingType,
            String unitLabel,
            int unitSize,
            int turnaroundMinHours,
            int turnaroundMaxHours,
            ServiceTerms.Fulfilment fulfilmentModes,
            ServiceTerms.AttachmentPolicy attachmentPolicy,
            String instructionsPrompt) {

        /** The terms as a response, or null for a goods product, which has none. */
        public static ServiceTermsResponse of(ServiceTerms terms) {
            if (terms == null) {
                return null;
            }
            return new ServiceTermsResponse(terms.getPricingType(), terms.getUnitLabel(),
                    terms.getUnitSize(), terms.getTurnaroundMinHours(), terms.getTurnaroundMaxHours(),
                    terms.getFulfilmentModes(), terms.getAttachmentPolicy(),
                    terms.getInstructionsPrompt());
        }
    }

    public record CategoryResponse(
            UUID id,
            String name,
            UUID parentId,
            /** Resolved to a loadable URL; null when no artwork has been uploaded. */
            String imageUrl,
            /**
             * Set only on the handful of categories that represent a storefront vertical, which is
             * what puts them in the customer app's home strip.
             */
            Store.Vertical vertical,
            /**
             * The shop that owns this section, or null for platform taxonomy.
             *
             * <p>Always null on this endpoint, which serves the platform tree only. It is present so
             * a client can tell the two apart from the payload alone rather than from which URL it
             * happened to call.
             */
            UUID storeId,
            List<CategoryResponse> children) {
    }

    public record CategoryRequest(
            @NotBlank @Size(max = 128) String name,
            UUID parentId) {
    }

    /** The client declares what it intends to upload; the service decides where it may go. */
    public record PresignUploadRequest(
            @NotBlank String contentType) {
    }

    public record PresignUploadResponse(
            UUID fileId,
            String uploadUrl,
            String objectKey,
            String contentType,
            Instant expiresAt,
            long maxSizeBytes) {
    }

    /** Envelope for paged results, so clients aren't coupled to Spring's Page serialisation. */
    public record PageResponse<T>(
            List<T> content,
            int page,
            int size,
            long totalElements,
            int totalPages) {

        public static <T> PageResponse<T> of(org.springframework.data.domain.Page<T> page) {
            return new PageResponse<>(
                    page.getContent(),
                    page.getNumber(),
                    page.getSize(),
                    page.getTotalElements(),
                    page.getTotalPages());
        }
    }
}
