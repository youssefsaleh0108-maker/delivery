package com.delivery.product.api.dto;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import com.delivery.product.domain.Product;
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
            UUID storeId) {
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
            Instant createdAt,
            Instant updatedAt) {
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
