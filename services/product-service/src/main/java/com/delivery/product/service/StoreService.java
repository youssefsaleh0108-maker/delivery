package com.delivery.product.service;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.product.api.dto.StoreDtos.CommercialsRequest;
import com.delivery.product.api.dto.StoreDtos.HoursRequest;
import com.delivery.product.api.dto.StoreDtos.OfferRequest;
import com.delivery.product.api.dto.StoreDtos.StoreRequest;
import com.delivery.product.domain.Category;
import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreFavorite;
import com.delivery.product.domain.StoreFavoriteRepository;
import com.delivery.product.domain.StoreHours;
import com.delivery.product.domain.StoreOffer;
import com.delivery.product.domain.StoreOfferRepository;
import com.delivery.product.domain.StoreRepository;

/**
 * Storefront reads and store administration.
 *
 * <p>Follows {@link CatalogService}'s convention: the caller's id is an explicit parameter on every
 * method that needs it, never read from ambient security context, so the ownership rules are
 * visible in the signature and testable without a mocked context.
 */
@Service
public class StoreService {

    private static final Logger log = LoggerFactory.getLogger(StoreService.class);

    private final StoreRepository stores;
    private final StoreOfferRepository offers;
    private final StoreFavoriteRepository favorites;
    private final ProductRepository products;
    private final CategoryRepository categories;
    private final Clock clock;

    public StoreService(StoreRepository stores, StoreOfferRepository offers,
                        StoreFavoriteRepository favorites, ProductRepository products,
                        CategoryRepository categories, Clock clock) {
        this.stores = stores;
        this.offers = offers;
        this.favorites = favorites;
        this.products = products;
        this.categories = categories;
        this.clock = clock;
    }

    // ---------------------------------------------------------------- storefront reads

    /**
     * A store with its time-dependent answers already worked out.
     *
     * <p>This type exists because of one hard-won bug. Availability is derived by walking
     * {@code Store.hours}, which is lazy — so computing it in the controller, after the
     * transaction has closed, throws {@code LazyInitializationException}. Returning a view means
     * the walk happens inside the session (where {@code @BatchSize} makes it one extra query for
     * the whole page) and no lazy state ever escapes this service.
     */
    public record StoreView(Store store, Store.Availability availability,
                            java.time.LocalTime closesAt) {
    }

    private StoreView view(Store store, Instant now) {
        return new StoreView(store, store.availabilityAt(now), store.closingTimeAt(now));
    }

    @Transactional(readOnly = true)
    public Page<StoreView> storefront(Store.Vertical vertical, String search,
                                      BigDecimal maxDeliveryFee, Integer maxEtaMinutes,
                                      BigDecimal minRating, Pageable pageable) {
        Instant now = clock.instant();
        return stores.findStorefront(vertical, SearchPatterns.like(search), maxDeliveryFee,
                maxEtaMinutes, minRating, pageable).map(s -> view(s, now));
    }

    @Transactional(readOnly = true)
    public Page<StoreView> favoritesOf(String userId, Pageable pageable) {
        Instant now = clock.instant();
        return stores.findFavoritesOf(userId, pageable).map(s -> view(s, now));
    }

    // ---------------------------------------------------------------- near me

    /**
     * A store, how far away it is, and the time-dependent answers already worked out.
     *
     * <p>Extends {@link StoreView}'s reason for existing with one more field. The distance belongs
     * on the view rather than being recomputed by the controller, so the number that orders the list
     * and the number printed on the card are the same number and cannot drift apart.
     */
    public record NearbyStoreView(StoreView store, double distanceMetres) {
    }

    /**
     * How much further than the requested radius the database is asked to look.
     *
     * <p>The database filters on the spheroid ({@code ST_DWithin}) and this service measures on a
     * sphere (haversine); they differ by about 0.3%. Without the slack a shop sitting within the
     * radius by haversine but a few metres outside it by the spheroid would be discarded before
     * Java ever saw it — a shop missing from a "near me" list for a reason no one could observe. One
     * percent comfortably covers the disagreement; the Java filter below is what actually decides.
     */
    private static final double RADIUS_SLACK = 1.01d;

