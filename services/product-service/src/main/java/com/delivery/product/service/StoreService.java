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
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
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

    /**
     * How long a merchant's power declaration counts as what the lights are doing NOW —
     * {@code delivery.product.power-declaration-fresh-for}, four hours unless configured.
     *
     * <p>A declaration is a statement about a moment, and nothing expires it by itself. Mains
     * rationing and generator switch-overs can change a shop's power several times a day, so
     * without a window "Generator active" drawn this evening could be this morning's news, and the
     * "on generator now" filter would answer with it. Four hours keeps a declaration made at opening
     * from being claimed at dinner, while a merchant who updates as the power changes is always
     * shown. Past the window nothing is deleted: the declaration is still stored and still shown to
     * its merchant — customers are just no longer told it is happening now.
     */
    private final Duration powerDeclarationFreshFor;

    /**
     * Which service categories are open. Consulted only by reads and writes about service shops, so a
     * mistake in that setting cannot reach a goods read.
     */
    private final ServiceCategories serviceCategories;

    /**
     * Asked whether a merchant with no shop at all applied to offer services, so that
     * {@link #requireStoreFor} never opens a restaurant for a print shop. Nothing else asks it.
     */
    private final OnboardingApplicationClient applications;

    public StoreService(StoreRepository stores, StoreOfferRepository offers,
                        StoreFavoriteRepository favorites, ProductRepository products,
                        CategoryRepository categories, ServiceCategories serviceCategories,
                        OnboardingApplicationClient applications,
                        Clock clock,
                        @Value("${delivery.product.power-declaration-fresh-for:4h}")
                        Duration powerDeclarationFreshFor) {
        this.stores = stores;
        this.offers = offers;
        this.favorites = favorites;
        this.products = products;
        this.categories = categories;
        this.serviceCategories = serviceCategories;
        this.applications = applications;
        this.clock = clock;
        this.powerDeclarationFreshFor = powerDeclarationFreshFor;
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
     *
     * <p>{@code powerCurrent} is here for the view's other reason to exist: it depends on the clock.
     * It says whether the merchant's power declaration is recent enough to be presented as what the
     * lights are doing now ({@link #powerDeclarationFreshFor}). A client draws "Generator active" or
     * dims a dark shop only when it is true, and the nearby search's power filter matches only such
     * declarations — so a card and the filter cannot disagree about the same shop.
     */
    public record StoreView(Store store, Store.Availability availability,
                            java.time.LocalTime closesAt, boolean powerCurrent) {
    }

    private StoreView view(Store store, Instant now) {
        return new StoreView(store, store.availabilityAt(now), store.closingTimeAt(now),
                store.powerDeclaredSince(powerDeclaredSince(now)));
    }

    /** The oldest declaration still presented as now. See {@link #powerDeclarationFreshFor}. */
    private Instant powerDeclaredSince(Instant now) {
        return now.minus(powerDeclarationFreshFor);
    }

    /** The storefront for a read that names no service category. See the overload below. */
    @Transactional(readOnly = true)
    public Page<StoreView> storefront(Store.Vertical vertical, String search,
                                      BigDecimal maxDeliveryFee, Integer maxEtaMinutes,
                                      BigDecimal minRating, String neighborhood,
                                      Pageable pageable) {
        return storefront(vertical, null, search, maxDeliveryFee, maxEtaMinutes, minRating,
                neighborhood, pageable);
    }

    /**
     * The storefront, and the Services tab's lists.
     *
     * <p>Which shops may come back is {@link ShopScope}'s decision. A goods read goes to the goods
     * query, which cannot return a service shop whatever it is passed. A services read goes to its
     * own query with the open categories it may show. A read that may show nothing is answered here
     * without asking the database.
     */
    @Transactional(readOnly = true)
    public Page<StoreView> storefront(Store.Vertical vertical, Store.ServiceCategory serviceCategory,
                                      String search, BigDecimal maxDeliveryFee,
                                      Integer maxEtaMinutes, BigDecimal minRating,
                                      String neighborhood, Pageable pageable) {
        Instant now = clock.instant();
        ShopScope scope = scopeOf(vertical, serviceCategory);
        if (!scope.services()) {
            return stores.findStorefront(scope.vertical(), SearchPatterns.like(search),
                            maxDeliveryFee, maxEtaMinutes, minRating, neighborhood,
                            bestFirst(pageable))
                    .map(s -> view(s, now));
        }
        if (scope.listsNothing()) {
            return Page.empty(pageable);
        }
        return stores.findServicesStorefront(scope.categories(), SearchPatterns.like(search),
                        maxDeliveryFee, maxEtaMinutes, minRating, neighborhood, bestFirst(pageable))
                .map(s -> view(s, now));
    }

    /**
     * Which shops one read may list, by vertical and service category. This is the one place
     * storefront isolation is decided, so the storefront and "near me" cannot disagree about it.
     *
     * <ul>
     *   <li>No vertical and no service category: every goods shop and no service shop. That is Home,
     *       its search, the shop lists and "near me" as every installed app asks for them — and those
     *       apps read an unknown vertical as a restaurant.
     *   <li>A goods vertical: that vertical, as it always was.
     *   <li>SERVICES, or a service category on its own: service shops, only in open categories
     *       ({@link ServiceCategories}), and only in the named one when there is one. A closed
     *       category shows nothing, even when asked for by name.
     *   <li>A goods vertical together with a service category: nothing. Filters narrow each other,
     *       and no goods shop has a service category.
     * </ul>
     *
     * <p>Favourites are deliberately outside it: a customer who starred a print shop starred it.
     *
     * @param vertical   the one vertical listed, or null for every goods vertical
     * @param categories for a services read, the categories it may show; empty shows no service shop
     */
    record ShopScope(Store.Vertical vertical, Set<Store.ServiceCategory> categories) {

        static final ShopScope GOODS = new ShopScope(null, Set.of());

        boolean services() {
            return vertical == Store.Vertical.SERVICES;
        }

        /** Nothing can match, so the caller can answer without asking the database. */
        boolean listsNothing() {
            return services() && categories.isEmpty();
        }

        /** The queries' rule, judged again on a row as read. */
        boolean admits(Store store) {
            if (vertical == null) {
                return store.getVertical() != Store.Vertical.SERVICES;
            }
            return store.getVertical() == vertical
                    && (!services() || categories.contains(store.getServiceCategory()));
        }
    }

    /**
     * See {@link ShopScope}. The open categories are read only for a read about service shops, so a
     * mistake in that setting can never break a goods read.
     */
    ShopScope scopeOf(Store.Vertical vertical, Store.ServiceCategory serviceCategory) {
        if (serviceCategory == null && vertical != Store.Vertical.SERVICES) {
            return vertical == null ? ShopScope.GOODS : new ShopScope(vertical, Set.of());
        }
        if (vertical != null && vertical != Store.Vertical.SERVICES) {
            // A goods vertical and a service category: no shop is both.
            return new ShopScope(Store.Vertical.SERVICES, Set.of());
        }
        Set<Store.ServiceCategory> open = serviceCategories.enabled();
        if (serviceCategory == null) {
            return new ShopScope(Store.Vertical.SERVICES, open);
        }
        return new ShopScope(Store.Vertical.SERVICES,
                open.contains(serviceCategory) ? Set.of(serviceCategory) : Set.of());
    }

    /** The open service categories, in taxonomy order. */
    public List<Store.ServiceCategory> openServiceCategories() {
        return List.copyOf(serviceCategories.enabled());
    }

    /**
     * Makes "sorted by rating" mean what a customer reads it to mean.
     *
     * <p>The controller asks for {@code rating DESC} and nothing more, which has two consequences
     * neither it nor the customer intends.
     *
     * <p><strong>Unrated shops came first.</strong> SQL sorts nulls first on a descending column,
     * and a shop nobody has reviewed has a null rating — so the top of the storefront was the
     * shops with no reviews at all, above a 4.9. On dev that put three unrated shops ahead of
     * every rated one. {@code nullsLast()} is the whole fix: no rating is not a good rating.
     *
     * <p><strong>And ties made rows repeat and vanish.</strong> Paging over a non-unique sort key
     * has no defined order within a tie, so the database is free to return a tied row on page one
     * and again on page two — and to never return another. Real catalogues tie constantly: three
     * shops at null, two at 4.8 here. The id breaks every tie, which costs nothing and makes the
     * pages add up.
     *
     * <p>An explicit sort from the caller is left alone; this only completes the default.
     */
    private static Pageable bestFirst(Pageable pageable) {
        Sort sort = pageable.getSort();
        boolean byRating = sort.stream().anyMatch(o -> "rating".equals(o.getProperty()));
        if (!byRating) {
            return pageable;
        }
        Sort stable = Sort.by(sort.stream()
                .map(o -> "rating".equals(o.getProperty()) ? o.nullsLast() : o)
                .toList());
        return PageRequest.of(pageable.getPageNumber(), pageable.getPageSize(),
                stable.and(Sort.by(Sort.Direction.ASC, "id")));
    }

    /** The district chips for the hyperlocal browse. */
    @Transactional(readOnly = true)
    public java.util.List<String> neighborhoods() {
        return stores.distinctNeighborhoods();
    }

    /**
     * The merchant draws their delivery circle: how far from the pin they will carry. Null
     * clears it back to zones-only. Refused without a pin — a circle needs a centre, and
     * accepting one that binds nothing would show the merchant a promise the storefront cannot
     * keep.
     */
    @Transactional
    public StoreView setDeliveryRadius(UUID id, String merchantId, Integer metres) {
        Store store = requireOwned(id, merchantId);
        if (metres != null && store.getLatitude() == null) {
            throw new org.springframework.web.server.ResponseStatusException(
                    org.springframework.http.HttpStatus.UNPROCESSABLE_ENTITY,
                    "Drop the shop's pin first — a delivery circle needs a centre.");
        }
        store.setDeliveryRadiusMetres(metres);
        return view(store, clock.instant());
    }

    /**
     * Whether the shop's circle covers the point. See the repository for the three answers.
     *
     * <p>Through {@link GeoPoint} for the same reason {@link #nearby} is: a latitude of 999 or a
     * dropped form field arriving as (0, 0) is not a place, and this endpoint used to answer
     * {@code canDeliver: true} for both — the "no circle drawn, so everywhere" answer, given about
     * a point that does not exist. Checkout then promised a delivery on the strength of it.
     */
    @Transactional(readOnly = true)
    public boolean deliversTo(UUID id, BigDecimal latitude, BigDecimal longitude) {
        GeoPoint where = new GeoPoint(latitude, longitude);
        Boolean answer = stores.deliversTo(id,
                where.latitude().doubleValue(), where.longitude().doubleValue());
        return answer == null || answer;
    }

    /** The merchant says what the lights are doing. Same shape as busy: declared, stamped. */
    @Transactional
    public StoreView declarePower(UUID id, String merchantId,
                                  Store.PowerStatus status, String note) {
        Store store = requireOwned(id, merchantId);
        store.declarePower(status, note, clock.instant());
        return view(store, clock.instant());
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
     *                      to lose the rest from — and is told so, by {@link NearbyResult#truncated}.
     */
    @Transactional(readOnly = true)
    public NearbyResult nearby(GeoPoint centre, double radiusMetres, int maxCandidates,
                               Pageable pageable) {
        return nearby(centre, radiusMetres, maxCandidates, NearbyFilters.NONE, pageable);
    }

    /**
     * A page of "near me", and whether the search stopped at its candidate ceiling.
     *
     * @param truncated true when more shops inside the radius matched the search's database-side
     *                  filters than the ceiling lets one search read. The page and its total then
     *                  describe the nearest {@code maxCandidates} of them, not the whole radius: a
     *                  shop further out was never looked at, so "no shop matches" over a truncated
     *                  answer means "none among the nearest", and a client must say it that way.
     */
    public record NearbyResult(Page<NearbyStoreView> page, boolean truncated) {
    }

    /**
     * What the neighbourhood browse may narrow "near me" by — each one a fact the platform already
     * holds, and none of them a guess.
     *
     * <p><strong>Where each is applied.</strong> Every filter but {@code openNow} is pushed into the
     * candidate query ({@link StoreRepository#findActiveIdsNear}), so the ceiling on candidates counts
     * shops that match rather than shops that happen to be near. They used to run only here, after
     * that ceiling: with 520 live shops inside the radius and the only one on a generator the 510th
     * nearest, the database handed back the nearest 500, none matched, and the customer was told no
     * shop did. {@code openNow} cannot be SQL at all: availability is walked out of the opening hours
     * at a given instant by {@link Store#availabilityAt}, and a second copy of that walk in SQL would
     * be a second answer to "is it open" free to disagree with the card.
     *
     * <p>Every filter is judged again here, on the rows as read, and this is what decides — the same
     * rule as the radius. The ids and the rows come from two queries, so a shop that changed between
     * them is judged on what it is now. The SQL and {@link #admits} must describe the same set, and
     * {@code NearbyStoreSearchTest}'s stand-in for the query holds them to it.
     *
     * <p>Filtering before the page is cut is what keeps pages full and totals honest. The one limit
     * left is the ceiling itself — within the nearest {@code maxCandidates} matching shops, which
     * {@link NearbyResult#truncated} reports reaching. Inside a neighbourhood-sized radius it is
     * nowhere near; at the endpoint's widest radius in a dense city, with "open now" narrowing a set
     * the database could not, it can be.
     *
     * @param openNow           drops a shop whose card would read CLOSED. BUSY and CLOSING_SOON stay:
     *                          both still take orders, and a customer asking "what is open" is
     *                          asking what they can buy from.
     * @param powerStatus       an exact match on what the merchant last declared the lights to be
     *                          doing, while that declaration is still current
     *                          ({@link StoreView#powerCurrent}). It is a statement about NOW —
     *                          GENERATOR means "running on the generator at the moment", not "owns
     *                          one" — so a shop that owns a generator but is on mains right now is
     *                          correctly left out, and so is one that said "generator" this morning
     *                          and has said nothing since. Clients must label it that way.
     * @param neighborhood      an exact match on the district the shop declared, the same rule as
     *                          the storefront's own filter and the district list. Trimmed; blank is
     *                          no filter.
     * @param newSinceDays      shops that first listed within this many days: "new on YouDrop".
     *                          Read from when the shop was published, not when its row was created —
     *                          a draft can sit for weeks before it lists, and it has not joined
     *                          anything until it does. A shop with no listing time is not new: the
     *                          badge is a claim, and nothing supports it.
     * @param verifiedLocalOnly only shops Backoffice has granted the trust badge.
     * @param vertical          one vertical only. Null is every goods vertical and no service shop,
     *                          which is what the neighbourhood browse and every installed app ask for.
     *                          Applied in SQL like the others; see {@link ShopScope}.
     * @param serviceCategory   service shops in one open category. Asking for a category is asking
     *                          for service shops; see {@link ShopScope}.
     */
    public record NearbyFilters(boolean openNow, Store.PowerStatus powerStatus,
                                String neighborhood, Integer newSinceDays,
                                boolean verifiedLocalOnly, Store.Vertical vertical,
                                Store.ServiceCategory serviceCategory) {

        public static final NearbyFilters NONE = new NearbyFilters(false, null, null, null, false);

        public NearbyFilters {
            neighborhood = neighborhood == null || neighborhood.isBlank() ? null : neighborhood.trim();
        }

        /** The neighbourhood browse's filters with no vertical: every goods shop, no service shop. */
        public NearbyFilters(boolean openNow, Store.PowerStatus powerStatus, String neighborhood,
                             Integer newSinceDays, boolean verifiedLocalOnly) {
            this(openNow, powerStatus, neighborhood, newSinceDays, verifiedLocalOnly, null, null);
        }

        boolean admits(StoreView view, Instant now) {
            Store store = view.store();
            if (openNow && view.availability() == Store.Availability.CLOSED) {
                return false;
            }
            if (powerStatus != null
                    && (store.getPowerStatus() != powerStatus || !view.powerCurrent())) {
                return false;
            }
            if (neighborhood != null && !neighborhood.equals(store.getNeighborhood())) {
                return false;
            }
            if (verifiedLocalOnly && !store.isVerifiedLocal()) {
                return false;
            }
            if (newSinceDays != null) {
                Instant listed = store.getPublishedAt();
                return listed != null && !listed.isBefore(listedSince(now));
            }
            return true;
        }

        /**
         * The earliest first listing "new" admits. Never null, because it is bound into the
         * candidate query beside the switch that says whether it applies — and a null bound into
         * native SQL is a parameter PostgreSQL cannot type.
         */
        Instant listedSince(Instant now) {
            return newSinceDays == null ? now : now.minus(Duration.ofDays(newSinceDays));
        }
    }

    /**
     * {@link #nearby(GeoPoint, double, int, Pageable)} narrowed by {@link NearbyFilters}.
     *
     * <p>A shop that is not ACTIVE is dropped here as well as in the candidate query, and the second
     * check is not redundant. The ids come from one query and the rows from another, so a shop
     * suspended — or pulled back to draft — between the two would otherwise be handed to a customer
     * on the strength of a status it no longer has. A DRAFT or SUSPENDED shop reaching a customer's
     * screen is the one thing every storefront read in this service is pinned against.
     *
     * <p>The database is asked for one row more than {@code maxCandidates}, so a search that reached
     * the ceiling is seen to have reached it rather than guessed at: exactly {@code maxCandidates}
     * rows back could be every shop there was.
     */
    @Transactional(readOnly = true)
    public NearbyResult nearby(GeoPoint centre, double radiusMetres, int maxCandidates,
                               NearbyFilters filters, Pageable pageable) {
        Instant now = clock.instant();
        ShopScope scope = scopeOf(filters.vertical(), filters.serviceCategory());
        if (scope.listsNothing()) {
            return new NearbyResult(pageOf(List.of(), pageable), false);
        }
        List<UUID> found = stores.findActiveIdsNear(
                centre.latitude().doubleValue(),
                centre.longitude().doubleValue(),
                radiusMetres * RADIUS_SLACK,
                filters.powerStatus() == null ? "" : filters.powerStatus().name(),
                powerDeclaredSince(now),
                filters.neighborhood() == null ? "" : filters.neighborhood(),
                filters.verifiedLocalOnly(),
                filters.newSinceDays() != null,
                filters.listedSince(now),
                scope.vertical() == null ? "" : scope.vertical().name(),
                scope.categories().stream().map(Enum::name).sorted()
                        .collect(Collectors.joining(",")),
                maxCandidates + 1);
        boolean truncated = found.size() > maxCandidates;
        // Nearest first, so the row left over is the furthest one.
        List<UUID> candidateIds = truncated ? found.subList(0, maxCandidates) : found;

        if (candidateIds.isEmpty()) {
            return new NearbyResult(pageOf(List.of(), pageable), false);
        }

        List<NearbyStoreView> near = new ArrayList<>(candidateIds.size());

        for (Store store : stores.findAllById(candidateIds)) {
            if (store.getStatus() != Store.Status.ACTIVE) {
                continue;
            }
            GeoPoint location = store.location();
            if (location == null) {
                // Only reachable if the pin were cleared between the two queries. Skipped rather
                // than defaulted: a store with no location has no distance, and inventing one would
                // put it somewhere in the list on the strength of a made-up number.
                continue;
            }
            double metres = centre.distanceMetresTo(location);
            if (metres > radiusMetres) {
                continue;
            }
            StoreView view = view(store, now);
            // The scope is judged again on the row as read, like every filter: the ids and the rows
            // come from two queries, and a shop re-filed under another category in between is
            // judged on what it is now.
            if (scope.admits(store) && filters.admits(view, now)) {
                near.add(new NearbyStoreView(view, metres));
            }
        }

        // The database's ordering is discarded here, deliberately — findAllById does not preserve
        // it anyway, and this is the ordering that ships. Ties break on the store id so a refresh
        // does not reshuffle two shops in the same building.
        near.sort(Comparator.comparingDouble(NearbyStoreView::distanceMetres)
                .thenComparing(n -> n.store().store().getId()));

        return new NearbyResult(pageOf(near, pageable), truncated);
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
     *
     * <p><strong>Never for a services applicant.</strong> A print shop's first offer — or a first
     * product or scan sent by an older app or the web portal — must not open a restaurant: a shop
     * never moves into SERVICES afterwards, so that mistake would be permanent. The provider's app
     * opens the services shop itself, from the application, before anything else ({@link #open}).
     * So a merchant with no shop at all is asked about, once, of Onboarding: a services applicant is
     * refused with {@link ServicesShopNotOpenedException}, and an Onboarding that cannot answer is a
     * 503 rather than a guess. A merchant who already has a shop — nearly every call — never waits
     * on that question.
     */
    @Transactional
    public Store requireStoreFor(String merchantId) {
        List<Store> owned = stores.findByMerchantIdOrderByCreatedAtDesc(merchantId);
        if (!owned.isEmpty()) {
            return owned.get(0);
        }
        // No shop yet. Take the merchant's lock and look again, so a first product racing another —
        // or racing the provider app opening its services shop — cannot act on a stale "nothing".
        stores.lockMerchantStores(merchantId);
        owned = stores.findByMerchantIdOrderByCreatedAtDesc(merchantId);
        if (!owned.isEmpty()) {
            return owned.get(0);
        }
        if (applications.appliedToOfferServices()) {
            throw new ServicesShopNotOpenedException();
        }
        Store store = new Store(merchantId, "My Store", Store.Vertical.RESTAURANT);
        store.replaceHours(java.util.Arrays.stream(DayOfWeek.values())
                .map(day -> new StoreHours(day, DEFAULT_OPENS, DEFAULT_CLOSES))
                .toList());
        store.publish(clock.instant());
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

    /**
     * Refused: this account applied to offer services and its services shop is not open yet, so a
     * path that would open a shop for it — a first product, a first scan — opens none.
     *
     * <p>A catalogue rule, so every caller that already turns those into a 422 keeps working; its own
     * title lets a client tell it apart (see {@code ApiExceptionHandler}).
     */
    public static class ServicesShopNotOpenedException
            extends CatalogService.CatalogRuleViolationException {
        public ServicesShopNotOpenedException() {
            super("This account applied to offer services, so no shop is opened for it "
                    + "automatically. Open your services shop first.");
        }
    }

    /**
     * What {@link #open} did.
     *
     * @param created false when a merchant asked for a services shop and already had one, which is
     *                handed back exactly as it was
     */
    public record Opened(StoreView view, boolean created) {
    }

    /** Opens a shop; see {@link #open}, which is the same call with what it did said out loud. */
    @Transactional
    public StoreView create(String merchantId, StoreRequest request) {
        return open(merchantId, request).view();
    }

    /**
     * Opens a shop.
     *
     * <p>A service shop is opened with its category, and only in an open one. The vertical and the
     * category must agree (see {@link Store}); a mismatch is refused as a 422 with a sentence, not
     * as a constraint name.
     *
     * <p><strong>A merchant has one services shop.</strong> The provider's app opens it on its first
     * entry after approval, from the application's name, category and area, and a retry after a
     * dropped connection, a second phone or a double tap has to land on that shop rather than open
     * another. So a SERVICES request from a merchant who already has one hands it back unchanged,
     * with {@code created} false; changing it is a save, not a second open. The merchant's lock is
     * taken before looking, so two requests at once cannot both find none. Goods shops open exactly
     * as before, one per call.
     */
    @Transactional
    public Opened open(String merchantId, StoreRequest request) {
        if (request.vertical() == Store.Vertical.SERVICES) {
            stores.lockMerchantStores(merchantId);
            Optional<Store> existing = stores.findByMerchantIdOrderByCreatedAtDesc(merchantId)
                    .stream()
                    .filter(Store::isServices)
                    .findFirst();
            if (existing.isPresent()) {
                return new Opened(view(existing.get(), clock.instant()), false);
            }
        }
        Store store;
        try {
            store = new Store(merchantId, request.name(), request.vertical(),
                    request.serviceCategory());
        } catch (IllegalArgumentException e) {
            throw new CatalogService.CatalogRuleViolationException(e.getMessage());
        }
        if (store.isServices()) {
            requireOpen(store.getServiceCategory());
        }
        store.updateProfile(request.name(), request.tagline(), request.description(),
                request.vertical(), request.tags(), request.timezone(), request.address());
        store.setNeighborhood(request.neighborhood());
        return new Opened(view(stores.save(store), clock.instant()), true);
    }

    /**
     * Refuses a service category that is not open (422). Only a choice is judged: see
     * {@link #update} for the shop already filed under a category that has since closed.
     */
    private void requireOpen(Store.ServiceCategory category) {
        Set<Store.ServiceCategory> open = serviceCategories.enabled();
        if (!open.contains(category)) {
            throw new CatalogService.CatalogRuleViolationException(
                    "Services in " + category + " are not offered yet. Open categories: " + open);
        }
    }

    /**
     * Saves the profile form.
     *
     * <p>The neighbourhood is only touched when the request mentions it. It used to be written
     * unconditionally, and no client sent it — the merchant form had no field for it — so every
     * profile save wrote null over it. Every shop's district was wiped the next time its owner fixed
     * a typo in their tagline, which is why the district list was empty in practice. The same shape
     * of failure {@link #pin} is kept off this form for: a field a client does not know about must
     * not be cleared by that client.
     *
     * <p>So: absent (null) leaves the district alone, blank clears it, anything else sets it. A client
     * that wants to clear it has to say so with an empty string, which only a client that knows the
     * field exists can do.
     *
     * <p><strong>The vertical never crosses into or out of SERVICES</strong> (422; see
     * {@link Store.Vertical#SERVICES}). An app built before services existed reads a service shop's
     * vertical as RESTAURANT and sends that back on every save. Refusing the move is what stops such
     * a save from turning a print shop into a restaurant.
     *
     * <p>The service category follows the district's rule, minus clearing: absent leaves it, and
     * anything else re-files the shop — a service shop only, and only under an open category. A shop
     * already filed under a category that has since closed keeps it through every other save:
     * closing a category is about what is offered, not a reason to rewrite a shop. The refusals leave
     * nothing written, because they end the transaction.
     */
    @Transactional
    public StoreView update(UUID id, String merchantId, StoreRequest request) {
        Store store = requireOwned(id, merchantId);
        Store.ServiceCategory refiled = request.serviceCategory() != null
                && request.serviceCategory() != store.getServiceCategory()
                ? request.serviceCategory() : null;
        try {
            store.updateProfile(request.name(), request.tagline(), request.description(),
                    request.vertical(), request.tags(), request.timezone(), request.address());
            if (refiled != null) {
                if (store.isServices()) {
                    requireOpen(refiled);
                }
                store.changeServiceCategory(refiled);
            }
        } catch (IllegalArgumentException | IllegalStateException e) {
            throw new CatalogService.CatalogRuleViolationException(e.getMessage());
        }
        if (request.neighborhood() != null) {
            store.setNeighborhood(request.neighborhood());
        }
        return view(store, clock.instant());
    }

    /**
     * Backoffice grants or withdraws a shop's "Trusted Local" badge.
     *
     * <p>No ownership rule, and that is the point: this is the one write on a store that is never
     * the merchant's. Who may call it is decided by the controller's role check; this only records
     * who did, because a trust badge is a claim the platform makes to a shop's neighbours and it
     * should be possible to say afterwards who made it.
     */
    @Transactional
    public StoreView setVerifiedLocal(UUID id, String backofficeId, boolean verified) {
        Store store = stores.findById(id)
                .orElseThrow(() -> new StoreNotFoundException(id.toString()));
        store.setVerifiedLocal(verified);
        log.info("Backoffice {} set verified-local on store {} to {}", backofficeId, id, verified);
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

    /**
     * Swaps the whole week.
     *
     * <p>The day is range-checked here and not left to {@code DayOfWeek.of}. Day 0 and day 8 are
     * what a client written against a zero-based or a Sunday-first calendar sends, and the enum
     * lookup answers them by throwing a date-time exception no handler maps — so the merchant got
     * "Internal error" for a request they could have fixed by reading one sentence. The bean
     * constraints on the request are the other half of this and cannot be the whole of it: element
     * constraints on a list body only run when the element itself is marked, so this method must
     * not assume anything checked the day before it arrived.
     */
    @Transactional
    public StoreView replaceHours(UUID id, String merchantId, List<HoursRequest> windows) {
        Store store = requireOwned(id, merchantId);
        List<StoreHours> replacement = new ArrayList<>(windows.size());
        for (HoursRequest window : windows) {
            if (window.dayOfWeek() < DayOfWeek.MONDAY.getValue()
                    || window.dayOfWeek() > DayOfWeek.SUNDAY.getValue()) {
                throw new CatalogService.CatalogRuleViolationException(
                        "A day is 1 (Monday) through 7 (Sunday); " + window.dayOfWeek()
                                + " is not one of them");
            }
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
            store.publish(clock.instant());
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

    /**
     * Takes a promotion down.
     *
     * <p>A miss is refused, not ignored. This used to end in {@code ifPresent}, so a merchant who
     * pasted the wrong id — or another shop's — was answered 204 and reasonably concluded the offer
     * was gone, while it went on discounting every basket. The two misses give the same answer on
     * purpose: which of them happened is a fact about another shop's promotions.
     */
    @Transactional
    public void withdrawOffer(UUID storeId, UUID offerId, String merchantId) {
        requireOwned(storeId, merchantId);
        offers.findById(offerId)
                .filter(o -> storeId.equals(o.getStoreId()))
                .orElseThrow(() -> new OfferNotFoundException(offerId))
                .withdraw();
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

    /** An offer id this shop does not have. Mapped to 404. */
    public static class OfferNotFoundException extends RuntimeException {
        public OfferNotFoundException(UUID offerId) {
            super("Offer " + offerId + " was not found");
        }
    }
}
