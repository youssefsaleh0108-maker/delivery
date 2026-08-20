package com.delivery.product.service;

import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.platform.storage.FilePurpose;
import com.delivery.platform.storage.PresignedUpload;
import com.delivery.platform.storage.StorageService;
import com.delivery.product.api.dto.BannerDtos.BannerRequest;
import com.delivery.product.domain.Banner;
import com.delivery.product.domain.BannerRepository;
import com.delivery.product.domain.Category;
import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;

/**
 * Home-screen banners, and the artwork behind the category strip.
 *
 * <p>Both are platform-wide editorial rather than merchant content — a banner promotes whatever the
 * business wants promoted this week, and the category taxonomy is shared by every store. So both
 * are BACKOFFICE-owned, unlike store logos which belong to the merchant who runs the shop.
 *
 * <p>Images reuse the {@code product-images} bucket with their own key prefixes, for the same
 * reason store artwork does: publicly readable storefront imagery, and a separate bucket would need
 * provisioning and a policy for no behavioural difference.
 */
@Service
public class BannerService {

    private final BannerRepository banners;
    private final CategoryRepository categories;
    private final StoreRepository stores;
    private final StorageService storage;
    private final Clock clock;

    public BannerService(BannerRepository banners, CategoryRepository categories,
                         StoreRepository stores, StorageService storage, Clock clock) {
        this.banners = banners;
        this.categories = categories;
        this.stores = stores;
        this.storage = storage;
        this.clock = clock;
    }

    // ---------------------------------------------------------------- reads

    /** The customer rail: live banners only, in curated order. */
    @Transactional(readOnly = true)
    public List<Banner> live() {
        Instant now = clock.instant();
        return banners.findActive().stream().filter(b -> b.isLiveAt(now)).toList();
    }

    /** The Backoffice list: everything, including withdrawn and scheduled. */
    @Transactional(readOnly = true)
    public Page<Banner> all(Pageable pageable) {
        return banners.findAllByOrderByPositionAscCreatedAtDesc(pageable);
    }

    @Transactional(readOnly = true)
    public Banner read(UUID id) {
        return banners.findById(id).orElseThrow(() -> new BannerNotFoundException(id));
    }

    // ---------------------------------------------------------------- writes

    @Transactional
    public Banner create(BannerRequest request) {
        try {
            Banner banner = new Banner(request.title(), request.subtitle(), request.linkKind(),
                    request.linkTarget(), request.position());
            validateTarget(banner);
            return banners.save(banner);
        } catch (IllegalArgumentException e) {
            throw new CatalogRuleViolationException(e.getMessage());
        }
    }

    @Transactional
    public Banner update(UUID id, BannerRequest request) {
        Banner banner = read(id);
        try {
            banner.update(request.title(), request.subtitle(), request.linkKind(),
                    request.linkTarget(), request.position(), request.active());
            validateTarget(banner);
        } catch (IllegalArgumentException e) {
            throw new CatalogRuleViolationException(e.getMessage());
        }
        return banner;
    }

    /**
     * Checks a STORE or CATEGORY banner actually points at something that exists.
     *
     * <p>Caught here rather than left to the tap: a banner pointing at a deleted category is a dead
     * end a customer discovers, and the person who could fix it is not the person who finds it.
     * URL targets are not followed — that is not this service's job.
     */
    private void validateTarget(Banner banner) {
        if (banner.getLinkKind() == Banner.LinkKind.NONE
                || banner.getLinkKind() == Banner.LinkKind.URL) {
            return;
        }
        UUID target;
        try {
            target = UUID.fromString(banner.getLinkTarget());
        } catch (IllegalArgumentException e) {
            throw new CatalogRuleViolationException(
                    "A " + banner.getLinkKind() + " banner needs an id to point at");
        }
        boolean exists = banner.getLinkKind() == Banner.LinkKind.CATEGORY
                ? categories.existsById(target)
                : stores.existsById(target);
        if (!exists) {
            throw new CatalogRuleViolationException(
                    "Nothing found for " + banner.getLinkKind() + " " + target);
        }
    }

    @Transactional
    public void delete(UUID id) {
        // Withdrawn, not deleted: a banner that ran is part of the record of what was promoted.
        read(id).withdraw();
    }

    // ---------------------------------------------------------------- imagery

    @Transactional
    public PresignedUpload presignBanner(UUID bannerId, String userId, String contentType) {
        read(bannerId);
        return storage.presignUpload(userId, FilePurpose.PRODUCT_IMAGE, contentType,
                "banners/" + bannerId);
    }

    @Transactional
    public Banner confirmBannerImage(UUID bannerId, String userId, UUID fileId) {
        Banner banner = read(bannerId);
        banner.setImageRef(storage.confirmUpload(fileId, userId).getObjectKey());
        return banner;
    }

    @Transactional
    public PresignedUpload presignCategory(UUID categoryId, String userId, String contentType) {
        requireCategory(categoryId);
        return storage.presignUpload(userId, FilePurpose.PRODUCT_IMAGE, contentType,
                "categories/" + categoryId);
    }

    @Transactional
    public Category confirmCategoryImage(UUID categoryId, String userId, UUID fileId) {
        Category category = requireCategory(categoryId);
        category.setImageRef(storage.confirmUpload(fileId, userId).getObjectKey());
        return category;
    }

    /** Sets or clears which vertical a category represents on the home strip. */
    @Transactional
    public Category setVertical(UUID categoryId, Store.Vertical vertical) {
        Category category = requireCategory(categoryId);
        category.setVertical(vertical);
        return category;
    }

    /** The home strip: categories tagged with a vertical, so each chip can filter the storefront. */
    @Transactional(readOnly = true)
    public List<Category> verticalCategories() {
        return categories.findAll().stream()
                .filter(c -> c.getVertical() != null)
                .sorted(java.util.Comparator.comparing(Category::getName))
                .toList();
    }

    private Category requireCategory(UUID id) {
        return categories.findById(id)
                .orElseThrow(() -> new CatalogRuleViolationException(
                        "Category " + id + " does not exist"));
    }

    public static class BannerNotFoundException extends RuntimeException {
        public BannerNotFoundException(UUID id) {
            super("Banner " + id + " was not found");
        }
    }
}