    /**
     * Live stores near a point, nearest first.
     *
     * <p>The split of work between database and service is argued in
     * {@link StoreRepository#findActiveIdsNear}: PostGIS narrows and caps using the GiST index, and
     * this method computes the distance, filters to the radius the caller actually asked for, orders
     * and pages. The short version is that the number a customer is shown should come from code the
     * build can test, and the candidate set is small enough that where it is sorted does not matter.
     *
     * <p>Stores with no pin never appear. That is the behaviour V18's flat-fee shops need: a
     * merchant who has not placed themselves on a map keeps trading exactly as before and is simply
     * absent from this one rail, rather than being given a default position.
     *
     * @param maxCandidates the ceiling on rows read from the database, so a very large radius in a
     *                      dense city cannot pull the whole table into memory. A caller who hits it
     *                      gets the nearest {@code maxCandidates} shops, which is the right subset
     *                      to lose the rest from.
     */
    @Transactional(readOnly = true)
    public Page<NearbyStoreView> nearby(GeoPoint centre, double radiusMetres, int maxCandidates,
                                        Pageable pageable) {
        List<UUID> candidateIds = stores.findActiveIdsNear(
                centre.latitude().doubleValue(),
                centre.longitude().doubleValue(),
                radiusMetres * RADIUS_SLACK,
                maxCandidates);

        if (candidateIds.isEmpty()) {
            return pageOf(List.of(), pageable);
        }

        Instant now = clock.instant();
        List<NearbyStoreView> near = new ArrayList<>(candidateIds.size());

        for (Store store : stores.findAllById(candidateIds)) {
            GeoPoint location = store.location();
            if (location == null) {
                // Only reachable if the pin were cleared between the two queries. Skipped rather
                // than defaulted: a store with no location has no distance, and inventing one would
                // put it somewhere in the list on the strength of a made-up number.
                continue;
            }
            double metres = centre.distanceMetresTo(location);
            if (metres <= radiusMetres) {
                near.add(new NearbyStoreView(view(store, now), metres));
            }
        }

        // The database's ordering is discarded here, deliberately — findAllById does not preserve
        // it anyway, and this is the ordering that ships. Ties break on the store id so a refresh
        // does not reshuffle two shops in the same building.
        near.sort(Comparator.comparingDouble(NearbyStoreView::distanceMetres)
                .thenComparing(n -> n.store().store().getId()));

        return pageOf(near, pageable);
    }

    /** The opening hours themselves, materialised inside the transaction for the same reason. */
    @Transactional(readOnly = true)
    public List<StoreHours> hoursOf(UUID storeId, String viewerId) {
        Store store = read(storeId.toString(), viewerId);
        return List.copyOf(store.getHours());
    }

    /**
     * Reads one store by id or slug.
     *
     * <p>Accepts both because a share link carries a slug while the app holds an id, and forcing the
     * client to know which it has just moves the branch somewhere less careful.
     */
    @Transactional(readOnly = true)
    public Store read(String idOrSlug, String viewerId) {
        Store store = resolve(idOrSlug);
        if (store.getStatus() != Store.Status.ACTIVE && !store.isOwnedBy(viewerId)) {
            // 404 rather than 403, matching CatalogService: a 403 would confirm the store exists.
            throw new StoreNotFoundException(idOrSlug);
        }
        return store;
    }

    /** The rendering form. Prefer this from a controller — see {@link StoreView}. */
    @Transactional(readOnly = true)
    public StoreView readView(String idOrSlug, String viewerId) {
        return view(read(idOrSlug, viewerId), clock.instant());
    }

    private Store resolve(String idOrSlug) {
        Optional<Store> bySlug = stores.findBySlug(idOrSlug);
        if (bySlug.isPresent()) {
            return bySlug.get();
        }
        try {
            return stores.findById(UUID.fromString(idOrSlug))
                    .orElseThrow(() -> new StoreNotFoundException(idOrSlug));
        } catch (IllegalArgumentException notAUuid) {
            throw new StoreNotFoundException(idOrSlug);
        }
    }

    /**
     * Which of these stores the customer has starred.
     *
     * <p>Returned as a set for the caller to apply while mapping, so rendering a page of cards costs
     * one query rather than one per card.
     */
    @Transactional(readOnly = true)
    public Set<UUID> favoriteIdsOf(String userId) {
        if (userId == null) {
            return Set.of();
        }
        return new HashSet<>(favorites.findStoreIdsByUserId(userId));
    }

