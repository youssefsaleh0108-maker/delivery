package com.delivery.product.api;

import java.util.List;
import java.util.UUID;

import jakarta.validation.Valid;

import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.data.web.PageableDefault;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.security.CurrentUser;
import com.delivery.product.api.dto.CatalogDtos.PageResponse;
import com.delivery.product.api.dto.ModerationDtos.BackofficeOfferResponse;
import com.delivery.product.api.dto.ModerationDtos.ModerationActionResponse;
import com.delivery.product.api.dto.ModerationDtos.ModerationRequest;
import com.delivery.product.domain.Store;
import com.delivery.product.service.OfferModerationService;
import com.delivery.product.service.OfferModerationService.ModeratedOffer;
import com.delivery.product.service.OfferModerationService.Moderator;
import com.delivery.product.service.OfferModerationService.StatusFilter;
import com.delivery.product.service.ProductImageService;

/**
 * Back office's moderation of service offers: the list of every service shop's offers, taking one down
 * with a reason, restoring it, and its trail (V36).
 *
 * <p>BACKOFFICE and nobody else, on every endpoint. Not a merchant, not even for its own offers: a hold
 * its provider could lift would hold nothing. Not a customer either, since the list shows offers no
 * customer may see. The actor is always the token's subject, never a field of the body.
 *
 * <p>Literal paths beside {@link ProductController}'s: {@code /services/all} is resolved before
 * {@code /{id}}, and {@code /{id}/moderation} names a second segment no product read uses.
 */
@RestController
@RequestMapping("/api/products")
public class OfferModerationController {

    private final OfferModerationService moderation;
    private final ProductImageService images;

    public OfferModerationController(OfferModerationService moderation, ProductImageService images) {
        this.moderation = moderation;
        this.images = images;
    }

    /**
     * Every service shop's offers, in any status, filtered by any of {@code status} (TAKEN_DOWN for the
     * held ones, ARCHIVED for the ones their providers archived), {@code serviceCategory}, {@code storeId}
     * and {@code search} (the offer's or the shop's name), a page at a time, newest first.
     *
     * <p>"All", as {@code /api/banners/all} and {@code /api/delivery-zones/all} are back office's reads of
     * what the customer reads leave out. A status or category this service does not have is a 400.
     */
    @GetMapping("/services/all")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public PageResponse<BackofficeOfferResponse> all(
            @RequestParam(required = false) StatusFilter status,
            @RequestParam(required = false) Store.ServiceCategory serviceCategory,
            @RequestParam(required = false) UUID storeId,
            @RequestParam(required = false) String search,
            @PageableDefault(size = 20, sort = "createdAt", direction = Sort.Direction.DESC)
            Pageable pageable) {
        return PageResponse.of(moderation.list(status, serviceCategory, storeId, search, pageable)
                .map(this::toResponse));
    }

    /**
     * Takes a service offer down with a reason: off sale for every customer at once, and its provider
     * cannot publish, resume or pause it until back office restores it. The provider reads the reason on
     * the offer.
     *
     * <p>404 for an id that names no product. 422 for a goods product, an offer already taken down, or a
     * reason the service refuses. 400 for a blank reason or one over 500 characters.
     */
    @PostMapping("/{id}/moderation/take-down")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public BackofficeOfferResponse takeDown(@PathVariable UUID id,
                                            @Valid @RequestBody ModerationRequest request) {
        return toResponse(moderation.takeDown(id, moderator(), request.reason()));
    }

    /**
     * Restores a taken-down offer, with a reason for the trail. It comes back as it was, except that an
     * offer that was on sale comes back paused, for its provider to resume.
     *
     * <p>404 for an id that names no product. 422 for a goods product or an offer that is not taken down.
     * 400 for a blank reason or one over 500 characters.
     */
    @PostMapping("/{id}/moderation/restore")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public BackofficeOfferResponse restore(@PathVariable UUID id,
                                           @Valid @RequestBody ModerationRequest request) {
        return toResponse(moderation.restore(id, moderator(), request.reason()));
    }

    /** One offer's trail of take-downs and restores, newest first. 404 for an id that names no product. */
    @GetMapping("/{id}/moderation")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public List<ModerationActionResponse> history(@PathVariable UUID id) {
        return moderation.history(id).stream().map(ModerationActionResponse::of).toList();
    }

    /** The caller, from their token: the only way an actor is ever named. */
    private static Moderator moderator() {
        return new Moderator(CurrentUser.requireId(), CurrentUser.username().orElse(null));
    }

    private BackofficeOfferResponse toResponse(ModeratedOffer offer) {
        Store shop = offer.store();
        return new BackofficeOfferResponse(
                ProductResponses.of(offer.view(), images),
                shop.getId(),
                shop.getName(),
                shop.getServiceCategory(),
                shop.getStatus());
    }
}
