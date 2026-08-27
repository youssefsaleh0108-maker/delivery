package com.delivery.product.api;

import java.math.BigDecimal;
import java.time.LocalTime;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.security.CurrentUser;
import com.delivery.platform.storage.PresignedUpload;
import com.delivery.product.api.dto.CatalogDtos.PageResponse;
import com.delivery.product.api.dto.CatalogDtos.PresignUploadRequest;
import com.delivery.product.api.dto.CatalogDtos.PresignUploadResponse;
import com.delivery.product.api.dto.CatalogDtos.ProductResponse;
import com.delivery.product.api.dto.GeoDtos.LocationRequest;
import com.delivery.product.api.dto.GeoDtos.NearbyStoreResponse;
import com.delivery.product.api.dto.StoreDtos.AisleResponse;
import com.delivery.product.api.dto.StoreDtos.BusyRequest;
import com.delivery.product.api.dto.StoreDtos.CommercialsRequest;
import com.delivery.product.api.dto.StoreDtos.HoursRequest;
import com.delivery.product.api.dto.StoreDtos.HoursResponse;
import com.delivery.product.api.dto.StoreDtos.OfferRequest;
import com.delivery.product.api.dto.StoreDtos.OfferResponse;
import com.delivery.product.api.dto.StoreDtos.ReviewRequest;
import com.delivery.product.api.dto.StoreDtos.ReviewResponse;
import com.delivery.product.api.dto.StoreDtos.StoreCardResponse;
import com.delivery.product.api.dto.StoreDtos.StoreRequest;
import com.delivery.product.api.dto.StoreDtos.StoreResponse;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreOffer;
import com.delivery.product.domain.StoreReview;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.ReviewService;
import com.delivery.product.service.StoreImageService;
import com.delivery.product.service.StoreService;
import com.delivery.product.service.StoreService.StoreView;

/**
 * The storefront API.
 *
 * <p>Same two-layer authorisation as {@link ProductController}: {@code @PreAuthorize} decides who
 * may call an endpoint, the service decides which rows they may touch. Browsing is deliberately
 * open to any authenticated caller — a customer with no role still needs to see the shops.
 */
@RestController
@RequestMapping("/api/stores")
public class StoreController {

    /**
     * The furthest "near me" will look: 50 km.
     *
     * <p>Not a performance number. Past this a proximity search has stopped being one — nobody is
     * choosing a restaurant fifty kilometres away on the strength of it being nearby — and an
     * uncapped radius would turn this endpoint into a way to page the entire store table sorted by
     * distance from an arbitrary point.
     */
    static final int MAX_NEARBY_RADIUS_METRES = 50_000;

    /**
     * The tightest circle worth asking for: 50 m.
     *
     * <p>A floor rather than an assertion about anything. Below this the radius is smaller than the
     * error in a hand-dropped pin, so a zero or negative value is a client bug rather than a
     * meaningful request, and answering it with an empty list forever would be an unhelpful way to
     * say so.
     */
    static final int MIN_NEARBY_RADIUS_METRES = 50;

    /**
     * The ceiling on rows read from the database for one nearby search.
     *
     * <p>The radius alone is not a bound: in a dense city a 50 km circle is every shop on the
     * platform. This caps what a single request can pull into memory to sort, and a caller who hits
     * it gets the nearest 500 — which is the right subset to lose the rest from.
     */
    static final int MAX_NEARBY_CANDIDATES = 500;

    private final StoreService storeService;
    private final CatalogService catalog;
    private final ProductImageService images;
    private final StoreImageService storeImages;
    private final ReviewService reviewService;

    public StoreController(StoreService storeService, CatalogService catalog,
                           ProductImageService images, StoreImageService storeImages,
                           ReviewService reviewService) {
        this.storeService = storeService;
        this.catalog = catalog;
        this.images = images;
        this.storeImages = storeImages;
        this.reviewService = reviewService;
    }

    // ---------------------------------------------------------------- storefront