    /** Live offers for one store, including the platform-wide ones. */
    @Transactional(readOnly = true)
    public List<StoreOffer> liveOffersFor(UUID storeId) {
        Instant now = clock.instant();
        return offers.findLiveFor(storeId).stream()
                .filter(o -> o.isLiveAt(now))
                .toList();
    }

    /**
     * Paged form of {@link #liveOffersFor}.
     *
     * <p>The live-window filter runs in Java (see {@link StoreOffer#isLiveAt}), so the page is cut
     * after filtering rather than by the database. Correct, and fine at this size — an offer list
     * is tens of rows, not thousands. If it ever were, the window predicate would have to move into
     * the query.
     */
    @Transactional(readOnly = true)
    public Page<StoreOffer> liveOffersFor(UUID storeId, Pageable pageable) {
        return pageOf(liveOffersFor(storeId), pageable);
    }

    /**
     * Live offers for many stores at once, grouped by store id.
     *
     * <p>The storefront needs a promotion ribbon per card. One query grouped in memory, rather than
     * {@link #liveOffersFor} in a loop, which is the same N+1 {@code @BatchSize} avoids for hours.
     * Platform-wide offers are excluded: a promotion that applies everywhere is not a reason to
     * badge one card.
     */
    @Transactional(readOnly = true)
    public Map<UUID, List<StoreOffer>> liveOffersByStore() {
        Instant now = clock.instant();
        return offers.findAllLive().stream()
                .filter(o -> o.getStoreId() != null && o.isLiveAt(now))
                .collect(Collectors.groupingBy(StoreOffer::getStoreId));
    }

    @Transactional(readOnly = true)
    public Page<StoreOffer> platformOffers(Pageable pageable) {
        return pageOf(platformOffers(), pageable);
    }

    /** Cuts an already-filtered list into the requested page. */
    private static <T> Page<T> pageOf(List<T> all, Pageable pageable) {
        int from = (int) Math.min(pageable.getOffset(), all.size());
        int to = Math.min(from + pageable.getPageSize(), all.size());
        return new org.springframework.data.domain.PageImpl<>(
                all.subList(from, to), pageable, all.size());
    }

    @Transactional(readOnly = true)
    public List<StoreOffer> platformOffers() {
        Instant now = clock.instant();
        return offers.findAllLive().stream()
                .filter(o -> o.getStoreId() == null && o.isLiveAt(now))
                .toList();
    }

    /**
     * The aisles a store actually stocks.
     *
     * <p>Derived from the catalog, not from the category tree: the taxonomy is platform-wide but no
     * one shop carries all of it, and an aisle that opens onto nothing is worse than no aisle.
     */
    @Transactional(readOnly = true)
    public List<Aisle> aislesOf(UUID storeId) {
        List<Object[]> counts = products.countActiveByCategoryInStore(storeId);
        if (counts.isEmpty()) {
            return List.of();
        }

        Map<UUID, String> names = categories.findAll().stream()
                .collect(Collectors.toMap(Category::getId, Category::getName));

        List<Aisle> aisles = new ArrayList<>(counts.size());
        for (Object[] row : counts) {
            UUID categoryId = (UUID) row[0];
            long count = ((Number) row[1]).longValue();
            // A category that has since been renamed away is skipped rather than rendered as null.
            String name = names.get(categoryId);
            if (name != null) {
                aisles.add(new Aisle(categoryId, name, count));
            }
        }
        aisles.sort(Comparator.comparing(Aisle::name));
        return aisles;
    }

    public record Aisle(UUID categoryId, String name, long productCount) {
    }

    // ---------------------------------------------------------------- favourites

    /**
     * Stars a store. Idempotent by construction.
     *
     * <p>The composite primary key means a repeat save is an update of a row that already exists,
     * so there is no check-then-insert window for two taps to race through.
     */
    @Transactional
    public void star(String userId, UUID storeId) {
        if (!stores.existsById(storeId)) {
            throw new StoreNotFoundException(storeId.toString());
        }
        favorites.save(new StoreFavorite(userId, storeId));
    }

    /** Unstars a store. Also idempotent: removing something absent is success, not an error. */
    @Transactional
    public void unstar(String userId, UUID storeId) {
        favorites.deleteById(new StoreFavorite.Id(userId, storeId));
    }

    // ---------------------------------------------------------------- administration

