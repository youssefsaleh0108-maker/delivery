package com.delivery.product.api;

import java.util.List;
import java.util.UUID;

import jakarta.validation.Valid;

import org.springframework.data.domain.Pageable;
import org.springframework.data.web.PageableDefault;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.security.CurrentUser;
import com.delivery.platform.storage.PresignedUpload;
import com.delivery.product.api.dto.BannerDtos.BannerRequest;
import com.delivery.product.api.dto.BannerDtos.BannerResponse;
import com.delivery.product.api.dto.BannerDtos.CategoryChipResponse;
import com.delivery.product.api.dto.BannerDtos.VerticalRequest;
import com.delivery.product.api.dto.CatalogDtos.PageResponse;
import com.delivery.product.api.dto.CatalogDtos.PresignUploadRequest;
import com.delivery.product.api.dto.CatalogDtos.PresignUploadResponse;
import com.delivery.product.domain.Banner;
import com.delivery.product.domain.Category;
import com.delivery.product.service.BannerService;
import com.delivery.product.service.ProductImageService;

/**
 * Banners and category imagery.
 *
 * <p>Reads are open to any authenticated customer; every write is BACKOFFICE-only. This is
 * editorial content for the whole platform, not something a merchant curates — the one meaningful
 * difference from store artwork, where the merchant owns their own shopfront.
 */
@RestController
@RequestMapping("/api")
public class BannerController {

    private final BannerService banners;
    private final ProductImageService images;

    public BannerController(BannerService banners, ProductImageService images) {
        this.banners = banners;
        this.images = images;
    }

    // ---------------------------------------------------------------- customer

    /** The home rail. Live banners only, in curated order. */
    @GetMapping("/banners")
    public List<BannerResponse> live() {
        return banners.live().stream().map(this::toResponse).toList();
    }

    /**
     * The home category strip: name, picture, and the vertical each chip filters by.
     *
     * <p>Data-driven rather than a hard-coded enum with Material icons, so a category can carry
     * artwork somebody uploaded.
     */
    @GetMapping("/categories/chips")
    public List<CategoryChipResponse> chips() {
        return banners.verticalCategories().stream().map(this::toChip).toList();
    }

    // ---------------------------------------------------------------- backoffice

    @GetMapping("/banners/all")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public PageResponse<BannerResponse> all(@PageableDefault(size = 20) Pageable pageable) {
        return PageResponse.of(banners.all(pageable).map(this::toResponse));
    }

    @PostMapping("/banners")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ResponseEntity<BannerResponse> create(@Valid @RequestBody BannerRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(toResponse(banners.create(request)));
    }

    @PutMapping("/banners/{id}")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public BannerResponse update(@PathVariable UUID id, @Valid @RequestBody BannerRequest request) {
        return toResponse(banners.update(id, request));
    }

    /** Withdraws rather than deletes — a banner that ran is part of the record. */
    @DeleteMapping("/banners/{id}")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ResponseEntity<Void> withdraw(@PathVariable UUID id) {
        banners.delete(id);
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/banners/{id}/image/presign")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ResponseEntity<PresignUploadResponse> presignBanner(
            @PathVariable UUID id, @Valid @RequestBody PresignUploadRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED).body(toPresign(
                banners.presignBanner(id, CurrentUser.requireId(), request.contentType())));
    }

    @PostMapping("/banners/{id}/image/{fileId}/confirm")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public BannerResponse confirmBanner(@PathVariable UUID id, @PathVariable UUID fileId) {
        return toResponse(banners.confirmBannerImage(id, CurrentUser.requireId(), fileId));
    }

    @PostMapping("/categories/{id}/image/presign")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ResponseEntity<PresignUploadResponse> presignCategory(
            @PathVariable UUID id, @Valid @RequestBody PresignUploadRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED).body(toPresign(
                banners.presignCategory(id, CurrentUser.requireId(), request.contentType())));
    }

    @PostMapping("/categories/{id}/image/{fileId}/confirm")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public CategoryChipResponse confirmCategory(@PathVariable UUID id, @PathVariable UUID fileId) {
        return toChip(banners.confirmCategoryImage(id, CurrentUser.requireId(), fileId));
    }

    /** Tags a category as representing a vertical, which is what puts it in the home strip. */
    @PutMapping("/categories/{id}/vertical")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public CategoryChipResponse setVertical(@PathVariable UUID id,
                                            @RequestBody VerticalRequest request) {
        return toChip(banners.setVertical(id, request.vertical()));
    }

    // ---------------------------------------------------------------- mapping

    private BannerResponse toResponse(Banner banner) {
        return new BannerResponse(
                banner.getId(),
                banner.getTitle(),
                banner.getSubtitle(),
                images.resolveUrl(banner.getImageRef()),
                banner.getLinkKind(),
                banner.getLinkTarget(),
                banner.getPosition(),
                banner.isActive(),
                banner.getStartsAt(),
                banner.getEndsAt());
    }

    private CategoryChipResponse toChip(Category category) {
        return new CategoryChipResponse(category.getId(), category.getName(),
                images.resolveUrl(category.getImageRef()), category.getVertical());
    }

    private static PresignUploadResponse toPresign(PresignedUpload upload) {
        return new PresignUploadResponse(upload.fileId(), upload.uploadUrl(), upload.objectKey(),
                upload.contentType(), upload.expiresAt(), upload.maxSizeBytes());
    }
}