    /**
     * The customer home screen.
     *
     * <p>Favourites and offers are each read once for the whole page and applied while mapping,
     * rather than per card. A storefront is the one screen where an N+1 is guaranteed to be noticed.
     */
    @GetMapping
    public PageResponse<StoreCardResponse> browse(
            @RequestParam(required = false) Store.Vertical vertical,
            @RequestParam(required = false) String search,
            @RequestParam(required = false) BigDecimal maxDeliveryFee,
            @RequestParam(required = false) Integer maxEtaMinutes,
            @RequestParam(required = false) BigDecimal minRating,
            @PageableDefault(size = 20, sort = "rating", direction = Sort.Direction.DESC)
            Pageable pageable) {

        Page<StoreView> page = storeService.storefront(vertical, search, maxDeliveryFee,
                maxEtaMinutes, minRating, pageable);

        Set<UUID> starred = storeService.favoriteIdsOf(CurrentUser.id().orElse(null));
        Map<UUID, List<StoreOffer>> offersByStore = storeService.liveOffersByStore();

        return PageResponse.of(page.map(v -> toCard(v, starred, offersByStore)));
    }

    /**
     * Live shops near a point, nearest first.
     *
     * <p>Open to any authenticated caller, exactly like {@link #browse} — a customer with no role
     * still needs to find the shops around them, and this returns nothing browsing does not already
     * return.
     *
     * <p>Deliberately not open to an unauthenticated one, though. A point is where somebody is
     * standing, and an endpoint that answers this to anyone is a free proximity oracle over the
     * whole store network; no signed-out client needs one.
     *
     * <p>Shops with no pin do not appear, and that is not a gap to be filled in later with a guess.
     * A merchant who has not placed themselves on a map has not told us where they are — and since
     * delivery is still priced by area (V18), nothing else about them changes.
     *
     * @param radiusMetres clamped into range rather than refused, which is the opposite of how the
     *                     coordinate is treated and deliberately so. A coordinate outside its range
     *                     is meaningless and there is no sensible answer to give; a radius of a
     *                     million metres is a client asking for "everything around here", and the
     *                     widest circle this endpoint supports genuinely answers that. Nothing
     *                     returned is untrue either way — every shop in the response really is
     *                     within the radius it was measured against.
     */
    @GetMapping("/nearby")
    public PageResponse<NearbyStoreResponse> nearby(
            @RequestParam BigDecimal latitude,
            @RequestParam BigDecimal longitude,
            @RequestParam(defaultValue = "5000") int radiusMetres,
            @PageableDefault(size = 20) Pageable pageable) {

        // Built here rather than passed on as two loose numbers, so an out-of-range or (0, 0)
        // coordinate is refused before it reaches the database — with the same message a merchant
        // saving a pin would get.
        GeoPoint centre = new GeoPoint(latitude, longitude);

        int radius = Math.min(Math.max(radiusMetres, MIN_NEARBY_RADIUS_METRES),
                MAX_NEARBY_RADIUS_METRES);

        Page<StoreService.NearbyStoreView> page =
                storeService.nearby(centre, radius, MAX_NEARBY_CANDIDATES, pageable);

        Set<UUID> starred = storeService.favoriteIdsOf(CurrentUser.id().orElse(null));
        Map<UUID, List<StoreOffer>> offersByStore = storeService.liveOffersByStore();

        return PageResponse.of(page.map(near -> new NearbyStoreResponse(
                toCard(near.store(), starred, offersByStore),
                near.store().store().getLatitude(),
                near.store().store().getLongitude(),
                // Whole metres. The pin this is measured from was dropped by hand on a map, so a
                // decimal place would be precision the number does not have.
                Math.round(near.distanceMetres()))));
    }

    /**
     * The starred row at the top of the home screen.
     *
     * <p>Paged like everything else. A customer who has starred two hundred shops should not send
     * two hundred cards down the wire to fill a rail that shows four.
     */
    @GetMapping("/favorites")
    public PageResponse<StoreCardResponse> favorites(
            @PageableDefault(size = 20) Pageable pageable) {
        String userId = CurrentUser.requireId();
        Page<StoreView> page = storeService.favoritesOf(userId, pageable);

        Set<UUID> starred = storeService.favoriteIdsOf(userId);
        Map<UUID, List<StoreOffer>> offersByStore = storeService.liveOffersByStore();

        return PageResponse.of(page.map(v -> toCard(v, starred, offersByStore)));
    }