    /**
     * Default hours for an auto-provisioned store: always open, until its owner says otherwise.
     *
     * <p>A narrower guess looks more realistic and is worse. We do not know when this shop trades,
     * and any window we invent silently refuses orders outside it — a merchant who adds a product
     * at 07:00 would find it unsellable for two hours with nothing on screen explaining why.
     * Always-open is the honest default: it withholds nothing, and the merchant sets real hours on
     * the My Shop page.
     */
    private static final java.time.LocalTime DEFAULT_OPENS = java.time.LocalTime.MIDNIGHT;
    private static final java.time.LocalTime DEFAULT_CLOSES = java.time.LocalTime.of(23, 59, 59);

    /**
     * The store a merchant's products belong to, created on first use.
     *
     * <p>Auto-provisioning keeps {@code products.store_id} non-null without making "create your
     * store" a step a merchant can skip and then hit a constraint violation on.
     *
     * <p>The generated store is <strong>listed and open</strong>, with a default week of hours. It
     * used to start DRAFT, on the reasoning that a half-configured shop should not appear on the
     * storefront — but that made a new merchant's very first product unsellable: a DRAFT store is
     * invisible to customers, so Order Manager's store lookup 404s and the order is refused. A
     * merchant adding a product is telling us they want to sell it, and an empty shopfront is a
     * smaller problem than an unsellable one.
     */
    @Transactional
    public Store requireStoreFor(String merchantId) {
        List<Store> owned = stores.findByMerchantIdOrderByCreatedAtDesc(merchantId);
        if (!owned.isEmpty()) {
            return owned.get(0);
        }
        Store store = new Store(merchantId, "My Store", Store.Vertical.RESTAURANT);
        store.replaceHours(java.util.Arrays.stream(DayOfWeek.values())
                .map(day -> new StoreHours(day, DEFAULT_OPENS, DEFAULT_CLOSES))
                .toList());
        store.publish();
        stores.save(store);
        log.info("Auto-provisioned store {} for merchant {}", store.getId(), merchantId);
        return store;
    }

    @Transactional(readOnly = true)
    public Page<StoreView> ownedByView(String merchantId, Pageable pageable) {
        Instant now = clock.instant();
        return stores.findByMerchantIdOrderByCreatedAtDesc(merchantId, pageable)
                .map(s -> view(s, now));
    }

    /** Entities, for the ownership check in {@link CatalogService}. Not for rendering. */
    @Transactional(readOnly = true)
    public List<Store> ownedBy(String merchantId) {
        return stores.findByMerchantIdOrderByCreatedAtDesc(merchantId);
    }

    @Transactional
    public StoreView create(String merchantId, StoreRequest request) {
        Store store = new Store(merchantId, request.name(), request.vertical());
        store.updateProfile(request.name(), request.tagline(), request.description(),
                request.vertical(), request.tags(), request.timezone(), request.address());
        return view(stores.save(store), clock.instant());
    }

    @Transactional
    public StoreView update(UUID id, String merchantId, StoreRequest request) {
        Store store = requireOwned(id, merchantId);
        store.updateProfile(request.name(), request.tagline(), request.description(),
                request.vertical(), request.tags(), request.timezone(), request.address());
        return view(store, clock.instant());
    }

    /**
     * Moves the shop's pin.
     *
     * <p>Its own operation rather than a field on {@link #update}, for the reason set out on
     * {@link Store#pinAt}: the profile form is saved whenever a merchant edits their tagline, and a
     * nullable coordinate pair on that request would clear the pin every time a client that predates
     * the field saved anything. Placing a shop on a map is a decision, and it gets its own call.
     *
     * <p>The coordinate has already been through {@link GeoPoint}'s rules by the time it arrives
     * here, and the {@code stores} CHECK constraints added in V20 stand behind those.
     */
    @Transactional
    public StoreView pin(UUID id, String merchantId, GeoPoint location) {
        Store store = requireOwned(id, merchantId);
        store.pinAt(location);
        return view(store, clock.instant());
    }

    /**
     * Takes the shop off the map.
     *
     * <p>The address text is kept. A merchant removing a wrong pin has not stopped having an
     * address, and clearing both would quietly delete the only thing a rider has to go on.
     */
    @Transactional
    public StoreView unpin(UUID id, String merchantId) {
        Store store = requireOwned(id, merchantId);
        store.clearPin();
        return view(store, clock.instant());
    }

