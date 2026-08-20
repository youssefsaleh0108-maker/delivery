package com.delivery.product.api.dto;

import java.time.Instant;
import java.util.UUID;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import com.delivery.product.domain.Banner;
import com.delivery.product.domain.Store;

/** Request and response shapes for banners and category imagery. */
public final class BannerDtos {

    private BannerDtos() {
    }

    public record BannerResponse(
            UUID id,
            String title,
            String subtitle,
            /** Resolved to a loadable URL; null when no artwork has been uploaded yet. */
            String imageUrl,
            Banner.LinkKind linkKind,
            String linkTarget,
            int position,
            boolean active,
            Instant startsAt,
            Instant endsAt) {
    }

    public record BannerRequest(
            @NotBlank @Size(max = 160) String title,
            @Size(max = 240) String subtitle,
            Banner.LinkKind linkKind,
            @Size(max = 512) String linkTarget,
            @Min(0) @Max(999) int position,
            boolean active) {

        /** A banner with no stated destination is informational, not invalid. */
        public BannerRequest {
            linkKind = linkKind == null ? Banner.LinkKind.NONE : linkKind;
        }
    }

    /**
     * A category as the home strip renders it: a name, a picture, and the vertical its chip filters
     * the storefront by.
     */
    public record CategoryChipResponse(
            UUID id,
            String name,
            String imageUrl,
            Store.Vertical vertical) {
    }

    public record VerticalRequest(Store.Vertical vertical) {
    }
}