    /** The Merchant Portal's list of its own stores, in any status. */
    @GetMapping("/mine")
    @PreAuthorize("hasRole('MERCHANT')")
    public PageResponse<StoreResponse> mine(@PageableDefault(size = 20) Pageable pageable) {
        String merchantId = CurrentUser.requireId();
        Set<UUID> starred = storeService.favoriteIdsOf(merchantId);
        return PageResponse.of(
                storeService.ownedByView(merchantId, pageable).map(v -> toResponse(v, starred)));
    }

    /** Platform-wide promotions — the ones not tied to any single shop. */
    @GetMapping("/offers")
    public PageResponse<OfferResponse> platformOffers(
            @PageableDefault(size = 20) Pageable pageable) {
        return PageResponse.of(storeService.platformOffers(pageable).map(StoreController::toOffer));
    }

    /** Accepts an id or a slug, so a shared link and an in-app tap hit the same endpoint. */
    @GetMapping("/{idOrSlug}")
    public StoreResponse read(@PathVariable String idOrSlug) {
        String viewerId = CurrentUser.id().orElse(null);
        return toResponse(storeService.readView(idOrSlug, viewerId),
                storeService.favoriteIdsOf(viewerId));
    }

    /** A store's shelf. */
    @GetMapping("/{id}/products")
    public PageResponse<ProductResponse> products(
            @PathVariable UUID id,
            @RequestParam(required = false) UUID categoryId,
            @RequestParam(required = false) String search,
            /**
             * Restricts the page to specific products. Used by Buy Again, which knows the ids it
             * wants from order history and needs them re-read from the live catalog — anything
             * since archived simply does not come back, which is the correct outcome.
             */
            @RequestParam(required = false) List<UUID> ids,
            @PageableDefault(size = 20, sort = "name", direction = Sort.Direction.ASC)
            Pageable pageable) {

        Page<Product> page = ids == null || ids.isEmpty()
                ? catalog.browseStore(id, categoryId, search, pageable)
                : catalog.browseStoreByIds(id, ids, pageable);
        return PageResponse.of(page.map(this::toProduct));
    }

    /** The Aisles tab: only the categories this store actually stocks. */
    @GetMapping("/{id}/aisles")
    public List<AisleResponse> aisles(@PathVariable UUID id) {
        return storeService.aislesOf(id).stream()
                .map(a -> new AisleResponse(a.categoryId(), a.name(), a.productCount()))
                .toList();
    }

    /** The Offers tab: this store's promotions plus the platform-wide ones. */
    @GetMapping("/{id}/offers")
    public PageResponse<OfferResponse> offers(@PathVariable UUID id,
                                              @PageableDefault(size = 20) Pageable pageable) {
        return PageResponse.of(storeService.liveOffersFor(id, pageable)
                .map(StoreController::toOffer));
    }

    @GetMapping("/{id}/hours")
    public List<HoursResponse> hours(@PathVariable UUID id) {
        return storeService.hoursOf(id, CurrentUser.id().orElse(null)).stream()
                .map(h -> new HoursResponse(h.getDay().getValue(), h.getOpensAt(), h.getClosesAt()))
                .sorted(java.util.Comparator.comparingInt(HoursResponse::dayOfWeek)
                        .thenComparing(HoursResponse::opensAt))
                .toList();
    }

    // ---------------------------------------------------------------- favourites

    @PutMapping("/{id}/favorite")
    public ResponseEntity<Void> star(@PathVariable UUID id) {
        storeService.star(CurrentUser.requireId(), id);
        return ResponseEntity.noContent().build();
    }

    @DeleteMapping("/{id}/favorite")
    public ResponseEntity<Void> unstar(@PathVariable UUID id) {
        storeService.unstar(CurrentUser.requireId(), id);
        return ResponseEntity.noContent().build();
    }