    @Transactional
    public StoreView updateCommercials(UUID id, String merchantId, CommercialsRequest request) {
        Store store = requireOwned(id, merchantId);
        try {
            store.updateCommercials(request.deliveryFee(), request.minOrder(),
                    request.etaMinMinutes(), request.etaMaxMinutes());
        } catch (IllegalArgumentException e) {
            throw new CatalogService.CatalogRuleViolationException(e.getMessage());
        }
        return view(store, clock.instant());
    }

    @Transactional
    public StoreView replaceHours(UUID id, String merchantId, List<HoursRequest> windows) {
        Store store = requireOwned(id, merchantId);
        List<StoreHours> replacement = new ArrayList<>(windows.size());
        for (HoursRequest window : windows) {
            try {
                replacement.add(new StoreHours(DayOfWeek.of(window.dayOfWeek()),
                        window.opensAt(), window.closesAt()));
            } catch (IllegalArgumentException e) {
                throw new CatalogService.CatalogRuleViolationException(e.getMessage());
            }
        }
        store.replaceHours(replacement);
        return view(store, clock.instant());
    }

    @Transactional
    public StoreView publish(UUID id, String merchantId) {
        Store store = requireOwned(id, merchantId);
        try {
            store.publish();
        } catch (IllegalStateException e) {
            throw new CatalogService.CatalogRuleViolationException(e.getMessage());
        }
        return view(store, clock.instant());
    }

    @Transactional
    public StoreView suspend(UUID id, String merchantId) {
        Store store = requireOwned(id, merchantId);
        store.suspend();
        return view(store, clock.instant());
    }

    @Transactional
    public StoreView setBusy(UUID id, String merchantId, int minutes) {
        Store store = requireOwned(id, merchantId);
        store.markBusyUntil(clock.instant().plus(Duration.ofMinutes(minutes)));
        return view(store, clock.instant());
    }

    @Transactional
    public StoreView clearBusy(UUID id, String merchantId) {
        Store store = requireOwned(id, merchantId);
        store.clearBusy();
        return view(store, clock.instant());
    }

    @Transactional
    public StoreOffer addOffer(UUID storeId, String merchantId, OfferRequest request) {
        requireOwned(storeId, merchantId);
        validateOffer(request);
        return offers.save(new StoreOffer(storeId, request.kind(), request.title(),
                request.subtitle(), request.value(), request.minSubtotal()));
    }

    @Transactional
    public void withdrawOffer(UUID storeId, UUID offerId, String merchantId) {
        requireOwned(storeId, merchantId);
        offers.findById(offerId)
                .filter(o -> storeId.equals(o.getStoreId()))
                .ifPresent(StoreOffer::withdraw);
    }

    /**
     * Mirrors the CHECK constraints in V11 so a bad offer fails as a 400 with a readable message
     * rather than a 500 carrying a constraint name.
     */
    private void validateOffer(OfferRequest request) {
        switch (request.kind()) {
            case PERCENT_OFF -> {
                if (request.value() == null
                        || request.value().compareTo(BigDecimal.ZERO) <= 0
                        || request.value().compareTo(BigDecimal.valueOf(100)) > 0) {
                    throw new CatalogService.CatalogRuleViolationException(
                            "A percentage offer needs a value between 0 and 100");
                }
            }
            case AMOUNT_OFF -> {
                if (request.value() == null || request.value().compareTo(BigDecimal.ZERO) <= 0) {
                    throw new CatalogService.CatalogRuleViolationException(
                            "An amount offer needs a value greater than zero");
                }
            }
            case FREE_DELIVERY -> {
                // No value to validate; the discount is the store's delivery fee.
            }
        }
    }

    // ---------------------------------------------------------------- internals

    /** The one place the store ownership rule is applied to a write. Mirrors CatalogService. */
    private Store requireOwned(UUID id, String merchantId) {
        return stores.findByIdAndMerchantId(id, merchantId)
                .orElseThrow(() -> {
                    if (stores.existsById(id)) {
                        log.warn("Merchant {} attempted to modify store {} they do not own",
                                merchantId, id);
                    }
                    return new StoreNotFoundException(id.toString());
                });
    }

    public static class StoreNotFoundException extends RuntimeException {
        public StoreNotFoundException(String idOrSlug) {
            super("Store " + idOrSlug + " was not found");
        }
    }
}
