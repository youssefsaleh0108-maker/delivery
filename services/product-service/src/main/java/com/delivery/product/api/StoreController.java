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
import com.delivery.product.api.dto.DeliveryZoneDtos.ZoneResponse;
import com.delivery.product.api.dto.GeoDtos.LocationRequest;
import com.delivery.product.api.dto.GeoDtos.NearbyPageResponse;
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
import com.delivery.product.api.dto.StoreDtos.PowerRequest;
import com.delivery.product.api.dto.StoreDtos.RadiusRequest;
import com.delivery.product.api.dto.StoreDtos.StoreResponse;
import com.delivery.product.api.dto.StoreDtos.TablesRequest;
import com.delivery.product.api.dto.StoreDtos.VerifiedLocalRequest;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreOffer;
import com.delivery.product.domain.StoreReview;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.CatalogService.ProductView;
import com.delivery.product.service.DeliveryZoneService;
import com.delivery.product.service.PopularServiceShops;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.ProductImageService.ImageUrl;
import com.delivery.product.service.ReviewService;
import com.delivery.product.service.StoreImageService;
import com.delivery.product.service.StoreService;
import com.delivery.product.service.StoreService.NearbyStoreView;
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
     * it gets the nearest 500 shops that match the search — the right subset to lose the rest from —
     * with {@code truncated} set, so that answer is never passed off as the whole radius.
     */
    static final int MAX_NEARBY_CANDIDATES = 500;

    /**
     * The widest "new on the platform" window the nearby search will apply: a year.
     *
     * <p>Past that "new" has stopped meaning anything, and a client asking for more is asking for
     * every shop, which a year's window already very nearly is.
     */
    static final int MAX_NEW_SINCE_DAYS = 365;

    private final StoreService storeService;
    private final CatalogService catalog;
    private final ProductImageService images;
    private final StoreImageService storeImages;
    private final ReviewService reviewService;
    private final PopularServiceShops popularServiceShops;

    /** For the areas a shop delivers to, which ride on the store as {@code deliveryZones}. */
    private final DeliveryZoneService deliveryZones;

    public StoreController(StoreService storeService, CatalogService catalog,
                           ProductImageService images, StoreImageService storeImages,
                           ReviewService reviewService, PopularServiceShops popularServiceShops,
                           DeliveryZoneService deliveryZones) {
        this.storeService = storeService;
        this.catalog = catalog;
        this.images = images;
        this.storeImages = storeImages;
        this.reviewService = reviewService;
        this.popularServiceShops = popularServiceShops;
        this.deliveryZones = deliveryZones;
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
            // No vertical is every goods vertical and no service shop: what Home and every installed
            // app ask for. SERVICES, or a serviceCategory on its own, lists service shops in the open
            // categories only. The rule lives in StoreService.ShopScope.
            @RequestParam(required = false) Store.Vertical vertical,
            @RequestParam(required = false) Store.ServiceCategory serviceCategory,
            @RequestParam(required = false) String search,
            @RequestParam(required = false) BigDecimal maxDeliveryFee,
            @RequestParam(required = false) Integer maxEtaMinutes,
            @RequestParam(required = false) BigDecimal minRating,
            @RequestParam(required = false) String neighborhood,
            @PageableDefault(size = 20, sort = "rating", direction = Sort.Direction.DESC)
            Pageable pageable) {

        Page<StoreView> page = storeService.storefront(vertical, serviceCategory, search,
                maxDeliveryFee, maxEtaMinutes, minRating, neighborhood, pageable);

        Set<UUID> starred = storeService.favoriteIdsOf(CurrentUser.id().orElse(null));
        Map<UUID, List<StoreOffer>> offersByStore = storeService.liveOffersByStore();

        return PageResponse.of(page.map(v -> toCard(v, starred, offersByStore)));
    }

    /**
     * The district chips for the hyperlocal browse — the distinct declared neighborhoods, of goods
     * shops only.
     */
    @GetMapping("/neighborhoods")
    public List<String> neighborhoods() {
        return storeService.neighborhoods();
    }

    /**
     * The service categories open right now, in taxonomy order: what a provider may file a shop
     * under, and what the Services tab may show. A closed category is in neither place.
     *
     * <p>Any signed-in caller, like the storefront it describes. The list is the same for everyone
     * and names no shop.
     */
    @GetMapping("/service-categories")
    @PreAuthorize("isAuthenticated()")
    public List<Store.ServiceCategory> serviceCategories() {
        return storeService.openServiceCategories();
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
     * @return the storefront's page shape plus {@code truncated}: true when more shops matched inside
     *         the radius than one search reads ({@link #MAX_NEARBY_CANDIDATES}), so the page and its
     *         total cover the nearest of them only. See {@link NearbyPageResponse}.
     */
    @GetMapping("/nearby")
    public NearbyPageResponse nearby(
            @RequestParam BigDecimal latitude,
            @RequestParam BigDecimal longitude,
            @RequestParam(defaultValue = "5000") int radiusMetres,
            // The neighbourhood browse's chips. Each is documented where it is applied — see
            // StoreService.NearbyFilters — because what a filter MEANS is a service rule, and the
            // one worth reading is powerStatus: what the lights are doing now, not what the shop
            // owns.
            @RequestParam(defaultValue = "false") boolean openNow,
            @RequestParam(required = false) Store.PowerStatus powerStatus,
            @RequestParam(required = false) String neighborhood,
            @RequestParam(required = false) Integer newSinceDays,
            @RequestParam(defaultValue = "false") boolean verifiedLocal,
            // As on the storefront: no vertical is every goods shop and no service shop; SERVICES
            // or a serviceCategory is service shops in open categories. See StoreService.ShopScope.
            @RequestParam(required = false) Store.Vertical vertical,
            @RequestParam(required = false) Store.ServiceCategory serviceCategory,
            @PageableDefault(size = 20) Pageable pageable) {

        // Built here rather than passed on as two loose numbers, so an out-of-range or (0, 0)
        // coordinate is refused before it reaches the database — with the same message a merchant
        // saving a pin would get.
        GeoPoint centre = new GeoPoint(latitude, longitude);

        int radius = Math.min(Math.max(radiusMetres, MIN_NEARBY_RADIUS_METRES),
                MAX_NEARBY_RADIUS_METRES);

        StoreService.NearbyFilters filters = new StoreService.NearbyFilters(
                openNow,
                powerStatus,
                neighborhood,
                // Clamped like the radius, and for the same reason: zero or a negative number of
                // days is a client bug with no sensible answer, and ten thousand days is a client
                // asking for "every shop", which the widest window genuinely answers.
                newSinceDays == null ? null
                        : Math.min(Math.max(newSinceDays, 1), MAX_NEW_SINCE_DAYS),
                verifiedLocal,
                vertical,
                serviceCategory);

        StoreService.NearbyResult result =
                storeService.nearby(centre, radius, MAX_NEARBY_CANDIDATES, filters, pageable);

        Set<UUID> starred = storeService.favoriteIdsOf(CurrentUser.id().orElse(null));
        Map<UUID, List<StoreOffer>> offersByStore = storeService.liveOffersByStore();

        return NearbyPageResponse.of(result.page().map(near -> new NearbyStoreResponse(
                        toCard(near.store(), starred, offersByStore),
                        near.store().store().getLatitude(),
                        near.store().store().getLongitude(),
                        // Whole metres. The pin this is measured from was dropped by hand on a map,
                        // so a decimal place would be precision the number does not have.
                        Math.round(near.distanceMetres()))),
                result.truncated(), MAX_NEARBY_CANDIDATES);
    }

    /**
     * The Services tab's "Popular near you" row: service shops near a point, ranked by the orders they
     * delivered in the last 30 days, most first ({@link PopularServiceShops}).
     *
     * <p>The answer is the cards in rank order, each with its pin and distance exactly as
     * {@link #nearby} draws them, and nothing more: no count, and no bucket standing in for one. The
     * counts rank the row on the server and stop there, because a competitor's order volume is not a
     * customer's to read. An empty list means no shop nearby has enough delivered orders yet, and the
     * app shows "Services near you" instead ({@code /nearby?vertical=SERVICES}).
     *
     * <p>The radius, the window and the floor are the server's settings
     * ({@code delivery.catalog.services.popular-*}), not parameters: a client that could widen the
     * circle could turn "near you" back into a nationwide ranking.
     *
     * <p>Any signed-in caller, like {@link #nearby} and for its reason: a point is where somebody is
     * standing, so no signed-out caller gets a proximity oracle, while a customer, a provider and back
     * office all read the same public cards. A literal path, never taken for {@code /{idOrSlug}}.
     *
     * @param serviceCategory one open category, or none for every open one; a closed one answers empty
     * @param limit           the most cards wanted, held to {@code PopularServiceShops.MAX_SHOPS}
     */
    @GetMapping("/services/popular")
    @PreAuthorize("isAuthenticated()")
    public List<NearbyStoreResponse> popularServices(
            @RequestParam BigDecimal latitude,
            @RequestParam BigDecimal longitude,
            @RequestParam(required = false) Store.ServiceCategory serviceCategory,
            @RequestParam(defaultValue = "10") int limit) {

        // Refused before the database, with the message "near me" gives: see nearby.
        GeoPoint centre = new GeoPoint(latitude, longitude);
        List<NearbyStoreView> popular = popularServiceShops.near(centre, serviceCategory, limit);
        if (popular.isEmpty()) {
            return List.of();
        }

        Set<UUID> starred = storeService.favoriteIdsOf(CurrentUser.id().orElse(null));
        Map<UUID, List<StoreOffer>> offersByStore = storeService.liveOffersByStore();

        return popular.stream()
                .map(near -> new NearbyStoreResponse(
                        toCard(near.store(), starred, offersByStore),
                        near.store().store().getLatitude(),
                        near.store().store().getLongitude(),
                        Math.round(near.distanceMetres())))
                .toList();
    }

    /**
     * The starred row at the top of the home screen: goods shops only.
     *
     * <p>Paged like everything else. A customer who has starred two hundred shops should not send
     * two hundred cards down the wire to fill a rail that shows four.
     *
     * <p>A starred service shop is kept but not listed here. This is Home, where service shops never
     * appear, and every installed app would draw one as a restaurant; see
     * {@code StoreRepository#findFavoritesOfWithStatus}. No Services screen draws favourites yet, so
     * there is no services read of them. One would take a vertical and a category exactly as
     * {@link #browse} does, and be scoped by {@code StoreService.ShopScope} to open categories.
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

    /**
     * The Merchant Portal's list of its own stores, in any status.
     *
     * <p>Without the areas each shop delivers to ({@code deliveryZones} is null, "not read"): they
     * cost one or two queries a store, and nothing that reads this list draws them. The customer's
     * shop page reads its store by id ({@link #read}), which carries them.
     */
    @GetMapping("/mine")
    @PreAuthorize("hasRole('MERCHANT')")
    public PageResponse<StoreResponse> mine(@PageableDefault(size = 20) Pageable pageable) {
        String merchantId = CurrentUser.requireId();
        Set<UUID> starred = storeService.favoriteIdsOf(merchantId);
        return PageResponse.of(storeService.ownedByView(merchantId, pageable)
                .map(v -> toResponse(v, starred, false)));
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

    /**
     * A store's shelf.
     *
     * <p>Read as the caller: a service shop that is a draft, suspended or in a closed category shows
     * its shelf to its provider only, and anybody else is told the shop is not found
     * ({@link CatalogService#browseStore}). A goods shop's shelf is served as it always was.
     */
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

        String viewerId = CurrentUser.id().orElse(null);
        Page<Product> page = ids == null || ids.isEmpty()
                ? catalog.browseStore(id, viewerId, categoryId, search, pageable)
                : catalog.browseStoreByIds(id, viewerId, ids, pageable);
        return PageResponse.of(catalog.views(page).map(this::toProduct));
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

    /**
     * Opens a shop for the calling merchant.
     *
     * <p>201 with the new shop. 200 with the merchant's existing services shop when they ask for a
     * SERVICES shop and already have one: the provider app opens that shop on its first entry after
     * approval, and a retry or a second phone has to land on the same shop rather than open another.
     * See {@link StoreService#open}.
     */
    @PostMapping
    @PreAuthorize("hasRole('MERCHANT')")
    public ResponseEntity<StoreResponse> create(@Valid @RequestBody StoreRequest request) {
        StoreService.Opened opened = storeService.open(CurrentUser.requireId(), request);
        return ResponseEntity.status(opened.created() ? HttpStatus.CREATED : HttpStatus.OK)
                .body(toResponse(opened.view(), Set.of()));
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
     *
     * <p>BACKOFFICE may also pin, on any shop, and that is a separate road through the same door
     * ({@link StoreService#pinAsBackoffice}, which records who did it). It is here for the shops
     * that went live before a pin was required: their merchant is otherwise the only person who can
     * put them on the map, and support cannot repair a trading shop that no "near you" can find.
     * Checked before ownership, so an account holding both roles is treated as the more privileged
     * one rather than being refused another merchant's shop.
     */
    @PutMapping("/{id}/location")
    @PreAuthorize("hasAnyRole('MERCHANT','BACKOFFICE')")
    public StoreResponse setLocation(@PathVariable UUID id,
                                     @Valid @RequestBody LocationRequest request) {
        GeoPoint location = new GeoPoint(request.latitude(), request.longitude());
        String caller = CurrentUser.requireId();
        return toResponse(CurrentUser.hasRole("BACKOFFICE")
                        ? storeService.pinAsBackoffice(id, caller, location)
                        : storeService.pin(id, caller, location),
                Set.of());
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
    // @Valid on the element rather than on the list, so what is cascaded into is stated rather than
    // inferred from the parameter's type. The 500 this endpoint used to answer for day 0 was never
    // the constraints failing to run — they ran, and the refusal they raise had no mapping in
    // ApiExceptionHandler, so it reached the catch-all. Both halves are fixed; this is the half
    // that says what the endpoint means.
    public List<HoursResponse> setHours(@PathVariable UUID id,
                                        @RequestBody List<@Valid HoursRequest> windows) {
        return storeService.replaceHours(id, CurrentUser.requireId(), windows).store().getHours().stream()
                .map(h -> new HoursResponse(h.getDay().getValue(), h.getOpensAt(), h.getClosesAt()))
                .toList();
    }

    /**
     * How many tables this shop seats, and whether it takes orders at them.
     *
     * <p>{@code PUT} with the whole number rather than a nudge, because the stepper on the share
     * screen is a number the merchant sets: two devices that both nudged would each apply their own
     * delta and the shop would end up with tables nobody has.
     *
     * <p>One call for both because they are one decision on one screen — "we seat twelve, and yes,
     * take orders there" — and because the two constrain each other: taking the tables to zero
     * turns ordering off with them. {@code ordering} omitted leaves the switch alone, so a client
     * that only knows about the count cannot quietly stop a restaurant trading.
     */
    @PutMapping("/{id}/tables")
    @PreAuthorize("hasRole('MERCHANT')")
    public StoreResponse setTables(@PathVariable UUID id, @Valid @RequestBody TablesRequest request) {
        return toResponse(
                storeService.setTables(id, CurrentUser.requireId(), request.tables(),
                        request.ordering()),
                Set.of());
    }

    /** The merchant draws (or clears) their delivery circle. */
    @PostMapping("/{id}/delivery-radius")
    @PreAuthorize("hasRole('MERCHANT')")
    public StoreResponse setDeliveryRadius(@PathVariable UUID id,
                                           @Valid @RequestBody RadiusRequest request) {
        return toResponse(storeService.setDeliveryRadius(
                id, CurrentUser.requireId(), request.metres()), Set.of());
    }

    /**
     * Whether this shop's circle covers a point — what checkout asks before promising a
     * delivery the shop never offered. Any authenticated caller: the answer is as public as the
     * storefront card that carries the radius.
     */
    @GetMapping("/{id}/can-deliver")
    public Map<String, Object> canDeliver(@PathVariable UUID id,
                                          @RequestParam BigDecimal latitude,
                                          @RequestParam BigDecimal longitude) {
        // BigDecimal rather than double so the pair goes through GeoPoint's rules in the service,
        // exactly as /nearby's does. As two loose doubles an impossible coordinate was answered
        // rather than refused.
        return Map.of("canDeliver", storeService.deliversTo(id, latitude, longitude));
    }

    /**
     * Backoffice grants or withdraws the dekkane "Trusted Local" badge.
     *
     * <p>BACKOFFICE and nobody else — not even the shop's own merchant, and that is the point of the
     * badge: it is a claim the platform makes to the shop's neighbours, and one the shop could award
     * itself would certify nothing. V23 made the column deliberately not merchant-writable and this
     * is the only road to it; it is not on {@link #update}'s form, so no profile save can touch it.
     *
     * <p>Any store, in any status. Vetting a shop before it is listed is exactly when Backoffice
     * would do it, and granting a badge to a draft shows it to nobody until the shop publishes.
     */
    @PutMapping("/{id}/verified-local")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public StoreResponse setVerifiedLocal(@PathVariable UUID id,
                                          @Valid @RequestBody VerifiedLocalRequest request) {
        return toResponse(storeService.setVerifiedLocal(
                id, CurrentUser.requireId(), request.verified()), Set.of());
    }

    /** The merchant declares what the lights are doing — the power chip's one source of truth. */
    @PostMapping("/{id}/power")
    @PreAuthorize("hasRole('MERCHANT')")
    public StoreResponse declarePower(@PathVariable UUID id,
                                      @Valid @RequestBody PowerRequest request) {
        return toResponse(storeService.declarePower(
                id, CurrentUser.requireId(), request.status(), request.note()), Set.of());
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

    /** A shop's card, as every list draws it ({@link StoreCards}). */
    private StoreCardResponse toCard(StoreView v, Set<UUID> starred,
                                     Map<UUID, List<StoreOffer>> offersByStore) {
        return StoreCards.of(v, starred, offersByStore, images);
    }

    /** A whole store, with the areas it delivers to. */
    private StoreResponse toResponse(StoreView v, Set<UUID> starred) {
        return toResponse(v, starred, true);
    }

    /**
     * @param withAreas whether to read the areas the shop delivers to ({@link #servedZonesOf}, one
     *                  or two queries). False leaves {@code deliveryZones} null, which a client
     *                  reads as "not said", never as "no areas": for a list nothing draws them from.
     */
    private StoreResponse toResponse(StoreView v, Set<UUID> starred, boolean withAreas) {
        Store store = v.store();
        ImageUrl logo = images.resolveImage(store.getLogoRef());
        ImageUrl cover = images.resolveImage(store.getCoverRef());
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
                ImageUrl.fullOf(logo),
                ImageUrl.fullOf(cover),
                ImageUrl.thumbOf(logo),
                ImageUrl.thumbOf(cover),
                store.getAddress(),
                store.getLatitude(),
                store.getLongitude(),
                starred.contains(store.getId()),
                storeService.liveOffersFor(store.getId()).stream()
                        .map(StoreController::toOffer).toList(),
                store.getStatus(),
                store.getCreatedAt(),
                store.getNeighborhood(),
                store.isVerifiedLocal(),
                store.getPowerStatus(),
                store.getPowerNote(),
                store.getPowerUpdatedAt(),
                v.powerCurrent(),
                store.getDeliveryRadiusMetres(),
                withAreas ? servedZonesOf(store) : null,
                store.getServiceCategory(),
                store.getTableCount(),
                store.isTableOrdering());
    }

    /**
     * Where a shop delivers by area, for its shop page's map, in the area picker's own shape: on
     * the full store only, never on a card, so the storefront grid costs no query per shop for it.
     */
    private List<ZoneResponse> servedZonesOf(Store store) {
        return deliveryZones.servedAreasOf(store.getId()).stream().map(ZoneResponse::of).toList();
    }

    private static OfferResponse toOffer(StoreOffer offer) {
        return StoreCards.offer(offer);
    }

    /**
     * The shop page's product list, the screen the list-sized derivative exists for, and a service
     * shop's offer cards with their terms and "From" price. Mapped where every product endpoint maps.
     */
    private ProductResponse toProduct(ProductView view) {
        return ProductResponses.of(view, images);
    }
}
