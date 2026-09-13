package com.delivery.product.api;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import jakarta.validation.Valid;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.security.CurrentUser;
import com.delivery.product.api.dto.GiftDtos.GiftBundleResponse;
import com.delivery.product.api.dto.GiftDtos.GiftFeaturedRequest;
import com.delivery.product.api.dto.GiftDtos.GiftFeaturedResponse;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.Store;
import com.delivery.product.service.GiftBundleService;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.ProductImageService.ImageUrl;

/**
 * The customer gift hub's featured care bundles, and the back office's hand on what it shows.
 *
 * <p>Reading is open to any authenticated caller, like the rest of browsing: it returns live products
 * of listed shops, nothing a shop page does not already show. Choosing is BACKOFFICE only — the hub
 * is the platform's window, and neither a merchant nor a customer may put products in it.
 */
@RestController
@RequestMapping("/api")
public class GiftBundleController {

    private final GiftBundleService gifts;
    private final ProductImageService images;

    public GiftBundleController(GiftBundleService gifts, ProductImageService images) {
        this.gifts = gifts;
        this.images = images;
    }

    /** The hub's bundles, newest pick first. An empty list is an ordinary answer: the hub hides it. */
    @GetMapping("/gift-bundles")
    public List<GiftBundleResponse> featured() {
        return gifts.featured(Instant.now()).stream().map(this::toResponse).toList();
    }

    /** Puts a product on the gift hub, or takes it off. */
    @PutMapping("/products/{id}/gift-featured")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public GiftFeaturedResponse setFeatured(@PathVariable UUID id,
                                            @Valid @RequestBody GiftFeaturedRequest request) {
        Product product = gifts.setFeatured(id, request.featured(), CurrentUser.requireId(),
                Instant.now());
        return new GiftFeaturedResponse(product.getId(), product.isGiftFeatured(),
                product.getGiftFeaturedAt());
    }

    private GiftBundleResponse toResponse(GiftBundleService.GiftBundle bundle) {
        Product product = bundle.product();
        Store shop = bundle.store();
        // One resolve, two lists — the same split the product API makes, so the hub row can draw
        // the 320px derivative and a detail screen the original.
        List<ImageUrl> resolved = images.resolveImages(product.getImageRefs());
        return new GiftBundleResponse(
                product.getId(),
                product.getMerchantId(),
                shop.getId(),
                shop.getSlug(),
                shop.getName(),
                product.getName(),
                product.getDescription(),
                product.getPrice(),
                resolved.stream().map(ImageUrl::full).toList(),
                resolved.stream().map(ImageUrl::thumb).toList(),
                bundle.availability(),
                bundle.sameDayDeliverable());
    }
}