    // ---------------------------------------------------------------- administration

    @PostMapping
    @PreAuthorize("hasRole('MERCHANT')")
    public ResponseEntity<StoreResponse> create(@Valid @RequestBody StoreRequest request) {
        StoreView created = storeService.create(CurrentUser.requireId(), request);
        return ResponseEntity.status(HttpStatus.CREATED).body(toResponse(created, Set.of()));
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasRole('MERCHANT')")
    public StoreResponse update(@PathVariable UUID id, @Valid @RequestBody StoreRequest request) {
        return toResponse(storeService.update(id, CurrentUser.requireId(), request), Set.of());
    }

    /**
     * Drops or moves the shop's map pin.
     *
     * <p>Separate from {@link #update} on purpose, and the reason is a failure mode rather than
     * tidiness: the profile form is saved every time a merchant edits their tagline, so a nullable
     * coordinate pair on {@code StoreRequest} would silently clear the pin on every save made by a
     * client that does not know the fields exist — which is every client today. Moving a shop is its
     * own decision and gets its own call.
     *
     * <p>MERCHANT, and the service then checks this merchant owns this store. Role alone would let
     * any merchant move any shop on the map.
     */
    @PutMapping("/{id}/location")
    @PreAuthorize("hasRole('MERCHANT')")
    public StoreResponse setLocation(@PathVariable UUID id,
                                     @Valid @RequestBody LocationRequest request) {
        GeoPoint location = new GeoPoint(request.latitude(), request.longitude());
        return toResponse(storeService.pin(id, CurrentUser.requireId(), location), Set.of());
    }

    /** Takes the shop off the map. The address text is kept — only the pin goes. */
    @DeleteMapping("/{id}/location")
    @PreAuthorize("hasRole('MERCHANT')")
    public StoreResponse clearLocation(@PathVariable UUID id) {
        return toResponse(storeService.unpin(id, CurrentUser.requireId()), Set.of());
    }

    @PutMapping("/{id}/commercials")
    @PreAuthorize("hasRole('MERCHANT')")
    public StoreResponse commercials(@PathVariable UUID id,
                                     @Valid @RequestBody CommercialsRequest request) {
        return toResponse(storeService.updateCommercials(id, CurrentUser.requireId(), request), Set.of());
    }

    @PutMapping("/{id}/hours")
    @PreAuthorize("hasRole('MERCHANT')")
    public List<HoursResponse> setHours(@PathVariable UUID id,
                                        @Valid @RequestBody List<HoursRequest> windows) {
        return storeService.replaceHours(id, CurrentUser.requireId(), windows).store().getHours().stream()
                .map(h -> new HoursResponse(h.getDay().getValue(), h.getOpensAt(), h.getClosesAt()))
                .toList();
    }

    @PostMapping("/{id}/publish")
    @PreAuthorize("hasRole('MERCHANT')")
    public StoreResponse publish(@PathVariable UUID id) {
        return toResponse(storeService.publish(id, CurrentUser.requireId()), Set.of());
    }

    @PostMapping("/{id}/suspend")
    @PreAuthorize("hasRole('MERCHANT')")
    public StoreResponse suspend(@PathVariable UUID id) {
        return toResponse(storeService.suspend(id, CurrentUser.requireId()), Set.of());
    }

    /** "We're behind" — self-expiring, so it cannot be left switched on overnight. */
    @PostMapping("/{id}/busy")
    @PreAuthorize("hasRole('MERCHANT')")
    public StoreResponse busy(@PathVariable UUID id, @Valid @RequestBody BusyRequest request) {
        return toResponse(storeService.setBusy(id, CurrentUser.requireId(), request.minutes()), Set.of());
    }

    @DeleteMapping("/{id}/busy")
    @PreAuthorize("hasRole('MERCHANT')")
    public StoreResponse clearBusy(@PathVariable UUID id) {
        return toResponse(storeService.clearBusy(id, CurrentUser.requireId()), Set.of());
    }

    // ---------------------------------------------------------------- reviews

    /** A store's reviews, newest first. */
    @GetMapping("/{id}/reviews")
    public PageResponse<ReviewResponse> reviews(
            @PathVariable UUID id,
            @PageableDefault(size = 20) Pageable pageable) {
        String viewer = CurrentUser.id().orElse(null);
        return PageResponse.of(reviewService.forStore(id, pageable)
                .map(r -> toReview(r, viewer)));
    }

    /**
     * Rates an order, or revises an existing rating.
     *
     * <p><strong>Known limit.</strong> This does not verify that the order exists, belongs to the
     * caller, or was ever delivered — those facts live in order-manager's schema, which this service
     * physically cannot read. The unique constraint on {@code order_id} bounds the damage to one
     * review per order id, but a determined caller could invent order ids. Closing it properly means
     * consuming {@code order.delivered} into a local projection of "who may review what", which is
     * the right shape and is not built yet.
     */
    @PostMapping("/{id}/reviews")
    @PreAuthorize("hasRole('CUSTOMER')")
    public ResponseEntity<ReviewResponse> review(@PathVariable UUID id,
                                                 @Valid @RequestBody ReviewRequest request) {
        String customerId = CurrentUser.requireId();
        StoreReview saved = reviewService.rate(
                id, customerId, request.orderId(), request.rating(), request.comment());
        return ResponseEntity.status(HttpStatus.CREATED).body(toReview(saved, customerId));
    }

    /** The caller's own review of one order, so the app can offer Rate or Edit. */
    @GetMapping("/reviews/order/{orderId}")
    @PreAuthorize("hasRole('CUSTOMER')")
    public ResponseEntity<ReviewResponse> reviewForOrder(@PathVariable UUID orderId) {
        String customerId = CurrentUser.requireId();
        return reviewService.forOrder(orderId)
                .filter(r -> r.isBy(customerId))
                .map(r -> ResponseEntity.ok(toReview(r, customerId)))
                .orElseGet(() -> ResponseEntity.noContent().build());
    }

    @DeleteMapping("/reviews/order/{orderId}")
    @PreAuthorize("hasRole('CUSTOMER')")
    public ResponseEntity<Void> deleteReview(@PathVariable UUID orderId) {
        reviewService.delete(orderId, CurrentUser.requireId());
        return ResponseEntity.noContent().build();
    }

    private static ReviewResponse toReview(StoreReview review, String viewer) {
        return new ReviewResponse(
                review.getId(),
                review.getStoreId(),
                review.getOrderId(),
                review.getRating(),
                review.getComment(),
                review.getCreatedAt(),
                review.isBy(viewer));
    }

    // ---------------------------------------------------------------- imagery

    /**
     * Step 1 of the upload: ask for a one-shot URL for this store's logo or cover.
     *
     * <p>{@code slot} is {@code logo} or {@code cover}. Same three-step flow as product images —
     * the bytes go straight from the browser to storage and never through this service.
     */
    @PostMapping("/{id}/images/{slot}/presign")
    @PreAuthorize("hasRole('MERCHANT')")
    public ResponseEntity<PresignUploadResponse> presignImage(
            @PathVariable UUID id,
            @PathVariable String slot,
            @Valid @RequestBody PresignUploadRequest request) {

        PresignedUpload upload = storeImages.presign(
                id, CurrentUser.requireId(), StoreImageService.slotOf(slot), request.contentType());

        return ResponseEntity.status(HttpStatus.CREATED).body(new PresignUploadResponse(
                upload.fileId(),
                upload.uploadUrl(),
                upload.objectKey(),
                upload.contentType(),
                upload.expiresAt(),
                upload.maxSizeBytes()));
    }

    /** Step 3: the bytes landed. Until this is called the picture is not attached to the store. */
    @PostMapping("/{id}/images/{slot}/{fileId}/confirm")
    @PreAuthorize("hasRole('MERCHANT')")
    public StoreResponse confirmImage(@PathVariable UUID id, @PathVariable String slot,
                                      @PathVariable UUID fileId) {
        storeImages.confirm(id, CurrentUser.requireId(), StoreImageService.slotOf(slot), fileId);
        return toResponse(storeService.readView(id.toString(), CurrentUser.requireId()), Set.of());
    }

    @DeleteMapping("/{id}/images/{slot}")
    @PreAuthorize("hasRole('MERCHANT')")
    public StoreResponse removeImage(@PathVariable UUID id, @PathVariable String slot) {
        storeImages.remove(id, CurrentUser.requireId(), StoreImageService.slotOf(slot));
        return toResponse(storeService.readView(id.toString(), CurrentUser.requireId()), Set.of());
    }

    @PostMapping("/{id}/offers")
    @PreAuthorize("hasRole('MERCHANT')")
    public ResponseEntity<OfferResponse> addOffer(@PathVariable UUID id,
                                                  @Valid @RequestBody OfferRequest request) {
        StoreOffer offer = storeService.addOffer(id, CurrentUser.requireId(), request);
        return ResponseEntity.status(HttpStatus.CREATED).body(toOffer(offer));
    }

    @DeleteMapping("/{id}/offers/{offerId}")
    @PreAuthorize("hasRole('MERCHANT')")
    public ResponseEntity<Void> withdrawOffer(@PathVariable UUID id, @PathVariable UUID offerId) {
        storeService.withdrawOffer(id, offerId, CurrentUser.requireId());
        return ResponseEntity.noContent().build();
    }

    // ---------------------------------------------------------------- mapping

    private StoreCardResponse toCard(StoreView v, Set<UUID> starred,
                                     Map<UUID, List<StoreOffer>> offersByStore) {
        Store store = v.store();
        List<StoreOffer> storeOffers = offersByStore.getOrDefault(store.getId(), List.of());
        return new StoreCardResponse(
                store.getId(),
                store.getSlug(),
                store.getName(),
                store.getVertical(),
                store.getTagline(),
                store.getTags(),
                store.getRating(),
                store.getRatingCount(),
                store.getDeliveryFee(),
                store.getMinOrder(),
                store.getEtaMinMinutes(),
                store.getEtaMaxMinutes(),
                v.availability(),
                images.resolveUrl(store.getLogoRef()),
                images.resolveUrl(store.getCoverRef()),
                starred.contains(store.getId()),
                storeOffers.isEmpty() ? null : toOffer(storeOffers.get(0)));
    }

    private StoreResponse toResponse(StoreView v, Set<UUID> starred) {
        Store store = v.store();
        return new StoreResponse(
                store.getId(),
                store.getSlug(),
                store.getName(),
                store.getVertical(),
                store.getTagline(),
                store.getDescription(),
                store.getTags(),
                store.getRating(),
                store.getRatingCount(),
                store.getDeliveryFee(),
                store.getMinOrder(),
                store.getEtaMinMinutes(),
                store.getEtaMaxMinutes(),
                v.availability(),
                v.closesAt(),
                images.resolveUrl(store.getLogoRef()),
                images.resolveUrl(store.getCoverRef()),
                store.getAddress(),
                store.getLatitude(),
                store.getLongitude(),
                starred.contains(store.getId()),
                storeService.liveOffersFor(store.getId()).stream()
                        .map(StoreController::toOffer).toList(),
                store.getStatus(),
                store.getCreatedAt());
    }

    private static OfferResponse toOffer(StoreOffer offer) {
        return new OfferResponse(
                offer.getId(),
                offer.getStoreId(),
                offer.getKind(),
                offer.getTitle(),
                offer.getSubtitle(),
                offer.getValue(),
                offer.getMinSubtotal(),
                offer.getEndsAt());
    }

    private ProductResponse toProduct(Product product) {
        List<String> refs = product.getImageRefs();
        return new ProductResponse(
                product.getId(),
                product.getMerchantId(),
                product.getStoreId(),
                product.getName(),
                product.getDescription(),
                product.getPrice(),
                product.getCategoryId(),
                refs,
                images.resolveUrls(refs),
                product.getStatus(),
                product.getCreatedAt(),
                product.getUpdatedAt());
    }
}
